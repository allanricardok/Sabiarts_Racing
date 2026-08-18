extends Node
class_name BotBrainV2

@export_group("IA Core & Missões")
@export var mission_target_collect_id : String = ""
@export var mission_target_destroy_id : String = ""
@export_range(0.0, 2.0) var global_aggression: float = 1.0 

@export_group("Foco no Player (Agressividade)")
@export_range(0.0, 100.0) var player_focus_base: float = 10.0 
@export_range(0.0, 33.0) var player_focus_variance: float = 33.0 

@export_group("Relação entre Bots (Amizade/Hostilidade)")
@export_range(0.0, 100.0) var bot_hostility_base: float = 100.0 
@export_range(0.0, 33.0) var bot_hostility_variance: float = 0.0

enum MacroState { WANDER, SEEK, BATTLE, FLEE }
var current_macro_state: MacroState = MacroState.WANDER

var tempo_no_estado : float = 0.0 
var state_lock_timer : float = 0.0

var car: Node3D 
var input: Node 
var stats: Node

# --- COMPONENTES FILHOS ---
var radar : BotRadarV2
var driver : BotDriverV2
var combat : BotCombatModuleV2
var tactics : BotTacticsV2 

# --- MEMÓRIA DE CURTO PRAZO ---
var _last_health_pct: float = 100.0
var _oportunidade_ativa: Node3D = null
var _tempo_oportunidade: float = 0.0
var ameacas_detectadas : int = 0
var _blacklisted_loots: Array[Node3D] = [] 

# --- PERSONALIDADE & ALVOS ---
var _my_player_focus_chance: float = 0.0 
var _my_bot_hostility_chance: float = 100.0 
var _player_radar_timer: float = 0.0
var _cached_player_target: Node3D = null
var _current_brain_target: Node3D = null # Trava anti-spam do log

# --- LOD E CAÇADOR DE LONGA DISTÂNCIA ---
var _is_sleeping: bool = false
var _is_out_of_range: bool = false
var _time_out_of_lod: float = 0.0
var _is_hunting_player: bool = false
var _lod_check_timer: float = 0.0
var _lod_quadrant_timer: float = 0.0
var _lod_forced_throttle: float = 0.0
var _lod_forced_steer: float = 0.0

# --- ANTI-STUCK ---
var _stuck_timer: float = 0.0
var _last_pos_check: Vector3 = Vector3.ZERO
var _is_unstucking: bool = false
var _unstuck_timer: float = 0.0
var _unstuck_phase: int = 0
var _reverse_tap_timer: float = 0.0 

# --- OTIMIZAÇÃO (TIME-SLICING) ---
var _think_timer: float = 0.0
var _think_interval: float = 0.1 
var _cached_intencoes: Dictionary = {"throttle": 0.0, "steering": 0.0, "jump": false, "force_straight": false, "handbrake": false}

# --- DEBUG VISUAL ---
var debug_label_macro: Label3D
var debug_label_micro: Label3D

func _ready():
	car = get_parent()
	if not is_instance_valid(car): return 
	
	input = car.get_node_or_null("%InputComponent")
	stats = car.get_node_or_null("%StatsComponent")
	
	if input: input.is_bot = true
	if stats: _last_health_pct = (stats.current_health / stats.max_health) * 100.0
	
	radar = BotRadarV2.new()
	radar.name = "BotRadarV2"
	add_child(radar)
	
	driver = BotDriverV2.new()
	driver.name = "BotDriverV2"
	add_child(driver)
	
	combat = BotCombatModuleV2.new()
	combat.name = "BotCombatModuleV2"
	add_child(combat)
	
	tactics = BotTacticsV2.new()
	tactics.name = "BotTacticsV2"
	add_child(tactics)
	
	driver.setup(car, input)
	combat.setup(car, input, stats, radar)
	tactics.setup(car, self, driver, radar, combat, stats)
	
	_my_player_focus_chance = clamp(player_focus_base + randf_range(-player_focus_variance, player_focus_variance), 0.0, 100.0)
	_my_bot_hostility_chance = clamp(bot_hostility_base + randf_range(-bot_hostility_variance, bot_hostility_variance), 0.0, 100.0)
	
	_lod_check_timer = _apply_variance(1.0)
	_player_radar_timer = randf_range(0.0, 5.0) 
	_scan_for_closest_player()
	
	call_deferred("_setup_initial_position")
	
	debug_label_macro = Label3D.new()
	debug_label_macro.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label_macro.no_depth_test = true
	debug_label_macro.position = Vector3(0, 7.0, 0) 
	debug_label_macro.pixel_size = 0.075 
	debug_label_macro.modulate = Color(1.0, 0.8, 0.0)
	debug_label_macro.outline_render_priority = 0
	debug_label_macro.outline_modulate = Color.BLACK
	car.call_deferred("add_child", debug_label_macro)

	debug_label_micro = Label3D.new()
	debug_label_micro.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label_micro.no_depth_test = true
	debug_label_micro.position = Vector3(0, 5.5, 0) 
	debug_label_micro.pixel_size = 0.05 
	debug_label_micro.modulate = Color.WHITE
	debug_label_micro.outline_render_priority = 0
	debug_label_micro.outline_modulate = Color.BLACK
	car.call_deferred("add_child", debug_label_micro)

