# AirMovementComponent.gd
extends Node
class_name AirMovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var trick_manager = %TrickManager

# --- PARÂMETROS DE CONTROLE ---
@export_group("Controle Aéreo")
@export var AIR_CONTROL_FORCE = 10.0
@export var AIR_TORQUE_FORCE = 20.0 
@export var EXTRA_FALL_FORCE = 25.0 
@export var FALL_FORCE_BUFFER_DISTANCE = 1.5 

@export_group("Multiplicadores de Manobra (Públicos)")
@export var STUNT_IMPULSE_POWER : float = 5.0
@export var ROLL_POWER_MULT : float = 1.0
@export var FLIP_POWER_MULT : float = 1.6 
@export var SPECIAL_POWER_MULT : float = 2.0

@export_group("Energia de Habilidade")
@export var ENERGY_COST_SPECIAL : float = 25.0
@export var ENERGY_RECOVERY_ROLL : float = 5.0
@export var ENERGY_RECOVERY_FLIP : float = 8.0
@export var ENERGY_RECOVERY_EMOTE : float = 10.0
@export var ENERGY_RECOVERY_SHIELD : float = 0
@export var ENERGY_RECOVERY_SPIN : float = 5.0 # Para o 360 automático

# --- ESTADO INTERNO ---
var is_doing_stunt := false
var current_stunt_axis := Vector3.ZERO
var current_trick_id := "" 
var accumulated_angle := 0.0
var last_basis : Basis
var stunt_timeout := 0.0 
var original_angular_damp : float = 0.0
var is_slow_mo_active := false
var is_invincible := false 
var trickdone = false

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
		
		var near_ground = is_near_ground()
		var orientation_factor = car.global_transform.basis.y.dot(Vector3.UP)
		if orientation_factor < 0.0 and near_ground and not is_doing_stunt:
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

# --- EXECUÇÃO DE COMANDO ---

func execute_stunt_command(axis: Vector3, trick_id: String):
	if is_doing_stunt: return
	
	current_trick_id = trick_id
	var p_mult = _get_power_mult_for_trick(trick_id)
	
	# Manobras que GASTAM (Fireball e Shockwave)
	if trick_id == "FIREBALL" or trick_id == "SHOCKWAVE":
		if _modify_energy(-ENERGY_COST_SPECIAL):
			_confirm_trick_success()
			_apply_special_instant_physics(trick_id)
		return
	
	if trick_id == "EMOTE":
		_start_emote_sequence(p_mult)
		return

	_start_angle_stunt(axis, p_mult)

# --- SISTEMA DE ENERGIA (GESTÃO CENTRALIZADA) ---

func _modify_energy(amount: float) -> bool:
	var ability = car.get_node_or_null("%AbilityComponent")
	if not ability: return false
	
	if amount < 0: # Gasto
		if ability.current_energy >= abs(amount):
			ability.current_energy -= abs(amount)
			return true
		else:
			if ability.has_method("_erro_falta_energia"):
				ability._erro_falta_energia()
			return false
	else: # Recuperação
		ability.current_energy = min(ability.current_energy + amount, ability.MAX_ENERGY)
		return true

func _get_recovery_for_trick(id: String) -> float:
	match id:
		"ROLL_L", "ROLL_R": return ENERGY_RECOVERY_ROLL
		"BACKFLIP", "FRONTFLIP": return ENERGY_RECOVERY_FLIP
		"EMOTE": return ENERGY_RECOVERY_EMOTE
		"SHIELD_SPIN": return ENERGY_RECOVERY_SHIELD
		"SPIN": return ENERGY_RECOVERY_SPIN
	return 0.0

# --- LÓGICA DE MANOBRAS ---

func _get_power_mult_for_trick(id: String) -> float:
	match id:
		"ROLL_L", "ROLL_R": return ROLL_POWER_MULT
		"BACKFLIP", "FRONTFLIP": return FLIP_POWER_MULT
		"SHIELD_SPIN": return SPECIAL_POWER_MULT
	return 1.0

