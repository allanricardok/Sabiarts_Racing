# WeaponManager.gd
extends Node3D
class_name WeaponManager

# --- VARIÁVEIS DA WEAPON WHEEL ---
var is_wheel_open: bool = false
var hovered_weapon_index: int = 0
var wheel_ui_node: WeaponWheel = null

# --- CONFIGURAÇÕES ---
@export_group("Armas")
@export var basic_weapon_resource: WeaponResource 
@export var fire_rate_basic : float = 0.12
@export var MAX_POOL_SIZE : int = 5 
var _previous_radar_mode : int = -1

# --- REFERÊNCIAS ---
@onready var car = owner
@onready var input = %InputComponent
@onready var targeting = %TargetingComponent

# --- DICIONÁRIO DE ARMAS ---
@onready var weapon_nodes = {
	"MachineGun": %MachineGun,
	"BigSlow": %BigSlow,
	"HomingMissile": %HomingMissile,
	"GrapplingMissile": %GrapplingMissile,
	"FreezingMissile": %FreezingMissile 
}

# --- ESTADO INTERNO ---
var weapon_pool : Array[WeaponResource] = [] 
var current_weapon_index : int = -1 
var basic_cooldown : float = 0.0
var special_cooldowns : Dictionary = {}
var player_suffix : String = "" 

# --- VISUAL E DESTAQUE ---
var highlight_material : StandardMaterial3D

var current_target: Node3D:
	get:
		if is_instance_valid(targeting) and is_instance_valid(targeting.current_target):
			return targeting.current_target
		return null

# --- SUPERAQUECIMENTO ---
var _basic_fire_time : float = 0.0
var _recovery_timer : float = 0.0
var _is_recovering : bool = false
var _was_firing : bool = false

func _ready():
	highlight_material = StandardMaterial3D.new()
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.albedo_color = Color(1.0, 0.8, 0.0, 0.4)
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	
	_update_visual_selection()

func setup_multiplayer(suffix: String):
	player_suffix = suffix
	if is_instance_valid(targeting):
		targeting.setup_multiplayer(suffix)
	_atualizar_interface()

func _process(delta):
	var is_bot = (input and "is_bot" in input and input.is_bot)
	var real_delta = delta / Engine.time_scale if is_instance_valid(car) and car.is_in_group("jogadores") and not is_bot else delta

	if basic_cooldown > 0: basic_cooldown -= real_delta
	for w in special_cooldowns.keys():
		if special_cooldowns[w] > 0: special_cooldowns[w] -= real_delta
		
	if not car.pode_mover: return
	
	if car.has_method("is_frozen") and car.is_frozen(): 
		_was_firing = false 
		return 

	var is_firing = false
	
	if is_bot:
		is_firing = input.is_action_pressed 
	else:
		if not is_instance_valid(wheel_ui_node):
			var hud = get_tree().get_first_node_in_group("HUD" + player_suffix)
			if hud: wheel_ui_node = hud.find_child("WeaponWheel", true, false)

		var wheel_action = "WeaponWheel" + input.suffix
		
		if Input.is_action_just_pressed(wheel_action):
			is_wheel_open = true
			Engine.time_scale = 0.4
			if is_instance_valid(wheel_ui_node):
				wheel_ui_node.open_wheel(weapon_pool)
				
		elif Input.is_action_just_released(wheel_action) and is_wheel_open:
			is_wheel_open = false
			Engine.time_scale = 1.0
			if is_instance_valid(wheel_ui_node):
				wheel_ui_node.close_wheel()
				equip_weapon_by_pool_index(hovered_weapon_index)

		if is_wheel_open:
			var dir_left = "Left" + input.suffix
			var dir_right = "Right" + input.suffix
			var dir_up = "AbilityUp" + input.suffix
			var dir_down = "AbilityDown" + input.suffix
			
			var analog_dir = Input.get_vector(dir_left, dir_right, dir_up, dir_down)
			
			if is_instance_valid(wheel_ui_node):
				hovered_weapon_index = wheel_ui_node.update_selection(analog_dir)
				
			return 
			
		var is_doing_ability = (input.ability_up or input.ability_down or input.ability_left or input.ability_right)
		is_firing = input.is_action_pressed and not is_doing_ability

		if input.suffix.begins_with("_K"):
			if Input.is_action_just_pressed("prev_weapon" + input.suffix): _switch_weapon(-1)
			if Input.is_action_just_pressed("next_weapon" + input.suffix): _switch_weapon(1)
			
		var fire_normal = Input.is_action_just_pressed("Fire" + input.suffix)

		if fire_normal:
			fire_special_weapon(false)

	if not is_firing:
		_basic_fire_time = 0.0
		_is_recovering = false
		_recovery_timer = 0.0

	if is_firing:
		_basic_fire_time += real_delta
		if basic_cooldown <= 0:
			fire_basic_weapon()

	_was_firing = is_firing