func _setup_initial_position():
	if is_instance_valid(car): _last_pos_check = car.global_position

func _apply_variance(base_value: float) -> float:
	return base_value * randf_range(0.85, 1.15)

func _physics_process(delta):
	if not is_instance_valid(car) or not is_instance_valid(input) or not is_instance_valid(stats): return
	if not car.get("pode_mover") or (car.has_method("is_frozen") and car.is_frozen()): 
		_reset_inputs()
		return
		
	if _is_unstucking:
		_unstuck_timer -= delta
		if _unstuck_timer <= 0.0: _is_unstucking = false
		else: _perform_unstuck_sequence()
		return 

	_lod_check_timer -= delta
	if _lod_check_timer <= 0:
		_update_lod_status()
		_lod_check_timer = _apply_variance(1.15) 

	if _is_out_of_range:
		_time_out_of_lod += delta
		if _time_out_of_lod >= 15.0:
			_is_sleeping = false
			_is_hunting_player = true
		else:
			_is_sleeping = true
			_is_hunting_player = false
	else:
		_time_out_of_lod = 0.0
		_is_sleeping = false
		_is_hunting_player = false
		
	if _is_sleeping:
		_process_lod_quadrant_rotation(delta)
		return
		
	_player_radar_timer -= delta
	if _player_radar_timer <= 0.0:
		_player_radar_timer = _apply_variance(5.0)
		_scan_for_closest_player()

	_stuck_timer += delta
	if _stuck_timer >= 2.0:
		var dist_moved = car.global_position.distance_to(_last_pos_check)
		if dist_moved < 4.0:
			_initiate_unstuck_maneuver()
		_last_pos_check = car.global_position
		_stuck_timer = 0.0
		
	if driver.processar_manobras_travantes(delta): return
	tempo_no_estado += delta
	
	radar.escanear_ambiente(car, delta)
	if is_instance_valid(combat): combat.processar_combate(delta)
		
	if radar.checar_ameacas_imediatas(car):
		ameacas_detectadas += 1
		if is_instance_valid(combat): combat.reagir_a_ameaca(ameacas_detectadas)
	
	if _processar_oportunismo(delta): return 
		
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	var damage_taken_instantly = _last_health_pct - health_pct
	_last_health_pct = health_pct
	
	if state_lock_timer > 0.0:
		state_lock_timer -= delta
		if damage_taken_instantly >= 15.0:
			state_lock_timer = 0.0
	
	if state_lock_timer <= 0.0 or _is_hunting_player:
		_evaluate_utility()
		state_lock_timer = _apply_variance(5.0)
		tempo_no_estado = 0.0
		
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = _think_interval 
		if is_instance_valid(tactics):
			_cached_intencoes = tactics.execute(delta, current_macro_state)
			
	# ====================================================================
	# OVERRIDE SENSORIAL: DESVIO DE MINAS ALIADAS
	# Roda exatamente antes de passar a decisão para o InputFinal
	# ====================================================================
	_processar_desvio_de_minas(_cached_intencoes)
			
	if is_instance_valid(driver):
		driver.aplicar_inputs_finais(delta, _cached_intencoes)
		_cached_intencoes["jump"] = false 
		
	if input.throttle < -0.1 and car.get("linear_velocity") and car.linear_velocity.length() < 1.5:
		_reverse_tap_timer += delta
		if _reverse_tap_timer > 0.2:
			input.throttle = 0.0 
			_reverse_tap_timer = 0.0
	else:
		_reverse_tap_timer = 0.0
		
	if is_instance_valid(debug_label_macro):
		if _is_hunting_player:
			debug_label_macro.text = "TERMINATOR (HUNTING)"
			debug_label_macro.modulate = Color.RED
		else:
			debug_label_macro.text = MacroState.keys()[current_macro_state]
			debug_label_macro.modulate = Color(1.0, 0.8, 0.0)
		
	if is_instance_valid(debug_label_micro) and is_instance_valid(tactics):
		if _oportunidade_ativa:
			debug_label_micro.text = "INSTINTO OPORTUNISTA!"
			debug_label_micro.modulate = Color(1.0, 0.0, 0.0)
		else:
			debug_label_micro.text = tactics.current_action_name
			debug_label_micro.modulate = Color(1.0, 1.0, 1.0)


