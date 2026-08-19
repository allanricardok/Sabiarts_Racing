extends Node
class_name AirMovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var trick_manager = %TrickManager
@onready var stunt_processor = $StuntProcessor 

# --- PARÂMETROS DE VOO ---
@export_group("Controle Aéreo")
@export var AIR_CONTROL_FORCE = 10.0
@export var AIR_TORQUE_FORCE = 20.0 
@export var EXTRA_FALL_FORCE = 25.0 
@export var FALL_FORCE_BUFFER_DISTANCE = 1.5 

# --- MEMÓRIA DO WALLRIDE (OVERRIDE) ---
var was_wallriding_internal := false
var wallride_immunity_timer := 0.0
var wallride_drop_immunity_timer : float = 0.0

# --- ESTADO COMPARTILHADO ---
var is_doing_stunt := false
var original_angular_damp : float = 0.0

# --- VARIÁVEIS DE QUEDA (SHAKE) ---
var was_on_ground := true
var max_air_height := 0.0

# ==============================================================================
# OTIMIZAÇÃO: MEMÓRIA CACHE
# ==============================================================================
var _wall_rider: Node
var _ability_component: Node
var _wheels: Array[VehicleWheel3D] = []
var _car_rid: RID

func _ready():
	original_angular_damp = car.angular_damp
	if stunt_processor:
		stunt_processor.setup(self, car)
		
	_wall_rider = car.get_node_or_null("%WallRideComponent")
	_ability_component = car.get_node_or_null("%AbilityComponent")
	_car_rid = car.get_rid()
	
	for child in car.get_children():
		if child is VehicleWheel3D:
			_wheels.append(child)

func _physics_process(delta):
	if not car.pode_mover: return
	
	var orientation = car.global_transform.basis.y.dot(Vector3.UP)
			
	var is_wallriding = false
	var time_out_of_wall = 999.0
	
	if is_instance_valid(_wall_rider):
		is_wallriding = _wall_rider.get("is_wallriding")
		time_out_of_wall = _wall_rider.get("time_since_last_wallride")
	
	var is_on_ground = false
	var is_transfer_protected = (time_out_of_wall < 0.5) and input.is_stunt_pressed and (orientation > 0.3)
	
	var grounded_wheels = get_grounded_wheels_count()
	
	if not is_wallriding and not is_transfer_protected:
		is_on_ground = (grounded_wheels >= 3) and (orientation > 0.3)
	
	if not is_on_ground:
		max_air_height = max(max_air_height, car.global_position.y)
		var is_coyote_air_active = (time_out_of_wall < 1.0) and (orientation > 0.3)
		
		_handle_air_logic(delta, is_coyote_air_active, grounded_wheels)
	else:
		if not was_on_ground:
			var fall_distance = max_air_height - car.global_position.y
			if fall_distance > 10.0:
				if car.has_method("play_camera_shake"):
					car.play_camera_shake("HardLand")
			max_air_height = car.global_position.y
			
		var is_clean = (orientation > 0.3) and not is_doing_stunt
			
		if is_doing_stunt:
			stunt_processor.apply_stunt_brake("Pouso no asfalto detectado.")
			
		trick_manager.check_landing(is_clean)

	was_on_ground = is_on_ground

func _handle_air_logic(delta, forcing_coyote: bool, grounded_wheels: int):
	var near_ground = false if forcing_coyote else is_near_ground()
	
	trick_manager.process_air_time(delta, near_ground)
	
	var is_riding = is_instance_valid(_wall_rider) and _wall_rider.get("is_wallriding")
	
	if not is_riding:
		_apply_fast_fall(delta)
		_handle_air_control(delta, grounded_wheels)
		
		if is_doing_stunt:
			stunt_processor.process_stunt_rotation(delta)

func get_grounded_wheels_count() -> int:
	if car.linear_velocity.y > 2.0:
		return 0

	var space_state = car.get_world_3d().direct_space_state
	var wheels_on_ground = 0
	
	for wheel in _wheels:
		if is_instance_valid(wheel) and wheel.is_in_contact():
			var ray_dist = wheel.wheel_radius + 0.2
			var query = PhysicsRayQueryParameters3D.create(wheel.global_position, wheel.global_position + (Vector3.DOWN * ray_dist))
			query.exclude = [_car_rid]
			query.hit_from_inside = true
			
			var result = space_state.intersect_ray(query)
			
			if result and result.normal.y > 0.8:
				wheels_on_ground += 1
				
	return wheels_on_ground

func execute_stunt_command(axis: Vector3, trick_id: String):
	if is_doing_stunt:
		return
		
	if trick_id in ["BACKFLIP", "FRONTFLIP", "ROLL_L", "ROLL_R"]:
		if is_too_close_for_flip():
			print("[AirMovement] FLIP BLOQUEADO (A menos de 4m do chão)! Área livre para mirar o Manual.")
			return
		
	if not stunt_processor: return
	stunt_processor.initiate_stunt(axis, trick_id)

func _modify_energy(amount: float) -> bool:
	if not is_instance_valid(_ability_component): return false
	
	if amount < 0: 
		if _ability_component.current_energy >= abs(amount):
			_ability_component.current_energy -= abs(amount)
			return true
		return false
	
	_ability_component.current_energy = min(_ability_component.current_energy + amount, _ability_component.MAX_ENERGY)
	return true

func _handle_air_control(delta, grounded_wheels: int):
	var forward_in_air = max(input.throttle, 0.0)
	
	if grounded_wheels > 0:
		forward_in_air = 0.0
		
	var move_dir = (car.global_transform.basis.x * input.steering) + (car.global_transform.basis.z * forward_in_air)
	car.apply_central_force(move_dir * AIR_CONTROL_FORCE * car.mass)
	car.apply_torque(-car.global_transform.basis.x * input.pitch * AIR_TORQUE_FORCE * car.mass)
	car.apply_torque(car.global_transform.basis.y * input.steering * AIR_TORQUE_FORCE * car.mass)

func _apply_fast_fall(_delta):
	if not is_near_ground():
		car.apply_central_force(Vector3.DOWN * EXTRA_FALL_FORCE * car.mass)

func is_near_ground() -> bool:
	var space_state = car.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(car.global_position, car.global_position + Vector3.DOWN * FALL_FORCE_BUFFER_DISTANCE, 1)
	query.exclude = [_car_rid]
	return space_state.intersect_ray(query).size() > 0

func is_too_close_for_flip() -> bool:
	var space_state = car.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(car.global_position, car.global_position + (Vector3.DOWN * 4.0), 1)
	query.exclude = [_car_rid]
	return space_state.intersect_ray(query).size() > 0