# --- GESTÃO DO INVENTÁRIO (POOL) ---
func get_active_special() -> WeaponResource:
	if current_weapon_index >= 0 and current_weapon_index < weapon_pool.size():
		return weapon_pool[current_weapon_index]
	return null

func equip_special_weapon(new_weapon_res: WeaponResource):
	var resource_name_to_check = ""
	if "nome" in new_weapon_res and new_weapon_res.nome != "":
		resource_name_to_check = new_weapon_res.nome
	else:
		resource_name_to_check = new_weapon_res.resource_path.get_file().get_basename()

	for i in range(weapon_pool.size()):
		var w = weapon_pool[i]
		var current_w_name = ""
		
		if "nome" in w and w.nome != "":
			current_w_name = w.nome
		else:
			current_w_name = w.resource_path.get_file().get_basename()

		if current_w_name == resource_name_to_check or (w.resource_path != "" and w.resource_path == new_weapon_res.resource_path):
			w.ammo += new_weapon_res.ammo
			
			if current_weapon_index == -1:
				current_weapon_index = i
				
			_update_visual_selection()
			_atualizar_interface()
			get_tree().call_group("TutorialUI", "complete_task", "grab_weapon")
			return

	if weapon_pool.size() < MAX_POOL_SIZE:
		var dup = new_weapon_res.duplicate()
		weapon_pool.append(dup)
		
		if current_weapon_index == -1:
			current_weapon_index = weapon_pool.size() - 1
			
		_update_visual_selection()
	
	_atualizar_interface()
	get_tree().call_group("TutorialUI", "complete_task", "grab_weapon")

func _switch_weapon(direction: int):
	if weapon_pool.size() <= 1: return 
	current_weapon_index += direction
	if current_weapon_index >= weapon_pool.size(): current_weapon_index = 0
	elif current_weapon_index < 0: current_weapon_index = weapon_pool.size() - 1
		
	_update_visual_selection()
	_atualizar_interface()

func equip_weapon_by_pool_index(index: int):
	if index >= 0 and index < weapon_pool.size():
		current_weapon_index = index
		_update_visual_selection()
		_atualizar_interface()

func _set_weapon_highlight(weapon_name: String, is_active: bool):
	var node = weapon_nodes.get(weapon_name)
	if not is_instance_valid(node): return
	var meshes = node.find_children("*", "MeshInstance3D", true)
	for mesh in meshes:
		if is_active: mesh.material_overlay = highlight_material
		else: mesh.material_overlay = null

# --- LÓGICA DE TIRO ---
func fire_basic_weapon():
	if not basic_weapon_resource: return
	
	var rage = car.get_node_or_null("%RageComponent")
	var rage_mult = rage.get_fire_rate_mult() if rage else 1.0
	
	var heat_efficiency = 1.0
	if _basic_fire_time > 1.0:
		heat_efficiency = remap(clamp(_basic_fire_time, 1.0, 4.0), 1.0, 4.0, 1.0, 0.25)
		
	basic_cooldown = fire_rate_basic / (heat_efficiency * rage_mult) 
	
	var weapon_name = basic_weapon_resource.nome
	
	_muzzle_flash_effect(weapon_name)
	_spawn_projectile(basic_weapon_resource, weapon_name, false)

