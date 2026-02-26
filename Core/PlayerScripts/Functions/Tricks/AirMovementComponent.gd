# AirMovementComponent.gd (Principal)
extends Node
class_name AirMovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var trick_manager = %TrickManager
@onready var stunt_processor = $StuntProcessor # Referência ao auxiliar

# --- PARÂMETROS DE VOO ---
@export_group("Controle Aéreo")
@export var AIR_CONTROL_FORCE = 10.0
@export var AIR_TORQUE_FORCE = 20.0 
@export var EXTRA_FALL_FORCE = 25.0 
@export var FALL_FORCE_BUFFER_DISTANCE = 1.5 

# --- ESTADO COMPARTILHADO ---
var is_doing_stunt := false
var is_slow_mo_active := false
var original_angular_damp : float = 0.0

func _ready():
	original_angular_damp = car.angular_damp
	# Garante que o processador conheça o carro
	if stunt_processor:
		stunt_processor.setup(self, car)

func _physics_process(delta):
	if not car.pode_mover: return
	var is_on_ground = check_grounded()
	
	if is_on_ground and is_slow_mo_active:
		_set_slow_motion(false)
	
	if not is_on_ground:
		_handle_air_logic(delta)
	else:
		if is_doing_stunt:
			stunt_processor.apply_stunt_brake()
		trick_manager.check_landing(is_doing_stunt)

func _handle_air_logic(delta):
	if Input.is_action_just_pressed("slow_mo"): 
		_set_slow_motion(!is_slow_mo_active)
		get_viewport().set_input_as_handled()
		
	var near_ground = is_near_ground()
	var orientation = car.global_transform.basis.y.dot(Vector3.UP)
	
	if orientation < 0.0 and near_ground and not is_doing_stunt:
		trick_manager.reset_trick()
	else:
		trick_manager.process_air_time(delta, near_ground)
	
	_apply_fast_fall(delta)
	_handle_air_control(delta)
	
	if is_doing_stunt:
		stunt_processor.process_stunt_rotation(delta)

# --- PONTE DE COMANDO (Mantém compatibilidade externa) ---

func execute_stunt_command(axis: Vector3, trick_id: String):
	if is_doing_stunt or not stunt_processor: return
	stunt_processor.initiate_stunt(axis, trick_id)

func _modify_energy(amount: float) -> bool:
	var ability = car.get_node_or_null("%AbilityComponent")
	if not ability: return false
	
	if amount < 0: # Gasto
		if ability.current_energy >= abs(amount):
			ability.current_energy -= abs(amount)
			return true
		elif ability.has_method("_erro_falta_energia"):
			ability._erro_falta_energia()
		return false
	
	ability.current_energy = min(ability.current_energy + amount, ability.MAX_ENERGY)
	return true

# --- AUXILIARES DE FÍSICA ---

func _handle_air_control(delta):
	var forward_in_air = max(input.throttle, 0.0)
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
	query.exclude = [car.get_rid()]
	return space_state.intersect_ray(query).size() > 0

func check_grounded() -> bool:
	for child in car.get_children():
		if child is VehicleWheel3D and child.is_in_contact(): return true
	return false

func _set_slow_motion(active: bool):
	is_slow_mo_active = active
	Engine.time_scale = 0.2 if active else 1.0