# ====================================================================
# LÓGICA DE DETECÇÃO E DESVIO ESPACIAL
# ====================================================================
func _processar_desvio_de_minas(intencoes: Dictionary):
	var closest_mine: Node3D = null
	var closest_dist_z: float = -999.0

	for mine in LandMine.active_bot_mines:
		if not is_instance_valid(mine) or mine.is_queued_for_deletion(): continue

		# Transforma a posição da mina para o espaço local do carro
		# Eixo Z: Negativo é na frente. Eixo X: Positivo é direita, Negativo é esquerda.
		var local_pos = car.global_transform.inverse() * mine.global_position

		# Se a mina estiver em um raio entre 0 e 40 metros na nossa frente
		if local_pos.z < 0.0 and local_pos.z > -40.0:
			# Se a mina estiver na nossa rota de colisão frontal (6 metros pra cada lado)
			if abs(local_pos.x) < 6.0:
				if local_pos.z > closest_dist_z: # Mais perto de zero significa mais próximo de nós
					closest_dist_z = local_pos.z
					closest_mine = mine

	if closest_mine:
		var local_pos = car.global_transform.inverse() * closest_mine.global_position

		# Puxa o volante violentamente para o lado oposto do obstáculo
		var direcao_fuga = -1.0 if local_pos.x >= 0 else 1.0

		# Intensidade aumenta quanto mais perto a mina estiver (de 0.3 a 1.0 total)
		var intensidade = clamp(1.0 - (abs(local_pos.z) / 40.0), 0.3, 1.0)
		intencoes["steering"] = direcao_fuga * intensidade

		# Se a mina estiver muito perto (menos de 20 metros), ele tenta brecar o avanço
		if abs(local_pos.z) < 20.0:
			intencoes["throttle"] = min(intencoes.get("throttle", 1.0), 0.3)
			if abs(local_pos.z) < 8.0:
				intencoes["handbrake"] = true


# ====================================================================
# ESCOLHA INTELIGENTE DE ALVOS (ANTI-SPAM)
# ====================================================================
func _decide_battle_target():
	var final_target: Node3D = null
	
	if _is_hunting_player and is_instance_valid(_cached_player_target):
		final_target = _cached_player_target
	else:
		if is_instance_valid(_cached_player_target):
			var dice_roll = randf() * 100.0
			if dice_roll <= _my_player_focus_chance:
				final_target = _cached_player_target

		if final_target == null and radar.inimigos_proximos.size() > 0:
			var bot_dice = randf() * 100.0
			if bot_dice <= _my_bot_hostility_chance:
				var target_is_weakest = (randf() <= 0.25)
				final_target = _find_best_bot_target(target_is_weakest)

	if final_target == null:
		if _current_brain_target != null:
			print("[BotBrainV2] ", car.name, " perdeu os alvos visíveis. Voltando para WANDER!")
			_current_brain_target = null
			
		current_macro_state = MacroState.WANDER
		if is_instance_valid(tactics): tactics.reset_target()
		if is_instance_valid(combat) and "target" in combat: combat.target = null
		return
		
	# LOG E ATUALIZAÇÃO APENAS SE MUDOU DE ALVO
	if final_target != _current_brain_target:
		print("[BotBrainV2] ⚔️ ALVO TRAVADO! ", car.name, " vai atacar -> ", final_target.name)
		_current_brain_target = final_target
		
	if is_instance_valid(tactics):
		if tactics.has_method("set_forced_target"):
			tactics.set_forced_target(final_target)
		elif "target" in tactics: 
			tactics.target = final_target

	# APLICA A DECISÃO TAMBÉM NAS ARMAS (Evita Fogo Amigo Rebelde)
	if is_instance_valid(combat):
		if combat.has_method("set_target"):
			combat.set_target(final_target)
		elif "target" in combat:
			combat.target = final_target

