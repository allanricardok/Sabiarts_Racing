# WeaponManager.gd
extends Node3D

# --- CONFIGURAÇÕES ---
@export_group("Armas")
@export var basic_weapon_resource: WeaponResource
@export var fire_rate_basic : float = 0.12
@export var MAX_WEAPON_SLOTS : int = 5

# --- REFERÊNCIAS ---
@onready var car = owner
@onready var input = %InputComponent

@onready var weapon_nodes = {
	"MachineGun": %MachineGun,
	"BigSlow": %BigSlow,
	"HomingMissile": %HomingMissile
}

# --- ESTADO INTERNO (INVENTÁRIO) ---
var inventory : Array[WeaponResource] = []
var current_index : int = -1 # -1 significa sem arma especial
var basic_cooldown : float = 0.0
var special_cooldowns : Dictionary = {}
var current_target: Node3D = null

func _ready():
	_reset_weapon_visibility()
	if weapon_nodes.has("MachineGun"):
		weapon_nodes["MachineGun"].visible = true
	_atualizar_interface()

func _process(delta):
	if basic_cooldown > 0:
		basic_cooldown -= delta
	
	for weapon_name in special_cooldowns.keys():
		if special_cooldowns[weapon_name] > 0:
			special_cooldowns[weapon_name] -= delta
		
	if not car.pode_mover: return

	# 1. TIRO BÁSICO
	if input.is_action_pressed and basic_cooldown <= 0:
		var is_doing_ability = (input.ability_up or input.ability_down or input.ability_left or input.ability_right)
		if not is_doing_ability:
			fire_basic_weapon()

	# 2. TIRO ESPECIAL
	var action_fire = "Fire" + input.suffix
	if Input.is_action_just_pressed(action_fire):
		fire_special_weapon()
	
	# 3. NAVEGAÇÃO ENTRE ARMAS (L1 / R1)
	# Assumindo que você criou as ações "PrevWeapon" e "NextWeapon" no Input Map
	if Input.is_action_just_pressed("PrevWeapon" + input.suffix):
		_switch_weapon(-1)
	if Input.is_action_just_pressed("NextWeapon" + input.suffix):
		_switch_weapon(1)
	
	# Lógica de trava do míssil
	var current_weapon = get_current_weapon()
	if current_weapon and current_weapon.nome == "HomingMissile":
		_find_lockon_target()

# --- LÓGICA DE INVENTÁRIO ---

func get_current_weapon() -> WeaponResource:
	if current_index >= 0 and current_index < inventory.size():
		return inventory[current_index]
	return null

func equip_special_weapon(new_weapon_res: WeaponResource):
	# 1. Verifica se já temos essa arma no inventário para somar munição
	for w in inventory:
		if w.nome == new_weapon_res.nome:
			w.ammo += new_weapon_res.ammo
			print("Munição acumulada para ", w.nome)
			_atualizar_interface()
			return

	# 2. Se for arma nova, verifica se há espaço
	if inventory.size() < MAX_WEAPON_SLOTS:
		var weapon_dup = new_weapon_res.duplicate()
		inventory.append(weapon_dup)
		
		# Inicializa cooldown
		if not special_cooldowns.has(weapon_dup.nome):
			special_cooldowns[weapon_dup.nome] = 0.0
			
		# Equipa a arma nova automaticamente ao coletar
		current_index = inventory.size() - 1
		_update_visual_weapon()
	else:
		print("Inventário cheio! Não foi possível coletar: ", new_weapon_res.nome)
	
	_atualizar_interface()

func _switch_weapon(direction: int):
	if inventory.size() <= 1: return # Nada para trocar
	
	# Cálculo circular do índice
	current_index = (current_index + direction) % inventory.size()
	if current_index < 0:
		current_index = inventory.size() - 1
		
	print("Trocou para: ", inventory[current_index].nome)
	_update_visual_weapon()
	_atualizar_interface()

func _update_visual_weapon():
	_reset_weapon_visibility()
	var current_weapon = get_current_weapon()
	if current_weapon and weapon_nodes.has(current_weapon.nome):
		weapon_nodes[current_weapon.nome].visible = true

func _reset_weapon_visibility():
	for key in weapon_nodes:
		if key != "MachineGun":
			weapon_nodes[key].visible = false

# --- LÓGICA DE TIRO ---

func fire_basic_weapon():
	if not basic_weapon_resource: return
	basic_cooldown = fire_rate_basic
	_muzzle_flash_effect("MachineGun")
	_spawn_projectile(basic_weapon_resource, "MachineGun")

func fire_special_weapon():
	var current_weapon = get_current_weapon()
	if not current_weapon or current_weapon.ammo <= 0: return
	
	if special_cooldowns.get(current_weapon.nome, 0.0) > 0: return
	
	special_cooldowns[current_weapon.nome] = current_weapon.fire_rate
	_muzzle_flash_effect(current_weapon.nome)
	_spawn_projectile(current_weapon, current_weapon.nome)
	
	current_weapon.ammo -= 1
	
	if current_weapon.ammo <= 0:
		_remove_current_weapon()
	
	_atualizar_interface()

func _remove_current_weapon():
	inventory.remove_at(current_index)
	
	if inventory.size() == 0:
		current_index = -1
		_reset_weapon_visibility()
	else:
		# Volta para a arma anterior ou a primeira
		current_index = max(0, current_index - 1)
		_update_visual_weapon()
		
	print("Arma removida por falta de munição.")

# --- AUXILIARES ---

func _spawn_projectile(res: WeaponResource, node_name: String):
	var proj = res.projectile_scene.instantiate()
	var muzzle = weapon_nodes[node_name].find_child("Muzzle", true, false)
	if muzzle:
		proj.global_transform = muzzle.global_transform
	get_tree().current_scene.add_child(proj)
	
	if proj.has_method("setup"):
		if node_name == "HomingMissile":
			proj.setup(res.dano, car.linear_velocity, car, current_target)
		else:
			proj.setup(res.dano, car.linear_velocity, car)

func _muzzle_flash_effect(node_name: String):
	var light = weapon_nodes[node_name].find_child("OmniLight3D", true, false)
	if light:
		light.visible = true
		await get_tree().create_timer(0.05).timeout
		light.visible = false

func _atualizar_interface():
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		var current_weapon = get_current_weapon()
		if current_weapon:
			hud.atualizar_arma(current_weapon.nome, current_weapon.ammo)
		else:
			hud.atualizar_arma("None", 0)

func _find_lockon_target():
	var targets = get_tree().get_nodes_in_group("Enemies")
	var best_target = null
	var min_angle = 35.0
	var max_dist = 120.0
	var car_forward = car.global_transform.basis.z 

	for t in targets:
		if not is_instance_valid(t): continue
		var dir = (t.global_position - car.global_position).normalized()
		var angle = rad_to_deg(car_forward.angle_to(dir))
		var dist = car.global_position.distance_to(t.global_position)
		if angle < min_angle and dist < max_dist:
			best_target = t
			min_angle = angle
	current_target = best_target
