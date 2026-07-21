extends Node
class_name StoryModeController

@export_group("Referências do Mapa")
@export var world_env: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var mission_ui: CanvasLayer 
@export var result_ui: CanvasLayer 
@export var bot_spawner: Node 

var last_played_mission: StoryMissionData = null
var last_played_portal: StoryMissionPortal = null

var original_env: Environment
var original_sun_color: Color
var original_sun_energy: float

var current_mission: StoryMissionData
var active_portal: StoryMissionPortal
var mission_timer: float = 0.0
var is_mission_running: bool = false

var active_classic_objective: MissionItem = null

var combat_targets: Array[Node] = []
var spawned_bots: Array[Node] = []
var original_transforms: Dictionary = {}

var completed_tiers_this_run: Array[int] = []
var current_tracked_score: float = 0.0

# ============================================================================
# NOVO: progresso rastreado via sinal, igual ao current_tracked_score do SCORE.
# Substitui a leitura direta de "active_classic_objective.current_progress",
# que dependia de uma checagem silenciosa (`if "current_progress" in mission`)
# e podia falhar sem aviso se a propriedade não existisse no MissionItem.
# ============================================================================
var current_tracked_progress: float = 0.0

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
	
	# NOVO: escuta diretamente o MissionManager, igual o ScoreManager acima.
	# Isso garante que qualquer tipo de missão (COLLECT, ROADKILL, SPEED...)
	# alimente os tiers da mesma forma robusta que o SCORE já usava.
	if is_instance_valid(MissionManager):
		if MissionManager.has_signal("mission_updated"):
			MissionManager.mission_updated.connect(_on_mission_progress_updated)
		if MissionManager.has_signal("mission_completed"):
			MissionManager.mission_completed.connect(_on_mission_progress_completed)
		
	call_deferred("_setup_inicial_seguro")
	call_deferred("_check_next_map_unlock")

func _on_global_score_changed(_player_id: int, new_score: int):
	current_tracked_score = float(new_score)

# NOVO: recebe o progresso diretamente do MissionManager, sem depender de
# nenhuma propriedade espelhada no resource. "mission" só é processado se
# for exatamente o classic_objective ativo desta missão de Story Mode.
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

func _process(delta):
	if get_tree().paused: return
	if physics.check_player_death(): return
	
	if not is_mission_running or not current_mission: return
	
	if current_mission.time_limit > 0:
		mission_timer -= delta
		get_tree().call_group("HUD", "atualizar_timer", mission_timer)
		
		if mission_timer <= 0:
			var won_any_tier = completed_tiers_this_run.size() > 0
			if current_mission.mission_tiers.is_empty(): won_any_tier = false
			end_mission(won_any_tier) 
			return

	var current_progress_value = _get_current_mission_progress()
	_update_tiers_progress(current_progress_value)

	match current_mission.mission_type:
		StoryMissionData.MissionType.CLASSIC_OBJECTIVE:
			if active_classic_objective and active_classic_objective.is_completed:
				if current_mission.mission_tiers.is_empty():
					end_mission(true)
				
		StoryMissionData.MissionType.COMBAT_DESTROY:
			var all_destroyed = true
			for target in combat_targets:
				if is_instance_valid(target) and not target.is_queued_for_deletion():
					if "_is_dead" in target and target._is_dead:
						continue 
						
					var target_stats = target.find_child("StatsComponent", true, false)
					if target_stats and "is_dead" in target_stats and target_stats.is_dead:
						continue
						
					all_destroyed = false
					break
			
			if all_destroyed and combat_targets.size() > 0:
				end_mission(true)

func _get_current_mission_progress() -> float:
	if not current_mission: return 0.0
	
	if current_mission.mission_type == StoryMissionData.MissionType.COMBAT_DESTROY:
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
		
	elif current_mission.mission_type == StoryMissionData.MissionType.CLASSIC_OBJECTIVE:
		# ALTERADO: prog agora vem do valor recebido via sinal
		# (current_tracked_progress), não mais de active_classic_objective.current_progress.
		var prog = current_tracked_progress
			
		var desc = str(current_mission.mission_description).to_upper()
		var m_name = str(current_mission.mission_name).to_upper()
		if "SCORE" in desc or "PONTO" in desc or "TRICK" in m_name:
			prog = max(prog, current_tracked_score)
				
		return prog
		
	return 0.0

func _update_tiers_progress(current_value: float):
	if not current_mission or current_mission.mission_tiers.is_empty(): return
	
	for i in range(current_mission.mission_tiers.size()):
		if completed_tiers_this_run.has(i): continue
		
		var tier = current_mission.mission_tiers[i]
		if current_value >= tier.target_value:
			completed_tiers_this_run.append(i)
			
			get_tree().call_group("HUD", "riscar_objetivo_tier", i, tier.tier_name)
			get_tree().call_group("HUD", "criar_toast", "🏆 TIER " + str(i + 1) + " ATINGIDO: " + tier.tier_name + "!", Color.GOLD)
			
			if completed_tiers_this_run.size() == current_mission.mission_tiers.size():
				end_mission(true)
				return

func _check_next_map_unlock():
	if is_mission_running:
		return

	for p in get_tree().get_nodes_in_group("mission_portals"):
		if p.has_method("activate_portal_safely"):
			p.activate_portal_safely()
			
	# ALTERADO: cada portal de próxima cidade (StoryNextMapPortal.gd) agora
	# guarda seu próprio "points_required" no Inspector, em vez de todos
	# compartilharem um único Global.points_to_next_city. O controller só
	# repassa a pontuação atual pra cada portal decidir sozinho.
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
	
	if mission_ui and mission_ui.has_method("show_mission_prompt"):
		mission_ui.show_mission_prompt(data, self)
	else:
		push_error("[StoryController] UI da missão não configurada!")

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
