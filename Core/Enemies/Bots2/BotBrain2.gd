extends Node
class_name BotBrainV2

@export_group("IA Core & Missões")
@export var mission_target_collect_id : String = ""
@export var mission_target_destroy_id : String = ""
@export_range(0.0, 2.0) var global_aggression: float = 1.0 

enum MacroState { WANDER, SEEK, BATTLE, FLEE }
var current_macro_state: MacroState = MacroState.WANDER

var tempo_no_estado : float = 0.0 
var state_lock_timer : float = 0.0

var car: BaseVehicle
var input: Node 
var stats: Node

var debug_label_macro: Label3D
var debug_label_micro: Label3D

# --- COMPONENTES FILHOS ---
var radar : BotRadarV2
var driver : BotDriverV2
var combat : BotCombatModuleV2
var tactics : BotTacticsV2 

# --- MEMÓRIA DE CURTO PRAZO ---
var _last_health_pct: float = 100.0
var _oportunidade_ativa: Node3D = null
var _tempo_oportunidade: float = 0.0
var _is_sleeping: bool = false
var _lod_check_timer: float = 0.0
var ameacas_detectadas : int = 0

func _ready():
	car = get_parent() as BaseVehicle
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
	
	# Configura todos os módulos injetando as referências
	driver.setup(car, input)
	combat.setup(car, input, stats, radar)
	tactics.setup(car, self, driver, radar, combat, stats)
	
	_lod_check_timer = randf_range(0.0, 1.0)
	
	# --- SETUP DOS LABELS DE DEBUG ---
	debug_label_macro = Label3D.new()
	debug_label_macro.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label_macro.no_depth_test = true # Aparece através das paredes!
	debug_label_macro.position = Vector3(0, 7.0, 0) # Altura ajustada para 7 metros
	debug_label_macro.pixel_size = 0.075 # 2.5x maior (era 0.03)
	debug_label_macro.modulate = Color(1.0, 0.8, 0.0)
	debug_label_macro.outline_render_priority = 0
	debug_label_macro.outline_modulate = Color.BLACK
	car.call_deferred("add_child", debug_label_macro)

	debug_label_micro = Label3D.new()
	debug_label_micro.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label_micro.no_depth_test = true
	debug_label_micro.position = Vector3(0, 5.5, 0) # Altura ajustada para 5.5 metros
	debug_label_micro.pixel_size = 0.05 # 2.5x maior (era 0.02)
	debug_label_micro.modulate = Color.WHITE
	debug_label_micro.outline_render_priority = 0
	debug_label_micro.outline_modulate = Color.BLACK
	car.call_deferred("add_child", debug_label_micro)

func _process(delta):
	if not is_instance_valid(car) or not is_instance_valid(input) or not is_instance_valid(stats): return
	if not car.pode_mover or (car.has_method("is_frozen") and car.is_frozen()): 
		_reset_inputs()
		return
		
	# LOD & Hibernação
	_lod_check_timer -= delta
	if _lod_check_timer <= 0:
		_update_lod_status()
		_lod_check_timer = 1.0 + randf_range(0.0, 0.3) 
		
	if _is_sleeping:
		_reset_inputs()
		if "handbrake" in input: input.handbrake = true
		return
		
	# 1. Reflexos
	if driver.processar_manobras_travantes(delta): return
	
	tempo_no_estado += delta
	
