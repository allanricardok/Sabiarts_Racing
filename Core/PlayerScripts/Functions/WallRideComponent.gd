# WallRideComponent.gd
extends Node
class_name WallRideComponent

@onready var car = owner as VehicleBody3D
@onready var input = car.get_node_or_null("%InputComponent")
@onready var trick_manager = car.get_node_or_null("%TrickManager")
@onready var air_move = car.get_node_or_null("%AirMovementComponent")

@export_group("Configurações do Wallride")
@export_flags_3d_physics var wall_collision_mask : int = 1 
@export var max_wall_distance : float = 3.5 
@export var min_speed_kmh : float = 1.0
@export var min_ground_height : float = 1.0

@export_group("Física Avançada")
@export var anti_gravity_start : float = 3.0 
@export var anti_gravity_end : float = 1.5 
@export var anti_gravity_decay_time : float = 5.0 

# --- NOVAS VARIÁVEIS DE HOVER (Levitação) ---
@export var wall_target_distance : float = 0.3 # Distância exata do centro do carro até a parede (Ajuste se as rodas entrarem no muro)
@export var wall_magnet_speed : float = 8.0 # Quão rápido ele corrige a distância (Mola)

@export var wall_forward_boost : float = 1.0 
@export var wall_turn_speed : float = 3.0 
@export var jump_up_force : float = 12.0 

@export_group("Pontuação")
@export var validation_time : float = 0.3 

var is_wallriding : bool = false
var is_exiting_wallride : bool = false 
var exit_wallride_timer : float = 0.0

var current_wall_normal : Vector3 = Vector3.ZERO
var time_in_wallride : float = 0.0
var point_tick_timer : float = 0.0
var is_validated : bool = false

var wall_lost_timer : float = 0.0
var wallride_cooldown : float = 0.0 

func _physics_process(delta):
	if not is_instance_valid(car) or not car.pode_mover: return
	if not input or not trick_manager or not air_move: return

	if wallride_cooldown > 0:
		wallride_cooldown -= delta

	if is_wallriding:
		_process_wallride(delta)
	else:
		var tried_entry = false
		if input.is_stunt_pressed:
			tried_entry = _check_wallride_entry()
			
		if is_exiting_wallride and not is_wallriding:
			_process_wallride_exit(delta)

func _check_wallride_entry() -> bool:
	if wallride_cooldown > 0: return false
	if air_move.check_grounded(): return false
	
	var speed_kmh = car.linear_velocity.length() * 3.6
	if speed_kmh < min_speed_kmh: return false
	
	var wall_info = _find_best_wall_360()
	if wall_info.has("normal"):
		var dist_ground = _get_ground_distance(Vector3.ZERO)
		if dist_ground > min_ground_height:
			_start_wallride(wall_info.normal)
			return true
	return false

func _start_wallride(normal: Vector3):
	is_wallriding = true
	is_exiting_wallride = false
	current_wall_normal = normal
	
	time_in_wallride = 0.0
	point_tick_timer = 0.0
	wall_lost_timer = 0.0
	is_validated = false 
	
	if air_move.is_doing_stunt and is_instance_valid(air_move.stunt_processor):
		air_move.stunt_processor.apply_stunt_brake()

func _process_wallride(delta):
	time_in_wallride += delta

	if not is_validated and time_in_wallride >= validation_time:
		is_validated = true
		trick_manager.add_external_action("Wallride In", 20, TrickManager.COLOR_SPECIAL)

	if not input.is_stunt_pressed:
		_stop_wallride("Botão Triângulo solto de forma limpa.")
		return

	var speed = car.linear_velocity.length()
	if (speed * 3.6) < min_speed_kmh:
		_stop_wallride("Velocidade insuficiente.")
		return

	# Offset do chão aumentado (1.5m) para garantir que o raio nunca bate na parede onde o carro está
	var dist_ground = _get_ground_distance(current_wall_normal * 1.5)
	if dist_ground <= min_ground_height:
		_stop_wallride("Atingiu o chão.")
		return

