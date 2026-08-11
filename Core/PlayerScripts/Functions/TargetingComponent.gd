extends Node3D
class_name TargetingComponent

# --- SISTEMA DE ALVOS TÁTICO ---
var target_categories = ["All Targets", "Adversaries", "Fuckers", "Environment"]
var current_category_index : int = 0 
var manual_target_index : int = 0
var active_targets_sorted : Array = []
var force_target_all : bool = false

var last_selected_target : Node3D = null 
var _previous_adversary_count : int = 0

# --- Cérebro de Abas Dinâmicas ---
var valid_category_indices : Array[int] = [0] 

@export_group("Radar e Sensores")
@export var radar_range : float = 350.0 
@export_flags_3d_physics var los_collision_mask = 1 

var current_target: Node3D = null
var radar_update_timer : float = 0.0
const RADAR_UPDATE_INTERVAL : float = 0.1
var player_suffix : String = "" 

@onready var car = owner
@onready var input = %InputComponent
@onready var weapons = %WeaponManager

# --- CACHE ---
var _is_bot: bool = false
var _cached_hud: Node = null
var _cached_camera: Camera3D = null
var _cached_reticle: Control = null

func _ready():
	# A MÁGICA: Independente de como o carro nasça, ele descobre se é bot sozinho!
	call_deferred("_universal_bot_check")

func _universal_bot_check():
	if is_instance_valid(input) and "is_bot" in input and input.is_bot:
		_is_bot = true
		set_process(false) # Desliga a CPU do bot 100%

func setup_multiplayer(suffix: String):
	player_suffix = suffix
	if _is_bot: return
		
	call_deferred("_cache_ui")
	call_deferred("_validate_initial_category")

func _cache_ui():
	_cached_hud = get_tree().get_first_node_in_group("HUD" + player_suffix)
	if _cached_hud:
		_cached_reticle = _cached_hud.find_child("Reticle", true, false)
	_cached_camera = get_viewport().get_camera_3d()

func _physics_process(delta):
	if _is_bot or not is_instance_valid(car) or not car.pode_mover: return
	
	var real_delta = delta / Engine.time_scale 
	
	var is_wheel_open = is_instance_valid(weapons) and "is_wheel_open" in weapons and weapons.is_wheel_open
	
	if not is_wheel_open:
		if InputMap.has_action("cat_left" + input.suffix) and Input.is_action_just_pressed("cat_left" + input.suffix): _cycle_category(-1)
		if InputMap.has_action("cat_right" + input.suffix) and Input.is_action_just_pressed("cat_right" + input.suffix): _cycle_category(1)
		if InputMap.has_action("target_up" + input.suffix) and Input.is_action_just_pressed("target_up" + input.suffix): _cycle_target(-1)
		if InputMap.has_action("target_down" + input.suffix) and Input.is_action_just_pressed("target_down" + input.suffix): _cycle_target(1)

	radar_update_timer -= real_delta
	if radar_update_timer <= 0:
		radar_update_timer = RADAR_UPDATE_INTERVAL
		_update_radar_and_lockon()
		
	_atualizar_posicao_reticulo()

func _validate_initial_category():
	_recalculate_valid_categories()
	
	_previous_adversary_count = _get_category_count(1)
	if _previous_adversary_count > 0:
		current_category_index = 1
	else:
		current_category_index = 0
		
	manual_target_index = 0
	last_selected_target = null

func _recalculate_valid_categories():
	valid_category_indices.clear()
	valid_category_indices.append(0) 
	
	if _get_category_count(1) > 0: valid_category_indices.append(1)
	if _get_category_count(2) > 0: valid_category_indices.append(2)
	if _get_category_count(3) > 0: valid_category_indices.append(3)
	
	valid_category_indices.sort() 

func _cycle_category(direction: int):
	_recalculate_valid_categories()
	
	if valid_category_indices.size() <= 1:
		current_category_index = 0
		return
		
	var array_pos = valid_category_indices.find(current_category_index)
	if array_pos == -1: 
		array_pos = 0 
		
	array_pos += direction
	
	if array_pos >= valid_category_indices.size(): array_pos = 0
	elif array_pos < 0: array_pos = valid_category_indices.size() - 1
	
	current_category_index = valid_category_indices[array_pos]
	
	manual_target_index = 0 
	last_selected_target = null 
	_update_radar_and_lockon() 

func _get_category_count(index: int) -> int:
	var count = 0
	if index == 0: return 1 
	elif index == 1:
		for p in get_tree().get_nodes_in_group("jogadores"):
			if p != car and is_instance_valid(p) and not p.is_queued_for_deletion(): count += 1
	elif index == 2:
		for t in get_tree().get_nodes_in_group("inimigos"):
			if is_instance_valid(t) and not t.is_queued_for_deletion(): count += 1
	elif index == 3:
		for p in get_tree().get_nodes_in_group("destructibles"):
			if is_instance_valid(p) and not p.is_queued_for_deletion(): count += 1
	return count

func _cycle_target(direction: int):
	if active_targets_sorted.is_empty(): return
	
	manual_target_index += direction
	if manual_target_index >= active_targets_sorted.size(): manual_target_index = 0
	elif manual_target_index < 0: manual_target_index = active_targets_sorted.size() - 1
	
	last_selected_target = active_targets_sorted[manual_target_index]
	_update_radar_and_lockon()

func _has_line_of_sight(target: Node3D) -> bool:
	var space_state = car.get_world_3d().direct_space_state
	var origin = car.global_position + Vector3.UP * 1.5
	var destination = target.global_position + Vector3.UP * 1.0 
	
	var query = PhysicsRayQueryParameters3D.create(origin, destination, los_collision_mask)
	query.exclude = [car.get_rid(), target.get_rid()] 
	var result = space_state.intersect_ray(query)
	return result.is_empty()