func _remove_current_weapon():
	weapon_pool.remove_at(current_weapon_index)
	if weapon_pool.size() == 0:
		current_weapon_index = -1
	else:
		current_weapon_index = clamp(current_weapon_index - 1, 0, weapon_pool.size() - 1)
	
	_update_visual_selection()
	_atualizar_interface()

func fire_special_weapon(backwards: bool = false):
	var active = get_active_special()
	if not active or active.ammo <= 0: return
	if special_cooldowns.get(active.nome, 0.0) > 0: return
	
	var rage = car.get_node_or_null("%RageComponent")
	var rate_mult = rage.get_fire_rate_mult() if rage else 1.0
	
	special_cooldowns[active.nome] = active.fire_rate / rate_mult
	_muzzle_flash_effect(active.nome)
	_spawn_projectile(active, active.nome, backwards)
	car.play_camera_shake("WeaponFire")
	
	active.ammo -= 1
	if active.ammo <= 0: _remove_current_weapon()
	_atualizar_interface()

func _spawn_projectile(res: WeaponResource, node_name: String, backwards: bool = false):
	var proj = ProjectilePool.get_projectile(res.projectile_scene)
	var muzzle = weapon_nodes[node_name].find_child("Muzzle", true, false)
	
	var car_forward = car.global_transform.basis.z.normalized()
	var spawn_pos = car.global_position
	var shoot_dir = car_forward
	
	if muzzle:
		spawn_pos = muzzle.global_position
		shoot_dir = -muzzle.global_transform.basis.z.normalized()
		
	if backwards:
		shoot_dir = -car_forward
		spawn_pos = car.global_position + (shoot_dir * 4.0) + Vector3(0, 0.8, 0)
		
	proj.global_position = spawn_pos
	
	proj.look_at(spawn_pos + shoot_dir, Vector3.UP)
	
	if "is_special_weapon" in proj: proj.is_special_weapon = (node_name != "MachineGun")
	
	proj.set("is_shot_backwards", backwards)
	
	if proj.has_method("setup"):
		if node_name == "HomingMissile" or node_name == "GrapplingMissile" or node_name == "FreezingMissile":
			var target = targeting.current_target if (is_instance_valid(targeting) and not backwards) else null
			proj.setup(res.dano, car.linear_velocity, car, target)
		else:
			proj.setup(res.dano, car.linear_velocity, car)

func _muzzle_flash_effect(node_name: String):
	if not weapon_nodes.has(node_name) or not is_instance_valid(weapon_nodes[node_name]): 
		return
		
	var light = weapon_nodes[node_name].find_child("OmniLight3D", true, false)
	if is_instance_valid(light):
		light.visible = true
		get_tree().create_timer(0.05).timeout.connect(func(): 
			if is_instance_valid(light):
				light.visible = false
		)

func _update_visual_selection():
	for key in weapon_nodes:
		if key != "MachineGun": weapon_nodes[key].visible = false
		_set_weapon_highlight(key, false)
		
	if weapon_nodes.has("MachineGun"): weapon_nodes["MachineGun"].visible = true

	for w in weapon_pool:
		if weapon_nodes.has(w.nome): weapon_nodes[w.nome].visible = true

	var active = get_active_special()
	if active and weapon_nodes.has(active.nome): 
		_set_weapon_highlight(active.nome, true)
		
	if is_instance_valid(targeting) and "current_category_index" in targeting:
		if active and active.nome == "GrapplingMissile":
			if _previous_radar_mode == -1:
				_previous_radar_mode = targeting.current_category_index
			targeting.current_category_index = 0
		else:
			if _previous_radar_mode != -1:
				targeting.current_category_index = _previous_radar_mode
				_previous_radar_mode = -1

func _atualizar_interface():
	if input and "is_bot" in input and input.is_bot: 
		return
		
	var hud = get_tree().get_first_node_in_group("HUD" + player_suffix)
	if hud and hud.has_method("atualizar_arma"):
		var active = get_active_special()
		
		if active: 
			hud.atualizar_arma(active.nome, active.ammo)
		else: 
			hud.atualizar_arma("None", 0)
