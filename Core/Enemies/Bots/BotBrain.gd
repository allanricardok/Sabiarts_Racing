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

var radar : BotRadar
var driver : BotDriver

var alvo_atual : Node3D = null

# --- TIMERS E CONTADORES ---
var timer_manobra : float = 0.0
var timer_busca_predios : float = 0.0
var chase_repeats : int = 0
var is_agressive : bool = false 
var debug_print_timer: float = 0.0

var ameacas_detectadas : int = 0
var disparos_especiais_seguidos : int = 0

# --- NOVO: REGENERAÇÃO DE MUNIÇÃO ---
var ammo_regen_timer : float = 5.0
var ammo_added_to_current : int = 0

func _ready():
	car = get_parent() as BaseVehicle
	input = car.get_node_or_null("%InputComponent")
	stats = car.get_node_or_null("%StatsComponent")
	
	if input: input.is_bot = true
	
	radar = BotRadar.new()
	radar.name = "BotRadar"
	add_child(radar)
	
	driver = BotDriver.new()
	driver.name = "BotDriver"
	add_child(driver)
	
	driver.setup(car, input)
	_rolar_dados_de_timers()

func _rolar_dados_de_timers():
	timer_manobra = randf_range(15.0, 30.0)
	timer_busca_predios = randf_range(25.0, 60.0)

func _process(delta):
	if not is_instance_valid(car) or not is_instance_valid(input) or not is_instance_valid(stats): return
	if not car.pode_mover or (car.has_method("is_frozen") and car.is_frozen()): 
		_reset_inputs()
		return
		
	tempo_no_estado += delta
	
	if driver.processar_manobra_pendente(delta): return 
		
	if current_state != State.FLEE:
		if current_state != State.SEEK_RAMP: timer_manobra = max(0.0, timer_manobra - delta)
		if current_state != State.SEEK_HEIGHT and current_state != State.ATTACK: 
			timer_busca_predios = max(0.0, timer_busca_predios - delta)
		
	radar.escanear_ambiente(car, current_state)
		
	_tomar_decisao_de_estado()
	_gerenciar_habilidades_do_bot()
	
	if radar.checar_ameacas_imediatas(car):
		ameacas_detectadas += 1
		_reagir_a_ameaca()
	
	_gerenciar_regeneracao_municao(delta) # <-- NOVO SISTEMA CHAMADO AQUI
	_gerenciar_armas_do_bot()
	
	var intencoes = _executar_estado_atual(delta)
	
	if intencoes.has("jump") and intencoes.jump:
		var ability = car.get_node_or_null("%AbilityComponent")
		if ability and ability.current_energy >= ability.COST_JUMP and ability.current_cooldown <= 0:
			input.is_attribute_pressed = true
			input.ability_down = true
			print("[DEBUG BOT] ", car.name, " executou Pulo Matemático de Interceptação!")

	var force_straight = intencoes.get("force_straight", false)
	driver.processar_direcao_final(delta, intencoes.throttle, intencoes.steering, force_straight)
	_process_debug(delta)

# --- NOVO SISTEMA: REGENERAÇÃO DE MUNIÇÃO PASSIVA ---
func _gerenciar_regeneracao_municao(delta: float):
	var wm = car.get_node_or_null("%WeaponManager")
	if not wm or wm.weapon_pool.is_empty(): return
	
	var active_w = wm.get_active_special()
	if not active_w: return
	
	ammo_regen_timer -= delta
	if ammo_regen_timer <= 0:
		ammo_regen_timer = 5.0 # Reseta o relógio de 5s
		
		# Só adiciona se ainda não bateu o limite de 6 na arma atual
		if ammo_added_to_current < 6:
			active_w.ammo += 1
			ammo_added_to_current += 1
			print("[DEBUG BOT] ", car.name, " gerou 1 munição para ", active_w.nome, " (Regen: ", ammo_added_to_current, "/6)")
			
			if ammo_added_to_current >= 6:
				if wm.weapon_pool.size() > 1:
					wm._switch_weapon(1)
					ammo_added_to_current = 0 # Zera para a próxima arma
					print("[DEBUG BOT] ", car.name, " Limite de 6 atingido! Trocando para próxima arma.")
				else:
					print("[DEBUG BOT] ", car.name, " Limite de 6 atingido, mas só possui uma arma. Regeneração pausada.")

func _reagir_a_ameaca():
	var ability = car.get_node_or_null("%AbilityComponent")
	if not ability or ability.current_cooldown > 0: return
	
	if ameacas_detectadas % 3 == 0:
		if ability.current_energy >= ability.COST_SHIELD:
			ability._execute_shield()
			return 
			
	if ameacas_detectadas % 5 == 0:
		if ability.current_energy >= ability.COST_JUMP:
			ability._execute_jump()
			return

