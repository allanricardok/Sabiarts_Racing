# BotBrain.gd
extends Node
class_name BotBrain

enum State { 
	WANDER_IDLE, 
	WANDER_CHASE, 
	WANDER_AMMO, 
	ATTACK, 
	FLEE, 
	SEEK_RAMP, 
	SEEK_HEIGHT 
}
var current_state : State = State.WANDER_IDLE
var tempo_no_estado : float = 0.0 

var car: BaseVehicle
var input: Node 
var stats: Node

# --- SENSORES (RAYCASTS) ---
var ray_left : RayCast3D
var ray_center : RayCast3D
var ray_right : RayCast3D
@export var ray_length : float = 20.0

# --- MEMÓRIA DO RADAR ---
var radar_timer : float = 0.0
var inimigos_proximos : Array = []
var vida_proxima : Array = []
var armas_proximas : Array = []
var rampas_proximas : Array = []

var alvo_atual : Node3D = null
var itens_ignorados : Array = [] 

# --- TIMERS DE OBJETIVO E STATUS ---
var timer_manobra : float = 0.0
var timer_busca_predios : float = 0.0

var chase_repeats : int = 0
var is_agressive : bool = false 

var stuck_timer: float = 0.0 
var reverse_time: float = 0.0 
var doing_stunt_timer: float = 0.0 
var debug_print_timer: float = 0.0

func _ready():
	car = get_parent() as BaseVehicle
	input = car.get_node_or_null("%InputComponent")
	stats = car.get_node_or_null("%StatsComponent")
	
	if input: input.is_bot = true

	_criar_sensores()
	_rolar_dados_de_timers()

func _rolar_dados_de_timers():
	timer_manobra = randf_range(15.0, 30.0)
	timer_busca_predios = randf_range(25.0, 60.0)

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
		
	tempo_no_estado += delta
	
	# MANOBRA NO AR (Bloqueia o pensamento)
	if doing_stunt_timer > 0:
		doing_stunt_timer -= delta
		input.throttle = 1.0
		input.pitch = 1.0 
		input.is_action_pressed = true 
		return
		
	if current_state != State.FLEE and current_state != State.ATTACK:
		if current_state != State.SEEK_RAMP: timer_manobra -= delta
		if current_state != State.SEEK_HEIGHT: timer_busca_predios -= delta
		
	radar_timer -= delta
	if radar_timer <= 0:
		radar_timer = 0.5
		_escanear_ambiente_150m()
		
	_tomar_decisao_de_estado()
	_gerenciar_habilidades_do_bot()
	_gerenciar_armas_do_bot()
	
	var intencoes = _executar_estado_atual(delta)
	_processar_direcao_final(delta, intencoes.throttle, intencoes.steering)
	_process_debug(delta)

func _mudar_estado(novo_estado: State):
	if current_state != novo_estado:
		print("[DEBUG BOT] ", car.name, " MUDOU DE ESTADO: ", State.keys()[current_state], " -> ", State.keys()[novo_estado])
		current_state = novo_estado
		tempo_no_estado = 0.0

