# MovementComponent.gd
extends Node
class_name MovementComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var stats = %StatsComponent

# --- PARÂMETROS RESGATADOS E EXPANDIDOS ---
@export_group("Física de Motor")
@export var ENGINE_POWER = 300.0
@export var MAX_STEER = 0.9
@export var BRAKE_POWER = 50.0
@export var BRAKE_ASSIST_FORCE = 25.0
@export var START_BOOST = 2.5        # Multiplicador de arrancada
@export var BOOST_LIMIT_SPEED = 15.0 # Até que velocidade o boost atua
@export var AIR_RESISTANCE = 0.12
@export var EXTRA_FALL_FORCE = 20.0 # Ajuste este valor para controlar a velocidade da queda
@export var FALL_FORCE_BUFFER_DISTANCE = 2.5 # Distância em metros para parar a força

@export_group("Fricção Dinâmica")
@export var speed_max_friction := 150.0
@export var friction_rear_min := 1.1
@export var friction_rear_max := 3.0
@export var friction_front_min := 1.1
@export var friction_front_max := 3.5

@export_group("Controle Aéreo")
@export var AIR_CONTROL_FORCE = 40.0
@export var AIR_TORQUE_FORCE = 1.0

# Rodas (Conectar no Inspector para precisão, senão o código busca auto)
@export var wheel_rear_left: VehicleWheel3D
@export var wheel_rear_right: VehicleWheel3D
@export var wheel_front_left: VehicleWheel3D
@export var wheel_front_right: VehicleWheel3D

@export_group("Giro e Esterçamento")
@export var STEER_TORQUE_FORCE = 5.0 # Força extra de rotação em movimento
@export var STATIONARY_TURN_SPEED = 8.0 # Velocidade do giro parado (estilo tanque)

var jump_count = 0
var flipped_timer = 0.0
var pode_resetar_pulo: bool = true

func _physics_process(delta):
	if not car.pode_mover: return
	
	var is_on_ground = _check_grounded()
	var speed_mps = car.linear_velocity.length()
	var speed_kmh = speed_mps * 3.6
	
	_handle_engine_and_steering(delta, is_on_ground, speed_mps)
	_apply_dynamic_friction(speed_kmh)
	
	if not is_on_ground:
		_handle_air_control(delta)
		_apply_fast_fall(delta) # <--- Nova função aqui
	
	_handle_auto_flip(delta, speed_kmh)
	_apply_drag(delta)

func _apply_fast_fall(delta):
	# Só aplicamos a força se NÃO estivermos perto do chão
	if not _is_near_ground():
		var fall_force = Vector3.DOWN * EXTRA_FALL_FORCE * car.mass
		car.apply_central_force(fall_force)
		
		# Força extra se já estiver caindo (velocidade Y negativa)
		if car.linear_velocity.y < 0:
			car.apply_central_force(fall_force * 0.5)
#	if _is_near_ground():
#		var fall_force = Vector3.DOWN * EXTRA_FALL_FORCE * car.mass
#		car.apply_central_force(fall_force * -1)


func _is_near_ground() -> bool:
	# Criamos um Raycast virtual que aponta para baixo
	var space_state = car.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		car.global_position, 
		car.global_position + Vector3.DOWN * FALL_FORCE_BUFFER_DISTANCE,
		1 # Layer de colisão do chão (ajuste se necessário)
	)
	
	# Ignora o próprio carro na detecção
	query.exclude = [car.get_rid()]
	
	var result = space_state.intersect_ray(query)
	
	# Se o resultado tiver algo, significa que o chão está perto
	return result.size() > 0

