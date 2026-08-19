extends Node3D
class_name WeaponManager

# --- VARIÁVEIS DA WEAPON WHEEL E TROCA RÁPIDA ---
var is_wheel_open: bool = false
var hovered_weapon_index: int = 0
var wheel_ui_node: WeaponWheel = null
var _wheel_hold_timer: float = 0.0 

# --- CONFIGURAÇÕES ---
@export_group("Armas")
@export var basic_weapon_resource: WeaponResource 
@export var fire_rate_basic : float = 0.12
@export var MAX_POOL_SIZE : int = 5 
@export var land_mine_scene: PackedScene 
var _previous_radar_mode : int = -1

@export_group("Loot System")
@export var drop_item_scene : PackedScene

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
	"FreezingMissile": %FreezingMissile,
	"BazookaMissile": %BazookaMissile, 
	"LandMine": %LandMine
}

# --- ESTADO INTERNO ---
var weapon_pool : Array[WeaponResource] = [] 
var current_weapon_index : int = -1 
var player_suffix : String = "" 
var _last_landmine_fire_time: float = 0.0 

var highlight_material : StandardMaterial3D
var shooter: WeaponShooter

var _is_bot: bool = false
var _cached_hud: Node = null
var _weapon_meshes_cache: Dictionary = {}

func _ready():
	highlight_material = MaterialCache.get_mat("WeaponHighlight")
	
	shooter = WeaponShooter.new()
	add_child(shooter)
	shooter.setup(car, targeting, weapon_nodes, basic_weapon_resource, fire_rate_basic)
	
	for key in weapon_nodes:
		var node = weapon_nodes[key]
		if is_instance_valid(node):
			var meshes = node.find_children("*", "MeshInstance3D", true, false)
			var valid_meshes = []
			for m in meshes:
				if m is MeshInstance3D: valid_meshes.append(m)
			_weapon_meshes_cache[key] = valid_meshes

	call_deferred("_late_bot_check")
	_update_visual_selection()

func _late_bot_check():
	if is_instance_valid(input) and "is_bot" in input:
		_is_bot = input.is_bot

func setup_multiplayer(suffix: String):
	player_suffix = suffix
	_is_bot = (input and "is_bot" in input and input.is_bot)
	
	if not _is_bot: call_deferred("_cache_ui")
		
	if is_instance_valid(targeting): targeting.setup_multiplayer(suffix)
	_atualizar_interface()

func _cache_ui():
	_cached_hud = get_tree().get_first_node_in_group("HUD" + player_suffix)
	if not _cached_hud: _cached_hud = get_tree().get_first_node_in_group("HUD")
		
	if is_instance_valid(_cached_hud):
		wheel_ui_node = _cached_hud.find_child("WeaponWheel", true, false)

func _process(delta):
	if not is_instance_valid(car) or not car.pode_mover: return
	
	var unscaled_delta = delta / Engine.time_scale if Engine.time_scale > 0.01 else delta
	var real_delta = unscaled_delta if (not _is_bot and car.is_in_group("jogadores")) else delta

	if car.has_method("is_frozen") and car.is_frozen(): 
		if is_instance_valid(shooter): shooter.process_shooting(real_delta, false)
		return 

	var is_firing_basic = false
	
	if _is_bot:
		is_firing_basic = input.is_action_pressed 
	else:
		# CORREÇÃO AQUI: Usando o nome real da sua ação de arma!
		var wheel_action = "next_weapon" + input.suffix 
		
		if InputMap.has_action(wheel_action):
			if Input.is_action_pressed(wheel_action):
				_wheel_hold_timer += unscaled_delta
				
				if _wheel_hold_timer > 0.2 and not is_wheel_open:
					is_wheel_open = true
					Engine.time_scale = 0.2 
					if is_instance_valid(wheel_ui_node):
						wheel_ui_node.open_wheel(weapon_pool)
			
			elif Input.is_action_just_released(wheel_action):
				if is_wheel_open:
					is_wheel_open = false
					Engine.time_scale = 1.0 
					if is_instance_valid(wheel_ui_node):
						wheel_ui_node.close_wheel()
						equip_weapon_by_pool_index(hovered_weapon_index)
				else:
					_switch_weapon(1)
					
				_wheel_hold_timer = 0.0

		if is_wheel_open:
			var analog_dir = input.look_vector
			if analog_dir.length() < 0.2:
				analog_dir = Vector2(input.steering, input.pitch) 
				
			if is_instance_valid(wheel_ui_node):
				hovered_weapon_index = wheel_ui_node.update_selection(analog_dir)
			return 
			
		var is_doing_ability = input.is_attribute_pressed
		is_firing_basic = input.is_action_pressed and not is_doing_ability

		var fire_special = Input.is_action_just_pressed("Fire" + input.suffix)
		if fire_special:
			var active = get_active_special()
			if active:
				var successfully_fired = false
				
				if active.nome == "LandMine":
					var now = Time.get_ticks_msec() / 1000.0
					if now - _last_landmine_fire_time >= active.fire_rate:
						successfully_fired = _fire_land_mine()
						if successfully_fired: _last_landmine_fire_time = now
							
				elif is_instance_valid(shooter) and shooter.try_fire_special(active, false):
					successfully_fired = true
					
				if successfully_fired:
					active.ammo -= 1
					if active.ammo <= 0: _remove_current_weapon()
					_atualizar_interface()

	if is_instance_valid(shooter):
		shooter.process_shooting(real_delta, is_firing_basic)

