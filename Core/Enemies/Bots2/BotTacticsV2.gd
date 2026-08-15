extends Node
class_name BotTacticsV2

# --- REFERÊNCIAS INJETADAS PELO CÉREBRO ---
var car: BaseVehicle
var brain: BotBrainV2
var driver: BotDriverV2
var radar: BotRadarV2
var combat: BotCombatModuleV2
var stats: Node

# --- MEMÓRIA TÁTICA LOCAL ---
var _last_attacker: Node3D = null
var _close_combat_timer: float = 0.0
var _is_getting_distance: bool = false
var _roam_pause_timer: float = 0.0
var _random_circle_pos: Vector3 = Vector3.ZERO
var current_target: Node3D = null
var current_action_name: String = "" 
var _seek_timer: float = 0.0
var _is_doing_180: bool = false
var _is_doing_burnout_180: bool = false
var _180_steer_dir: float = 0.0
var _random_stunt_timer: float = 15.0

func setup(_car: BaseVehicle, _brain: BotBrainV2, _driver: BotDriverV2, _radar: BotRadarV2, _combat: BotCombatModuleV2, _stats: Node):
	car = _car
	brain = _brain
	driver = _driver
	radar = _radar
	combat = _combat
	stats = _stats
	
	if is_instance_valid(stats) and stats.has_signal("took_damage"):
		stats.took_damage.connect(func(atk): if is_instance_valid(atk): _last_attacker = atk)

func reset_target():
	current_target = null
	_is_getting_distance = false
	_close_combat_timer = 0.0
	_seek_timer = 0.0
	_is_doing_180 = false
	_is_doing_burnout_180 = false

# --- CORRIGIDO: Retorna um Dictionary para o Cérebro fazer o Time-Slicing ---
func execute(delta: float, current_macro_state: int) -> Dictionary:
	var intencoes = {"throttle": 0.0, "steering": 0.0, "jump": false, "force_straight": false, "handbrake": false}
	
	match current_macro_state:
		BotBrainV2.MacroState.BATTLE: intencoes = _tactic_battle(delta)
		BotBrainV2.MacroState.SEEK:   intencoes = _tactic_seek(delta)
		BotBrainV2.MacroState.FLEE:   intencoes = _tactic_flee(delta)
		BotBrainV2.MacroState.WANDER: intencoes = _tactic_wander(delta)
		
	# --- MANOBRAS DE EXIBIÇÃO ALEATÓRIAS ---
	_random_stunt_timer -= delta
	if _random_stunt_timer <= 0.0:
		_random_stunt_timer = randf_range(12.0, 30.0) # Sorteia o próximo showoff
		var speed_kmh = car.linear_velocity.length() * 3.6
		if speed_kmh > 40.0: # Só faz graça se estiver correndo
			intencoes.jump = true
			current_action_name = "Showoff Stunt!"
			
	# Retorna a decisão para o Cérebro guardar no cache!
	return intencoes