func _handle_engine_and_steering(delta, is_on_ground, speed_mps):
	# 1. Esterçamento Visual/Físico das rodas
	car.steering = move_toward(car.steering, input.steering * MAX_STEER, delta * 10)
	
	var speed_kmh = speed_mps * 2.6
	var turn_dir = input.steering
	
	# 2. GIRO NO PRÓPRIO EIXO (Parado)
	if is_on_ground and speed_kmh < 30.0 and abs(input.steering) > 0.1:
	# 1. Calculamos a velocidade relativa ao bico do carro
	# Positivo = Indo para frente | Negativo = Indo para trás
		var forward_speed = car.linear_velocity.dot(car.global_transform.basis.z)
		turn_dir = input.steering
	# 2. SE o vetor de movimento for negativo (está se movendo para trás)
	# Invertemos o torque para o bico girar conforme a direção da tela
		if forward_speed < -0.1:
			turn_dir = -input.steering
		car.apply_torque(car.global_transform.basis.y * turn_dir * STATIONARY_TURN_SPEED * car.mass)	
	# 3. AUXÍLIO DE CURVA (Em Movimento)
	if is_on_ground and speed_kmh >= 20.0 and abs(input.steering) > 0.7:
		# Aplica um torque extra para o bico do carro virar mais rápido
		var assist_force = input.steering * STEER_TORQUE_FORCE * (speed_mps / 10.0)
		car.apply_torque(car.global_transform.basis.y * assist_force * car.mass)
	# 2. Lógica de Motor e Freio
	var forward_velocity = car.linear_velocity.dot(car.global_transform.basis.z)
	car.brake = 0.0
	
	if is_on_ground:
		# FREIO ASSISTIDO (Contra-fluxo)
		var braking_forward = (forward_velocity > 0.5 and input.throttle < -0.1)
		var braking_reverse = (forward_velocity < -0.5 and input.throttle > 0.1)
		
		if braking_forward or braking_reverse:
			car.brake = BRAKE_POWER * abs(input.throttle)
			var assist_dir = car.global_transform.basis.z * (BRAKE_ASSIST_FORCE if forward_velocity < 0 else -BRAKE_ASSIST_FORCE)
			car.apply_central_force(assist_dir * car.mass)
			car.engine_force = 0
		else:
			# ACELERAÇÃO COM BOOST DE ARRANCADA
			var boost_factor = remap(speed_mps, 0, BOOST_LIMIT_SPEED, START_BOOST, 1.0)
			boost_factor = clamp(boost_factor, 1.0, START_BOOST)
			
			var speed_mult = stats.speed_multiplier if stats else 1.0
			car.engine_force = input.throttle * (ENGINE_POWER * speed_mult) * boost_factor
	else:
		car.engine_force = 0.0
		car.brake = 0.0

func _apply_dynamic_friction(speed_kmh):
	var speed_clamp = clamp(speed_kmh, 0, speed_max_friction)
	var f_rear = remap(speed_clamp, 0, speed_max_friction, friction_rear_min, friction_rear_max)
	var f_front = remap(speed_clamp, 0, speed_max_friction, friction_front_max, friction_front_min)
	
	# Se as rodas não foram arrastadas no Inspector, tentamos achar por nome
	var wheels = [wheel_rear_left, wheel_rear_right, wheel_front_left, wheel_front_right]
	for wheel in wheels:
		if is_instance_valid(wheel):
			if wheel == wheel_rear_left or wheel == wheel_rear_right:
				wheel.wheel_friction_slip = f_rear
			else:
				wheel.wheel_friction_slip = f_front

func _handle_air_control(delta):
	# 1. EMPUXO E MOVIMENTAÇÃO LATERAL NO AR
	var forward_in_air = max(input.throttle, 0.0) # Sem ré no ar
	var move_dir = (car.global_transform.basis.x * input.steering) + (car.global_transform.basis.z * forward_in_air)
	car.apply_central_force(move_dir * AIR_CONTROL_FORCE * car.mass)
	
	# 2. TORQUE (PITCH E GIRO)
	# Pitch (Bicada)
	car.apply_torque(car.global_transform.basis.x * input.pitch * AIR_TORQUE_FORCE * car.mass)
	# Yaw (Giro lateral)
	car.apply_torque(car.global_transform.basis.y * input.steering * AIR_TORQUE_FORCE * car.mass)

func _check_grounded() -> bool:
	for child in car.get_children():
		if child is VehicleWheel3D and child.is_in_contact():
			return true
	return false

func _handle_auto_flip(delta, speed_kmh):
	# Pegamos o vetor "Cima" do carro e comparamos com o "Cima" do mundo
	var up_dot = car.global_transform.basis.y.dot(Vector3.UP)
	
	# Se o carro estiver inclinado mais de 60 graus (up_dot < 0.5) 
	# e quase parado (menos de 10 km/h)
	if up_dot < 0.5 and speed_kmh < 15.0:
		flipped_timer += delta
		
		# Se ficar 2 segundos "capotado" ou de lado
		if flipped_timer > 0.5:
			_reset_car_orientation()
			flipped_timer = 0.0
	else:
		# Se o carro voltar ao normal sozinho ou acelerar, reseta o tempo
		flipped_timer = 0.0

func _reset_car_orientation():
	# Força a rotação a ficar reta (Identity) sem perder a posição X e Z
	var current_pos = car.global_position
	
	# Resetamos a base da matriz (rotação e escala) para o padrão
	car.global_transform.basis = Basis.IDENTITY
	
	# Levantamos o carro um pouco para não nascer dentro do chão
	car.global_position = current_pos + Vector3(0, 2.5, 0)
	
	# Zera as velocidades para evitar que o carro "quique" ao resetar
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	
	print("Auto-flip executado: Brasília desvirada!")

func _apply_drag(delta):
	if car.linear_velocity.length() < 0.1: return
	var drag = -car.linear_velocity.normalized() * car.linear_velocity.length_squared() * AIR_RESISTANCE
	car.apply_central_force(drag * car.mass * delta)