func _find_best_bot_target(buscar_fraco: bool) -> Node3D:
	var best_target: Node3D = null
	var best_health: float = 999999.0 if buscar_fraco else -1.0
	
	for ini in radar.inimigos_proximos:
		if not is_instance_valid(ini) or ini.is_queued_for_deletion(): continue
		var ini_stats = ini.get_node_or_null("%StatsComponent")
		if ini_stats:
			var hp = ini_stats.current_health
			if buscar_fraco and hp < best_health:
				best_health = hp
				best_target = ini
			elif not buscar_fraco and hp > best_health:
				best_health = hp
				best_target = ini
	return best_target

func _scan_for_closest_player():
	_cached_player_target = null
	var jogadores = get_tree().get_nodes_in_group("jogadores")
	var closest_dist_sq = 999999999.0 
	
	for p in jogadores:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			var inp = p.get_node_or_null("%InputComponent")
			if inp and "is_bot" in inp and not inp.is_bot:
				var d_sq = car.global_position.distance_squared_to(p.global_position)
				if d_sq <= closest_dist_sq:
					closest_dist_sq = d_sq
					_cached_player_target = p

# ====================================================================
# SEQUÊNCIA DE DESTRAVAMENTO FÍSICO
# ====================================================================
func _initiate_unstuck_maneuver():
	if is_instance_valid(_oportunidade_ativa):
		if not _blacklisted_loots.has(_oportunidade_ativa):
			_blacklisted_loots.append(_oportunidade_ativa)
		_oportunidade_ativa = null

	_is_unstucking = true
	_unstuck_timer = 1.5
	_unstuck_phase = 0
	current_macro_state = MacroState.FLEE
	state_lock_timer = _apply_variance(6.0)
	if is_instance_valid(tactics): tactics.reset_target()

func _perform_unstuck_sequence():
	if _unstuck_timer > 1.0:
		if _unstuck_phase == 0:
			_unstuck_phase = 1
			var mass = car.get("mass") if car.get("mass") else 1000.0
			car.apply_central_impulse(Vector3.UP * mass * 6.0)
			var spin_dir = 1.0 if randf() > 0.5 else -1.0
			car.apply_torque_impulse(car.global_transform.basis.y * mass * 18.0 * spin_dir)
		input.throttle = 0.0
		input.steering = 0.0
	else:
		input.throttle = 1.0
		input.steering = 0.0

# ====================================================================
# ROTAÇÃO DE QUADRANTE E UTILIDADE
# ====================================================================
func _process_lod_quadrant_rotation(delta):
	_lod_quadrant_timer -= delta
	if _lod_quadrant_timer <= 0.0:
		if _lod_forced_throttle == 0.0:
			_lod_forced_throttle = 1.0
			_lod_forced_steer = randf_range(-1.0, 1.0)
			_lod_quadrant_timer = _apply_variance(5.0)
		else:
			_lod_forced_throttle = 0.0
			_lod_forced_steer = 0.0
			_lod_quadrant_timer = _apply_variance(15.0)
			
	input.throttle = _lod_forced_throttle
	input.steering = _lod_forced_steer
	input.pitch = 0.0
	if "handbrake" in input: input.handbrake = (_lod_forced_throttle == 0.0)

