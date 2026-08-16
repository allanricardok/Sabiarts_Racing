# StoryModeController.gd
extends Node
class_name StoryModeController

@export_group("Referências do Mapa")
@export var world_env: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var mission_ui: CanvasLayer 
@export var result_ui: CanvasLayer 
@export var bot_spawnerV2: Node 

var last_played_mission: StoryMissionData = null
var last_played_portal: StoryMissionPortal = null

var original_env: Environment
var original_sun_color: Color
var original_sun_energy: float

var current_mission: StoryMissionData
var active_portal: StoryMissionPortal
var mission_timer: float = 0.0
var is_mission_running: bool = false
# --- VARIÁVEIS MULTI-TASK ---
var multitask_progress: Dictionary = {}

var active_classic_objective: MissionItem = null

var combat_targets: Array[Node] = []
var spawned_bots: Array[Node] = []
var original_transforms: Dictionary = {}

var completed_tiers_this_run: Array[int] = []
var current_tracked_progress: float = 0.0
var current_tracked_score: float = 0.0

# --- NOVAS VARIÁVEIS PARA DELIVERY ---
var delivery_items_held: int = 0
var delivery_items_delivered: int = 0

# --- GERENCIADORES INTERNOS (COMPOSIÇÃO) ---
var lifecycle: StoryMissionLifecycle
var physics: StoryMissionPhysics

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS 
	add_to_group("StoryController")
	
	# Instancia os componentes de lógica e os adiciona à árvore de cena
	lifecycle = StoryMissionLifecycle.new()
	add_child(lifecycle)
	lifecycle.setup(self)
	
	physics = StoryMissionPhysics.new()
	add_child(physics)
	physics.setup(self)
	
	if world_env: original_env = world_env.environment
	if sun_light:
		original_sun_color = sun_light.light_color
		original_sun_energy = sun_light.light_energy
		
	if is_instance_valid(ScoreManager) and ScoreManager.has_signal("score_changed"):
		ScoreManager.score_changed.connect(_on_global_score_changed)

		
	call_deferred("_setup_inicial_seguro")
	call_deferred("_check_next_map_unlock")

# ====================================================================
# LIMPEZA OBRIGATÓRIA AO SAIR DO MAPA (END RUN)
# ====================================================================
func _exit_tree():
	print("[StoryController] Mapa descarregado. Limpando dados fantasmas da memória...")
	force_cancel_all_missions()

func force_cancel_all_missions():
	is_mission_running = false
	current_mission = null
	active_portal = null
	active_classic_objective = null
	combat_targets.clear()
	spawned_bots.clear()
	completed_tiers_this_run.clear()
	current_tracked_progress = 0.0
	current_tracked_score = 0.0
	delivery_items_held = 0
	delivery_items_delivered = 0
	multitask_progress.clear()
# ====================================================================

func _on_global_score_changed(_player_id: int, new_score: int):
	current_tracked_score = float(new_score)

func _on_mission_progress_updated(mission: MissionItem, current: float, _target: float):
	if is_instance_valid(active_classic_objective) and mission == active_classic_objective:
		current_tracked_progress = current

func _on_mission_progress_completed(mission: MissionItem):
	if is_instance_valid(active_classic_objective) and mission == active_classic_objective:
		active_classic_objective.is_completed = true
		current_tracked_progress = max(current_tracked_progress, mission.target_value)

func _setup_inicial_seguro():
	get_tree().call_group("HUD", "atualizar_timer", 0.0)
	get_tree().call_group("HUD", "esconder_timer")
	get_tree().call_group("HUD", "esconder_missao_ativa")

# ============================================================================
# O GERENTE ÚNICO DE PROGRESSO

