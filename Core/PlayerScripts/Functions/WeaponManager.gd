# WeaponManager.gd
extends Node3D

# --- CONFIGURAÇÕES ---
@export_group("Armas")
@export var basic_weapon_resource: WeaponResource 
@export var fire_rate_basic : float = 0.12
@export var MAX_POOL_SIZE : int = 5 # Limite de 5 armas especiais

# --- REFERÊNCIAS ---
@onready var car = owner
@onready var input = %InputComponent

@onready var weapon_nodes = {
	"MachineGun": %MachineGun,
	"BigSlow": %BigSlow,
	"HomingMissile": %HomingMissile,
	"GrapplingMissile": %GrapplingMissile 
}

# --- ESTADO INTERNO (INVENTÁRIO) ---
var weapon_pool : Array[WeaponResource] = [] # Nossa lista de armas
var current_weapon_index : int = -1 # -1 significa nenhuma arma especial
var current_target: Node3D = null
var basic_cooldown : float = 0.0
var special_cooldowns : Dictionary = {}

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

	# 2. TROCA DE ARMAS (L1 / R1)
	if Input.is_action_just_pressed("prev_weapon" + input.suffix): # L1
		_switch_weapon(-1)
	if Input.is_action_just_pressed("next_weapon" + input.suffix): # R1
		_switch_weapon(1)

	# 3. TIRO ESPECIAL
	var action_name = "Fire" + input.suffix
	if Input.is_action_just_pressed(action_name):
		fire_special_weapon()
	
	# 4. LOCK-ON (Apenas para a arma selecionada no momento)
	var active_weapon = get_active_special()
	if active_weapon and (active_weapon.nome == "HomingMissile" or active_weapon.nome == "GrapplingMissile"):
		_find_lockon_target()

# --- GESTÃO DO INVENTÁRIO (POOL) ---

func get_active_special() -> WeaponResource:
	if current_weapon_index >= 0 and current_weapon_index < weapon_pool.size():
		return weapon_pool[current_weapon_index]
	return null

func equip_special_weapon(new_weapon_res: WeaponResource):
	# 1. Verifica se já temos essa arma no pool para somar munição
	for i in range(weapon_pool.size()):
		var w = weapon_pool[i]
		if w.nome == new_weapon_res.nome:
			w.ammo += new_weapon_res.ammo
			print("Munição adicionada ao pool: ", w.nome)
			
			# Força a seleção para a arma que acabou de receber munição
			current_weapon_index = i
			_update_visual_selection()
			_atualizar_interface()
			return

	# 2. Se não temos, tentamos adicionar ao pool
	if weapon_pool.size() < MAX_POOL_SIZE:
		var dup = new_weapon_res.duplicate()
		weapon_pool.append(dup)
		
		# Seleciona sempre a arma recém-adicionada (a última do array)
		current_weapon_index = weapon_pool.size() - 1
		_update_visual_selection()
			
		print("Nova arma adicionada ao pool: ", dup.nome)
	else:
		print("Pool cheio! Não é possível carregar mais armas.")
	
	_atualizar_interface()

func _switch_weapon(direction: int):
	if weapon_pool.size() <= 1: return # Nada para trocar
	
	current_weapon_index += direction
	
	# Loop infinito no inventário
	if current_weapon_index >= weapon_pool.size():
		current_weapon_index = 0
	elif current_weapon_index < 0:
		current_weapon_index = weapon_pool.size() - 1
		
	_update_visual_selection()
	_atualizar_interface()

func _update_visual_selection():
	_reset_weapon_visibility()
	var active = get_active_special()
	if active and weapon_nodes.has(active.nome):
		weapon_nodes[active.nome].visible = true

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
	var active = get_active_special()
	if not active or active.ammo <= 0: return
		
	if special_cooldowns.get(active.nome, 0.0) > 0: return
	
	special_cooldowns[active.nome] = active.fire_rate
	_muzzle_flash_effect(active.nome)
	_spawn_projectile(active, active.nome)
	
	active.ammo -= 1
	if active.ammo <= 0:
		_remove_current_weapon()
	
	_atualizar_interface()

func _remove_current_weapon():
	weapon_pool.remove_at(current_weapon_index)
	
	if weapon_pool.size() == 0:
		current_weapon_index = -1
		_reset_weapon_visibility()
	else:
		# Volta para a arma anterior ou a primeira
		current_weapon_index = clamp(current_weapon_index - 1, 0, weapon_pool.size() - 1)
		_update_visual_selection()
	
	_atualizar_interface()

func _spawn_projectile(res: WeaponResource, node_name: String):
	var proj = res.projectile_scene.instantiate()
	var muzzle = weapon_nodes[node_name].find_child("Muzzle", true, false)
	
	if muzzle:
		proj.global_transform = muzzle.global_transform
	
	get_tree().current_scene.add_child(proj)
	
	if proj.has_method("setup"):
		if node_name == "HomingMissile" or node_name == "GrapplingMissile":
			proj.setup(res.dano, car.linear_velocity, car, current_target)
		else:
			proj.setup(res.dano, car.linear_velocity, car)

# --- REVISÃO DA RÉ (CORREÇÃO QUE FIZEMOS ANTES) ---

func _muzzle_flash_effect(node_name: String):
	var light = weapon_nodes[node_name].find_child("OmniLight3D", true, false)
	if light:
		light.visible = true
		await get_tree().create_timer(0.05).timeout
		light.visible = false

func _atualizar_interface():
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		var active = get_active_special()
		if active:
			hud.atualizar_arma(active.nome, active.ammo)
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
