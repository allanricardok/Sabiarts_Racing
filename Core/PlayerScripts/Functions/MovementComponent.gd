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
@export var MIN_DRIFT_SPEED := 20.0 

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

@export_group("Burnout Balance")
@export var burnout_min_time: float = 0.2
@export var burnout_max_time: float = 1.5
@export var burnout_min_mult: float = 0.4
@export var burnout_max_mult: float = 2.0

@export_group("Recuperação e Manobras")
@export var FALL_FORCE_BUFFER_DISTANCE = 1.5 
@export var REVERSE_DELAY := 0.2
@export var EXTRA_FALL_GRAVITY : float = 25.0

var flipped_timer = 0.0
var _reverse_timer := 0.0
var _steering_hold_time := 0.0
var _drift_cooldown := 0.0 
var _drift_dir := 0.0 

# Variáveis de Estado do Zerinho (Burnout) e Drift
var _is_doing_burnout := false 
var _was_doing_burnout := false 
var _burnout_charge_time := 0.0 
var _burnout_smoke_timer := 0.0
var _drift_smoke_timer := 0.0 

# ==============================================================================
# OTIMIZAÇÃO: MEMÓRIA CACHE (Isso salva a CPU)
# ==============================================================================
var _rage_component: Node
var _ability_component: Node
var _burnout_meter: Node
var _camera_shake: Node
var _trick_manager: Node
var _wheels: Array[VehicleWheel3D] = []

func _ready():
	# Guarda todos os nós pesados na memória uma única vez!
	_rage_component = car.get_node_or_null("%RageComponent")
	_ability_component = car.get_node_or_null("%AbilityComponent")
	_burnout_meter = car.find_child("BurnoutMeter", true, false)
	_trick_manager = car.get_node_or_null("%TrickManager")
	
	var shakes = car.find_children("*", "CameraShake", true, false)
	if shakes.size() > 0:
		_camera_shake = shakes[0]
		
	# Array estático para não causar Garbage Collection nos frames
	if is_instance_valid(wheel_rear_left): _wheels.append(wheel_rear_left)
	if is_instance_valid(wheel_rear_right): _wheels.append(wheel_rear_right)
	if is_instance_valid(wheel_front_left): _wheels.append(wheel_front_left)
	if is_instance_valid(wheel_front_right): _wheels.append(wheel_front_right)

func _physics_process(delta):
	if not car.pode_mover: return
	
	var is_on_ground = _check_grounded()
	
	var flat_velocity = Vector3(car.linear_velocity.x, 0, car.linear_velocity.z)
	var speed_mps = flat_velocity.length()
	var speed_kmh = speed_mps * 3.6
	
	if _drift_cooldown > 0:
		_drift_cooldown -= delta
	
	if is_on_ground and not _was_on_ground:
		var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
		landed.emit(up_dot > 0.1)
		
	_was_on_ground = is_on_ground
	
	_handle_engine_and_steering(delta, is_on_ground, speed_kmh)
	_apply_dynamic_friction(delta, speed_kmh) 
	_handle_auto_flip(delta, speed_kmh)
	_apply_drag(delta)
	_apply_extra_gravity(is_on_ground)

# --- FUNÇÕES DE MOVIMENTAÇÃO ---

