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
signal special_trick_triggered(trick_id: String)  # <-- ADICIONE ESTA LINHA no topo

# --- CONTADORES DO FIREBALL ---
var fireball_combo_count : int = 0

func setup(_parent, _car):
	parent = _parent
	car = _car
	# Conecta o sinal nativo do MovementComponent para resetar o Fireball SEMPRE que pousar!
	var move_comp = car.get_node_or_null("%MovementComponent")
	if move_comp and move_comp.has_signal("landed"):
		move_comp.landed.connect(_on_car_landed)

# Função exclusiva para limpar o estado de manobras no ar
func _on_car_landed(_is_clean: bool):
	fireball_combo_count = 0

func initiate_stunt(axis: Vector3, trick_id: String):
	current_trick_id = trick_id
	var p_mult = _get_power_mult(trick_id)
	
	if trick_id == "FIREBALL" or trick_id == "SHOCKWAVE":
		
		if trick_id == "FIREBALL":
			if fireball_combo_count >= 3:
				_emitir_falha_energia()
				return
		
		if parent._modify_energy(-ENERGY_COST_SPECIAL):
			car.play_camera_shake("Stunt")
			_confirm_trick_success()
			_apply_instant_physics(trick_id)
			special_trick_triggered.emit(trick_id)   # <-- ADICIONE ESTA LINHA
		else:
			_emitir_falha_energia()
		return
	
	if trick_id == "EMOTE":
		_start_emote_sequence(p_mult)
		return

	_start_rotation_stunt(axis, p_mult)

func _emitir_falha_energia():
	var ability = car.get_node_or_null("%AbilityComponent")
	if ability and ability.has_method("_erro_falta_energia"):
		ability._erro_falta_energia()

func _start_rotation_stunt(axis: Vector3, p_mult: float):
	print("=========================================")
	print("[STUNT PROCESSOR] 🎬 INICIANDO MANOBRA: ", current_trick_id)
	print(" -> Retirando atrito (angular_damp = 0.01)")
	
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

	var is_immune = false
	var wall_rider = car.get_node_or_null("%WallRideComponent")
	if not wall_rider: wall_rider = car.find_child("WallRideComponent", true, false)
	
	if is_instance_valid(wall_rider):
		if wall_rider.get("is_exiting_wallride") or wall_rider.get("wallride_cooldown") > 0.0:
			is_immune = true

	# =========================================================
	# CORREÇÃO: O RAIO-X DO CHÃO
	# Como não podemos ler a normal da colisão diretamente aqui, 
	# nós lançamos um raio para baixo sempre que o carro bater em algo.
	# =========================================================
	if not is_immune and car.get_contact_count() > 0:
		var bateu_no_chao = false
		var space_state = car.get_world_3d().direct_space_state
		
		# Dispara um raio de 2.5 metros do centro do carro para baixo (gravidade)
		var query = PhysicsRayQueryParameters3D.create(car.global_position, car.global_position + (Vector3.DOWN * 2.5))
		query.exclude = [car.get_rid()]
		query.hit_from_inside = true
		
		var result = space_state.intersect_ray(query)
		
		# Se atingiu algo logo abaixo e a superfície aponta para cima (chão)
		if result and result.normal.y > 0.4:
			bateu_no_chao = true
			
		# Só trava a manobra se realmente bateu as costas/teto no chão!
		if bateu_no_chao:
			apply_stunt_brake("Colisão com o CHÃO interrompeu a manobra!")
			return
	# =========================================================

	var current_basis = car.global_transform.basis
	var frame_angle = (last_basis.inverse() * current_basis).get_rotation_quaternion().get_angle()
	accumulated_angle += abs(frame_angle)
	last_basis = current_basis
	stunt_timeout -= delta

	if accumulated_angle >= (PI * 1.6) and not trickdone:
		_confirm_trick_success()
		
	if accumulated_angle >= (PI * 2):
		apply_stunt_brake("Giro completo concluído com sucesso!")
	elif stunt_timeout <= 0:
		apply_stunt_brake("Timeout estourou.")

# --- MÁQUINA DE FREIO BLINDADA ---
func apply_stunt_brake(motivo: String = "Chamada Forçada"):
	print("[STUNT PROCESSOR] 🛑 FREIO ACIONADO! Motivo: ", motivo)
	
	if is_invincible: _call_ability_shield(false)
	
	# Garante que o atrito volta ao normal SEMPRE
	car.angular_damp = parent.original_angular_damp
	print(" -> Atrito restaurado para normal: ", parent.original_angular_damp)
	
	if current_trick_id != "EMOTE" and current_trick_id != "":
		var local_vel = car.global_transform.basis.inverse() * car.angular_velocity
		local_vel -= current_stunt_axis * local_vel.dot(current_stunt_axis)
		car.angular_velocity = car.global_transform.basis * local_vel
	
	parent.is_doing_stunt = false
	current_trick_id = ""
	accumulated_angle = 0.0
	print("=========================================")

func _confirm_trick_success():
	if current_trick_id != "" and parent.trick_manager:
		parent.trick_manager.add_trick_manually(current_trick_id)
		var recovery = _get_recovery(current_trick_id)
		if recovery > 0: parent._modify_energy(recovery)
		# Cole logo antes do trickdone = true:
	get_tree().call_group("TutorialUI", "complete_task", "trick")
	trickdone = true

func _apply_instant_physics(id: String):
	if id == "FIREBALL":
		# LÓGICA DE FORÇA REDUZIDA
		var force_multiplier = pow(0.5, fireball_combo_count)
		
		var launch = (car.global_transform.basis.z * 0.1 + Vector3.UP * 1.5).normalized()
		car.apply_central_impulse(launch * (30.0 * force_multiplier) * car.mass)
		
		fireball_combo_count += 1
		
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
