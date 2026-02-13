# MovementComponent.gd
extends Node
class_name MovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var stats = %StatsComponent

# --- PARÂMETROS ---
@export_group("Física de Motor")
@export var ENGINE_POWER = 300.0
@export var MAX_STEER = 0.9
@export var BRAKE_POWER = 50.0
@export var BRAKE_ASSIST_FORCE = 25.0
@export var START_BOOST = 2.5
@export var BOOST_LIMIT_SPEED = 15.0
@export var AIR_RESISTANCE = 0.12
@export var EXTRA_FALL_FORCE = 20.0 
@export var FALL_FORCE_BUFFER_DISTANCE = 1.5 

@export_group("Fricção Dinâmica")
@export var speed_max_friction := 150.0
@export var friction_rear_min := 1.1
@export var friction_rear_max := 3.0
@export var friction_front_min := 1.1
@export var friction_front_max := 3.5

@export_group("Controle Aéreo")
@export var AIR_CONTROL_FORCE = 40.0
@export var AIR_TORQUE_FORCE = 1.0

@export_group("Rodas")
@export var wheel_rear_left: VehicleWheel3D
@export var wheel_rear_right: VehicleWheel3D
@export var wheel_front_left: VehicleWheel3D
@export var wheel_front_right: VehicleWheel3D

@export_group("Giro e Esterçamento")
@export var STEER_TORQUE_START = 8.0
@export var STEER_TORQUE_END = 2.0
@export var SPEED_MIN_ASSIST = 25.0
@export var SPEED_MAX_ASSIST = 300.0
@export var STATIONARY_TURN_SPEED = 8.0 

# --- SISTEMA DE PONTOS DE AR ---
var air_time : float = 0.0
var tracking_jump : bool = false
@onready var ability_comp = %AbilityComponent # Adicione isso logo abaixo das outras referências

var flipped_timer = 0.0
@export var REVERSE_DELAY := 0.2
var _reverse_timer := 0.0

func _physics_process(delta):
	if not car.pode_mover: return
	
	var is_on_ground = _check_grounded()
	var speed_mps = car.linear_velocity.length()
	var speed_kmh = speed_mps * 3.6
	
	_handle_engine_and_steering(delta, is_on_ground, speed_mps)
	_apply_dynamic_friction(speed_kmh)
	
	if not is_on_ground:
		_handle_air_control(delta)
		_apply_fast_fall(delta)
		_handle_air_time_logic(delta) # Lógica nova aqui
	else:
		_check_landing() # Verifica se acabamos de pousar
	
	_handle_auto_flip(delta, speed_kmh)
	_apply_drag(delta)

# --- LÓGICA DE PULO (Sem Exploit) ---

func _handle_air_time_logic(delta):
	# SÓ conta tempo se estiver REALMENTE longe do chão (Raycast não bate em nada)
	# Isso garante que se você capotar, o Raycast bate no chão e o timer não sobe.
	if not _is_near_ground():
		air_time += delta
		if air_time >= 1.1:
			tracking_jump = true
			var hud = get_tree().get_first_node_in_group("HUD")
			if hud:
				hud.atualizar_cronometro_ar(air_time)
	else:
		# Se estiver perto do chão mas sem rodas (ex: capotado), 
		# limpamos o air_time para não acumular "no teto"
		if not tracking_jump:
			air_time = 0.0
			
func _process_jump_reward():
	# Cálculo: pontos = tempo * 10
	var pontos = int(air_time * 10)
	var mensagem = ""
	
	# Sua lógica de mensagens (Mantida)
	if air_time < 1.5: mensagem = "Cool air"
	elif air_time < 2: mensagem = "Nice air!"
	elif air_time < 3: mensagem = "You are flying"
	elif air_time < 4: mensagem = "WOW LOOK AT THAT"
	else: mensagem = "911"

	# 1. Reverte em energia (Agora acessando o componente correto)
	if ability_comp:
		ability_comp.current_energy = clamp(ability_comp.current_energy + pontos, 0, ability_comp.MAX_ENERGY)
	
	# 2. Avisa a UI (HUD)
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		hud.mostrar_resultado_ar(air_time, pontos, mensagem)

# --- CONTROLE AÉREO (Restaurado e Protegido) ---

func _handle_air_control(delta):
	# Agora a movimentação aérea (Central Force) funciona sempre,
	# permitindo que você se mova mesmo perto do chão.
	var forward_in_air = max(input.throttle, 0.0)
	var move_dir = (car.global_transform.basis.x * input.steering) + (car.global_transform.basis.z * forward_in_air)
	car.apply_central_force(move_dir * AIR_CONTROL_FORCE * car.mass)
	
	# Controle de Pitch (Bico pra cima/baixo) - Liberado
	car.apply_torque(-car.global_transform.basis.x * input.pitch * AIR_TORQUE_FORCE * car.mass)
	
	# CONTROLE DE GIRO (YAW/EIXO Y):
	# Só aplicamos o torque de giro se o carro NÃO estiver capotado no chão.
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	var is_upside_down = up_dot < 0.5
	
	# Se estiver de cabeça para baixo e perto do chão, o torque de giro é desativado
	# Isso impede o "spin" no teto que gera velocidade.
	if not (is_upside_down and _is_near_ground()):
		car.apply_torque(car.global_transform.basis.y * input.steering * AIR_TORQUE_FORCE * car.mass)

# --- AUTO FLIP (Correção da Velocidade) ---