func _start_angle_stunt(axis: Vector3, p_mult: float):
	is_doing_stunt = true
	accumulated_angle = 0.0
	stunt_timeout = 2.0
	current_stunt_axis = axis
	last_basis = car.global_transform.basis
	car.angular_damp = 2.0 
	trickdone = false
	
	var local_ang_vel = car.global_transform.basis.inverse() * car.angular_velocity
	if abs(axis.z) > 0.5:
		local_ang_vel.x = 0 
		local_ang_vel.y = 0
	car.angular_velocity = car.global_transform.basis * local_ang_vel

	if abs(axis.z) > 0.5:
		var nose_tilt = car.global_transform.basis.z.y 
		var correction_strength = 25.0
		var correction_impulse = car.global_transform.basis.x * (nose_tilt * car.mass * correction_strength)
		car.apply_torque_impulse(correction_impulse)
	
	var final_force = STUNT_IMPULSE_POWER * p_mult
	var stunt_impulse = axis * final_force * car.mass
	car.apply_torque_impulse(car.global_transform.basis * stunt_impulse)
	
	if current_trick_id == "SHIELD_SPIN":
		_call_ability_shield(true)

func _call_ability_shield(active: bool):
	is_invincible = active
	var ability = car.get_node_or_null("%AbilityComponent")
	if ability:
		ability._set_car_silver_effect(active)
		if ability.stats:
			ability.stats.is_invulnerable = active

func _apply_special_instant_physics(id: String):
	if id == "FIREBALL":
		var forward_component = car.global_transform.basis.z * 0.2
		var upward_component = Vector3.UP * 1.4
		var launch_dir = (forward_component + upward_component).normalized()
		car.apply_central_impulse(launch_dir * 25.0 * car.mass)
	elif id == "SHOCKWAVE":
		car.angular_velocity = Vector3.ZERO
		var current_up = car.global_transform.basis.y
		var tilt_correction = current_up.cross(Vector3.UP)
		car.apply_torque_impulse(tilt_correction * 20.0 * car.mass)
		car.apply_central_impulse(Vector3.DOWN * 40.0 * car.mass)

func _start_emote_sequence(p_mult: float):
	is_doing_stunt = true
	current_stunt_axis = Vector3.UP
	
	car.angular_damp = 2
	var impulse = Vector3.UP * (STUNT_IMPULSE_POWER * p_mult) * car.mass
	var nose_tilt = car.global_transform.basis.z.y 
	var correction_strength = 3.0
	var correction_impulse = car.global_transform.basis.x * (nose_tilt * car.mass * correction_strength)
	
	car.apply_torque_impulse(car.global_transform.basis * impulse)
	car.apply_torque_impulse(correction_impulse)
	
	await get_tree().create_timer(0.3).timeout
	if not is_doing_stunt: return 

	car.angular_velocity = Vector3.ZERO
	# Validamos o Emote aqui (Recupera energia ao chegar na pose)
	_confirm_trick_success()
	
	await get_tree().create_timer(0.4).timeout
	if not is_doing_stunt: return

	car.apply_torque_impulse(car.global_transform.basis * impulse)
	await get_tree().create_timer(0.3).timeout
	
	_apply_stunt_brake()

# --- MONITORAMENTO E VALIDAÇÃO ---

func _monitor_stunt_angle(delta):
	if current_trick_id == "EMOTE": return
	if car.get_contact_count() > 0:
		_apply_stunt_brake()
		return

	var current_basis = car.global_transform.basis
	var frame_angle = (last_basis.inverse() * current_basis).get_rotation_quaternion().get_angle()
	accumulated_angle += abs(frame_angle)
	last_basis = current_basis
	stunt_timeout -= delta

	if accumulated_angle >= (PI * 1.6) and not trickdone:
		_confirm_trick_success()
	if accumulated_angle >= (PI * 2) or stunt_timeout <= 0:
		_apply_stunt_brake()

func _confirm_trick_success():
	if current_trick_id != "" and trick_manager:
		trick_manager.add_trick_manually(current_trick_id)
		
		# --- RECUPERAÇÃO DE ENERGIA ---
		var recovery = _get_recovery_for_trick(current_trick_id)
		if recovery > 0:
			_modify_energy(recovery)
			print("[AirMove] Energia recuperada: +", recovery)
			
	trickdone = true

func _apply_stunt_brake():
	if is_invincible:
		_call_ability_shield(false)

	car.angular_damp = original_angular_damp

	if current_trick_id == "EMOTE": 
		is_doing_stunt = false
		current_trick_id = ""
		return

	var local_angular_vel = car.global_transform.basis.inverse() * car.angular_velocity
	var velocity_on_axis = local_angular_vel.dot(current_stunt_axis)
	var counter_impulse = -current_stunt_axis * velocity_on_axis * car.mass
	car.apply_torque_impulse(car.global_transform.basis * counter_impulse)
	
	is_doing_stunt = false
	current_trick_id = ""
	accumulated_angle = 0.0

# --- AUXILIARES ---

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
