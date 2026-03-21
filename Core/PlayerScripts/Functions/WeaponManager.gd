# WeaponManager.gd
extends Node3D
class_name WeaponManager

# --- CONFIGURAÇÕES ---
@export_group("Armas")
@export var basic_weapon_resource: WeaponResource 
@export var fire_rate_basic : float = 0.12
@export var MAX_POOL_SIZE : int = 5 

# --- REFERÊNCIAS ---
@onready var car = owner
@onready var input = %InputComponent
@onready var targeting = %TargetingComponent # <-- Ligação com o novo cérebro!

@onready var weapon_nodes = {
	"MachineGun": %MachineGun,
	"BigSlow": %BigSlow,
	"HomingMissile": %HomingMissile,
	"GrapplingMissile": %GrapplingMissile 
}

# --- ESTADO INTERNO ---
var weapon_pool : Array[WeaponResource] = [] 
var current_weapon_index : int = -1 
var basic_cooldown : float = 0.0
var special_cooldowns : Dictionary = {}
var player_suffix : String = "" 
# --- PONTE PARA A HUD NÃO QUEBRAR ---
var current_target: Node3D:
	get:
		# Checa se o Targeting existe E se o alvo dele ainda está vivo na cena
		if is_instance_valid(targeting) and is_instance_valid(targeting.current_target):
			return targeting.current_target
		return null

# --- SUPERAQUECIMENTO ---
var _basic_fire_time : float = 0.0
var _recovery_timer : float = 0.0
var _is_recovering : bool = false
var _was_firing : bool = false

func _ready():
	_reset_weapon_visibility()
	if weapon_nodes.has("MachineGun"):
		weapon_nodes["MachineGun"].visible = true

func setup_multiplayer(suffix: String):
	player_suffix = suffix
	if is_instance_valid(targeting):
		targeting.setup_multiplayer(suffix)
	_atualizar_interface()

func _process(delta):
	var real_delta = delta / Engine.time_scale if is_instance_valid(car) and car.is_in_group("jogadores") else delta

	if basic_cooldown > 0: basic_cooldown -= real_delta
	for w in special_cooldowns.keys():
		if special_cooldowns[w] > 0: special_cooldowns[w] -= real_delta
		
	if not car.pode_mover: return

	# LÓGICA DE TIRO BÁSICO E SUPERAQUECIMENTO
	var is_doing_ability = (input.ability_up or input.ability_down or input.ability_left or input.ability_right)
	var is_firing = input.is_action_pressed and not is_doing_ability

	# Soltou o botão? Inicia a recuperação paralela!
	if not is_firing and _was_firing:
		_is_recovering = true
		_recovery_timer = 0.0

	# O timer roda independente de estar atirando de novo ou não
	if _is_recovering:
		_recovery_timer += real_delta
		if _recovery_timer >= 2.0:
			_basic_fire_time = 0.0
			_is_recovering = false

	# Aplica o tempo de tiro (aquece a arma)
	if is_firing:
		_basic_fire_time += real_delta
		if basic_cooldown <= 0:
			fire_basic_weapon()

	_was_firing = is_firing

	# TROCA E TIRO ESPECIAL
	if Input.is_action_just_pressed("prev_weapon" + input.suffix): _switch_weapon(-1)
	if Input.is_action_just_pressed("next_weapon" + input.suffix): _switch_weapon(1)
	if Input.is_action_just_pressed("Fire" + input.suffix): fire_special_weapon()


# --- GESTÃO DO INVENTÁRIO (POOL) ---

func get_active_special() -> WeaponResource:
	if current_weapon_index >= 0 and current_weapon_index < weapon_pool.size():
		return weapon_pool[current_weapon_index]
	return null