func _handle_engine_and_steering(delta, is_on_ground, speed_kmh):
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	
	var flat_velocity = Vector3(car.linear_velocity.x, 0, car.linear_velocity.z)
	var speed_mps = flat_velocity.length()
	
	if car.has_method("is_frozen") and car.is_frozen():
		car.engine_force = 0.0
		car.brake = BRAKE_POWER 
		car.steering = 0.0 
		return 
	
	# Usa o componente já salvo em cache
	var rage_speed_mult = _rage_component.get_speed_mult() if is_instance_valid(_rage_component) else 1.0
	
	if abs(input.steering) > 0.05:
		_steering_hold_time += delta
	else:
		_steering_hold_time = 0.0
		
	var steer_multiplier = 1.0 
	
	if speed_kmh > 30.0 and speed_kmh <= 100.0:
		steer_multiplier = remap(speed_kmh, 30.0, 100.0, 1.0, 0.6)
	elif speed_kmh > 100.0:
		steer_multiplier = 0.6
	
	var max_steer_dynamic = MAX_STEER * steer_multiplier
	var aim_precision_ramp = clamp(_steering_hold_time / 0.4, 0.2, 1.0)
	var steer_speed = lerp(3.0, 10.0, aim_precision_ramp)
	
	car.steering = move_toward(car.steering, input.steering * max_steer_dynamic, delta * steer_speed)
	
	var turn_dir = input.steering
	var forward_velocity = car.linear_velocity.dot(car.global_transform.basis.z)
	
	# LÓGICA DO ZERINHO COM SISTEMA DE CARREGAMENTO
	var holding_both_pedals = false
	if "is_accelerating" in input and "is_braking" in input:
		holding_both_pedals = input.is_accelerating and input.is_braking
		
	if holding_both_pedals:
		if not _is_doing_burnout and speed_kmh <= 130.0:
			_is_doing_burnout = true
	else:
		_is_doing_burnout = false

	var charge_ratio = 0.0 

	if _is_doing_burnout:
		_burnout_charge_time += delta
		charge_ratio = _burnout_charge_time / 1.5 
		
		# --- SCREENSHAKE DE CARREGAMENTO USANDO CACHE ---
		if is_instance_valid(_camera_shake):
			var shake_intensity = clamp(remap(_burnout_charge_time, 0.0, 1.5, 1, 12), 1, 12)
			_camera_shake.trigger_event("BurnoutCharge", shake_intensity)
			
	else:
		if _was_doing_burnout:
			if input.is_accelerating and not input.is_braking and _burnout_charge_time >= 0.2:
				var boost_mult = clamp(remap(_burnout_charge_time, burnout_min_time, burnout_max_time, burnout_min_mult, burnout_max_mult), burnout_min_mult, burnout_max_mult)				
				
				if is_instance_valid(_ability_component) and _ability_component.has_method("execute_burnout_boost"):
					_ability_component.execute_burnout_boost(boost_mult)
					
			_burnout_charge_time = 0.0
			
	_was_doing_burnout = _is_doing_burnout

	# COMUNICAÇÃO COM A NOVA BARRA VISUAL USANDO CACHE
	if is_instance_valid(_burnout_meter) and _burnout_meter.has_method("update_charge"):
		_burnout_meter.update_charge(charge_ratio)

	if is_on_ground:
		var is_braking_hard = (forward_velocity > 2.0 and input.throttle < -0.1)
		var contact_ratio = _get_grounded_ratio()
		var torque_contact_multiplier = pow(contact_ratio, 3)

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
		
		# EXECUÇÃO DA FÍSICA E FUMAÇA DO ZERINHO
		if _is_doing_burnout:
			car.engine_force = 0.0
			car.brake = BRAKE_POWER * 2.5 
			
			var rear_offset = -car.global_transform.basis.z * 1.5
			var down_force = Vector3.DOWN * car.mass * 15.0
			car.apply_force(down_force, rear_offset)
			
			if abs(input.steering) > 0.05:
				var spin_force = STATIONARY_TURN_SPEED * abs(input.steering) * torque_contact_multiplier
				car.apply_torque(car.global_transform.basis.y * sign(input.steering) * spin_force * car.mass)
				
			_burnout_smoke_timer -= delta
			if _burnout_smoke_timer <= 0.0:
				_burnout_smoke_timer = 0.2 
				_spawn_burnout_smoke()
				
		elif braking_forward or braking_reverse or holding_brake_in_cooldown:
			_burnout_smoke_timer = 0.0
			car.brake = BRAKE_POWER * abs(input.throttle)
			car.engine_force = 0.0
			
			if holding_brake_in_cooldown:
				if speed_mps < 1.0:
					car.linear_velocity = Vector3.ZERO
					car.brake = BRAKE_POWER * 15.0 
			else:
				var assist_dir = car.global_transform.basis.z * (BRAKE_ASSIST_FORCE if forward_velocity < 0 else -BRAKE_ASSIST_FORCE)
				car.apply_central_force(assist_dir * car.mass)
				
		else:
			_burnout_smoke_timer = 0.0
			var boost_factor = clamp(remap(speed_mps, 0, BOOST_LIMIT_SPEED, START_BOOST, 1.0), 1.0, START_BOOST)
			var speed_mult = stats.speed_multiplier if stats else 1.0
			
			var final_throttle = input.throttle
			if _drift_cooldown > 0 and final_throttle < 0:
				final_throttle = 0.0 
			
			var current_engine_power = ENGINE_POWER * rage_speed_mult
			car.engine_force = final_throttle * (current_engine_power * speed_mult) * boost_factor
	else:
		car.engine_force = 0.0
		car.brake = 0.0