# --- RADAR ---
func _escanear_ambiente_150m():
	var car_pos = car.global_position
	var range_sq = 150.0 * 150.0 
	
	itens_ignorados = itens_ignorados.filter(func(i): return is_instance_valid(i))
	
	# BUG CORRIGIDO: Limite de Altura (Eixo Y) para não focar em itens no teto
	var max_y_diff_items = 5.0
	var max_y_diff_players = 10.0 # Um pouco mais tolerante para inimigos na rampa
	
	inimigos_proximos.clear()
	var range_enemy_sq = 250.0 * 250.0 
	for p in get_tree().get_nodes_in_group("jogadores"):
		if p != car and is_instance_valid(p) and p.global_position.distance_squared_to(car_pos) <= range_enemy_sq:
			if abs(p.global_position.y - car_pos.y) <= max_y_diff_players:
				inimigos_proximos.append(p)
			
	vida_proxima.clear()
	var search_range_health = (250.0 * 250.0) if current_state == State.FLEE else range_sq
	for v in get_tree().get_nodes_in_group("health_pickups"):
		if is_instance_valid(v) and v.global_position.distance_squared_to(car_pos) <= search_range_health and not v in itens_ignorados:
			if abs(v.global_position.y - car_pos.y) <= max_y_diff_items:
				vida_proxima.append(v)
			
	armas_proximas.clear()
	for a in get_tree().get_nodes_in_group("weapon_pickups"):
		if is_instance_valid(a) and a.global_position.distance_squared_to(car_pos) <= range_sq and not a in itens_ignorados:
			if abs(a.global_position.y - car_pos.y) <= max_y_diff_items:
				armas_proximas.append(a)
			
	rampas_proximas.clear()
	var search_range_ramp = (250.0 * 250.0) if current_state == State.SEEK_HEIGHT else range_sq
	for r in get_tree().get_nodes_in_group("rampas"):
		if is_instance_valid(r) and r.global_position.distance_squared_to(car_pos) <= search_range_ramp:
			if abs(r.global_position.y - car_pos.y) <= max_y_diff_items:
				rampas_proximas.append(r)

func _get_total_ammo() -> int:
	var ammo = 0
	var wm = car.get_node_or_null("%WeaponManager")
	if wm:
		for w in wm.weapon_pool: ammo += w.ammo
	return ammo

# --- INTELIGÊNCIA DE TRANSIÇÃO ---
func _tomar_decisao_de_estado():
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	var ammo_total = _get_total_ammo()
	
	if ammo_total > 7: is_agressive = true
	else: is_agressive = false
	
	if health_pct < 40.0:
		_mudar_estado(State.FLEE)
		return
		
	if current_state == State.FLEE and health_pct > 50.0:
		_mudar_estado(State.WANDER_IDLE)
		return
		
	if is_agressive and inimigos_proximos.size() > 0:
		alvo_atual = inimigos_proximos[0]
		_mudar_estado(State.ATTACK)
		return
		
	if timer_busca_predios <= 0:
		_mudar_estado(State.SEEK_HEIGHT)
		return
		
	if timer_manobra <= 0:
		_mudar_estado(State.SEEK_RAMP)
		return
		
	if ammo_total <= 7 and armas_proximas.size() > 0:
		_mudar_estado(State.WANDER_AMMO)
		return
		
	if inimigos_proximos.size() > 0 and chase_repeats < 5:
		alvo_atual = inimigos_proximos[0]
		_mudar_estado(State.WANDER_CHASE)
		return
	
	if inimigos_proximos.is_empty(): 
		chase_repeats = 0 
		
	_mudar_estado(State.WANDER_IDLE)

func _gerenciar_habilidades_do_bot():
	input.is_attribute_pressed = false
	input.ability_up = false
	input.ability_down = false
	input.ability_left = false
	input.ability_right = false
	
	var ability = car.get_node_or_null("%AbilityComponent")
	if not ability or ability.current_cooldown > 0: return
	
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	
	if current_state == State.FLEE or health_pct < 40.0:
		if ability.current_energy >= ability.COST_SHIELD:
			input.is_attribute_pressed = true
			input.ability_right = true
			return
			
	if current_state == State.FLEE or (current_state == State.ATTACK and is_instance_valid(alvo_atual) and car.global_position.distance_to(alvo_atual.global_position) > 40.0):
		if ability.current_energy >= ability.COST_BOOST:
			input.is_attribute_pressed = true
			input.ability_up = true
			return

func _gerenciar_armas_do_bot():
	input.is_action_pressed = false 
	if current_state == State.ATTACK and is_instance_valid(alvo_atual):
		var wm = car.get_node_or_null("%WeaponManager")
		if not wm: return
		
		input.is_action_pressed = true 
		var active_w = wm.get_active_special()
		if active_w and wm.special_cooldowns.get(active_w.nome, 0.0) <= 0:
			var ev = InputEventAction.new()
			ev.action = "Fire" + input.suffix
			ev.pressed = true
			Input.parse_input_event(ev)