func equip_special_weapon(new_weapon_res: WeaponResource):
	for i in range(weapon_pool.size()):
		var w = weapon_pool[i]
		if w.nome == new_weapon_res.nome:
			w.ammo += new_weapon_res.ammo
			current_weapon_index = i
			_update_visual_selection()
			_atualizar_interface()
			return

	if weapon_pool.size() < MAX_POOL_SIZE:
		var dup = new_weapon_res.duplicate()
		weapon_pool.append(dup)
		current_weapon_index = weapon_pool.size() - 1
		_update_visual_selection()
	
	_atualizar_interface()

func _switch_weapon(direction: int):
	if weapon_pool.size() <= 1: return 
	current_weapon_index += direction
	if current_weapon_index >= weapon_pool.size(): current_weapon_index = 0
	elif current_weapon_index < 0: current_weapon_index = weapon_pool.size() - 1
		
	_update_visual_selection()
	_atualizar_interface()

func _update_visual_selection():
	_reset_weapon_visibility()
	var active = get_active_special()
	if active and weapon_nodes.has(active.nome):
		weapon_nodes[active.nome].visible = true

func _reset_weapon_visibility():
	for key in weapon_nodes:
		if key != "MachineGun": weapon_nodes[key].visible = false

# --- LÓGICA DE TIRO ---

func fire_basic_weapon():
	if not basic_weapon_resource: return
	
	var rage = car.get_node_or_null("%RageComponent")
	var rage_mult = rage.get_fire_rate_mult() if rage else 1.0
	
	var heat_efficiency = 1.0
	if _basic_fire_time > 2.0:
		heat_efficiency = remap(clamp(_basic_fire_time, 1.0, 10.0), 1.0, 10.0, 1.0, 0.25)
		
	basic_cooldown = fire_rate_basic / (heat_efficiency * rage_mult) 
	
	_muzzle_flash_effect("MachineGun")
	_spawn_projectile(basic_weapon_resource, "MachineGun")

func fire_special_weapon():
	var active = get_active_special()
	if not active or active.ammo <= 0: return
	if special_cooldowns.get(active.nome, 0.0) > 0: return
	
	var rage = car.get_node_or_null("%RageComponent")
	var rate_mult = rage.get_fire_rate_mult() if rage else 1.0
	
	special_cooldowns[active.nome] = active.fire_rate / rate_mult
	_muzzle_flash_effect(active.nome)
	_spawn_projectile(active, active.nome)
	
	active.ammo -= 1
	if active.ammo <= 0: _remove_current_weapon()
	_atualizar_interface()

func _remove_current_weapon():
	weapon_pool.remove_at(current_weapon_index)
	if weapon_pool.size() == 0:
		current_weapon_index = -1
		_reset_weapon_visibility()
	else:
		current_weapon_index = clamp(current_weapon_index - 1, 0, weapon_pool.size() - 1)
		_update_visual_selection()
	_atualizar_interface()

func _spawn_projectile(res: WeaponResource, node_name: String):
	var proj = ProjectilePool.get_projectile(res.projectile_scene)
	var muzzle = weapon_nodes[node_name].find_child("Muzzle", true, false)
	
	if muzzle: proj.global_transform = muzzle.global_transform
	
	if proj.has_method("setup"):
		if node_name == "HomingMissile" or node_name == "GrapplingMissile":
			# Puxa o alvo atual do script auxiliar de Targeting
			var target = targeting.current_target if is_instance_valid(targeting) else null
			proj.setup(res.dano, car.linear_velocity, car, target)
		else:
			proj.setup(res.dano, car.linear_velocity, car)

func _muzzle_flash_effect(node_name: String):
	var light = weapon_nodes[node_name].find_child("OmniLight3D", true, false)
	if light:
		light.visible = true
		get_tree().create_timer(0.05).timeout.connect(func(): light.visible = false)

func _atualizar_interface():
	var hud = get_tree().get_first_node_in_group("HUD" + player_suffix)
	if hud and hud.has_method("atualizar_arma"):
		var active = get_active_special()
		if active: hud.atualizar_arma(active.nome, active.ammo)
		else: hud.atualizar_arma("None", 0)
