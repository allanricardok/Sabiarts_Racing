# AirMovementComponent.gd
extends Node
class_name AirMovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var trick_manager = %TrickManager # Referência ao novo componente

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
var accumulated_angle := 0.0
var last_basis : Basis
var stunt_timeout := 0.0 
var original_angular_damp : float = 0.0

func _ready():
	original_angular_damp = car.angular_damp

func _physics_process(delta):
	if not car.pode_mover: return
	var is_on_ground = check_grounded()
	
	if not is_on_ground:
		# 1. Checamos se estamos perto do chão
		var near_ground = is_near_ground()
		
		# 2. Checamos a orientação (1.0 = em pé, -1.0 = de ponta cabeça)
		var orientation_factor = car.global_transform.basis.y.dot(Vector3.UP)
		var is_upside_down = orientation_factor < 0.0
		
		# --- NOVA LÓGICA DE CANCELAMENTO ---
		# SÓ cancelamos se (estiver de ponta cabeça) E (perto do chão) E (NÃO estiver em manobra)
		if is_upside_down and near_ground and not is_doing_stunt:
			trick_manager.reset_trick()
		else:
			# Caso contrário, continua contando os pontos normalmente
			trick_manager.process_air_time(delta, near_ground)
		
		_apply_fast_fall(delta)
		
		if input.is_stunt_pressed and not is_doing_stunt:
			_check_stunt_inputs()
		
		if is_doing_stunt:
			_monitor_stunt_angle(delta)
		
		_handle_air_control(delta)
	else:
		trick_manager.check_landing(is_doing_stunt)

func _check_stunt_inputs():
	if input.steering < -0.8:
		_start_angle_stunt(Vector3(0, 0, 1), "Barrel Roll Esq")
	elif input.steering > 0.8:
		_start_angle_stunt(Vector3(0, 0, -1), "Barrel Roll Dir")
	elif input.pitch < -0.8:
		_start_angle_stunt(Vector3(1, 0, 0), "Front Flip")
	elif input.pitch > 0.8:
		_start_angle_stunt(Vector3(-1, 0, 0), "Back Flip")

func _start_angle_stunt(axis: Vector3, anim_name: String):
	is_doing_stunt = true
	accumulated_angle = 0.0
	stunt_timeout = 2.0
	current_stunt_axis = axis
	last_basis = car.global_transform.basis
	car.angular_damp = 2
	
	var impulse = axis * STUNT_IMPULSE_POWER * car.mass
	car.apply_torque_impulse(car.global_transform.basis * impulse)

func _monitor_stunt_angle(delta):
	if car.get_contact_count() > 0:
		_cancel_stunt()
		return

	var current_basis = car.global_transform.basis
	var relative_basis = last_basis.inverse() * current_basis
	var frame_angle = relative_basis.get_rotation_quaternion().get_angle()
	accumulated_angle += abs(frame_angle)
	last_basis = current_basis
	stunt_timeout -= delta

	if accumulated_angle >= (PI * 2.0) or stunt_timeout <= 0:
		_apply_stunt_brake()

func _apply_stunt_brake():
	var local_angular_vel = car.global_transform.basis.inverse() * car.angular_velocity
	var velocity_on_axis = local_angular_vel.dot(current_stunt_axis)
	var counter_impulse = -current_stunt_axis * velocity_on_axis * car.mass
	car.apply_torque_impulse(car.global_transform.basis * counter_impulse)
	
	car.angular_damp = original_angular_damp
	is_doing_stunt = false

func _handle_air_control(delta):
	var forward_in_air = max(input.throttle, 0.0)
	var move_dir = (car.global_transform.basis.x * input.steering) + (car.global_transform.basis.z * forward_in_air)
	car.apply_central_force(move_dir * AIR_CONTROL_FORCE * car.mass)
	
	car.apply_torque(-car.global_transform.basis.x * input.pitch * AIR_TORQUE_FORCE * car.mass)
	car.apply_torque(car.global_transform.basis.y * input.steering * AIR_TORQUE_FORCE * car.mass)

func _cancel_stunt():
	car.angular_damp = original_angular_damp
	is_doing_stunt = false

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
