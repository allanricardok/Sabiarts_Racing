extends Camera3D

@export_group("Velocidades de Seguimento")
@export var follow_speed_lateral := 4.0
@export var follow_speed_depth := 15.0
@export var follow_speed_vertical := 20.0

@export_group("Configurações do Analógico")
@export var stick_sensitivity_x := 5.0 
@export var stick_sensitivity_y := 2.5 

@export_group("Configurações Look Back")
@export var look_back_distance_multiplier := 1.2 
@export var look_back_height_offset := 0.5

@export_group("Limites de Segurança")
@export var min_local_y := -0.8 
@export var max_local_y := 8.0 
@export var look_offset := 1.0

@export_group("Suavização de Transição")
@export var transition_speed := 1.0 
@export var air_delay_threshold := 0.2 
var air_mode_weight : float = 0.0

@export_group("Colisão da Câmera")
@export var camera_collision_margin := 0.2
@export_flags_3d_physics var collision_mask = 1

@onready var target_node = $"../CameraTarget"
@onready var car = $".."
@onready var input = car.get_node_or_null("%InputComponent")
@onready var trick_manager = car.get_node_or_null("%TrickManager")

@export_group("Efeitos de Velocidade e Turbo")
@export var speed_pullback_max := 2.0 
@export var speed_pullback_min_kmh := 40.0
@export var speed_pullback_max_kmh := 150.0
@export var reverse_pullback_mult := 0.2 
@export var turbo_kickback_recovery := 0.8 

@export var turbo_kickback_force := 3.0 
@export var turbo_fov_increase := 20.0 

var current_turbo_kickback := 0.0
var current_turbo_fov := 0.0

var air_move : Node = null
var default_target_offset : Vector3

var original_target_offset : Vector3
var original_look_offset : float
var current_camera_mode : int = 0

# OTIMIZAÇÃO: Cache de Identidade e RID
var _is_bot: bool = false
var _car_rid: RID

func _ready():
	original_target_offset = target_node.position
	default_target_offset = original_target_offset
	original_look_offset = look_offset
	set_as_top_level(true)
	global_position = target_node.global_position
	air_move = car.find_child("AirMovementComponent", true, false)
	_car_rid = car.get_rid()
	
	call_deferred("_late_bot_check")

func _late_bot_check():
	if is_instance_valid(input) and "is_bot" in input and input.is_bot:
		_is_bot = true
		# A MÁGICA DE PERFORMANCE AQUI: O bot ignora 100% o processamento desta câmera e desliga ela
		set_physics_process(false)
		current = false

func set_camera_mode(mode: int):
	current_camera_mode = mode
	match mode:
		0: 
			target_node.position = original_target_offset
			default_target_offset = original_target_offset
			look_offset = original_look_offset
		1: 
			var capo_pos = Vector3(0, 1.3, 1.3) 
			if "hood_camera_pos" in car:
				capo_pos = car.hood_camera_pos
				
			target_node.position = capo_pos
			default_target_offset = capo_pos
			look_offset = 0.0
		2: 
			var far_offset = Vector3(0, 3, -5) 
			if "far_camera_offset" in car:
				far_offset = car.far_camera_offset
				
			var far_pos = original_target_offset + far_offset
			target_node.position = far_pos
			default_target_offset = far_pos
			look_offset = original_look_offset + 0.5