func _tactic_battle(delta: float) -> Dictionary:
	var intencoes = {"throttle": 0.0, "steering": 0.0, "jump": false, "force_straight": false, "handbrake": false}
	
	if not is_instance_valid(current_target) or current_target.is_queued_for_deletion():
		current_target = _get_best_combat_target()
		
	if not is_instance_valid(current_target):
		current_action_name = "Idle (Sem Alvo)"
		return intencoes

	var car_pos = car.global_position
	var target_pos = current_target.global_position
	var dist_sq = car_pos.distance_squared_to(target_pos)
	var forward = car.global_transform.basis.z.normalized()
	var dir_to_target = (target_pos - car_pos).normalized()
	var dot_p = forward.dot(dir_to_target)
	
	var flat_forward = Vector3(forward.x, 0, forward.z).normalized()
	var flat_dir = Vector3(dir_to_target.x, 0, dir_to_target.z).normalized()
	intencoes.steering = clamp(flat_forward.cross(flat_dir).y * 3.0, -1.0, 1.0)
	
	var target_stats = current_target.get_node_or_null("%StatsComponent")
	var target_hp_pct = 0.0
	if target_stats: target_hp_pct = (target_stats.current_health / target_stats.max_health) * 100.0
	
	# 1. GET_DISTANCE
	if dist_sq < 64.0: 
		_close_combat_timer += delta
		if _close_combat_timer > 3.0: _is_getting_distance = true
	else:
		_close_combat_timer = 0.0
		
	if _is_getting_distance:
		if dist_sq > 625.0: _is_getting_distance = false
		else:
			current_action_name = "Get Distance"
			intencoes.throttle = 1.0
			intencoes.steering = -intencoes.steering
			return intencoes

	# 2. EXTREME ATTACK vs NORMAL ATTACK (Desativado durante o 180)
	if not _is_doing_180:
		if target_hp_pct > 80.0:
			current_action_name = "Extreme Attack"
			intencoes.throttle = 1.0
		else:
			current_action_name = "Normal Attack"
			if dist_sq > 400.0: intencoes.throttle = 1.0 
			elif dist_sq < 144.0: intencoes.throttle = -0.5
			else: intencoes.throttle = 0.0

	# 3. COLLIDE
	if dist_sq > 6400.0 and dist_sq < 14400.0 and dot_p > 0.90 and not _is_doing_180:
		current_action_name = "Collide"
		intencoes.throttle = 1.0
		intencoes.force_straight = true

	# ====================================================================
	# 4. PERFORM 180 DINÂMICO (3 Estágios Absolutos)
	# ====================================================================
	var speed_kmh = car.linear_velocity.length() * 3.6

	# Gatilho Inicial: Inimigo nas costas
	if not _is_doing_180 and dot_p < -0.5:
		_is_doing_180 = true
		_180_steer_dir = 1.0 if flat_forward.cross(flat_dir).y > 0 else -1.0
		# Se já está devagar, entra direto no Burnout!
		_is_doing_burnout_180 = (speed_kmh < 50.0) 

	if _is_doing_180:
		if _is_doing_burnout_180:
			current_action_name = "180: Burnout Recovery"
			# CONDIÇÃO 3 (< 50km/h): Acelera e Freia ao mesmo tempo!
			if dot_p > 0.8: # Já rotacionou o suficiente pra ficar de frente
				_is_doing_180 = false
				_is_doing_burnout_180 = false
			else:
				intencoes.throttle = 1.0
				intencoes.brake = 1.0 # Acende a lanterna e trava pneu
				intencoes.steering = _180_steer_dir
				return intencoes
		else:
			if speed_kmh > 70.0:
				current_action_name = "180: High Speed Drift"
				# CONDIÇÃO 1 (> 70km/h): Freia e vira (sem acelerar)
				if dot_p > 0.8:
					_is_doing_180 = false
				else:
					intencoes.throttle = 0.0
					intencoes.brake = 1.0
					intencoes.steering = _180_steer_dir
					return intencoes
					
			elif speed_kmh >= 50.0 and speed_kmh <= 70.0:
				current_action_name = "180: Speeding Up"
				# CONDIÇÃO 2 (50 a 70km/h): Acelera reto com turbo
				intencoes.throttle = 1.0
				intencoes.brake = 0.0
				intencoes.force_straight = true
				
				var ability = car.get_node_or_null("%AbilityComponent")
				if ability and ability.current_energy >= ability.COST_BOOST and ability.current_cooldown <= 0:
					ability._execute_boost()
				return intencoes
				
			else:
				# FAILSAFE: Caiu abaixo de 50km/h no meio da derrapagem! Trava no Burnout (Condição 3).
				_is_doing_burnout_180 = true
				return intencoes
	# ====================================================================

	# 5. TURN NORMAL (Flancos)
	if dot_p < 0.5 and not _is_doing_180:
		current_action_name = "Turn Drift"
		intencoes.handbrake = true
		intencoes.throttle = 0.8

	# GATILHO DAS ARMAS
	if dot_p > 0.85 and is_instance_valid(combat):
		combat.tentar_atirar(current_target, (target_hp_pct > 80.0))

	return intencoes
	
