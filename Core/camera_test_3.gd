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
@onready var target_node = $"../CameraTarget"
@onready var car = $".."

@export_group("Suavização de Transição")
@export var transition_speed := 1.0 
@export var air_delay_threshold := 0.2 
var air_mode_weight : float = 0.0

@export_group("Colisão da Câmera")
@export var camera_collision_margin := 0.2
@export_flags_3d_physics var collision_mask = 1

@onready var trick_manager = car.get_node("%TrickManager")

var air_move : Node = null
var default_target_offset : Vector3

func _ready():
	set_as_top_level(true)
	global_position = target_node.global_position
	air_move = car.find_child("AirMovementComponent")
	default_target_offset = target_node.position

func _physics_process(delta):
	if not car or not target_node or not air_move: return

	# --- 1. LÓGICA DE OVERRIDE DE MANOBRA ---
	var is_actually_in_air = not air_move.check_grounded()
	var current_air_time = trick_manager.air_time
	var is_stunting = air_move.is_doing_stunt # Puxamos o estado da manobra

	var target_weight = 0.0
	var current_transition = transition_speed

	# Se estiver fazendo manobra, target_weight é 1.0 IMEDIATAMENTE
	if is_actually_in_air:
		if is_stunting or current_air_time > air_delay_threshold:
			target_weight = 1.0
			# Se for manobra, aceleramos a velocidade de transição para 10x mais rápido
			if is_stunting: current_transition = 15.0 
	
	air_mode_weight = lerp(air_mode_weight, target_weight, delta * current_transition)

	# --- 2. BASES E DIREÇÕES ---
	var ground_fwd = -car.global_transform.basis.z
	ground_fwd.y = clamp(ground_fwd.y, -0.5, 0.5)
	
	# No ar ou manobra, a base de referência é a velocidade (estabilizada)
	var air_fwd = -car.linear_velocity
	if air_fwd.length() < 1.0: air_fwd = ground_fwd
	air_fwd.y = 0
	
	var blended_fwd = ground_fwd.lerp(air_fwd.normalized(), air_mode_weight)
	var current_basis = Basis.looking_at(blended_fwd.normalized(), Vector3.UP)

	var real_target = target_node.global_position
	var ghost_target = car.global_position + (current_basis * default_target_offset)
	var final_target_pos = real_target.lerp(ghost_target, air_mode_weight)

	# --- 3. CÁLCULO DE POSIÇÃO LOCAL ---
	var current_local_pos = current_basis.inverse() * (global_position - car.global_position)
	var target_local_pos = current_basis.inverse() * (final_target_pos - car.global_position)

	var r_stick = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if r_stick.length() < 0.15: r_stick = Vector2.ZERO
	
	target_local_pos.x += r_stick.x * stick_sensitivity_x
	var offset_y = -r_stick.y * stick_sensitivity_y
	target_local_pos.y += clamp(offset_y, min_local_y, max_local_y)
	target_local_pos.z -= offset_y * 0.5 
	
	var final_local_pos : Vector3
	final_local_pos.x = lerp(current_local_pos.x, target_local_pos.x, delta * follow_speed_lateral)
	final_local_pos.z = lerp(current_local_pos.z, target_local_pos.z, delta * follow_speed_depth)
	final_local_pos.y = lerp(current_local_pos.y, target_local_pos.y, delta * follow_speed_vertical)

	var ideal_global_pos = current_basis * final_local_pos + car.global_position

	# --- 4. LÓGICA ANTI-CLIPPING ---
	var space_state = get_world_3d().direct_space_state
	var ray_origin = car.global_position + Vector3.UP * 0.5
	var ray_query = PhysicsRayQueryParameters3D.create(ray_origin, ideal_global_pos, collision_mask)
	ray_query.exclude = [car.get_rid()]
	
	var collision = space_state.intersect_ray(ray_query)
	
	if collision:
		global_position = collision.position + (collision.normal * camera_collision_margin)
	else:
		global_position = ideal_global_pos

	# ROTAÇÃO FINAL
	look_at(car.global_position + Vector3.UP * look_offset, Vector3.UP)
	
	# 5. FOV (Mantido conforme solicitado)
	var speed = car.linear_velocity.length()
	fov = lerpf(fov, remap(clamp(speed, 0, 60), 0, 100, 100, 100), 0.1)
