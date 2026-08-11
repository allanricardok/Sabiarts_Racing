extends Node
class_name BotBrain

@export_group("Foco em Missões")
@export var mission_target_collect_id : String = ""
@export var mission_target_destroy_id : String = ""

enum State { 
	WANDER_IDLE, WANDER_CHASE, WANDER_AMMO, ATTACK, FLEE, SEEK_RAMP, SEEK_HEIGHT, 
	SEEK_MISSION_OBJECTIVE
}
var current_state : State = State.WANDER_IDLE
var tempo_no_estado : float = 0.0 

var car: BaseVehicle
var input: Node 
var stats: Node

var radar : BotRadar
var driver : BotDriver
var combat : BotCombatModule 

var alvo_atual : Node3D = null

var timer_manobra : float = 0.0
var timer_busca_predios : float = 0.0
var chase_repeats : int = 0
var is_agressive : bool = false 
var debug_print_timer: float = 0.0
var mission_seek_cooldown : float = 0.0
var vip_attack_cooldown : float = 0.0 

var ameacas_detectadas : int = 0

func _ready():
	car = get_parent() as BaseVehicle
	input = car.get_node_or_null("%InputComponent")
	stats = car.get_node_or_null("%StatsComponent")
	
	if input: input.is_bot = true
	
	car.set("has_teleportkey", true)
	if stats: stats.set("has_teleportkey", true)
	
	radar = BotRadar.new()
	radar.name = "BotRadar"
	add_child(radar)
	
	driver = BotDriver.new()
	driver.name = "BotDriver"
	add_child(driver)
	
	combat = BotCombatModule.new()
	combat.name = "BotCombatModule"
	add_child(combat)
	
	driver.setup(car, input)
	combat.setup(car, input, stats, radar)
	
	_rolar_dados_de_timers()

func _rolar_dados_de_timers():
	timer_manobra = randf_range(15.0, 30.0)
	timer_busca_predios = randf_range(25.0, 60.0)

func _process(delta):
	if not is_instance_valid(car) or not is_instance_valid(input) or not is_instance_valid(stats): return
	if not car.pode_mover or (car.has_method("is_frozen") and car.is_frozen()): 
		_reset_inputs()
		return
		
	if alvo_atual != null and (not is_instance_valid(alvo_atual) or alvo_atual.is_queued_for_deletion()):
		alvo_atual = null
		
	mission_seek_cooldown = max(0.0, mission_seek_cooldown - delta)
	vip_attack_cooldown = max(0.0, vip_attack_cooldown - delta) 
	tempo_no_estado += delta
	
	if driver.processar_manobra_pendente(delta): return 
		
	if current_state != State.FLEE:
		if current_state != State.SEEK_RAMP: timer_manobra = max(0.0, timer_manobra - delta)
		if current_state != State.SEEK_HEIGHT and current_state != State.ATTACK: 
			timer_busca_predios = max(0.0, timer_busca_predios - delta)
		
	radar.escanear_ambiente(car, current_state)
	_tomar_decisao_de_estado()
	
	if typeof(alvo_atual) == TYPE_OBJECT:
		if not is_instance_valid(alvo_atual) or alvo_atual.is_queued_for_deletion():
			alvo_atual = null
			
	combat.processar_combate(delta, current_state, alvo_atual)
	
	if combat.disparou_no_vip:
		_aplicar_cooldown_vip()
	
	if radar.checar_ameacas_imediatas(car):
		ameacas_detectadas += 1
		combat.reagir_a_ameaca(ameacas_detectadas)
	
	var intencoes = _executar_estado_atual(delta)
	
	if intencoes.has("jump") and intencoes.jump:
		var ability = car.get_node_or_null("%AbilityComponent")
		if ability and ability.current_energy >= ability.COST_JUMP and ability.current_cooldown <= 0:
			input.is_attribute_pressed = true
			input.ability_down = true
			
	var force_straight = intencoes.get("force_straight", false)
	driver.processar_direcao_final(delta, intencoes.throttle, intencoes.steering, force_straight)
	_process_debug(delta)