# --- EXECUÇÃO DE ESTADOS ---
func _executar_estado_atual(delta) -> Dictionary:
	var desire_throttle = 1.0
	var desire_steering = 0.0
	input.pitch = 0.0
	
	match current_state:
		State.WANDER_IDLE:
			desire_steering = sin(Time.get_ticks_msec() * 0.001) * 0.3
			
		State.WANDER_AMMO:
			if armas_proximas.size() > 0: 
				var alvo_arma = armas_proximas[0]
				if is_instance_valid(alvo_arma):
					var nav = _direcionar_para_coletavel(alvo_arma, delta)
					desire_steering = nav.steering
					desire_throttle = nav.throttle
				else: armas_proximas.remove_at(0) 
			
		State.WANDER_CHASE:
			if is_instance_valid(alvo_atual):
				desire_steering = _calcular_volante_para_alvo(alvo_atual.global_position)
			if tempo_no_estado >= 5.0:
				tempo_no_estado = 0.0 
				if inimigos_proximos.has(alvo_atual): chase_repeats += 1
				else: chase_repeats = 5 
					
		State.ATTACK:
			if is_instance_valid(alvo_atual):
				desire_steering = _calcular_volante_para_alvo(alvo_atual.global_position)
				
				var forward = car.global_transform.basis.z
				var dir = (alvo_atual.global_position - car.global_position).normalized()
				var dot_p = forward.dot(dir)
				var dist = car.global_position.distance_to(alvo_atual.global_position)
				
				if dot_p > 0.8:
					desire_throttle = 0.5 
					if dist < 20.0: desire_throttle = -0.5 
				else:
					desire_throttle = 1.0 
				
		State.FLEE:
			if vida_proxima.size() > 0:
				var alvo_vida = vida_proxima[0]
				if is_instance_valid(alvo_vida):
					var nav = _direcionar_para_coletavel(alvo_vida, delta)
					desire_steering = nav.steering
					desire_throttle = nav.throttle
				else: vida_proxima.remove_at(0)
			else:
				desire_throttle = 1.0
				
		State.SEEK_HEIGHT:
			if tempo_no_estado >= 60.0:
				timer_busca_predios = randf_range(25.0, 60.0)
				_mudar_estado(State.WANDER_IDLE)
			else:
				if rampas_proximas.size() > 0: 
					if is_instance_valid(rampas_proximas[0]):
						desire_steering = _calcular_volante_para_alvo(rampas_proximas[0].global_position)
					else: rampas_proximas.remove_at(0)
				
		State.SEEK_RAMP:
			if rampas_proximas.is_empty() or tempo_no_estado >= 15.0:
				_iniciar_manobra_chao()
			else:
				var target_ramp = rampas_proximas[0]
				if is_instance_valid(target_ramp):
					desire_steering = _calcular_volante_para_alvo(target_ramp.global_position)
					if car.global_position.distance_to(target_ramp.global_position) < 15.0:
						input.is_attribute_pressed = true
						input.ability_up = true
						doing_stunt_timer = 2.0 
						timer_manobra = randf_range(15.0, 30.0)
						_mudar_estado(State.WANDER_IDLE)
				else: rampas_proximas.remove_at(0)
		
	return {"throttle": desire_throttle, "steering": desire_steering}

var alvo_coletavel_atual : Node3D = null
var tempo_buscando_coletavel : float = 0.0

