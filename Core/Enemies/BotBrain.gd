# BotBrain.gd
extends Node
class_name BotBrain

enum State { WANDER, ATTACK, FLEE, SEEK_RAMP, SEEK_HEIGHT }
var current_state : State = State.WANDER

var car: BaseVehicle
var input: Node 
var stats: Node

# --- SENSORES (RAYCASTS) ---
var ray_left : RayCast3D
var ray_center : RayCast3D
var ray_right : RayCast3D
@export var ray_length : float = 20.0

# --- MEMÓRIA DO RADAR (150m) ---
var radar_timer : float = 0.0
var inimigos_proximos : Array = []
var vida_proxima : Array = []
var armas_proximas : Array = []
var rampas_proximas : Array = []
var alvo_perseguicao : Node3D = null

# --- TIMERS DE OBJETIVO ---
var timer_manobra : float = 0.0
var timer_busca_predios : float = 0.0
var timer_ataque : float = 0.0

# Timers de Perseguição no Wander
var tempo_perseguindo : float = 0.0
var tempo_alvo_perdido : float = 0.0

# Timers de Sobrevivência (Antitravamento)
var stuck_timer: float = 0.0 
var reverse_time: float = 0.0 

func _ready():
	car = get_parent() as BaseVehicle
	input = car.get_node_or_null("%InputComponent")
	stats = car.get_node_or_null("%StatsComponent")
	
	if input: input.is_bot = true

	_criar_sensores()
	_rolar_dados_de_timers()

func _rolar_dados_de_timers():
	timer_manobra = randf_range(25.0, 35.0)
	timer_busca_predios = randf_range(45.0, 120.0)
	timer_ataque = randf_range(20.0, 50.0)

func _criar_sensores():
	ray_left = RayCast3D.new()
	ray_center = RayCast3D.new()
	ray_right = RayCast3D.new()
	car.add_child(ray_left)
	car.add_child(ray_center)
	car.add_child(ray_right)
	
	var eye_height = Vector3(0, 1.0, 0)
	ray_left.position = eye_height
	ray_center.position = eye_height
	ray_right.position = eye_height
	
	ray_center.target_position = Vector3(0, 0, ray_length) 
	ray_left.target_position = Vector3(-ray_length * 0.7, 0, ray_length * 0.8)
	ray_right.target_position = Vector3(ray_length * 0.7, 0, ray_length * 0.8)
	
	ray_left.collision_mask = 1
	ray_center.collision_mask = 1
	ray_right.collision_mask = 1
	
	ray_left.add_exception(car)
	ray_center.add_exception(car)
	ray_right.add_exception(car)

func _process(delta):
	if not is_instance_valid(car) or not is_instance_valid(input) or not is_instance_valid(stats): return
	
	if not car.pode_mover or (car.has_method("is_frozen") and car.is_frozen()): 
		_reset_inputs()
		return
		
	# 1. ATUALIZA CRONÔMETROS
	timer_manobra -= delta
	timer_busca_predios -= delta
	timer_ataque -= delta
	
	# 2. RADAR: Escaneia o ambiente a cada 0.5s (Economia de Performance)
	radar_timer -= delta
	if radar_timer <= 0:
		radar_timer = 0.5
		_escanear_ambiente_150m()
		
	# 3. CÉREBRO: Decide o que fazer
	_tomar_decisao_de_estado(delta)
	
	# 4. AÇÃO: Motor e Volante baseados no Estado
	var intencoes = _executar_estado_atual()
	
	# 5. REFLEXO: Tenta não bater na parede enquanto faz a ação!
	_processar_direcao_final(delta, intencoes.throttle, intencoes.steering)

# --- RADAR ---
func _escanear_ambiente_150m():
	var car_pos = car.global_position
	var range_sq = 150.0 * 150.0 # Mais rápido calcular a distância ao quadrado
	
	inimigos_proximos.clear()
	for p in get_tree().get_nodes_in_group("jogadores"):
		if p != car and is_instance_valid(p) and p.global_position.distance_squared_to(car_pos) <= range_sq:
			inimigos_proximos.append(p)
			
	vida_proxima.clear()
	for v in get_tree().get_nodes_in_group("health_pickups"):
		if is_instance_valid(v) and v.global_position.distance_squared_to(car_pos) <= range_sq:
			vida_proxima.append(v)
			
	armas_proximas.clear()
	for a in get_tree().get_nodes_in_group("weapon_pickups"):
		if is_instance_valid(a) and a.global_position.distance_squared_to(car_pos) <= range_sq:
			armas_proximas.append(a)
			
	rampas_proximas.clear()
	for r in get_tree().get_nodes_in_group("rampas"):
		if is_instance_valid(r) and r.global_position.distance_squared_to(car_pos) <= range_sq:
			rampas_proximas.append(r)