# ============================================================================
# O GERENTE ÚNICO DE PROGRESSO
# ============================================================================
func notify_progress(type: int, raw_value, item_id: String = ""):
	if not is_mission_running or not current_mission: return
	var value = float(raw_value)
	
	# REGRA DE PROTEÇÃO 1: O evento pertence ao tipo de missão atual? (Agora aceita MULTI_TASK)
	if current_mission.mission_type != type and current_mission.mission_type != StoryMissionData.MissionType.MULTI_TASK: return
	
	# =================================================================
	# NOVA ROTA: LÓGICA MULTI_TASK (CHECKLIST)
	# =================================================================
	if current_mission.mission_type == StoryMissionData.MissionType.MULTI_TASK:
		for i in range(current_mission.mission_tiers.size()):
			var tier = current_mission.mission_tiers[i]
			if not tier: continue
			
			# Se o grito for do tipo que essa Tier está pedindo...
			if tier.tier_mission_type == type:
				# Verifica se a Tier exige um objeto específico
				if tier.tier_target_id != "" and item_id != "" and item_id != tier.tier_target_id:
					continue
				
				var prev_prog = multitask_progress.get(i, 0.0)
				var new_prog = prev_prog
				
				# Aplica as regras de cada tipo independentemente!
				match type:
					StoryMissionData.MissionType.SPEED, StoryMissionData.MissionType.SCORE_COMBO:
						if value > prev_prog: new_prog = value
					StoryMissionData.MissionType.COLLECT, StoryMissionData.MissionType.ROADKILL, StoryMissionData.MissionType.DESTROY, StoryMissionData.MissionType.DELIVERY:
						new_prog += value
					StoryMissionData.MissionType.GAP, StoryMissionData.MissionType.EXPLORE:
						new_prog = 1.0
						
				multitask_progress[i] = new_prog
				
				if new_prog > prev_prog and new_prog <= tier.target_value:
					var texto = tier.tier_name + ": " + str(int(new_prog)) + "/" + str(int(tier.target_value))
					get_tree().call_group("HUD", "criar_toast", texto, Color.CORNFLOWER_BLUE)
					
		return # Encerra aqui, pois o Multi-Task já cuidou do evento!
	
# --- A CORREÇÃO DO FILTRO (Agora aceita Delivery e Defend) ---
	var is_delivery_action = (type == StoryMissionData.MissionType.DELIVERY and item_id in ["collect", "dropoff"])
	var is_defend_action = (type == StoryMissionData.MissionType.DEFEND and item_id == "vip_destroyed")
	
	if not is_delivery_action and not is_defend_action:
		if current_mission.mission_id != "" and item_id != "" and item_id != current_mission.mission_id:
			return
			
	var progresso_antigo = current_tracked_progress
		
	# CALCULA A META CORRETA MESMO SE USAR TIERS (Correção da Imagem 3)
	var meta = int(current_mission.base_target_value)
	if not current_mission.mission_tiers.is_empty():
		for tier in current_mission.mission_tiers:
			if tier and current_tracked_progress < int(tier.target_value):
				meta = int(tier.target_value)
				break
		if meta == int(current_mission.base_target_value) and current_mission.mission_tiers.size() > 0:
			var last_tier = current_mission.mission_tiers[-1]
			if last_tier: meta = int(last_tier.target_value)
			
	# APLICAÇÃO DAS REGRAS
	match type:
		StoryMissionData.MissionType.SPEED, StoryMissionData.MissionType.SCORE_COMBO:
			if value > current_tracked_progress:
				current_tracked_progress = value
				
		StoryMissionData.MissionType.COLLECT, StoryMissionData.MissionType.ROADKILL, StoryMissionData.MissionType.DESTROY:
			current_tracked_progress += value
			
		StoryMissionData.MissionType.GAP, StoryMissionData.MissionType.EXPLORE:
			current_tracked_progress = 1.0
		
		# --- NOVA REGRA DE DEFESA ---
		StoryMissionData.MissionType.DEFEND:
			if item_id == "vip_destroyed" or value == -1:
				get_tree().call_group("HUD", "criar_toast", "O alvo foi destruído! Missão Falhou.", Color.RED)
				end_mission(false) # Falha imediata!
			