func _mudar_estado(novo_estado: State):
	if current_state != novo_estado:
		if current_state == State.SEEK_RAMP and (novo_estado == State.ATTACK or novo_estado == State.FLEE):
			timer_manobra = randf_range(15.0, 30.0)
		if current_state == State.SEEK_HEIGHT and (novo_estado == State.ATTACK or novo_estado == State.FLEE):
			timer_busca_predios = randf_range(25.0, 60.0)

		current_state = novo_estado
		tempo_no_estado = 0.0

func _get_total_ammo() -> int:
	var ammo = 0
	var wm = car.get_node_or_null("%WeaponManager")
	if wm:
		for w in wm.weapon_pool: ammo += w.ammo
	return ammo

func _tomar_decisao_de_estado():
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	var ammo_total = _get_total_ammo()
	
	is_agressive = (ammo_total > 7)
	
	if health_pct < 40.0:
		_mudar_estado(State.FLEE)
		return
	if current_state == State.FLEE and health_pct > 50.0:
		_mudar_estado(State.WANDER_IDLE)
		return
	if is_agressive and radar.inimigos_proximos.size() > 0:
		alvo_atual = radar.inimigos_proximos[0]
		_mudar_estado(State.ATTACK)
		
		if timer_manobra <= 0:
			timer_manobra = randf_range(15.0, 30.0)
			driver.iniciar_manobra_chao() 
		return
		
	if timer_busca_predios <= 0:
		_mudar_estado(State.SEEK_HEIGHT)
		return
	if timer_manobra <= 0:
		_mudar_estado(State.SEEK_RAMP)
		return
	if ammo_total <= 7 and radar.armas_proximas.size() > 0:
		_mudar_estado(State.WANDER_AMMO)
		return
	if radar.inimigos_proximos.size() > 0 and chase_repeats < 5:
		alvo_atual = radar.inimigos_proximos[0]
		_mudar_estado(State.WANDER_CHASE)
		return
	
	if radar.inimigos_proximos.is_empty(): chase_repeats = 0 
	_mudar_estado(State.WANDER_IDLE)

func _gerenciar_habilidades_do_bot():
	var ability = car.get_node_or_null("%AbilityComponent")
	if not ability or ability.current_cooldown > 0: return
	
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	
	if current_state == State.FLEE or health_pct < 40.0:
		if ability.current_energy >= ability.COST_SHIELD:
			ability._execute_shield()
			return
			
	if current_state == State.FLEE or (current_state == State.ATTACK and is_instance_valid(alvo_atual) and car.global_position.distance_to(alvo_atual.global_position) > 40.0):
		if ability.current_energy >= ability.COST_BOOST:
			ability._execute_boost()
			return

func _gerenciar_armas_do_bot():
	input.is_action_pressed = false 
	var alvo_tiro = null
	
	if current_state == State.ATTACK and is_instance_valid(alvo_atual):
		alvo_tiro = alvo_atual
	elif current_state == State.FLEE and radar.inimigos_proximos.size() > 0:
		alvo_tiro = radar.inimigos_proximos[0]
	
	if is_instance_valid(alvo_tiro):
		var wm = car.get_node_or_null("%WeaponManager")
		if not wm: return
		
		var forward = car.global_transform.basis.z
		var dir = (alvo_tiro.global_position - car.global_position).normalized()
		var dot_p = forward.dot(dir)
		
		if dot_p > 0.4: 
			input.is_action_pressed = true 
			
			# TIRO DE EMERGÊNCIA (FLEE)
			if current_state == State.FLEE:
				var active_w = wm.get_active_special()
				if active_w and wm.special_cooldowns.get(active_w.nome, 0.0) <= 0:
					wm.fire_special_weapon() 
					ammo_added_to_current = 0 # <-- ZERA A REGENERAÇÃO AQUI
					print("[DEBUG BOT] ", car.name, " TIRO DE EMERGÊNCIA: ", active_w.nome, " | Regen Zerada!")
		
		# TIRO ESPECIAL (ATTACK)
		if current_state == State.ATTACK and dot_p > 0.85:
			var active_w = wm.get_active_special()
			if active_w and wm.special_cooldowns.get(active_w.nome, 0.0) <= 0:
				wm.fire_special_weapon() 
				ammo_added_to_current = 0 # <-- ZERA A REGENERAÇÃO AQUI
				print("[DEBUG BOT] ", car.name, " DISPAROU ESPECIAL: ", active_w.nome, " | Regen Zerada!")
				
				disparos_especiais_seguidos += 1
				if disparos_especiais_seguidos >= 2:
					disparos_especiais_seguidos = 0
					if wm.weapon_pool.size() > 1:
						wm._switch_weapon(1)
						ammo_added_to_current = 0 # Garante que a próxima arma comece do zero
						print("[DEBUG BOT] ", car.name, " Trocou de Arma taticamente!")