func _evaluate_utility():
	if _is_hunting_player:
		if current_macro_state != MacroState.BATTLE:
			current_macro_state = MacroState.BATTLE
		_decide_battle_target()
		return 

	var health_pct = (stats.current_health / stats.max_health) * 100.0
	var ammo_total = combat.get_total_ammo() if is_instance_valid(combat) else 0
	
	var tem_inimigo_perto = _tem_inimigo_em_raio(4000000.0) 
	var tem_inimigo_muito_perto = _tem_inimigo_em_raio(2500.0) 
	var tem_item_missao = (mission_target_collect_id != "" and radar.itens_missao_proximos.size() > 0)
	
	var score_wander = _apply_variance(30.0) 
	var score_seek = 0.0
	var score_battle = 0.0
	var score_flee = 0.0
	
	if health_pct < 25.0 and tem_inimigo_muito_perto:
		score_flee = _apply_variance(200.0) 
		
	if health_pct < 25.0 and radar.vida_proxima.size() > 0:
		score_seek = _apply_variance(150.0)
		
	if tem_item_missao and not tem_inimigo_perto:
		score_seek = max(score_seek, _apply_variance(120.0)) 
		
	if health_pct >= 25.0 and ammo_total > 0 and tem_inimigo_perto:
		score_battle = _apply_variance(100.0) * global_aggression
		if current_macro_state == MacroState.BATTLE: score_battle += 20.0 

	if ammo_total <= 0:
		if radar.armas_proximas.size() > 0:
			score_seek = max(score_seek, _apply_variance(80.0))
		elif tem_inimigo_perto:
			score_flee = max(score_flee, _apply_variance(90.0))
		
	var highest_score = score_wander
	var winner_state = MacroState.WANDER
	
	if score_seek > highest_score:
		highest_score = score_seek
		winner_state = MacroState.SEEK
	if score_battle > highest_score:
		highest_score = score_battle
		winner_state = MacroState.BATTLE
	if score_flee > highest_score:
		highest_score = score_flee
		winner_state = MacroState.FLEE
		
	if current_macro_state != winner_state:
		current_macro_state = winner_state
		if winner_state == MacroState.BATTLE:
			_decide_battle_target()
		else:
			if is_instance_valid(tactics): tactics.reset_target()
			
	elif current_macro_state == MacroState.BATTLE:
		if is_instance_valid(tactics):
			var current_target = tactics.get("target") if "target" in tactics else null
			if not is_instance_valid(current_target):
				_decide_battle_target()

func _processar_oportunismo(delta: float) -> bool:
	if current_macro_state == MacroState.BATTLE:
		return false 
		
	if is_instance_valid(radar.item_oportunidade) and not _blacklisted_loots.has(radar.item_oportunidade):
		_oportunidade_ativa = radar.item_oportunidade
		_tempo_oportunidade = _apply_variance(4.0) 
		
	if is_instance_valid(_oportunidade_ativa):
		_tempo_oportunidade -= delta
		if _tempo_oportunidade <= 0.0 or not _oportunidade_ativa.is_inside_tree():
			if is_instance_valid(_oportunidade_ativa) and not _blacklisted_loots.has(_oportunidade_ativa):
				_blacklisted_loots.append(_oportunidade_ativa)
			_oportunidade_ativa = null
			return false
			
		var intencoes = driver.navegar_para_ponto(_oportunidade_ativa.global_position, delta)
		if is_instance_valid(driver):
			driver.aplicar_inputs_finais(delta, intencoes)
		return true 
		
	return false

func _tem_inimigo_em_raio(raio_sq: float) -> bool:
	var car_pos = car.global_position
	for ini in radar.inimigos_proximos:
		if is_instance_valid(ini) and not ini.is_queued_for_deletion() and ini.global_position.distance_squared_to(car_pos) <= raio_sq:
			return true
	return false

func _update_lod_status():
	var jogadores = get_tree().get_nodes_in_group("jogadores")
	var closest_dist_sq = 99999999.0
	var cached_human = null
	
	for p in jogadores:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			var inp = p.get_node_or_null("%InputComponent")
			if inp and "is_bot" in inp and not inp.is_bot:
				var d_sq = car.global_position.distance_squared_to(p.global_position)
				if d_sq < closest_dist_sq:
					closest_dist_sq = d_sq
					cached_human = p

	if is_instance_valid(cached_human):
		if closest_dist_sq < 10000.0:
			_think_interval = _apply_variance(0.05)
			if is_instance_valid(driver): driver.current_lod_level = 0
			_is_out_of_range = false
		elif closest_dist_sq < 62500.0:
			_think_interval = _apply_variance(0.2)
			if is_instance_valid(driver): driver.current_lod_level = 1
			_is_out_of_range = false
		elif closest_dist_sq < 250000.0:
			_think_interval = _apply_variance(0.5)
			if is_instance_valid(driver): driver.current_lod_level = 2 
			_is_out_of_range = false
		else:
			_is_out_of_range = true
	else:
		_think_interval = _apply_variance(0.3)
		_is_out_of_range = false

func _reset_inputs():
	input.throttle = 0.0
	input.steering = 0.0
	input.pitch = 0.0
	if "handbrake" in input: input.handbrake = false
	input.is_action_pressed = false