func _handle_auto_flip(delta, speed_kmh):
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	
	if up_dot < 0.7:
		# Removi a checagem de velocidade (speed_kmh < 15.0).
		# Se você está capotado e perto do chão, o timer DEVE contar,
		# não importa quão rápido você esteja girando/deslizando.
		if _is_near_ground():
			flipped_timer += delta
			if flipped_timer > 0.5: # 0.5s é um tempo seguro
				_reset_car_orientation()
				flipped_timer = 0.0
	else:
		flipped_timer = 0.0

func _check_landing():
	# Se pousou e estávamos rastreando um pulo válido (> 0.5s)
	if tracking_jump:
		_process_jump_reward()
		tracking_jump = false
	
	air_time = 0.0 # Reseta sempre que encostar no chão

func _apply_fast_fall(delta):
	if not _is_near_ground():
		var fall_force = Vector3.DOWN * EXTRA_FALL_FORCE * car.mass
		car.apply_central_force(fall_force)
		if car.linear_velocity.y < 0:
			car.apply_central_force(fall_force * 0.5)

func _is_near_ground() -> bool:
	var space_state = car.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		car.global_position, 
		car.global_position + Vector3.DOWN * FALL_FORCE_BUFFER_DISTANCE,
		1 
	)
	query.exclude = [car.get_rid()]
	var result = space_state.intersect_ray(query)
	return result.size() > 0

func _handle_engine_and_steering(delta, is_on_ground, speed_mps):
	# Cálculo para saber se o carro está em pé (1.0 = reto, < 0.5 = capotado/muito inclinado)
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	
	car.steering = move_toward(car.steering, input.steering * MAX_STEER, delta * 10)
	var speed_kmh = speed_mps * 2.0 
	var turn_dir = input.steering
	
	# 1. GIRO NO PRÓPRIO EIXO (Adicionada a trava: up_dot > 0.7)
	# Isso impede que o carro ganhe torque de giro quando estiver de cabeça para baixo
	if is_on_ground and up_dot > 0.7 and speed_kmh < SPEED_MIN_ASSIST and abs(input.steering) > 0.1:
		var forward_speed = car.linear_velocity.dot(car.global_transform.basis.z)
		
		# Inversão simples para manobra de ré
		if forward_speed < -0.1:
			turn_dir = -input.steering
			
		car.apply_torque(car.global_transform.basis.y * turn_dir * STATIONARY_TURN_SPEED * car.mass)	

	# 2. AUXÍLIO DE CURVA DINÂMICO
	if is_on_ground and speed_kmh >= SPEED_MIN_ASSIST and abs(input.steering) > 0.88:
		var speed_factor = clamp(speed_kmh, SPEED_MIN_ASSIST, SPEED_MAX_ASSIST)
		var dynamic_torque = remap(speed_factor, SPEED_MIN_ASSIST, SPEED_MAX_ASSIST, STEER_TORQUE_START, STEER_TORQUE_END)
		
		var assist_force = input.steering * dynamic_torque
		car.apply_torque(car.global_transform.basis.y * assist_force * car.mass)

	# 3. MOTOR E FREIO
	var forward_velocity = car.linear_velocity.dot(car.global_transform.basis.z)
	car.brake = 0.0
	
	if is_on_ground:
		var braking_forward = (forward_velocity > 0.5 and input.throttle < -0.1)
		var braking_reverse = (forward_velocity < -0.5 and input.throttle > 0.1)
		
		if braking_forward or braking_reverse:
			car.brake = BRAKE_POWER * abs(input.throttle)
			var assist_dir = car.global_transform.basis.z * (BRAKE_ASSIST_FORCE if forward_velocity < 0 else -BRAKE_ASSIST_FORCE)
			car.apply_central_force(assist_dir * car.mass)
			car.engine_force = 0
		else:
			var boost_factor = clamp(remap(speed_mps, 0, BOOST_LIMIT_SPEED, START_BOOST, 1.0), 1.0, START_BOOST)
			var speed_mult = stats.speed_multiplier if stats else 1.0
			car.engine_force = input.throttle * (ENGINE_POWER * speed_mult) * boost_factor
	else:
		car.engine_force = 0.0
		car.brake = 0.0

func _apply_dynamic_friction(speed_kmh):
	var speed_clamp = clamp(speed_kmh, 0, speed_max_friction)
	var f_rear = remap(speed_clamp, 0, speed_max_friction, friction_rear_min, friction_rear_max)
	var f_front = remap(speed_clamp, 0, speed_max_friction, friction_front_max, friction_front_min)
	
	var wheels = [wheel_rear_left, wheel_rear_right, wheel_front_left, wheel_front_right]
	for wheel in wheels:
		if is_instance_valid(wheel):
			wheel.wheel_friction_slip = f_rear if (wheel == wheel_rear_left or wheel == wheel_rear_right) else f_front

func _check_grounded() -> bool:
	var wheels = [wheel_rear_left, wheel_rear_right, wheel_front_left, wheel_front_right]
	for wheel in wheels:
		if is_instance_valid(wheel) and wheel.is_in_contact():
			return true
	return false

func _reset_car_orientation():
	var current_pos = car.global_position
	car.global_transform.basis = Basis.IDENTITY
	car.global_position = current_pos + Vector3(0, 2.5, 0)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO

func _apply_drag(delta):
	if car.linear_velocity.length() < 0.1: return
	var drag = -car.linear_velocity.normalized() * car.linear_velocity.length_squared() * AIR_RESISTANCE
	car.apply_central_force(drag * car.mass * delta)
