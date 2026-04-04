# TargetingComponent.gd
extends Node3D
class_name TargetingComponent

# --- SISTEMA DE ALVOS TÁTICO ---
var target_categories = ["All Targets", "Adversaries", "Fuckers", "Environment"]
# MODIFICADO: Agora começa direto no índice 1 (Adversaries) em vez de 0.
var current_category_index : int = 1 
var manual_target_index : int = 0
var active_targets_sorted : Array = []
var force_target_all : bool = false

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

func setup_multiplayer(suffix: String):
	player_suffix = suffix
	call_deferred("_validate_initial_category")

func _process(delta):
	if not is_instance_valid(car) or not car.pode_mover: return
	
	var real_delta = delta / Engine.time_scale if car.is_in_group("jogadores") else delta
	
	if Input.is_action_just_pressed("cat_left" + input.suffix): _cycle_category(-1)
	if Input.is_action_just_pressed("cat_right" + input.suffix): _cycle_category(1)
	if Input.is_action_just_pressed("target_up" + input.suffix): _cycle_target(-1)
	if Input.is_action_just_pressed("target_down" + input.suffix): _cycle_target(1)

	radar_update_timer -= real_delta
	if radar_update_timer <= 0:
		radar_update_timer = RADAR_UPDATE_INTERVAL
		_update_radar_and_lockon()
		
	_atualizar_posicao_reticulo()

func _cycle_category(direction: int):
	for i in range(4): 
		current_category_index += direction
		if current_category_index > 3: current_category_index = 0
		elif current_category_index < 0: current_category_index = 3
		
		if _get_category_count(current_category_index) > 0: break
	
	manual_target_index = 0 
	_update_radar_and_lockon() 
	print("[Targeting] Categoria alterada para: ", target_categories[current_category_index])
		
func _get_category_count(index: int) -> int:
	var count = 0
	if index == 0: return 1 
	elif index == 1:
		for p in get_tree().get_nodes_in_group("jogadores"):
			if p != car and is_instance_valid(p): count += 1
	elif index == 2:
		for t in get_tree().get_nodes_in_group("inimigos"):
			if is_instance_valid(t): count += 1
	elif index == 3:
		for p in get_tree().get_nodes_in_group("destructibles"):
			if is_instance_valid(p): count += 1
	return count

func _validate_initial_category():
	if _get_category_count(current_category_index) == 0:
		_cycle_category(1)

func _cycle_target(direction: int):
	if active_targets_sorted.is_empty(): return
	
	manual_target_index += direction
	if manual_target_index >= active_targets_sorted.size(): manual_target_index = 0
	elif manual_target_index < 0: manual_target_index = active_targets_sorted.size() - 1
	
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
	
	var all_players = get_tree().get_nodes_in_group("jogadores")
	var all_turrets = get_tree().get_nodes_in_group("inimigos")
	var all_props = get_tree().get_nodes_in_group("destructibles")
	var all_peds = get_tree().get_nodes_in_group("pedestrians")
	
	var all_targets = all_players + all_turrets + all_props + all_peds
	var car_pos = car.global_position
	var car_forward = car.global_transform.basis.z 
	
	var radar_data = []
	var category_bucket = [] 

	for t in all_targets:
		if not is_instance_valid(t) or t == car: continue
		if t.is_in_group("pedestrians") and "is_invincible" in t and t.is_invincible: continue
			
		var dist = car_pos.distance_to(t.global_position)
		
		if dist <= radar_range or t.is_in_group("jogadores") or t.is_in_group("inimigos"):
			if not t.is_in_group("pedestrians"): radar_data.append(t)
			
			if _has_line_of_sight(t):
				if current_category_index == 0: category_bucket.append(t)
				elif current_category_index == 1 and t.is_in_group("jogadores"): category_bucket.append(t)
				elif current_category_index == 2 and t.is_in_group("inimigos"): category_bucket.append(t)
				elif current_category_index == 3 and (t.is_in_group("destructibles") or t.is_in_group("pedestrians")): category_bucket.append(t)

	category_bucket.sort_custom(func(a, b):
		var pos_a = a.global_position
		var pos_b = b.global_position
		var dir_a = (pos_a - car_pos).normalized()
		var score_a = rad_to_deg(car_forward.angle_to(dir_a)) + (car_pos.distance_to(pos_a) * 0.1)
		var dir_b = (pos_b - car_pos).normalized()
		var score_b = rad_to_deg(car_forward.angle_to(dir_b)) + (car_pos.distance_to(pos_b) * 0.1)
		return score_a < score_b
	)
	
	active_targets_sorted = category_bucket
	var closest_radar_target = null
	
	if not active_targets_sorted.is_empty():
		manual_target_index = clampi(manual_target_index, 0, active_targets_sorted.size() - 1)
		closest_radar_target = active_targets_sorted[manual_target_index]
		
	current_target = null
	var active = weapons.get_active_special() if is_instance_valid(weapons) else null
	
	if is_instance_valid(closest_radar_target) and active and (active.nome == "HomingMissile" or active.nome == "GrapplingMissile" or active.nome == "FreezingMissile"):
		var dist = car_pos.distance_to(closest_radar_target.global_position)
		var angle = rad_to_deg(car_forward.angle_to((closest_radar_target.global_position - car_pos).normalized()))
		if dist <= active.lockon_range and angle <= 45.0:
			current_target = closest_radar_target 

	var hud = get_tree().get_first_node_in_group("HUD" + player_suffix)
	if hud and hud.has_method("update_radar_data"):
		var cat_name = target_categories[current_category_index]
		hud.update_radar_data(radar_data, closest_radar_target, car_pos, car_forward, current_category_index, cat_name)

func _atualizar_posicao_reticulo():
	var active = weapons.get_active_special() if is_instance_valid(weapons) else null
	var hud = get_tree().get_first_node_in_group("HUD" + player_suffix)
	
	if not hud: return
	var reticle = hud.find_child("Reticle", true, false)
	if not reticle: return

	if active and (active.nome == "HomingMissile" or active.nome == "GrapplingMissile" or active.nome == "FreezingMissile") and is_instance_valid(current_target):
		var camera = get_viewport().get_camera_3d()
		if camera and not camera.is_position_behind(current_target.global_position):
			var screen_pos = camera.unproject_position(current_target.global_position)
			reticle.visible = true
			reticle.global_position = hud.get_viewport().get_screen_transform() * screen_pos
		else:
			reticle.visible = false
	else:
		reticle.visible = false