func _aplicar_cooldown_vip():
	vip_attack_cooldown = 20.0
	if is_instance_valid(alvo_atual) and alvo_atual.is_in_group("destructible_vips"):
		alvo_atual = null 
		print("[DEBUG BOT] ", car.name, " entrou em COOLDOWN de 10s contra o VIP!")
		_mudar_estado(State.WANDER_IDLE)

func _mudar_estado(novo_estado: State):
	if current_state != novo_estado:
		if current_state == State.SEEK_RAMP and (novo_estado == State.ATTACK or novo_estado == State.FLEE):
			timer_manobra = randf_range(15.0, 30.0)
		if current_state == State.SEEK_HEIGHT and (novo_estado == State.ATTACK or novo_estado == State.FLEE):
			timer_busca_predios = randf_range(25.0, 60.0)
		current_state = novo_estado
		tempo_no_estado = 0.0

func _escolher_alvo_inimigo() -> Node3D:
	if mission_target_destroy_id != "" and vip_attack_cooldown <= 0.0:
		var alvos_vip = get_tree().get_nodes_in_group("destructible_vips")
		for vip in alvos_vip:
			if is_instance_valid(vip) and not vip.is_queued_for_deletion() and vip.get("mission_id") == mission_target_destroy_id:
				# OTIMIZAÇÃO: 800.0 -> 640000.0
				if car.global_position.distance_squared_to(vip.global_position) < 640000.0:
					return vip 
					
	var humanos_globais = []
	for p in get_tree().get_nodes_in_group("jogadores"):
		if is_instance_valid(p) and not p.is_queued_for_deletion() and p != car:
			var inp = p.get_node_or_null("%InputComponent")
			if inp and "is_bot" in inp and not inp.is_bot:
				if not ("is_dead" in p and p.is_dead):
					humanos_globais.append(p)
	
	if humanos_globais.size() > 0 and randf() <= 0.85:
		var alvo_humano = humanos_globais[0]
		# OTIMIZAÇÃO: Menor distância ao quadrado
		var menor_dist_sq = car.global_position.distance_squared_to(alvo_humano.global_position)
		for i in range(1, humanos_globais.size()):
			var h = humanos_globais[i]
			var dist_sq = car.global_position.distance_squared_to(h.global_position)
			if dist_sq < menor_dist_sq:
				menor_dist_sq = dist_sq
				alvo_humano = h
		# 400.0 -> 160000.0
		if menor_dist_sq < 160000.0:
			return alvo_humano

	if not radar.inimigos_proximos.is_empty():
		for inimigo in radar.inimigos_proximos:
			if is_instance_valid(inimigo) and not inimigo.is_queued_for_deletion():
				return inimigo
		
	return null