# --- INTELIGÊNCIA DE TRANSIÇÃO ---
func _tomar_decisao_de_estado(delta):
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	var ammo_total = 0 # TODO: Puxar do WeaponManager no futuro
	
	# Regra de Sobrevivência (Sempre vence)
	if health_pct <= 30.0:
		current_state = State.FLEE
		return
		
	if current_state == State.FLEE and health_pct > 50.0:
		current_state = State.WANDER
		
	# Regra da Manobra (Vence Wander e Flee)
	if timer_manobra <= 0 and (current_state == State.WANDER or current_state == State.FLEE):
		current_state = State.SEEK_RAMP
		return
		
	# Regra da Perseguição no Wander
	if current_state == State.WANDER:
		if alvo_perseguicao != null and is_instance_valid(alvo_perseguicao):
			if alvo_perseguicao in inimigos_proximos:
				tempo_perseguindo += delta
				tempo_alvo_perdido = 0.0
				if tempo_perseguindo >= 10.0:
					alvo_perseguicao = null # Cansa de perseguir
			else:
				tempo_alvo_perdido += delta
				if tempo_alvo_perdido >= 5.0:
					alvo_perseguicao = null # Perdeu de vista
		else:
			tempo_perseguindo = 0.0
			tempo_alvo_perdido = 0.0
			# Tenta achar alguém novo
			if inimigos_proximos.size() > 0:
				alvo_perseguicao = inimigos_proximos[0]
				
	# TODO: Regras de BuscaPredios e Ataque entram aqui no futuro!

# --- EXECUÇÃO DE ESTADOS ---
func _executar_estado_atual() -> Dictionary:
	var desire_throttle = 1.0
	var desire_steering = 0.0
	
	match current_state:
		State.WANDER:
			# Passeia, mas vira na direção do alvo se estiver perseguindo!
			if alvo_perseguicao:
				desire_steering = _calcular_volante_para_alvo(alvo_perseguicao.global_position)
			else:
				desire_steering = sin(Time.get_ticks_msec() * 0.001) * 0.3
		State.FLEE:
			# Fuga simples: tenta ir para onde tiver vida
			if vida_proxima.size() > 0:
				desire_steering = _calcular_volante_para_alvo(vida_proxima[0].global_position)
			else:
				desire_throttle = 1.0
		State.SEEK_RAMP:
			if rampas_proximas.size() > 0:
				desire_steering = _calcular_volante_para_alvo(rampas_proximas[0].global_position)
			else:
				# Pula no chão mesmo e reseta!
				if input.has_method("is_action_pressed"): input.is_action_pressed = true # Finge que apertou pulo
				timer_manobra = randf_range(25.0, 35.0)
				current_state = State.WANDER
		
	return {"throttle": desire_throttle, "steering": desire_steering}

func _calcular_volante_para_alvo(alvo_pos: Vector3) -> float:
	var forward = car.global_transform.basis.z
	var dir_to_alvo = (alvo_pos - car.global_position).normalized()
	# Usa o Cross Product para saber se o alvo está na esquerda ou direita (-1 a 1)
	return forward.cross(dir_to_alvo).y * 2.0

# --- NAVEGAÇÃO E FÍSICA ---
func _processar_direcao_final(delta, intencao_throttle, intencao_steering):
	var speed = car.linear_velocity.length()
	
	if speed < 2.0 and input.throttle > 0.5: stuck_timer += delta
	else: stuck_timer = 0.0
		
	if stuck_timer > 1.2:
		reverse_time = 1.5
		stuck_timer = 0.0
		
	if reverse_time > 0:
		reverse_time -= delta
		input.throttle = -1.0
		input.steering = 1.0 
		return 
		
	var steer_final = intencao_steering
	var is_avoiding = false
	var final_throttle = intencao_throttle
	
	ray_left.force_raycast_update()
	ray_center.force_raycast_update()
	ray_right.force_raycast_update()
	
	if ray_center.is_colliding():
		is_avoiding = true
		final_throttle = 0.4 
		if not ray_left.is_colliding(): steer_final = -1.0 
		elif not ray_right.is_colliding(): steer_final = 1.0 
		else: steer_final = 1.0 
	elif ray_left.is_colliding():
		is_avoiding = true
		steer_final = 1.0 
	elif ray_right.is_colliding():
		is_avoiding = true
		steer_final = -1.0 

	input.throttle = final_throttle
	if is_avoiding: input.steering = lerp(input.steering, steer_final, delta * 8.0)
	else: input.steering = clamp(steer_final, -1.0, 1.0)

func _reset_inputs():
	input.throttle = 0.0
	input.steering = 0.0
	input.is_action_pressed = false