# --- RADAR DE MANUTENÇÃO ---
	var ray_start = car.global_position + (current_wall_normal * 1.5)
	var ray_dir = -current_wall_normal * (max_wall_distance * 2.0)
	var result = _shoot_ray_ignoring_holos(ray_start, ray_start + ray_dir)

	var target_vel_wall = 0.0 # Começa neutro

	if result:
		current_wall_normal = result.normal
		wall_lost_timer = 0.0 
		
		# ========================================================
		# O SEGREDO DO HOVERCRAFT (Calcula apenas se achou a parede)
		# ========================================================
		var dist_to_wall = car.global_position.distance_to(result.position)
		var error = dist_to_wall - wall_target_distance
		target_vel_wall = clamp(-error * wall_magnet_speed, -15.0, 15.0)
	else:
		wall_lost_timer += delta
		if wall_lost_timer > 0.25: 
			_stop_wallride("Radar de manutenção perdeu a parede.")
			return
		# Se estiver na tolerância da quina, o target_vel_wall continua 0.0 (desliza livre)

	# Aplica a levitação (seja a correção do Hovercraft ou o deslize neutro da quina)
	var current_vel_wall = car.linear_velocity.dot(current_wall_normal)
	car.linear_velocity -= current_wall_normal * current_vel_wall
	car.linear_velocity += current_wall_normal * target_vel_wall

	# --- FÍSICA RESTANTE ---
	var current_anti_grav = lerp(anti_gravity_start, anti_gravity_end, min(time_in_wallride / anti_gravity_decay_time, 1.0))
	var real_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	var anti_gravity = Vector3.UP * (real_gravity * car.mass * current_anti_grav)
	
	var car_fwd = -car.global_transform.basis.z.normalized()
	var forward_dir = (car_fwd - current_wall_normal * car_fwd.dot(current_wall_normal))
	if forward_dir.length_squared() < 0.01:
		forward_dir = car.global_transform.basis.y
	forward_dir = forward_dir.normalized()
	
	if abs(input.steering) > 0.05:
		forward_dir = forward_dir.rotated(current_wall_normal, -input.steering * wall_turn_speed * delta).normalized()
	
	var motor_force = Vector3.ZERO
	if input.throttle > 0:
		motor_force = forward_dir * (wall_forward_boost * car.mass * input.throttle)
		
	car.apply_central_force(anti_gravity + motor_force) # Repare que "glue" não é mais empurrada aqui!

	if input.is_jump_pressed:
		car.apply_central_impulse(Vector3.UP * jump_up_force * car.mass)
		car.apply_central_impulse(current_wall_normal * (jump_up_force * car.mass * 0.5)) 
		trick_manager.add_external_action("Wall Jump", 10, TrickManager.COLOR_SPECIAL)
		_stop_wallride("Wall-Jump executado!")
		return

	# --- ROTAÇÃO VISUAL E BLOQUEIO ---
	var z_axis = -forward_dir
	var y_axis = current_wall_normal 
	var x_axis = y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized() 
	
	var target_basis = Basis(x_axis, y_axis, z_axis)
	car.global_transform.basis = car.global_transform.basis.slerp(target_basis, delta * 15.0)
	
	car.angular_velocity = Vector3.ZERO

	if is_validated:
		point_tick_timer += delta
		if point_tick_timer >= 0.25: 
			point_tick_timer -= 0.25
			trick_manager.add_external_action("Wallride", 10, TrickManager.COLOR_SPECIAL)

func _stop_wallride(reason: String = ""):
	if not is_wallriding: return
	is_wallriding = false
	is_exiting_wallride = true
	exit_wallride_timer = 0.5 
	wallride_cooldown = 0.5 

func _process_wallride_exit(delta):
	exit_wallride_timer -= delta
	
	var is_ground_immune = (exit_wallride_timer > 0.3) 
	var is_touching_ground = air_move.check_grounded()
	
	if exit_wallride_timer <= 0 or (is_touching_ground and not is_ground_immune):
		is_exiting_wallride = false
		return

	var z_axis = car.global_transform.basis.z
	z_axis.y = 0.0 
	if z_axis.length_squared() < 0.01: 
		z_axis = car.global_transform.basis.x.cross(Vector3.UP)
	z_axis = z_axis.normalized()
	
	var y_axis = Vector3.UP
	var x_axis = y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized() 
	
	var upright_basis = Basis(x_axis, y_axis, z_axis)
	car.global_transform.basis = car.global_transform.basis.slerp(upright_basis, delta * 8.0)
	car.angular_velocity = car.angular_velocity.lerp(Vector3.ZERO, delta * 5.0)

# ==========================================
# SENSORES E RADARES AVANÇADOS
# ==========================================

func _shoot_ray_ignoring_holos(start_pos: Vector3, end_pos: Vector3) -> Dictionary:
	var space_state = car.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.exclude = [car.get_rid()]
	query.collision_mask = wall_collision_mask
	query.hit_from_inside = true 
	
	var result = {}
	for i in range(4): 
		result = space_state.intersect_ray(query)
		if not result: break
		
		if result.collider.is_in_group("ignorar_gancho") or "Holo" in result.collider.name:
			var ex = query.exclude
			ex.append(result.collider.get_rid())
			query.exclude = ex
		else:
			break 
			
	return result

func _find_best_wall_360() -> Dictionary:
	var best_normal = Vector3.ZERO
	var closest_dist = INF
	var found = false
	
	var steps = 12
	var angle_step = (PI * 2.0) / steps
	
	for i in range(steps):
		var angle = i * angle_step
		var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
		var result = _shoot_ray_ignoring_holos(car.global_position, car.global_position + (dir * max_wall_distance))
		
		if result:
			if abs(result.normal.y) < 0.4:
				var dist = car.global_position.distance_to(result.position)
				if dist < closest_dist:
					closest_dist = dist
					best_normal = result.normal
					found = true

	if found: return {"normal": best_normal}
	return {}

func _get_ground_distance(offset_from_wall: Vector3) -> float:
	var ray_start = car.global_position + offset_from_wall
	var result = _shoot_ray_ignoring_holos(ray_start, ray_start + Vector3.DOWN * 15.0)
	
	if result:
		if result.normal.y > 0.85:
			return ray_start.distance_to(result.position)
	return INF