func _fire_land_mine() -> bool:
	if not land_mine_scene: return false
		
	var mine = land_mine_scene.instantiate()
	get_tree().current_scene.add_child(mine)
	mine.shooter = car 
	
	var mine_visual_node = weapon_nodes.get("LandMine")
	var muzzle = null
	if is_instance_valid(mine_visual_node):
		muzzle = mine_visual_node.find_child("Muzzle", true, false)
		
	if is_instance_valid(muzzle): mine.global_position = muzzle.global_position
	else: mine.global_position = car.global_position - (car.global_transform.basis.z * 3.0) + (car.global_transform.basis.y * 1.5)
		
	mine.global_rotation = Vector3.ZERO
	return true

func get_active_special() -> WeaponResource:
	if current_weapon_index >= 0 and current_weapon_index < weapon_pool.size(): return weapon_pool[current_weapon_index]
	return null

func equip_special_weapon(new_weapon_res: WeaponResource) -> bool:
	var resource_name_to_check = new_weapon_res.nome if "nome" in new_weapon_res and new_weapon_res.nome != "" else new_weapon_res.resource_path.get_file().get_basename()
	var success = false

	for i in range(weapon_pool.size()):
		var w = weapon_pool[i]
		var current_w_name = w.nome if "nome" in w and w.nome != "" else w.resource_path.get_file().get_basename()

		if current_w_name == resource_name_to_check or (w.resource_path != "" and w.resource_path == new_weapon_res.resource_path):
			if w.ammo >= w.max_ammo:
				_trigger_pickup_flash(false) 
				return false 
			
			w.ammo = min(w.ammo + new_weapon_res.ammo, w.max_ammo)
			if current_weapon_index == -1: current_weapon_index = i
			
			success = true
			break

	if not success:
		var dup = new_weapon_res.duplicate()
		dup.ammo = min(dup.ammo, dup.max_ammo)
		
		if weapon_pool.size() < MAX_POOL_SIZE:
			weapon_pool.append(dup)
			if current_weapon_index == -1: current_weapon_index = weapon_pool.size() - 1
			success = true
		else:
			if current_weapon_index != -1 and drop_item_scene:
				var old_weapon = weapon_pool[current_weapon_index]
				
				if is_instance_valid(LootDropManager) and is_instance_valid(car):
					var eject_dir = (car.global_transform.basis.z + (Vector3.UP * 0.8)).normalized()
					var drop_pos = car.global_position + Vector3(0, 1.5, 0)
					
					var dropped_item = LootDropManager.spawn_ejected_loot(drop_pos, eject_dir, drop_item_scene, old_weapon, 15.0)
					if is_instance_valid(dropped_item): _temporarily_disable_collider(dropped_item)
				
				weapon_pool[current_weapon_index] = dup
				success = true
			else:
				_trigger_pickup_flash(false)
				return false

	if success:
		_update_visual_selection()
		_atualizar_interface()
		get_tree().call_group("TutorialUI", "complete_task", "grab_weapon")
		_trigger_pickup_flash(true) 
		return true

	return false

func _temporarily_disable_collider(loot_node: Node):
	var colliders = loot_node.find_children("*", "CollisionShape3D", true, false)
	for col in colliders: col.set_deferred("disabled", true)
	await get_tree().create_timer(0.5, false).timeout
	if is_instance_valid(loot_node):
		for col in colliders:
			if is_instance_valid(col): col.set_deferred("disabled", false)

func _trigger_pickup_flash(success: bool):
	if _is_bot: return
	if is_instance_valid(_cached_hud) and _cached_hud.has_method("play_pickup_flash"):
		_cached_hud.play_pickup_flash(success)

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

func _remove_current_weapon():
	weapon_pool.remove_at(current_weapon_index)
	if weapon_pool.size() == 0: current_weapon_index = -1
	else: current_weapon_index = clamp(current_weapon_index - 1, 0, weapon_pool.size() - 1)
	
	_update_visual_selection()
	_atualizar_interface()

func _set_weapon_highlight(weapon_name: String, is_active: bool):
	if not _weapon_meshes_cache.has(weapon_name): return
	
	for mesh in _weapon_meshes_cache[weapon_name]:
		if is_instance_valid(mesh):
			if is_active: mesh.material_overlay = highlight_material
			else: mesh.material_overlay = null

func _update_visual_selection():
	for key in weapon_nodes:
		if key != "MachineGun" and is_instance_valid(weapon_nodes[key]): 
			weapon_nodes[key].visible = false
		_set_weapon_highlight(key, false)
		
	if weapon_nodes.has("MachineGun") and is_instance_valid(weapon_nodes["MachineGun"]): 
		weapon_nodes["MachineGun"].visible = true

	for w in weapon_pool:
		if weapon_nodes.has(w.nome) and is_instance_valid(weapon_nodes[w.nome]): 
			weapon_nodes[w.nome].visible = true

	var active = get_active_special()
	if active and weapon_nodes.has(active.nome): 
		_set_weapon_highlight(active.nome, true)
		
	if is_instance_valid(targeting) and "current_category_index" in targeting:
		if active and active.nome == "GrapplingMissile":
			if _previous_radar_mode == -1: _previous_radar_mode = targeting.current_category_index
			targeting.current_category_index = 0
		else:
			if _previous_radar_mode != -1:
				targeting.current_category_index = _previous_radar_mode
				_previous_radar_mode = -1

func _atualizar_interface():
	if _is_bot: return
	
	if is_instance_valid(_cached_hud):
		var active = get_active_special()
		
		# Atualiza o texto (seu sistema antigo)
		if _cached_hud.has_method("atualizar_arma"):
			if active: 
				_cached_hud.atualizar_arma(active.nome, active.ammo)
			else: 
				_cached_hud.atualizar_arma("No weapons", 0)
				
		# Nova UI dos Quadradinhos (com animação de pulo)
		if _cached_hud.has_method("atualizar_lista_armas"):
			_cached_hud.atualizar_lista_armas(weapon_pool, current_weapon_index)
