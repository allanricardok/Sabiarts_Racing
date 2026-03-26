# StuntProcessor.gd (Auxiliar)
extends Node
class_name StuntProcessor

var parent : AirMovementComponent
var car : VehicleBody3D

@export_group("Multiplicadores de Manobra")
@export var STUNT_IMPULSE_POWER : float = 16.0
@export var ROLL_POWER_MULT : float = 1.2
@export var FLIP_POWER_MULT : float = 1.8 
@export var SPECIAL_POWER_MULT : float = 3.0

@export_group("Energia de Habilidade")
@export var ENERGY_COST_SPECIAL : float = 20.0
@export var ENERGY_RECOVERY_ROLL : float = 5.0
@export var ENERGY_RECOVERY_FLIP : float = 8.0
@export var ENERGY_RECOVERY_EMOTE : float = 10.0
@export var ENERGY_RECOVERY_SHIELD : float = 0.0
@export var ENERGY_RECOVERY_SPIN : float = 5.0

# Estado Interno
var current_trick_id := ""
var current_stunt_axis := Vector3.ZERO
var accumulated_angle := 0.0
var last_basis : Basis
var stunt_timeout := 0.0
var trickdone := false
var is_invincible := false

func setup(_parent, _car):
	parent = _parent
	car = _car

func initiate_stunt(axis: Vector3, trick_id: String):
	current_trick_id = trick_id
	var p_mult = _get_power_mult(trick_id)
	
	# --- TRUQUES ESPECIAIS COM CUSTO ---
	if trick_id == "FIREBALL" or trick_id == "SHOCKWAVE":
		if parent._modify_energy(-ENERGY_COST_SPECIAL):
			_confirm_trick_success()
			_apply_instant_physics(trick_id)
		else:
			# NOVO: Se falhar o gasto de energia, dispara o feedback visual
			var ability = car.get_node_or_null("%AbilityComponent")
			if ability and ability.has_method("_erro_falta_energia"):
				ability._erro_falta_energia()
		return
	
	if trick_id == "EMOTE":
		_start_emote_sequence(p_mult)
		return

	_start_rotation_stunt(axis, p_mult)

func _start_rotation_stunt(axis: Vector3, p_mult: float):
	parent.is_doing_stunt = true
	accumulated_angle = 0.0
	stunt_timeout = 2.0
	current_stunt_axis = axis
	last_basis = car.global_transform.basis
	car.angular_damp = 0.01
	trickdone = false
	
	var local_ang_vel = car.global_transform.basis.inverse() * car.angular_velocity
	if abs(axis.z) > 0.5: local_ang_vel.x = 0; local_ang_vel.y = 0
	car.angular_velocity = car.global_transform.basis * local_ang_vel

	if abs(axis.z) > 0.5:
		var nose_tilt = car.global_transform.basis.z.y 
		var correction_impulse = car.global_transform.basis.x * (nose_tilt * car.mass * 5.0)
		car.apply_torque_impulse(correction_impulse)
	
	var stunt_impulse = axis * (STUNT_IMPULSE_POWER * p_mult*1.5) * car.mass
	car.apply_torque_impulse(car.global_transform.basis * stunt_impulse)
	
	if current_trick_id == "SHIELD_SPIN": _call_ability_shield(true)

func process_stunt_rotation(delta):
	if current_trick_id == "EMOTE": return
	if car.get_contact_count() > 0:
		apply_stunt_brake()
		return

	var current_basis = car.global_transform.basis
	var frame_angle = (last_basis.inverse() * current_basis).get_rotation_quaternion().get_angle()
	accumulated_angle += abs(frame_angle)
	last_basis = current_basis
	stunt_timeout -= delta

	if accumulated_angle >= (PI * 1.6) and not trickdone:
		_confirm_trick_success()
	if accumulated_angle >= (PI * 2) or stunt_timeout <= 0:
		apply_stunt_brake()

func _confirm_trick_success():
	if current_trick_id != "" and parent.trick_manager:
		parent.trick_manager.add_trick_manually(current_trick_id)
		var recovery = _get_recovery(current_trick_id)
		if recovery > 0: parent._modify_energy(recovery)
	trickdone = true

func apply_stunt_brake():
	if is_invincible: _call_ability_shield(false)
	car.angular_damp = parent.original_angular_damp
	
	if current_trick_id != "EMOTE":
		# Pegamos a velocidade de giro atual do carro
		var local_vel = car.global_transform.basis.inverse() * car.angular_velocity
		
		# --- CORREÇÃO DO FREIO ---
		# Em vez de aplicar um empurrão contrário, nós simplesmente subtraímos 
		# a velocidade daquele eixo específico (zerando o giro da manobra).
		# Isso mantém intactas outras forças (como você virando o volante).
		local_vel -= current_stunt_axis * local_vel.dot(current_stunt_axis)
		
		# Devolvemos a velocidade limpa para o carro
		car.angular_velocity = car.global_transform.basis * local_vel
	
	parent.is_doing_stunt = false
	current_trick_id = ""
	accumulated_angle = 0.0

func _apply_instant_physics(id: String):
	if id == "FIREBALL":
		var launch = (car.global_transform.basis.z * 0.1 + Vector3.UP * 1.5).normalized()
		car.apply_central_impulse(launch * 30.0 * car.mass)
	elif id == "SHOCKWAVE":
		car.angular_velocity = Vector3.ZERO
		car.apply_torque_impulse(car.global_transform.basis.y.cross(Vector3.UP) * 20.0 * car.mass)
		car.apply_central_impulse(Vector3.DOWN * 40.0 * car.mass)

func _start_emote_sequence(p_mult: float):
	parent.is_doing_stunt = true
	current_stunt_axis = Vector3.UP
	car.angular_damp = 0.1
	var impulse = Vector3.UP * (STUNT_IMPULSE_POWER * p_mult * 4.8) * car.mass
	car.apply_torque_impulse(car.global_transform.basis * impulse)
	car.apply_torque_impulse(car.global_transform.basis.x * (car.global_transform.basis.z.y * car.mass * 5.0))
	
	await get_tree().create_timer(0.1).timeout
	if not parent.is_doing_stunt: return
	car.angular_velocity = Vector3.ZERO
	_confirm_trick_success()
	await get_tree().create_timer(0.25).timeout
	if not parent.is_doing_stunt: return
	car.apply_torque_impulse(car.global_transform.basis * impulse)
	await get_tree().create_timer(0.1).timeout
	apply_stunt_brake()

func _call_ability_shield(active: bool):
	is_invincible = active
	var ability = car.get_node_or_null("%AbilityComponent")
	if ability:
		ability._set_car_silver_effect(active)
		if ability.stats: ability.stats.is_invulnerable = active

func _get_power_mult(id) -> float:
	match id:
		"ROLL_L", "ROLL_R": return ROLL_POWER_MULT
		"BACKFLIP", "FRONTFLIP": return FLIP_POWER_MULT
		"SHIELD_SPIN": return SPECIAL_POWER_MULT
	return 1.0

func _get_recovery(id) -> float:
	match id:
		"ROLL_L", "ROLL_R": return ENERGY_RECOVERY_ROLL
		"BACKFLIP", "FRONTFLIP": return ENERGY_RECOVERY_FLIP
		"EMOTE": return ENERGY_RECOVERY_EMOTE
		"SHIELD_SPIN": return ENERGY_RECOVERY_SHIELD
		"SPIN": return ENERGY_RECOVERY_SPIN
	return 0.0
