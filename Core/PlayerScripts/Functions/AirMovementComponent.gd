# AirMovementComponent.gd
extends Node
class_name AirMovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var trick_manager = %TrickManager

# --- PARÂMETROS ---
@export_group("Controle Aéreo")
@export var AIR_CONTROL_FORCE = 10.0
@export var AIR_TORQUE_FORCE = 20.0 
@export var EXTRA_FALL_FORCE = 25.0 
@export var FALL_FORCE_BUFFER_DISTANCE = 1.5 

@export_group("Manobras (Ângulo)")
@export var STUNT_IMPULSE_POWER := 5 

var is_doing_stunt := false
var current_stunt_axis := Vector3.ZERO
var current_trick_id := "" # NOVO: Armazena o ID para validar no final
var accumulated_angle := 0.0
var last_basis : Basis
var stunt_timeout := 0.0 
var original_angular_damp : float = 0.0
var is_slow_mo_active := false

func _ready():
	original_angular_damp = car.angular_damp

func _physics_process(delta):
	if not car.pode_mover: return
	var is_on_ground = check_grounded()
	
	if is_on_ground and is_slow_mo_active:
		_set_slow_motion(false)
	
	if not is_on_ground:
		if Input.is_action_just_pressed("slow_mo"): 
			_set_slow_motion(!is_slow_mo_active)
			get_viewport().set_input_as_handled()
	
	if not is_on_ground:
		var near_ground = is_near_ground()
		var orientation_factor = car.global_transform.basis.y.dot(Vector3.UP)
		var is_upside_down = orientation_factor < 0.0
		
		if is_upside_down and near_ground and not is_doing_stunt:
			trick_manager.reset_trick()
		else:
			trick_manager.process_air_time(delta, near_ground)
		
		_apply_fast_fall(delta)
		
		if is_doing_stunt:
			_monitor_stunt_angle(delta)
		
		_handle_air_control(delta)
	else:
		if is_doing_stunt:
			_apply_stunt_brake()
			
		trick_manager.check_landing(is_doing_stunt)

# --- CHAMADO PELO TRICKBUILDER ---
# Agora recebe o ID da manobra para saber o que validar
func execute_stunt_command(axis: Vector3, trick_id: String):
	if is_doing_stunt: return
	current_trick_id = trick_id
	_start_angle_stunt(axis)

func _start_angle_stunt(axis: Vector3):
	is_doing_stunt = true
	accumulated_angle = 0.0
	stunt_timeout = 2.0
	current_stunt_axis = axis
	last_basis = car.global_transform.basis
	
	car.angular_damp = 2.0
	
	var local_ang_vel = car.global_transform.basis.inverse() * car.angular_velocity
	if abs(axis.z) > 0.5:
		local_ang_vel.x = 0 
		local_ang_vel.y = 0
	car.angular_velocity = car.global_transform.basis * local_ang_vel

	if abs(axis.z) > 0.5:
		var nose_tilt = car.global_transform.basis.z.y 
		var correction_strength = 15.0
		var correction_impulse = car.global_transform.basis.x * (nose_tilt * car.mass * correction_strength)
		car.apply_torque_impulse(correction_impulse)
	
	var stunt_impulse = axis * STUNT_IMPULSE_POWER * car.mass
	car.apply_torque_impulse(car.global_transform.basis * stunt_impulse)

func _monitor_stunt_angle(delta):
	if car.get_contact_count() > 0:
		_apply_stunt_brake()
		return

	var current_basis = car.global_transform.basis
	var relative_basis = last_basis.inverse() * current_basis
	
	var frame_angle = relative_basis.get_rotation_quaternion().get_angle()
	accumulated_angle += abs(frame_angle)
	last_basis = current_basis
	stunt_timeout -= delta

	# Se completou o giro (PI * 1.9 para margem de erro)
	if accumulated_angle >= (PI * 1.9):
		_confirm_trick_success()
		_apply_stunt_brake()
	elif stunt_timeout <= 0:
		_apply_stunt_brake()

func _confirm_trick_success():
	# Só agora enviamos para o Manager contar os pontos!
	if current_trick_id != "" and trick_manager:
		trick_manager.add_trick_manually(current_trick_id)
		print("[AirMovement] Manobra Validada: ", current_trick_id)
	current_trick_id = ""

func _apply_stunt_brake():
	var local_angular_vel = car.global_transform.basis.inverse() * car.angular_velocity
	var velocity_on_axis = local_angular_vel.dot(current_stunt_axis)
	var counter_impulse = -current_stunt_axis * velocity_on_axis * car.mass
	car.apply_torque_impulse(car.global_transform.basis * counter_impulse)
	
	car.angular_damp = original_angular_damp
	is_doing_stunt = false
	current_trick_id = "" # Limpa o ID se a manobra falhar ou acabar o tempo
	accumulated_angle = 0.0

func _handle_air_control(delta):
	var forward_in_air = max(input.throttle, 0.0)
	var move_dir = (car.global_transform.basis.x * input.steering) + (car.global_transform.basis.z * forward_in_air)
	car.apply_central_force(move_dir * AIR_CONTROL_FORCE * car.mass)
	
	car.apply_torque(-car.global_transform.basis.x * input.pitch * AIR_TORQUE_FORCE * car.mass)
	car.apply_torque(car.global_transform.basis.y * input.steering * AIR_TORQUE_FORCE * car.mass)

func _apply_fast_fall(delta):
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
