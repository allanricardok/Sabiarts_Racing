extends Node
class_name WallRideMechanics

var car : VehicleBody3D

@export_group("Física Avançada")
@export var anti_gravity_start : float = 3.0 
@export var anti_gravity_end : float = 1.5 
@export var anti_gravity_decay_time : float = 5.0 

@export_group("Levitação e Impulso")
@export var wall_target_distance : float = 0.3
@export var wall_magnet_speed : float = 8.0
@export var wall_forward_boost : float = 1.0 
@export var wall_turn_speed : float = 3.0 
@export var jump_up_force : float = 12.0 

func apply_wall_physics(delta: float, current_wall_normal: Vector3, time_in_wallride: float, input_throttle: float, input_steering: float) -> Vector3:
	if not is_instance_valid(car): return current_wall_normal

	# --- FÍSICA ANTIGRAVIDADE E MOTOR ---
	var current_anti_grav = lerp(anti_gravity_start, anti_gravity_end, min(time_in_wallride / anti_gravity_decay_time, 1.0))
	var real_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	var anti_gravity = Vector3.UP * (real_gravity * car.mass * current_anti_grav)
	
	var car_fwd = -car.global_transform.basis.z.normalized()
	var forward_dir = (car_fwd - current_wall_normal * car_fwd.dot(current_wall_normal))
	
	if forward_dir.length_squared() < 0.01:
		forward_dir = car.global_transform.basis.y
		
	forward_dir = forward_dir.normalized()
	
	if abs(input_steering) > 0.05:
		forward_dir = forward_dir.rotated(current_wall_normal, -input_steering * wall_turn_speed * delta).normalized()
	
	var motor_force = Vector3.ZERO
	if input_throttle > 0:
		motor_force = forward_dir * (wall_forward_boost * car.mass * input_throttle)
		
	car.apply_central_force(anti_gravity + motor_force)

# --- ROTAÇÃO VISUAL BLINDADA (ORTHONORMALIZED + ZERO VECTOR SAFE) ---
	var z_axis = -forward_dir
	var y_axis = current_wall_normal 
	var x_axis = y_axis.cross(z_axis)
	
	# O SEGREDO AQUI: Se o produto vetorial der Zero (carro embicou reto na parede)
	if x_axis.length_squared() < 0.001:
		# Dá um micro-desvio no eixo Z só para a matemática conseguir calcular o X!
		z_axis = z_axis.rotated(Vector3.UP, 0.05).normalized()
		x_axis = y_axis.cross(z_axis)
		
	x_axis = x_axis.normalized()
	z_axis = x_axis.cross(y_axis).normalized() 
	
	var target_basis = Basis(x_axis, y_axis, z_axis).orthonormalized()
	car.global_transform.basis = car.global_transform.basis.slerp(target_basis, delta * 15.0)
	car.angular_velocity = Vector3.ZERO

	return forward_dir

func apply_wall_jump(current_wall_normal: Vector3, applied_jump_force: float):
	if not is_instance_valid(car): return
	car.apply_central_impulse(Vector3.UP * applied_jump_force * car.mass)
	car.apply_central_impulse(current_wall_normal * (applied_jump_force * car.mass * 0.5))