# --- A CORREÇÃO DO DELIVERY ---
		StoryMissionData.MissionType.DELIVERY:
			if item_id == "collect":
				delivery_items_held += int(value)
				get_tree().call_group("HUD", "criar_toast", "Carga recolhida! (" + str(delivery_items_held) + " no carro)", Color.YELLOW)
				
			elif item_id == "dropoff":
				if delivery_items_held > 0:
					delivery_items_delivered += delivery_items_held
					delivery_items_held = 0
					
					# Sincroniza a barra visual da HUD com o que foi entregue!
					current_tracked_progress = float(delivery_items_delivered) 
					
					get_tree().call_group("HUD", "criar_toast", "Entregue: " + str(delivery_items_delivered) + "/" + str(meta), Color.GREEN)


	# TOAST DE PROGRESSO GERAL (Roadkill, Collect, Destroy)
	if type in [StoryMissionData.MissionType.COLLECT, StoryMissionData.MissionType.ROADKILL, StoryMissionData.MissionType.DESTROY]:
		if meta > 0 and current_tracked_progress > progresso_antigo:
			var nome_base = current_mission.mission_name if current_mission.mission_name != "" else "Progresso"
			var texto_toast = nome_base + ": " + str(int(current_tracked_progress)) + "/" + str(meta)
			get_tree().call_group("HUD", "criar_toast", texto_toast, Color.ORANGE)
			
	# Debug no console
	if current_tracked_progress > progresso_antigo:
		print("[StoryController] Progresso da Missão atualizado: ", current_tracked_progress)
		
func _get_current_mission_progress() -> float:
	if not current_mission: return 0.0
	
	match current_mission.mission_type:
		StoryMissionData.MissionType.COMBAT_DESTROY:
			# Regra: Combat Destroy lê automaticamente o status dos bots spawnados
			var dead_count = 0
			for t in combat_targets:
				if not is_instance_valid(t) or t.is_queued_for_deletion():
					dead_count += 1
				elif "_is_dead" in t and t._is_dead:
					dead_count += 1
				else:
					var stats = t.find_child("StatsComponent", true, false)
					if stats and "is_dead" in stats and stats.is_dead:
						dead_count += 1
			return float(dead_count)
			
		StoryMissionData.MissionType.SCORE:
			# Regra: Score lê direto da pontuação global acumulada da run
			return current_tracked_score
			
		_:
			# Regra: SPEED, COLLECT, ROADKILL, DESTROY, GAP e EXPLORE
			# Lê da variável alimentada pelo notify_progress
			return current_tracked_progress

func _process(delta):
	if get_tree().paused: return
	if physics.check_player_death(): return
	
	if not is_mission_running or not current_mission: return
	
# Lógica do Temporizador
	if current_mission.time_limit > 0:
		mission_timer -= delta
		get_tree().call_group("HUD", "atualizar_timer", mission_timer)
		
		if mission_timer <= 0:
			# === NOVA REGRA DE DEFESA: Sobreviver ao tempo = Vitória! ===
			if current_mission.mission_type == StoryMissionData.MissionType.DEFEND:
				# A CORREÇÃO: Dá a tier como concluída automaticamente ao sobreviver!
				if not current_mission.mission_tiers.is_empty():
					for i in range(current_mission.mission_tiers.size()):
						if not completed_tiers_this_run.has(i):
							completed_tiers_this_run.append(i)
				
				end_mission(true)
			else:
				# Regra padrão para outras missões
				var won_any_tier = completed_tiers_this_run.size() > 0
				if current_mission.mission_tiers.is_empty(): won_any_tier = false
				end_mission(won_any_tier) 
			return
	# Checagem de sucesso e atualização de Tiers
	var current_progress_value = _get_current_mission_progress()
	_update_tiers_progress(current_progress_value)

	# Validação para missões SIMPLES (Sem Tiers configuradas)
# Validação para missões SIMPLES (Sem Tiers configuradas)
	if current_mission.mission_tiers.is_empty():
		match current_mission.mission_type:
			StoryMissionData.MissionType.COMBAT_DESTROY:
				if current_progress_value >= combat_targets.size() and combat_targets.size() > 0:
					end_mission(true)
					
			StoryMissionData.MissionType.SCORE:
				if current_tracked_score >= current_mission.base_target_value:
					end_mission(true)
					
			# ---> ADICIONE O DELIVERY AQUI NESTA LINHA! <---
			StoryMissionData.MissionType.SPEED, StoryMissionData.MissionType.COLLECT, StoryMissionData.MissionType.ROADKILL, StoryMissionData.MissionType.DESTROY, StoryMissionData.MissionType.DELIVERY:
				if current_tracked_progress >= current_mission.base_target_value:
					end_mission(true)
					
			StoryMissionData.MissionType.GAP, StoryMissionData.MissionType.EXPLORE:
				if current_tracked_progress >= 1.0:
					end_mission(true)