# === HELPER: CRIA A FUMAÇA =======================================
func _spawn_burnout_smoke():
	if not is_instance_valid(ExplosionManager): return
	
	var smoke_color = Color(0.82, 0.82, 0.82, 1.0) 
	
	if is_instance_valid(wheel_rear_left):
		ExplosionManager.explode(wheel_rear_left.global_position, smoke_color, 0.0, 3, 0.0, smoke_color, 1, 0.2)
	
	if is_instance_valid(wheel_rear_right):
		ExplosionManager.explode(wheel_rear_right.global_position, smoke_color, 0.0, 3, 0.0, smoke_color, 1, 0.2)
# =================================================================

func _apply_dynamic_friction(delta, speed_kmh): 
	if car.has_method("is_frozen") and car.is_frozen():
		for wheel in _wheels:
			wheel.wheel_friction_slip = 0.1 
		return 
		
	if _is_doing_burnout:
		for wheel in _wheels:
			if wheel == wheel_rear_left or wheel == wheel_rear_right:
				wheel.wheel_friction_slip = friction_rear_min * 0.3 
			else:
				wheel.wheel_friction_slip = friction_front_max 
		return 

	var speed_clamp = clamp(speed_kmh, 0, speed_max_friction)
	var f_rear = remap(speed_clamp, 0, speed_max_friction, friction_rear_min, friction_rear_max)
	var f_front = remap(speed_clamp, 0, speed_max_friction, friction_front_max, friction_front_min)
	
	var forward_speed = car.linear_velocity.dot(car.global_transform.basis.z)
	
	if forward_speed > MIN_DRIFT_SPEED and input.throttle < -0.8 and abs(input.steering) > 0.8 and _drift_cooldown <= 0.0:
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
			
			_drift_smoke_timer -= delta
			if _drift_smoke_timer <= 0.0:
				if _drift_cooldown > 1.0:
					_drift_smoke_timer = 0.04
				else:
					_drift_smoke_timer = 0.2 
				
				_spawn_burnout_smoke()
				
		else:
			f_rear = 3.5  
			f_front = 3.3 
			_drift_smoke_timer = 0.0 
		
	elif forward_speed < -2.0 and input.throttle > 0.1:
		f_rear = 1.0  
		f_front = 1.8 
		_drift_smoke_timer = 0.0
		
	for wheel in _wheels:
		wheel.wheel_friction_slip = f_rear if (wheel == wheel_rear_left or wheel == wheel_rear_right) else f_front

func _get_grounded_ratio() -> float:
	var count = 0
	for wheel in _wheels:
		if wheel.is_in_contact():
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
	
	if is_instance_valid(_trick_manager) and _trick_manager.has_method("reset_trick"):
		_trick_manager.reset_trick()
	
	car.global_rotation = Vector3(0, current_yaw, 0)
	car.global_position = current_pos + Vector3(0, 2.5, 0)
	
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	
	vehicle_reset.emit()

func _apply_drag(delta):
	if car.linear_velocity.length() < 0.1: return
	
	var drag_multiplier = 1.0
	
	if is_instance_valid(_rage_component):
		var speed_buff = _rage_component.get_speed_mult()
		if speed_buff > 1.0:
			drag_multiplier = 1.0 / speed_buff 
			
	var current_resistance = AIR_RESISTANCE * drag_multiplier
	var drag = -car.linear_velocity.normalized() * car.linear_velocity.length_squared() * current_resistance
	car.apply_central_force(drag * car.mass * delta)

func _apply_extra_gravity(is_on_ground: bool):
	if not is_on_ground:
		car.apply_central_force(Vector3.DOWN * EXTRA_FALL_GRAVITY * car.mass)
