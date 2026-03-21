# MovementComponent.gd
extends Node
class_name MovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var stats = %StatsComponent

# SINAIS PARA SINCRONIZAÇÃO
signal landed(is_clean: bool)
signal vehicle_reset() 

var _was_on_ground: bool = true

# --- PARÂMETROS ORIGINAIS PRESERVADOS ---
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
@export var SPEED_MIN_ASSIST = 15.0 
@export var SPEED_MAX_ASSIST = 180.0 
@export var STATIONARY_TURN_SPEED = 35.0 

@export_group("Recuperação")
@export var FALL_FORCE_BUFFER_DISTANCE = 1.5 
@export var REVERSE_DELAY := 0.2

var flipped_timer = 0.0
var _reverse_timer := 0.0
var _steering_hold_time := 0.0
var _drift_cooldown := 0.0 
var _drift_dir := 0.0 

func _physics_process(delta):
	if not car.pode_mover: return
	
	var is_on_ground = _check_grounded()
	var speed_mps = car.linear_velocity.length()
	var speed_kmh = speed_mps * 3.6
	
	if _drift_cooldown > 0:
		_drift_cooldown -= delta
	
	if is_on_ground and not _was_on_ground:
		var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
		landed.emit(up_dot > 0.1)
		
	_was_on_ground = is_on_ground
	
	_handle_engine_and_steering(delta, is_on_ground, speed_mps)
	_apply_dynamic_friction(speed_kmh)
	_handle_auto_flip(delta, speed_kmh)
	_apply_drag(delta)

# --- FUNÇÕES DE MOVIMENTAÇÃO ---

func _handle_engine_and_steering(delta, is_on_ground, speed_mps):
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	
	var rage = car.get_node_or_null("%RageComponent")
	var rage_speed_mult = rage.get_speed_mult() if rage else 1.0
	
	if abs(input.steering) > 0.05:
		_steering_hold_time += delta
	else:
		_steering_hold_time = 0.0
		
	var vertical_speed = abs(car.linear_velocity.y)
	var vertical_dampening = clamp(1.0 - (vertical_speed / 25.0), 0.5, 1.0)
		
	var aim_precision_ramp = clamp(_steering_hold_time / 0.4, 0.2, 1.0)
	var steer_speed = lerp(3.0, 10.0, aim_precision_ramp)
	
	var max_steer_dynamic = MAX_STEER * vertical_dampening
	car.steering = move_toward(car.steering, input.steering * max_steer_dynamic, delta * steer_speed)
	
	var speed_kmh = speed_mps * 3.6 
	var turn_dir = input.steering
	var forward_velocity = car.linear_velocity.dot(car.global_transform.basis.z)
	
	if is_on_ground:
		var is_braking_hard = (forward_velocity > 2.0 and input.throttle < -0.1)
		
		var contact_ratio = _get_grounded_ratio()
		var torque_contact_multiplier = pow(contact_ratio, 3)

		if up_dot > 0.7 and speed_kmh < SPEED_MIN_ASSIST and abs(input.steering) > 0.1 and not is_braking_hard and _drift_cooldown <= 0:
			if forward_velocity < -0.1: turn_dir = -input.steering
			
			var final_turn_speed = STATIONARY_TURN_SPEED * aim_precision_ramp * torque_contact_multiplier
			car.apply_torque(car.global_transform.basis.y * turn_dir * final_turn_speed * car.mass)	
			
		if speed_kmh >= SPEED_MIN_ASSIST and abs(input.steering) > 0.88:
			var speed_factor = clamp(speed_kmh, SPEED_MIN_ASSIST, SPEED_MAX_ASSIST)
			var dynamic_torque = remap(speed_factor, SPEED_MIN_ASSIST, SPEED_MAX_ASSIST, STEER_TORQUE_START, STEER_TORQUE_END)
			
			var high_speed_turn_dir = input.steering
			if forward_velocity < -1.0: high_speed_turn_dir = -input.steering
			
			car.apply_torque(car.global_transform.basis.y * high_speed_turn_dir * dynamic_torque * torque_contact_multiplier * car.mass)
			
		car.brake = 0.0
		var braking_forward = (forward_velocity > 0.5 and input.throttle < -0.1)
		var braking_reverse = (forward_velocity < -0.5 and input.throttle > 0.1)
		
		var holding_brake_in_cooldown = (_drift_cooldown > 0.0 and input.throttle < -0.1)
		
		if braking_forward or braking_reverse or holding_brake_in_cooldown:
			car.brake = BRAKE_POWER * abs(input.throttle)
			car.engine_force = 0.0
			
			if holding_brake_in_cooldown:
				if speed_mps < 1.0:
					car.linear_velocity = Vector3.ZERO
					car.brake = BRAKE_POWER * 5.0 
			else:
				var assist_dir = car.global_transform.basis.z * (BRAKE_ASSIST_FORCE if forward_velocity < 0 else -BRAKE_ASSIST_FORCE)
				car.apply_central_force(assist_dir * car.mass)
				
		else:
			var boost_factor = clamp(remap(speed_mps, 0, BOOST_LIMIT_SPEED, START_BOOST, 1.0), 1.0, START_BOOST)
			var speed_mult = stats.speed_multiplier if stats else 1.0
			
			var final_throttle = input.throttle
			if _drift_cooldown > 0 and final_throttle < 0:
				final_throttle = 0.0 
			
			# --- A MÁGICA DO MOTOR ACONTECE AQUI ---
			var current_engine_power = ENGINE_POWER * rage_speed_mult
			car.engine_force = final_throttle * (current_engine_power * speed_mult) * boost_factor
	else:
		car.engine_force = 0.0
		car.brake = 0.0