func _executar_estado_atual(delta) -> Dictionary:
	var desire_throttle = 1.0
	var desire_steering = 0.0
	input.pitch = 0.0
	
	match current_state:
		State.WANDER_IDLE:
			desire_steering = sin(Time.get_ticks_msec() * 0.001) * 0.3
			
		State.WANDER_AMMO:
			if radar.armas_proximas.size() > 0: 
				var alvo_arma = radar.armas_proximas[0]
				if is_instance_valid(alvo_arma):
					var nav = driver.direcionar_para_coletavel(alvo_arma, delta, radar)
					desire_steering = nav.steering
					desire_throttle = nav.throttle
				else: radar.armas_proximas.remove_at(0) 
			
		State.WANDER_CHASE:
			if is_instance_valid(alvo_atual):
				desire_steering = driver.calcular_volante_para_alvo(alvo_atual.global_position)
			if tempo_no_estado >= 5.0:
				tempo_no_estado = 0.0 
				if radar.inimigos_proximos.has(alvo_atual): chase_repeats += 1
				else: chase_repeats = 5 
					
		State.ATTACK:
			if is_instance_valid(alvo_atual):
				desire_steering = driver.calcular_volante_para_alvo(alvo_atual.global_position)
				var forward = car.global_transform.basis.z
				var dir = (alvo_atual.global_position - car.global_position).normalized()
				var dot_p = forward.dot(dir)
				var dist = car.global_position.distance_to(alvo_atual.global_position)
				
				if dot_p > 0.8:
					desire_throttle = 0.5 
					if dist < 20.0: desire_throttle = -0.5 
				else: desire_throttle = 1.0 
				
		State.FLEE:
			if radar.vida_proxima.size() > 0:
				var alvo_vida = radar.vida_proxima[0]
				if is_instance_valid(alvo_vida):
					# IGNORA O INIMIGO E FOCA 100% NA VIDA
					var nav = driver.direcionar_para_coletavel(alvo_vida, delta, radar)
					desire_steering = nav.steering
					desire_throttle = nav.throttle
				else: radar.vida_proxima.remove_at(0)
			else:
				desire_throttle = 1.0
				if radar.inimigos_proximos.size() > 0:
					var enemy = radar.inimigos_proximos[0]
					if is_instance_valid(enemy):
						var dir_away = (car.global_position - enemy.global_position).normalized()
						var ponto_fuga = car.global_position + (dir_away * 50.0)
						desire_steering = driver.calcular_volante_para_alvo(ponto_fuga)
				else:
					desire_steering = sin(Time.get_ticks_msec() * 0.001) * 0.3
				
		State.SEEK_HEIGHT:
			if tempo_no_estado >= 5.0:
				timer_busca_predios = randf_range(25.0, 60.0)
				_mudar_estado(State.WANDER_IDLE)
			else:
				if radar.rampas_proximas.size() > 0: 
					if is_instance_valid(radar.rampas_proximas[0]):
						desire_steering = driver.calcular_volante_para_alvo(radar.rampas_proximas[0].global_position)
					else: radar.rampas_proximas.remove_at(0)
				
		State.SEEK_RAMP:
			if radar.rampas_proximas.is_empty() or tempo_no_estado >= 15.0:
				_mudar_estado(State.WANDER_IDLE)
				timer_manobra = randf_range(15.0, 30.0)
				driver.iniciar_manobra_chao()
			else:
				var target_ramp = radar.rampas_proximas[0]
				if is_instance_valid(target_ramp):
					desire_steering = driver.calcular_volante_para_alvo(target_ramp.global_position)
					
					if car.global_position.distance_to(target_ramp.global_position) < 15.0:
						input.is_attribute_pressed = true
						input.ability_up = true
						_mudar_estado(State.WANDER_IDLE)
						timer_manobra = randf_range(15.0, 30.0)
						
						var t = get_tree().create_timer(0.4)
						t.timeout.connect(func():
							if is_instance_valid(car):
								var sp = car.find_child("StuntProcessor*", true, false)
								if sp and sp.has_method("initiate_stunt"):
									sp.initiate_stunt(Vector3(1, 0, 0), "BACKFLIP")
						)
				else: radar.rampas_proximas.remove_at(0)
		
	return {"throttle": desire_throttle, "steering": desire_steering}

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
			"Alvo: ", target_name, " | Ignorados: ", radar.itens_ignorados.size(), "\n",
			"Ameaças Evadidas: ", ameacas_detectadas, "\n",
			"===================="
		)
		# Deixei o print(log_str) desligado para focar nas mensagens importantes de tiro/regen.
		# Descomente se precisar dele ativo de novo:
		# print(log_str)