func _tactic_seek(delta: float) -> Dictionary:
	if not is_instance_valid(current_target) or current_target.is_queued_for_deletion() or ("visible" in current_target and not current_target.visible):
		current_target = _get_best_seek_target()
		_random_circle_pos = Vector3.ZERO
		
	if not is_instance_valid(current_target):
		current_action_name = "Circle Around"
		if _random_circle_pos == Vector3.ZERO or car.global_position.distance_squared_to(_random_circle_pos) < 100.0:
			var rand_x = randf_range(-150, 150)
			var rand_z = randf_range(-150, 150)
			_random_circle_pos = car.global_position + Vector3(rand_x, 0, rand_z)
		return driver.navegar_para_ponto(_random_circle_pos, delta)

	var dist_sq = car.global_position.distance_squared_to(current_target.global_position)
	# Após calcular as intencoes de navegação
	var intencoes = driver.navegar_para_ponto(current_target.global_position, delta)
	
	# NOVO: TIMEOUT DO SEEK
	_seek_timer += delta
	if _seek_timer > 10.0:
		radar.ignorar_item(current_target, 15.0)
		current_target = null
		_seek_timer = 0.0
		return intencoes
		
	if dist_sq < 900.0:
		current_action_name = "Grab Object"
		intencoes.throttle = 1.0
		intencoes.force_straight = true
		if current_target.global_position.y - car.global_position.y > 2.0:
			intencoes.jump = true
	else:
		var is_mission = current_target.is_in_group("itens_missao")
		current_action_name = "Seek Fast (Missão)" if is_mission else "Seek (Loot)"
		intencoes.throttle = 1.0 
		
	return intencoes

func _tactic_flee(delta: float) -> Dictionary:
	var intencoes = {"throttle": 1.0, "steering": 0.0, "jump": false, "force_straight": false, "handbrake": false}
	current_action_name = "Normal Flee"
	
	if radar.quadrantes_mapa.size() > 0:
		var best_flee_node = null
		var max_dist = -1.0
		
		for node in radar.quadrantes_mapa:
			var dist_to_enemies = 0.0
			for ini in radar.inimigos_proximos:
				if is_instance_valid(ini):
					dist_to_enemies += node.global_position.distance_squared_to(ini.global_position)
			
			if dist_to_enemies > max_dist:
				max_dist = dist_to_enemies
				best_flee_node = node
				
		if best_flee_node:
			intencoes = driver.navegar_para_ponto(best_flee_node.global_position, delta)
	else:
		var direcao_fuga = Vector3.ZERO
		for ini in radar.inimigos_proximos:
			if is_instance_valid(ini):
				direcao_fuga += (car.global_position - ini.global_position).normalized()
		if direcao_fuga == Vector3.ZERO:
			direcao_fuga = car.global_transform.basis.z 
		var ponto_fuga = car.global_position + (direcao_fuga.normalized() * 50.0)
		intencoes = driver.navegar_para_ponto(ponto_fuga, delta)
	
	intencoes.throttle = 1.0
	
	var ability = car.get_node_or_null("%AbilityComponent")
	if ability and ability.current_energy >= ability.COST_BOOST and ability.current_cooldown <= 0:
		current_action_name = "Fast Flee (Turbo)"
		ability._execute_boost()
		
	if radar.inimigos_proximos.size() > 0 and is_instance_valid(radar.inimigos_proximos[0]):
		var ini_dir = (radar.inimigos_proximos[0].global_position - car.global_position).normalized()
		var forward = car.global_transform.basis.z.normalized()
		if forward.dot(ini_dir) < -0.85 and is_instance_valid(combat):
			current_action_name = "Attack Flee"
			combat.tentar_atirar_pra_tras(radar.inimigos_proximos[0])
			
	return intencoes

