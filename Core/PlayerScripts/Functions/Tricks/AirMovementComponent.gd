# AirMovementComponent.gd (Principal)
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

# --- ESTADO COMPARTILHADO ---
var is_doing_stunt := false
var is_slow_mo_active := false
var original_angular_damp : float = 0.0

var slomo_drain_timer : float = 0.0
const SLOMO_DRAIN_INTERVAL : float = 0.1 

# --- VARIÁVEIS DE QUEDA (SHAKE) ---
var was_on_ground := true
var max_air_height := 0.0

func _ready():
	original_angular_damp = car.angular_damp
	if stunt_processor:
		stunt_processor.setup(self, car)

func _physics_process(delta):
	if not car.pode_mover: return
	
	# 1. Pega a inclinação exata do carro (1.0 = em pé, 0.0 = de lado na parede, -1.0 = teto)
	var orientation = car.global_transform.basis.y.dot(Vector3.UP)
	
	# 2. A MÁGICA: Só considera que pousou se as rodas tocarem E o carro não estiver de lado!
	# Como na parede a orientação é próxima de 0.0, ele vai ignorar as rodas raspando no muro.
	var is_on_ground = check_grounded() and (orientation > 0.4)
	
	if is_on_ground and is_slow_mo_active:
		_set_slow_motion(false)
	
	if is_slow_mo_active:
		_process_slomo_drain(delta)
	
	if not is_on_ground:
		# --- RASTREIA A ALTURA MÁXIMA NO AR ---
		max_air_height = max(max_air_height, car.global_position.y)
		_handle_air_logic(delta)
	else:
		# --- GATILHO DE POUSO (SHAKE) ---
		if not was_on_ground:
			var fall_distance = max_air_height - car.global_position.y
			if fall_distance > 10.0:
				if car.has_method("play_camera_shake"):
					car.play_camera_shake("HardLand")
			max_air_height = car.global_position.y # Reseta para o nível do chão
			
		if is_doing_stunt:
			stunt_processor.apply_stunt_brake()
		trick_manager.check_landing(is_doing_stunt)

	# Grava para o próximo frame
	was_on_ground = is_on_ground

func _process_slomo_drain(delta):
	slomo_drain_timer += delta / Engine.time_scale
	if slomo_drain_timer >= SLOMO_DRAIN_INTERVAL:
		slomo_drain_timer = 0.0
		var success = _modify_energy(-1.0)
		if not success:
			_set_slow_motion(false)

func _handle_air_logic(delta):
	if Input.is_action_just_pressed("slow_mo"): 
		if not is_slow_mo_active:
			if _modify_energy(0.0): 
				_set_slow_motion(true)
		else:
			_set_slow_motion(false)
		get_viewport().set_input_as_handled()
		
	var near_ground = is_near_ground()
	var orientation = car.global_transform.basis.y.dot(Vector3.UP)
	
	# Verifica se está no meio do Wallride
	var wall_rider = car.get_node_or_null("WallRideComponent")
	var is_wallriding = wall_rider and wall_rider.is_wallriding
	
	# O SEGREDO DO RESET: Se a orientação for < 0.2 (deitado de lado ou de ponta-cabeça)
	# e perto do chão, ele cancela a manobra IMEDIATAMENTE (ignorando se estiver em Wallride).
	if orientation < 0.2 and near_ground and not is_doing_stunt and not is_wallriding:
		trick_manager.reset_trick()
	else:
		trick_manager.process_air_time(delta, near_ground)
	
	# Desliga controles aéreos de Rotação e Queda Rápida enquanto está no muro
	if not is_wallriding:
		_apply_fast_fall(delta)
		_handle_air_control(delta)
		
		if is_doing_stunt:
			stunt_processor.process_stunt_rotation(delta)

func execute_stunt_command(axis: Vector3, trick_id: String):
	if is_doing_stunt or not stunt_processor: return
	stunt_processor.initiate_stunt(axis, trick_id)

func _modify_energy(amount: float) -> bool:
	var ability = car.get_node_or_null("%AbilityComponent")
	if not ability: return false
	
	if amount < 0: 
		if ability.current_energy >= abs(amount):
			ability.current_energy -= abs(amount)
			return true
		return false
	
	ability.current_energy = min(ability.current_energy + amount, ability.MAX_ENERGY)
	return true

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
	slomo_drain_timer = 0.0