func _apply_dynamic_friction(speed_kmh):
	var speed_clamp = clamp(speed_kmh, 0, speed_max_friction)
	var f_rear = remap(speed_clamp, 0, speed_max_friction, friction_rear_min, friction_rear_max)
	var f_front = remap(speed_clamp, 0, speed_max_friction, friction_front_max, friction_front_min)
	
	var forward_speed = car.linear_velocity.dot(car.global_transform.basis.z)
	
	if forward_speed > 30.0 and input.throttle < -0.8 and abs(input.steering) > 0.8 and _drift_cooldown <= 0.0:
		_drift_cooldown = 1.5 
		_drift_dir = sign(input.steering) 
		
	if _drift_cooldown > 0.5: 
		var current_steer_dir = sign(input.steering)
		var steer_intensity = abs(input.steering)
		
		if steer_intensity > 0.1 and current_steer_dir == _drift_dir:
			f_rear = 0.0  
			f_front = 3.8 
			
			var smooth_spin_assist = 10.0 * steer_intensity
			car.apply_torque(car.global_transform.basis.y * _drift_dir * smooth_spin_assist * car.mass)
		else:
			f_rear = 3.5  
			f_front = 3.3 
		
	elif forward_speed < -2.0 and input.throttle > 0.1:
		f_rear = 1.0  
		f_front = 1.8 
		
	var wheels = [wheel_rear_left, wheel_rear_right, wheel_front_left, wheel_front_right]
	for wheel in wheels:
		if is_instance_valid(wheel):
			wheel.wheel_friction_slip = f_rear if (wheel == wheel_rear_left or wheel == wheel_rear_right) else f_front

# --- FUNÇÕES DE ESTADO (HELPERS) ---
	
func _get_grounded_ratio() -> float:
	var count = 0
	var wheels = [wheel_rear_left, wheel_rear_right, wheel_front_left, wheel_front_right]
	for wheel in wheels:
		if is_instance_valid(wheel) and wheel.is_in_contact():
			count += 1
	return float(count) / 4.0

func _handle_auto_flip(delta, speed_kmh):
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	if up_dot < 0.2:
		if _is_near_ground():
			flipped_timer += delta
			if flipped_timer > 0.5:
				_reset_car_orientation()
				flipped_timer = 0.0
	else:
		flipped_timer = 0.0

func _check_grounded() -> bool:
	return _get_grounded_ratio() > 0.0

func _is_near_ground() -> bool:
	var space_state = car.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(car.global_position, car.global_position + Vector3.DOWN * FALL_FORCE_BUFFER_DISTANCE, 1)
	query.exclude = [car.get_rid()]
	var result = space_state.intersect_ray(query)
	return result.size() > 0

func _reset_car_orientation():
	var current_pos = car.global_position
	var current_yaw = car.global_rotation.y 
	
	car.global_rotation = Vector3(0, current_yaw, 0)
	car.global_position = current_pos + Vector3(0, 2.5, 0)
	
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	vehicle_reset.emit()

func _apply_drag(delta):
	if car.linear_velocity.length() < 0.1: return
	
	# --- RAGE QUEBRA A BARREIRA DO AR ---
	var drag_multiplier = 1.0
	var rage = car.get_node_or_null("%RageComponent")
	
	if rage:
		var speed_buff = rage.get_speed_mult()
		if speed_buff > 1.0:
			# Se o Rage estiver dando +40% de velocidade (1.4x),
			# nós reduzimos a resistência do ar em 60% (drag fica 0.4)
			# Isso permite que o carro acelere muito além do limite normal!
			drag_multiplier = 0.6 
			
	var current_resistance = AIR_RESISTANCE * drag_multiplier
	var drag = -car.linear_velocity.normalized() * car.linear_velocity.length_squared() * current_resistance
	car.apply_central_force(drag * car.mass * delta)