func _tactic_wander(delta: float) -> Dictionary:
	if radar.rampas_proximas.size() > 0 and is_instance_valid(radar.rampas_proximas[0]):
		var rampa = radar.rampas_proximas[0]
		var dist_sq = car.global_position.distance_squared_to(rampa.global_position)
		if dist_sq < 10000.0:
			current_action_name = "Seek Ramp"
			var inte = driver.navegar_para_ponto(rampa.global_position, delta)
			inte.throttle = 1.0
			if dist_sq < 100.0: inte.jump = true
			return inte
			
	if radar.teleporters_proximos.size() > 0 and is_instance_valid(radar.teleporters_proximos[0]):
		if car.global_position.distance_squared_to(radar.teleporters_proximos[0].global_position) < 10000.0:
			current_action_name = "Seek Teleport"
			var inte = driver.navegar_para_ponto(radar.teleporters_proximos[0].global_position, delta)
			inte.throttle = 1.0
			return inte

	if _roam_pause_timer > 0.0:
		current_action_name = "Roam Pause"
		_roam_pause_timer -= delta
		return {"throttle": 0.0, "steering": 0.0, "jump": false, "force_straight": false, "handbrake": true}
		
	if randf() < 0.005:
		_roam_pause_timer = randf_range(2.0, 4.0)
		
	current_action_name = "Roam Around"
	if _random_circle_pos == Vector3.ZERO or car.global_position.distance_squared_to(_random_circle_pos) < 100.0:
		if radar.quadrantes_mapa.size() > 0:
			_random_circle_pos = radar.quadrantes_mapa.pick_random().global_position
		else:
			_random_circle_pos = car.global_position + Vector3(randf_range(-100, 100), 0, randf_range(-100, 100))
			
	var intencoes = driver.navegar_para_ponto(_random_circle_pos, delta)
	intencoes.throttle = 0.9
	return intencoes
	
func _get_best_combat_target() -> Node3D:
	if radar.inimigos_proximos.is_empty(): return null
	
	# Desempate 1: Vingança (Último que atirou) com checagem reforçada
	if is_instance_valid(_last_attacker) and not _last_attacker.is_queued_for_deletion() and radar.inimigos_proximos.has(_last_attacker):
		return _last_attacker
		
	# Inicia nulo para evitar fantasmas
	var best_target: Node3D = null
	var highest_hp_pct = -1.0
	
	for ini in radar.inimigos_proximos:
		# Filtro anti-crash
		if is_instance_valid(ini) and not ini.is_queued_for_deletion():
			var t_stats = ini.get_node_or_null("%StatsComponent")
			if t_stats:
				var hp_pct = (t_stats.current_health / t_stats.max_health) * 100.0
				if hp_pct > highest_hp_pct:
					highest_hp_pct = hp_pct
					best_target = ini
			else:
				# Fallback de segurança se o objeto não tiver Stats
				if highest_hp_pct == -1.0: 
					best_target = ini
					
	return best_target

func _get_best_seek_target() -> Node3D:
	if brain.mission_target_collect_id != "" and radar.itens_missao_proximos.size() > 0:
		for m in radar.itens_missao_proximos:
			if is_instance_valid(m) and not m.is_queued_for_deletion() and ("visible" not in m or m.visible): 
				return m
			
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	if health_pct < 20.0 and radar.vida_proxima.size() > 0:
		for v in radar.vida_proxima:
			if is_instance_valid(v) and not v.is_queued_for_deletion(): return v
		
	if is_instance_valid(combat) and combat.get_total_ammo() < 3 and radar.armas_proximas.size() > 0:
		for a in radar.armas_proximas:
			if is_instance_valid(a) and not a.is_queued_for_deletion(): return a
		
	return null