func _update_radar_and_lockon():
	if not is_instance_valid(car): return

	_recalculate_valid_categories()
	var current_adv_count = _get_category_count(1)
	
	if current_adv_count > 0 and _previous_adversary_count == 0:
		current_category_index = 1
		manual_target_index = 0
		last_selected_target = null
	elif current_adv_count == 0 and _previous_adversary_count > 0:
		if current_category_index == 1:
			current_category_index = 0
			manual_target_index = 0
			last_selected_target = null
			
	if not valid_category_indices.has(current_category_index):
		current_category_index = 0
		manual_target_index = 0
		last_selected_target = null
		
	_previous_adversary_count = current_adv_count

	var radar_data = []
	var category_bucket = [] 
	var car_pos = car.global_position
	var car_forward = car.global_transform.basis.z 
	var radar_range_sq = radar_range * radar_range
	
	var search_groups = ["jogadores", "inimigos", "destructibles", "pedestrians"]
	var raw_targets = []
	for g in search_groups:
		raw_targets.append_array(get_tree().get_nodes_in_group(g))

	for t in raw_targets:
		if not is_instance_valid(t) or t == car or t.is_queued_for_deletion(): continue
		if t.is_in_group("pedestrians") and "is_invincible" in t and t.is_invincible: continue
			
		var dist_sq = car_pos.distance_squared_to(t.global_position)
		
		if dist_sq <= radar_range_sq or t.is_in_group("jogadores") or t.is_in_group("inimigos"):
			if not t.is_in_group("pedestrians"): radar_data.append(t)
			
			var is_valid_category = false
			if current_category_index == 0: is_valid_category = true
			elif current_category_index == 1 and t.is_in_group("jogadores"): is_valid_category = true
			elif current_category_index == 2 and t.is_in_group("inimigos"): is_valid_category = true
			elif current_category_index == 3 and (t.is_in_group("destructibles") or t.is_in_group("pedestrians")): is_valid_category = true
			
			if is_valid_category:
				var has_los = false
				if t == last_selected_target: 
					has_los = true
				else:
					# OTIMIZAÇÃO EXTREMA: Só faz o RayCast se o alvo estiver no seu cone frontal visual (90 graus)
					var dir_to_t = (t.global_position - car_pos).normalized()
					if rad_to_deg(car_forward.angle_to(dir_to_t)) <= 90.0:
						has_los = _has_line_of_sight(t)

				if has_los:
					category_bucket.append(t)

	var organized_bucket = []
	for t in category_bucket:
		var pos = t.global_position
		var dir = (pos - car_pos).normalized()
		var score = rad_to_deg(car_forward.angle_to(dir)) + (sqrt(car_pos.distance_squared_to(pos)) * 0.1)
		
		if t == last_selected_target: score -= 30.0
		
		organized_bucket.append({"node": t, "score": score})
	
	organized_bucket.sort_custom(func(a, b): return a.score < b.score)
	
	active_targets_sorted.clear()
	for item in organized_bucket:
		active_targets_sorted.append(item.node)

	if manual_target_index > 0:
		if is_instance_valid(last_selected_target) and active_targets_sorted.has(last_selected_target):
			manual_target_index = active_targets_sorted.find(last_selected_target)
		else:
			manual_target_index = 0 
	else:
		manual_target_index = 0

	var closest_radar_target = null
	if not active_targets_sorted.is_empty():
		manual_target_index = clampi(manual_target_index, 0, active_targets_sorted.size() - 1)
		closest_radar_target = active_targets_sorted[manual_target_index]
		last_selected_target = closest_radar_target 
	else:
		last_selected_target = null
		manual_target_index = 0
		
	current_target = null
	var active = weapons.get_active_special() if is_instance_valid(weapons) else null
	
	if is_instance_valid(closest_radar_target) and active and (active.nome == "HomingMissile" or active.nome == "GrapplingMissile" or active.nome == "FreezingMissile"):
		var dist_sq = car_pos.distance_squared_to(closest_radar_target.global_position)
		var angle = rad_to_deg(car_forward.angle_to((closest_radar_target.global_position - car_pos).normalized()))
		var lockon_sq = active.lockon_range * active.lockon_range
		if dist_sq <= lockon_sq and angle <= 45.0:
			current_target = closest_radar_target 

	if is_instance_valid(_cached_hud) and _cached_hud.has_method("update_radar_data"):
		var cat_name = target_categories[current_category_index]
		_cached_hud.update_radar_data(radar_data, closest_radar_target, car_pos, car_forward, current_category_index, cat_name)

func _atualizar_posicao_reticulo():
	if not is_instance_valid(_cached_hud) or not is_instance_valid(_cached_reticle): 
		return

	var active = weapons.get_active_special() if is_instance_valid(weapons) else null

	if active and (active.nome == "HomingMissile" or active.nome == "GrapplingMissile" or active.nome == "FreezingMissile") and is_instance_valid(current_target):
		if not is_instance_valid(_cached_camera):
			_cached_camera = get_viewport().get_camera_3d()
			
		if is_instance_valid(_cached_camera) and not _cached_camera.is_position_behind(current_target.global_position):
			var screen_pos = _cached_camera.unproject_position(current_target.global_position)
			_cached_reticle.visible = true
			_cached_reticle.global_position = _cached_hud.get_viewport().get_screen_transform() * screen_pos
		else:
			_cached_reticle.visible = false
	else:
		_cached_reticle.visible = false