# 2. ESCANEAMENTO DO RADAR
	radar.escanear_ambiente(car, delta)
	# --- REAÇÃO A AMEAÇAS E DEFESA ---
	if radar.checar_ameacas_imediatas(car):
		ameacas_detectadas += 1
		if is_instance_valid(combat): combat.reagir_a_ameaca(ameacas_detectadas)
	
	# NOVO: Atualiza os timers do combate (Armas e Munição)
	if is_instance_valid(combat):
		combat.processar_combate(delta)
	
	# 3. Verificação do Instinto Oportunista
	if _processar_oportunismo(delta):
		return 
		
	# 4. Avaliação de Utilidade
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	var damage_taken_instantly = _last_health_pct - health_pct
	_last_health_pct = health_pct
	
	if state_lock_timer > 0.0:
		state_lock_timer -= delta
		if damage_taken_instantly >= 15.0:
			state_lock_timer = 0.0
			print("[BotBrainV2] Dano massivo detectado! Repensando tática!")
	
	if state_lock_timer <= 0.0:
		_evaluate_utility()
		state_lock_timer = 5.0
		tempo_no_estado = 0.0
		
	# 5. Execução Tática delegada ao BotTacticsV2
	if is_instance_valid(tactics):
		tactics.execute(delta, current_macro_state)
		
	# 6. ATUALIZAÇÃO DOS LABELS DE DEBUG
	if is_instance_valid(debug_label_macro):
		debug_label_macro.text = MacroState.keys()[current_macro_state]
		
	if is_instance_valid(debug_label_micro) and is_instance_valid(tactics):
		if _oportunidade_ativa: # Se o Instinto ativou, avisa na tela!
			debug_label_micro.text = "INSTINTO OPORTUNISTA!"
			debug_label_micro.modulate = Color.RED
		else:
			debug_label_micro.text = tactics.current_action_name
			debug_label_micro.modulate = Color.WHITE

func _evaluate_utility():
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	var ammo_total = combat.get_total_ammo() if is_instance_valid(combat) else 0
	
	# Raio de combate normal (200m)
	var tem_inimigo_perto = _tem_inimigo_em_raio(40000.0) 
	# Raio de perigo extremo (50m = 50 * 50 = 2500)
	var tem_inimigo_muito_perto = _tem_inimigo_em_raio(2500.0) 
	
	var tem_item_missao = (mission_target_collect_id != "" and radar.itens_missao_proximos.size() > 0)
	
	var score_wander = 30.0 
	var score_seek = 0.0
	var score_battle = 0.0
	var score_flee = 0.0
	
	# --- CÁLCULO FLEE ---
	# Só foge desesperado se estiver morrendo E o inimigo estiver a menos de 50 metros!
	if health_pct < 20.0 and tem_inimigo_muito_perto:
		score_flee = 100.0 
		
	# --- CÁLCULO BATTLE ---
	if health_pct >= 20.0 and ammo_total >= 6 and tem_inimigo_perto:
		score_battle = 80.0 * global_aggression
		if current_macro_state == MacroState.BATTLE: score_battle += 15.0 

	# --- CÁLCULO SEEK ---
	# Se a vida está < 20.0, MAS ele já despistou o inimigo (> 50m), o Flee é 0 e o Seek passa a ser prioridade máxima (85)!
	if health_pct < 20.0 and radar.vida_proxima.size() > 0:
		score_seek = 85.0
	elif ammo_total < 3 and radar.armas_proximas.size() > 0:
		score_seek = 80.0
		
	if tem_item_missao and not tem_inimigo_perto:
		score_seek = 95.0
		
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
		if is_instance_valid(tactics):
			tactics.reset_target() # Avisa a tática para limpar os alvos focados!

func _processar_oportunismo(delta: float) -> bool:
	if is_instance_valid(radar.item_oportunidade):
		if randf() <= 0.5: 
			_oportunidade_ativa = radar.item_oportunidade
			_tempo_oportunidade = 2.0 
		radar.iniciar_cooldown_oportunidade(8.0) 
		
	if is_instance_valid(_oportunidade_ativa):
		_tempo_oportunidade -= delta
		if _tempo_oportunidade <= 0.0 or not _oportunidade_ativa.is_inside_tree():
			_oportunidade_ativa = null
			return false
			
		var intencoes = driver.navegar_para_ponto(_oportunidade_ativa.global_position, delta)
		driver.aplicar_inputs_finais(delta, intencoes)
		return true 
		
	return false

func _tem_inimigo_em_raio(raio_sq: float) -> bool:
	var car_pos = car.global_position
	for ini in radar.inimigos_proximos:
		if is_instance_valid(ini) and ini.global_position.distance_squared_to(car_pos) <= raio_sq:
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
		_is_sleeping = false
		if closest_dist_sq < 250000.0:
			pass # Processamento normal
		else:
			_is_sleeping = true
	else:
		_is_sleeping = false

func _reset_inputs():
	input.throttle = 0.0
	input.steering = 0.0
	input.pitch = 0.0
	if "handbrake" in input: input.handbrake = false
	input.is_action_pressed = false