func _physics_process(delta):
	if not car or not target_node or not air_move or not input: return

	current_turbo_kickback = lerp(current_turbo_kickback, 0.0, delta * turbo_kickback_recovery)
	current_turbo_fov = lerp(current_turbo_fov, 0.0, delta * turbo_kickback_recovery)

	if current_camera_mode == 1:
		var hood_global = car.global_transform * default_target_offset
		global_position = hood_global
		
		if input.is_look_behind_pressed:
			look_at(hood_global + (-car.global_transform.basis.z * 10.0), Vector3.UP)
		else:
			look_at(hood_global + (car.global_transform.basis.z * 10.0), Vector3.UP)
			
		var spd = car.linear_velocity.length()
		var base_fov = remap(clamp(spd, 0, 60), 0, 100, 100, 100)
		fov = lerpf(fov, base_fov + current_turbo_fov, 0.1)
		
		return 

	# ====================================================================
	# CORREÇÃO: Usando a nova função do AirMovementComponent
	# Se tiver menos de 3 rodas no chão, consideramos que está "no ar"
	# ====================================================================
	var is_actually_in_air = air_move.get_grounded_wheels_count() < 3
	
	var current_air_time = trick_manager.air_time if is_instance_valid(trick_manager) else 0.0
	var is_stunting = air_move.is_doing_stunt 
	var is_looking_back = input.is_look_behind_pressed 

	var target_weight = 0.0
	var current_transition = transition_speed

	if is_actually_in_air:
		if is_stunting or current_air_time > air_delay_threshold:
			target_weight = 1.0
			if is_stunting: current_transition = 15.0 
			
	air_mode_weight = lerp(air_mode_weight, target_weight, delta * current_transition)

	var ground_fwd = -car.global_transform.basis.z
	ground_fwd.y = clamp(ground_fwd.y, -0.5, 0.5)
	
	var air_fwd = -car.linear_velocity
	if air_fwd.length_squared() < 1.0: air_fwd = ground_fwd
	air_fwd.y = 0
	
	var blended_fwd = ground_fwd.lerp(air_fwd.normalized(), air_mode_weight)
	var current_basis = Basis.looking_at(blended_fwd.normalized(), Vector3.UP)

	var ghost_target = car.global_position + (current_basis * default_target_offset)
	var final_target_pos = target_node.global_position.lerp(ghost_target, air_mode_weight)

	var current_local_pos = current_basis.inverse() * (global_position - car.global_position)
	var target_local_pos = current_basis.inverse() * (final_target_pos - car.global_position)

	if is_looking_back:
		target_local_pos.z = -target_local_pos.z * look_back_distance_multiplier
		target_local_pos.y += look_back_height_offset

	var look_dir = input.look_vector
	target_local_pos.x += look_dir.x * stick_sensitivity_x
	var offset_y = -look_dir.y * stick_sensitivity_y
	target_local_pos.y += clamp(offset_y, min_local_y, max_local_y)
	target_local_pos.z -= offset_y * 0.5 
	
	var forward_vel = car.global_transform.basis.z.dot(car.linear_velocity)
	var speed_kmh = abs(forward_vel) * 2.3
	
	var is_reversing = forward_vel < -1.0
	
	var speed_offset = 0.0
	if speed_kmh > speed_pullback_min_kmh:
		speed_offset = clamp(remap(speed_kmh, speed_pullback_min_kmh, speed_pullback_max_kmh, 0.0, speed_pullback_max), 0.0, speed_pullback_max)
		if is_reversing:
			speed_offset *= reverse_pullback_mult 
			
	target_local_pos.z -= (speed_offset + current_turbo_kickback)
	
	var final_local_pos : Vector3
	if is_looking_back:
		final_local_pos = target_local_pos
	else:
		final_local_pos.x = lerp(current_local_pos.x, target_local_pos.x, delta * follow_speed_lateral)
		final_local_pos.z = lerp(current_local_pos.z, target_local_pos.z, delta * follow_speed_depth)
		final_local_pos.y = lerp(current_local_pos.y, target_local_pos.y, delta * follow_speed_vertical)

	var ideal_global_pos = current_basis * final_local_pos + car.global_position

	var space_state = get_world_3d().direct_space_state
	var ray_origin = car.global_position + Vector3.UP * 0.5
	var ray_query = PhysicsRayQueryParameters3D.create(ray_origin, ideal_global_pos, collision_mask)
	# OTIMIZAÇÃO: Usar o RID em cache!
	ray_query.exclude = [_car_rid]
	var collision = space_state.intersect_ray(ray_query)
	
	if collision:
		global_position = collision.position + (collision.normal * camera_collision_margin)
	else:
		global_position = ideal_global_pos

	look_at(car.global_position + Vector3.UP * look_offset, Vector3.UP)
	
	var speed = car.linear_velocity.length()
	var base_fov = remap(clamp(speed, 0, 60), 0, 100, 100, 100) 
	fov = lerpf(fov, base_fov + current_turbo_fov, 0.1)
	
func apply_turbo_kickback():
	if _is_bot: return
	current_turbo_kickback = turbo_kickback_force
	current_turbo_fov = turbo_fov_increase
