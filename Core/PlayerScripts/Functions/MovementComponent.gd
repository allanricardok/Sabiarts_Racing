# MovementComponent.gd
extends Node
class_name MovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var stats = %StatsComponent

# --- PARÂMETROS DE MOTOR E FÍSICA ---
@export_group("Física de Motor")
@export var ENGINE_POWER = 3200.0
@export var MAX_STEER = 0.35
@export var BRAKE_POWER = 20.0
@export var BRAKE_ASSIST_FORCE = 45.0
@export var START_BOOST = 4.5
@export var BOOST_LIMIT_SPEED = 35.0
@export var AIR_RESISTANCE = 0.1

@export_group("Fricção Dinâmica")
@export var speed_max_friction := 160.0
@export var friction_rear_min := 2.0
@export var friction_rear_max := 3.0
@export var friction_front_min := 3.3
@export var friction_front_max := 3.8

@export_group("Rodas")
@export var wheel_rear_left: VehicleWheel3D
@export var wheel_rear_right: VehicleWheel3D
@export var wheel_front_left: VehicleWheel3D
@export var wheel_front_right: VehicleWheel3D

@export_group("Giro e Esterçamento")
@export var STEER_TORQUE_START = 15.0
@export var STEER_TORQUE_END = 5.0
@export var SPEED_MIN_ASSIST = 25.0
@export var SPEED_MAX_ASSIST = 180.0
@export var STATIONARY_TURN_SPEED = 35.0 

@export_group("Recuperação")
@export var FALL_FORCE_BUFFER_DISTANCE = 1.5 
@export var REVERSE_DELAY := 0.2

var flipped_timer = 0.0
var _reverse_timer := 0.0

func _physics_process(delta):
	if not car.pode_mover: return
	
	var is_on_ground = _check_grounded()
	var speed_mps = car.linear_velocity.length()
	var speed_kmh = speed_mps * 3.6
	
	# Lógica de Solo
	_handle_engine_and_steering(delta, is_on_ground, speed_mps)
	_apply_dynamic_friction(speed_kmh)
	
	# Auxiliares de Solo/Física Geral
	_handle_auto_flip(delta, speed_kmh)
	_apply_drag(delta)

# --- FUNÇÕES DE MOVIMENTAÇÃO PADRÃO ---

func _handle_engine_and_steering(delta, is_on_ground, speed_mps):
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	car.steering = move_toward(car.steering, input.steering * MAX_STEER, delta * 10)
	
	var speed_kmh = speed_mps * 2.0 
	var turn_dir = input.steering
	
	if is_on_ground:
		# 1. GIRO NO PRÓPRIO EIXO (Estacionário)
		if up_dot > 0.7 and speed_kmh < SPEED_MIN_ASSIST and abs(input.steering) > 0.1:
			var forward_speed = car.linear_velocity.dot(car.global_transform.basis.z)
			if forward_speed < -0.1:
				turn_dir = -input.steering
			car.apply_torque(car.global_transform.basis.y * turn_dir * STATIONARY_TURN_SPEED * car.mass)	

		# 2. AUXÍLIO DE CURVA DINÂMICO
		if speed_kmh >= SPEED_MIN_ASSIST and abs(input.steering) > 0.88:
			var speed_factor = clamp(speed_kmh, SPEED_MIN_ASSIST, SPEED_MAX_ASSIST)
			var dynamic_torque = remap(speed_factor, SPEED_MIN_ASSIST, SPEED_MAX_ASSIST, STEER_TORQUE_START, STEER_TORQUE_END)
			var assist_force = input.steering * dynamic_torque
			car.apply_torque(car.global_transform.basis.y * assist_force * car.mass)

		# 3. MOTOR E FREIO
		var forward_velocity = car.linear_velocity.dot(car.global_transform.basis.z)
		car.brake = 0.0
		
		var braking_forward = (forward_velocity > 0.5 and input.throttle < -0.1)
		var braking_reverse = (forward_velocity < -0.5 and input.throttle > 0.1)
		
		if braking_forward or braking_reverse:
			car.brake = BRAKE_POWER * abs(input.throttle)
			var assist_dir = car.global_transform.basis.z * (BRAKE_ASSIST_FORCE if forward_velocity < 0 else -BRAKE_ASSIST_FORCE)
			car.apply_central_force(assist_dir * car.mass)
			car.engine_force = 0
		else:
			var boost_factor = clamp(remap(speed_mps, 0, BOOST_LIMIT_SPEED, START_BOOST, 1.0), 1.0, START_BOOST)
			var speed_mult = stats.speed_multiplier if stats else 1.0
			car.engine_force = input.throttle * (ENGINE_POWER * speed_mult) * boost_factor
	else:
		car.engine_force = 0.0
		car.brake = 0.0

func _apply_dynamic_friction(speed_kmh):
	var speed_clamp = clamp(speed_kmh, 0, speed_max_friction)
	var f_rear = remap(speed_clamp, 0, speed_max_friction, friction_rear_min, friction_rear_max)
	var f_front = remap(speed_clamp, 0, speed_max_friction, friction_front_max, friction_front_min)
	
	var wheels = [wheel_rear_left, wheel_rear_right, wheel_front_left, wheel_front_right]
	for wheel in wheels:
		if is_instance_valid(wheel):
			wheel.wheel_friction_slip = f_rear if (wheel == wheel_rear_left or wheel == wheel_rear_right) else f_front

func _handle_auto_flip(delta, speed_kmh):
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	if up_dot < 0.7:
		if _is_near_ground():
			flipped_timer += delta
			if flipped_timer > 0.5:
				_reset_car_orientation()
				flipped_timer = 0.0
	else:
		flipped_timer = 0.0

func _check_grounded() -> bool:
	var wheels = [wheel_rear_left, wheel_rear_right, wheel_front_left, wheel_front_right]
	for wheel in wheels:
		if is_instance_valid(wheel) and wheel.is_in_contact():
			return true
	return false

func _is_near_ground() -> bool:
	var space_state = car.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		car.global_position, 
		car.global_position + Vector3.DOWN * FALL_FORCE_BUFFER_DISTANCE,
		1 
	)
	query.exclude = [car.get_rid()]
	var result = space_state.intersect_ray(query)
	return result.size() > 0

func _reset_car_orientation():
	var current_pos = car.global_position
	car.global_transform.basis = Basis.IDENTITY
	car.global_position = current_pos + Vector3(0, 2.5, 0)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO

func _apply_drag(delta):
	if car.linear_velocity.length() < 0.1: return
	var drag = -car.linear_velocity.normalized() * car.linear_velocity.length_squared() * AIR_RESISTANCE
	car.apply_central_force(drag * car.mass * delta)