func _update_tiers_progress(current_value: float):
	if not current_mission or current_mission.mission_tiers.is_empty(): return
	
	for i in range(current_mission.mission_tiers.size()):
		if completed_tiers_this_run.has(i): continue
		var tier = current_mission.mission_tiers[i]
		
		# Define de onde leremos o progresso (Do geral ou do Checklist?)
		var prog_to_check = current_value
		
		if current_mission.mission_type == StoryMissionData.MissionType.MULTI_TASK:
			# =========================================================
			# LÓGICA ISOLADA: Conta os bots mortos diretamente aqui!
			# =========================================================
			if tier.tier_mission_type == StoryMissionData.MissionType.COMBAT_DESTROY:
				var dead_count = 0
				for t in combat_targets:
					if not is_instance_valid(t) or t.is_queued_for_deletion():
						dead_count += 1
					elif "_is_dead" in t and t._is_dead:
						dead_count += 1
					else:
						var stats = t.find_child("StatsComponent", true, false)
						if stats and "is_dead" in stats and stats.is_dead:
							dead_count += 1
				prog_to_check = float(dead_count)
				
			elif tier.tier_mission_type == StoryMissionData.MissionType.SCORE:
				prog_to_check = current_tracked_score
			else:
				# Puxa os dados dos eventos normais (Roadkill, Destroy, etc)
				prog_to_check = multitask_progress.get(i, 0.0)
				
		# Se a meta da Tier foi batida
		if prog_to_check >= tier.target_value:
			completed_tiers_this_run.append(i)
			
			get_tree().call_group("HUD", "riscar_objetivo_tier", i, tier.tier_name)
			get_tree().call_group("HUD", "criar_toast", "🏆 TAREFA CONCLUÍDA: " + tier.tier_name + "!", Color.GOLD)
			
			# Checa se o checklist inteiro acabou
			if completed_tiers_this_run.size() == current_mission.mission_tiers.size():
				end_mission(true)
				return

func _check_next_map_unlock():
	if is_mission_running:
		return

	for p in get_tree().get_nodes_in_group("mission_portals"):
		if p.has_method("activate_portal_safely"):
			p.activate_portal_safely()
			
	if is_instance_valid(Global) and "story_total_points" in Global:
		for p in get_tree().get_nodes_in_group("next_map_portals"):
			if p.has_method("try_activate"):
				p.try_activate(Global.story_total_points)

# ====================================================================
# --- DELEGAÇÃO DE COMANDOS PARA OS COMPONENTES ---
# ====================================================================

func request_mission_start(portal: StoryMissionPortal, data: StoryMissionData):
	active_portal = portal
	current_mission = data
	
	_conectar_morte_jogador()
	
	if mission_ui and mission_ui.has_method("show_mission_prompt"):
		mission_ui.show_mission_prompt(data, self)
	else:
		push_error("[StoryController] UI da missão não configurada!")
		
func _conectar_morte_jogador():
	var players = get_tree().get_nodes_in_group("jogadores")
	for p in players:
		var stats = p.find_child("StatsComponent*", true, false)
		if stats and not stats.is_connected("health_depleted", _on_player_died):
			stats.health_depleted.connect(_on_player_died)

func _on_player_died(_attacker):
	if is_mission_running:
		print("[StoryController] O jogador foi destruído! Encerrando a missão com falha...")
		end_mission(false)

func accept_mission():
	lifecycle.accept_mission()

func decline_mission():
	lifecycle.decline_mission()

func end_mission(success: bool):
	lifecycle.end_mission(success)

func restart_current_mission():
	lifecycle.restart_current_mission()

func start_last_played_mission():
	if not last_played_mission or not is_instance_valid(last_played_portal): 
		return
	current_mission = last_played_mission
	active_portal = last_played_portal
	is_mission_running = true 
	restart_current_mission()

func resume_open_world():
	is_mission_running = false
	current_mission = null
	active_portal = null
	get_tree().paused = false