func _tomar_decisao_de_estado():
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	var ammo_total = combat.get_total_ammo()
	
	var tem_missao_destruicao = (mission_target_destroy_id != "" and vip_attack_cooldown <= 0.0)
	
	is_agressive = (ammo_total > 7) or tem_missao_destruicao
	
	if health_pct < 20.0:
		_mudar_estado(State.FLEE)
		return
	if current_state == State.FLEE and health_pct > 26.0:
		_mudar_estado(State.WANDER_IDLE)
		return
		
	var ja_roubou_algo = car.has_meta("maletas_roubadas") and car.get_meta("maletas_roubadas").size() > 0
	
	if mission_target_collect_id != "" and mission_seek_cooldown <= 0.0 and not ja_roubou_algo:
		var itens_no_mapa = get_tree().get_nodes_in_group("itens_missao")
		for item in itens_no_mapa:
			if is_instance_valid(item) and item.get("mission_id") == mission_target_collect_id and item.visible:
				# OTIMIZAÇÃO: 300.0 -> 90000.0
				if car.global_position.distance_squared_to(item.global_position) < 90000.0:
					_mudar_estado(State.SEEK_MISSION_OBJECTIVE)
					return
		
	if radar.has_method("escanear_ambiente") and "teleporters_proximos" in radar and radar.teleporters_proximos.size() > 0:
		var tp = radar.teleporters_proximos[0]
		# OTIMIZAÇÃO: 80.0 -> 6400.0
		if is_instance_valid(tp) and car.global_position.distance_squared_to(tp.global_position) <= 6400.0:
			_mudar_estado(State.SEEK_HEIGHT)
			return

	var tem_inimigos_no_radar = radar.inimigos_proximos.size() > 0
	
	if is_agressive and (tem_inimigos_no_radar or tem_missao_destruicao):
		var precisa_novo_alvo = false
		if current_state != State.ATTACK or not is_instance_valid(alvo_atual):
			precisa_novo_alvo = true
		elif not tem_missao_destruicao and not radar.inimigos_proximos.has(alvo_atual):
			precisa_novo_alvo = true
			
		if precisa_novo_alvo:
			var alvo_anterior = alvo_atual
			alvo_atual = _escolher_alvo_inimigo()
			
			if alvo_atual != alvo_anterior:
				var nome_alvo = alvo_atual.name if is_instance_valid(alvo_atual) else "Nenhum"
				print("[DEBUG BOT] ", car.name, " 🎯 TRAVOU A MIRA NO ALVO: ", nome_alvo)
		
		if is_instance_valid(alvo_atual):
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
		if current_state != State.WANDER_CHASE or not is_instance_valid(alvo_atual) or not radar.inimigos_proximos.has(alvo_atual):
			alvo_atual = _escolher_alvo_inimigo()
		_mudar_estado(State.WANDER_CHASE)
		return
	
	if radar.inimigos_proximos.is_empty(): chase_repeats = 0 
	_mudar_estado(State.WANDER_IDLE)

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
				
				# OTIMIZAÇÃO: 12.0 -> 144.0 e 20.0 -> 400.0
				var dist_sq = car.global_position.distance_squared_to(alvo_atual.global_position)
				var is_vip = alvo_atual.is_in_group("destructible_vips")
				
				if is_vip:
					desire_throttle = 1.0
					if dist_sq < 144.0:
						_aplicar_cooldown_vip()
						
				else:
					if dot_p > 0.8:
						desire_throttle = 0.5 
						if dist_sq < 400.0: desire_throttle = -0.5 
					else: desire_throttle = 1.0
		State.FLEE:
			if radar.vida_proxima.size() > 0:
				var alvo_vida = radar.vida_proxima[0]
				if is_instance_valid(alvo_vida):
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
			if tempo_no_estado >= 30.0:
				timer_busca_predios = randf_range(25.0, 60.0)
				_mudar_estado(State.WANDER_IDLE)
			else:
				if radar.has_method("escanear_ambiente") and "teleporters_proximos" in radar and radar.teleporters_proximos.size() > 0: 
					var alvo_teleporter = radar.teleporters_proximos[0]
					if is_instance_valid(alvo_teleporter):
						var nav = driver.direcionar_para_coletavel(alvo_teleporter, delta, radar)
						desire_steering = nav.steering
						desire_throttle = nav.throttle
					else: 
						radar.teleporters_proximos.remove_at(0)
				else:
					desire_throttle = 1.0
					desire_steering = sin(Time.get_ticks_msec() * 0.001) * 0.3
		State.SEEK_MISSION_OBJECTIVE:
			if tempo_no_estado >= 20.0:
				mission_seek_cooldown = 20.0
				_mudar_estado(State.WANDER_IDLE)
			else:
				var encontrou_alvo = false
				if mission_target_collect_id != "":
					var itens_no_mapa = get_tree().get_nodes_in_group("itens_missao")
					for item in itens_no_mapa:
						if is_instance_valid(item) and item.get("mission_id") == mission_target_collect_id and item.visible:
							var nav = driver.direcionar_para_coletavel(item, delta, radar)
							desire_steering = nav.steering
							desire_throttle = nav.throttle
							encontrou_alvo = true
							break 
				if not encontrou_alvo:
					_mudar_estado(State.WANDER_IDLE)
		State.SEEK_RAMP:
			if radar.rampas_proximas.is_empty() or tempo_no_estado >= 15.0:
				_mudar_estado(State.WANDER_IDLE)
				timer_manobra = randf_range(15.0, 30.0)
				driver.iniciar_manobra_chao()
			else:
				var target_ramp = radar.rampas_proximas[0]
				if is_instance_valid(target_ramp):
					desire_steering = driver.calcular_volante_para_alvo(target_ramp.global_position)
					# OTIMIZAÇÃO: 15.0 -> 225.0
					if car.global_position.distance_squared_to(target_ramp.global_position) < 225.0:
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
		var ammo = combat.get_total_ammo()
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