func _direcionar_para_coletavel(alvo: Node3D, delta: float) -> Dictionary:
	var forward = car.global_transform.basis.z
	var dir = (alvo.global_position - car.global_position).normalized()
	var dist = car.global_position.distance_to(alvo.global_position)
	
	var steer = clamp(forward.cross(dir).y * 3.0, -1.0, 1.0)
	var throttle = 1.0
	
	var dot_p = forward.dot(dir)
	if dot_p < 0.2: throttle = 0.4
	elif dist < 12.0: throttle = 0.6
		
	if alvo_coletavel_atual != alvo:
		alvo_coletavel_atual = alvo
		tempo_buscando_coletavel = 0.0
	else:
		tempo_buscando_coletavel += delta
		if tempo_buscando_coletavel > 12.0: 
			itens_ignorados.append(alvo)
			alvo_coletavel_atual = null
			tempo_buscando_coletavel = 0.0
			
	return {"steering": steer, "throttle": throttle}

func _iniciar_manobra_chao():
	# BUG CORRIGIDO: Muda de estado IMEDIATAMENTE para a MDE não chamar a função repetidas vezes no mesmo frame
	_mudar_estado(State.WANDER_IDLE)
	timer_manobra = randf_range(15.0, 30.0)
	doing_stunt_timer = 1.0 
	
	print("[DEBUG BOT] ", car.name, ": Pulo Tático e Manobra Direta!")
	
	var ability = car.get_node_or_null("%AbilityComponent")
	if ability and ability.current_energy >= ability.COST_JUMP and ability.current_cooldown <= 0:
		ability._execute_jump()
	else:
		if car.has_method("apply_central_impulse"):
			# Força rebalanceada para 15 (Em vez de 350, que mandava ele pra lua!)
			car.apply_central_impulse(Vector3.UP * car.mass * 15.0) 
			
	await get_tree().create_timer(0.05).timeout
	
	if car.has_method("apply_torque_impulse"):
		car.apply_torque_impulse(car.global_transform.basis.x * car.mass * 20.0)
			
	var tm = car.get_node_or_null("%TrickManager")
	if tm and tm.has_method("add_external_action"):
		tm.add_external_action("Tactical Flip", 150, "#00aaff") 

func _calcular_volante_para_alvo(alvo_pos: Vector3) -> float:
	var forward = car.global_transform.basis.z
	var dir_to_alvo = (alvo_pos - car.global_position).normalized()
	return forward.cross(dir_to_alvo).y * 2.0

# --- NAVEGAÇÃO E FÍSICA ---
func _processar_direcao_final(delta, intencao_throttle, intencao_steering):
	var speed = car.linear_velocity.length()
	
	if speed < 2.0 and intencao_throttle > 0.5: stuck_timer += delta
	else: stuck_timer = 0.0
		
	if stuck_timer > 1.5:
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
	input.pitch = 0.0
	input.is_action_pressed = false
	input.is_attribute_pressed = false
	input.ability_up = false
	input.ability_down = false
	input.ability_left = false
	input.ability_right = false

# --- SISTEMA DE LOGGING ---
func _process_debug(delta):
	debug_print_timer -= delta
	if debug_print_timer <= 0:
		debug_print_timer = 1.0 
		var ammo = _get_total_ammo()
		var health_pct = int((stats.current_health / stats.max_health) * 100.0) if stats else 0
		var target_name = alvo_atual.name if alvo_atual and is_instance_valid(alvo_atual) else "Nenhum"
		var log_str = str(
			"\n=== ", car.name, " STATUS ===\n",
			"Estado: ", State.keys()[current_state], "\n",
			"Tempo no Est.: ", int(tempo_no_estado), "s\n",
			"Vida: ", health_pct, "% | Munição: ", ammo, "\n",
			"Alvo: ", target_name, " | Ignorados: ", itens_ignorados.size(), "\n",
			"T. Manobra: ", int(timer_manobra), "s\n",
			"T. Prédios: ", int(timer_busca_predios), "s\n",
			"Rampas Perto: ", rampas_proximas.size(), " | Armas: ", armas_proximas.size(), "\n",
			"===================="
		)
		print(log_str)
