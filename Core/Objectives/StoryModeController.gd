# StoryModeController.gd
extends Node
class_name StoryModeController

@export_group("Referências do Mapa")
@export var world_env: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var mission_ui: CanvasLayer 
@export var result_ui: CanvasLayer 
@export var bot_spawner: Node 

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

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS 
	add_to_group("StoryController")
	
	if world_env: original_env = world_env.environment
	if sun_light:
		original_sun_color = sun_light.light_color
		original_sun_energy = sun_light.light_energy

func _process(delta):
	if not is_mission_running or get_tree().paused: return
	
	if current_mission.time_limit > 0:
		mission_timer -= delta
		get_tree().call_group("HUD", "atualizar_timer", mission_timer)
		
		if mission_timer <= 0:
			end_mission(false) 
			return

	match current_mission.mission_type:
		StoryMissionData.MissionType.CLASSIC_OBJECTIVE:
			if active_classic_objective and active_classic_objective.is_completed:
				end_mission(true)
				
		StoryMissionData.MissionType.COMBAT_DESTROY:
			var all_destroyed = true
			for target in combat_targets:
				if is_instance_valid(target) and not target.is_queued_for_deletion():
					if "_is_dead" in target and target._is_dead:
						continue 
					all_destroyed = false
					break
			
			if all_destroyed and combat_targets.size() > 0:
				end_mission(true)

func request_mission_start(portal: StoryMissionPortal, data: StoryMissionData):
	active_portal = portal
	current_mission = data
	
	if mission_ui and mission_ui.has_method("show_mission_prompt"):
		mission_ui.show_mission_prompt(data, self)
	else:
		push_error("[StoryController] UI da missão não configurada!")

# --- CORREÇÃO: RELIGA OS PORTAIS CASO A MISSÃO SEJA RECUSADA ---
func decline_mission():
	print("[StoryController] Missão Recusada. Reativando portais.")
	
	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.visible = true
		p.is_active = true
		p.set_deferred("monitoring", true)
		p.set_deferred("monitorable", true)
		
	current_mission = null
	active_portal = null
	get_tree().paused = false

func accept_mission():
	combat_targets.clear()
	spawned_bots.clear()
	active_classic_objective = null
	
	if is_instance_valid(ScoreManager):
		if ScoreManager.has_method("reset_score"): ScoreManager.reset_score()
		elif ScoreManager.has_method("clear_score"): ScoreManager.clear_score()

	if current_mission.mission_type == StoryMissionData.MissionType.CLASSIC_OBJECTIVE:
		if current_mission.classic_objective:
			active_classic_objective = current_mission.classic_objective.duplicate()
			
			if is_instance_valid(MissionManager):
				var fake_map_data = MapMissionData.new()
				fake_map_data.map_name = current_mission.mission_name
				fake_map_data.missions.clear()
				fake_map_data.missions.append(active_classic_objective)
				
				MissionManager.setup_map(fake_map_data)
				
				active_classic_objective.is_completed = false
				if "current_progress" in active_classic_objective:
					active_classic_objective.current_progress = 0.0
					
				if "completed_mission_ids" in MissionManager:
					MissionManager.completed_mission_ids.erase(active_classic_objective.id)
				if "completed_count" in MissionManager: 
					MissionManager.completed_count = 0
		else:
			push_error("[StoryController] Tipo Clássico sem 'classic_objective'!")

	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.visible = false
		p.is_active = false
		p.set_deferred("monitoring", false)
		p.set_deferred("monitorable", false)

	if current_mission.mission_environment and world_env:
		world_env.environment = current_mission.mission_environment
	if sun_light:
		sun_light.light_color = current_mission.mission_sun_color
		sun_light.light_energy = current_mission.mission_sun_energy

	if current_mission.mission_type == StoryMissionData.MissionType.COMBAT_DESTROY:
		if bot_spawner and bot_spawner.has_method("spawn_single_bot"):
			for i in range(current_mission.enemy_count):
				var enemy = bot_spawner.spawn_single_bot(i)
				if enemy:
					combat_targets.append(enemy)
					spawned_bots.append(enemy)

	for path in current_mission.nodes_to_enable:
		var node = get_node_or_null(path)
		if not node:
			var node_name = String(path).split("/")[-1]
			node = get_tree().current_scene.find_child(node_name, true, false)
			
		if node:
			if not original_transforms.has(node):
				original_transforms[node] = node.global_transform
			
			node.global_transform = original_transforms[node]
			node.visible = true
			node.process_mode = Node.PROCESS_MODE_INHERIT
			
			if node.has_method("reset"):
				node.reset()
				
			if current_mission.mission_type == StoryMissionData.MissionType.COMBAT_DESTROY and not combat_targets.has(node):
				combat_targets.append(node)

	mission_timer = current_mission.time_limit
	is_mission_running = true
	get_tree().paused = false

func complete_current_mission():
	if is_mission_running:
		end_mission(true)

func abort_current_mission():
	if is_mission_running:
		end_mission(false)

func has_active_mission() -> bool:
	return is_mission_running

func end_mission(success: bool):
	is_mission_running = false
	active_classic_objective = null
	
	if is_instance_valid(MissionManager):
		MissionManager.current_map_data = null
	
	for bot in spawned_bots:
		if is_instance_valid(bot) and not bot.is_queued_for_deletion():
			bot.queue_free()
	spawned_bots.clear()
	combat_targets.clear()
	
	if world_env: world_env.environment = original_env
	if sun_light:
		sun_light.light_color = original_sun_color
		sun_light.light_energy = original_sun_energy

	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.visible = true
		p.is_active = true
		p.set_deferred("monitoring", true)
		p.set_deferred("monitorable", true)

	var mission_name_temp = "Missão"
	var points_earned = 0
	
	if current_mission:
		mission_name_temp = current_mission.mission_name
		if success:
			if not Global.completed_story_missions.has(current_mission.mission_id):
				points_earned = current_mission.mission_reward_points
				Global.story_total_points += points_earned
				Global.completed_story_missions.append(current_mission.mission_id)
				
				if active_portal:
					active_portal.make_semitransparent()
			else:
				points_earned = 0
			
		for path in current_mission.nodes_to_enable:
			var node = get_node_or_null(path)
			if not node:
				var node_name = String(path).split("/")[-1]
				node = get_tree().current_scene.find_child(node_name, true, false)
			if node:
				node.visible = false
				node.process_mode = Node.PROCESS_MODE_DISABLED
	
	_restore_all_health_and_energy()
	
	if is_instance_valid(ScoreManager):
		if ScoreManager.has_method("reset_score"): ScoreManager.reset_score()
		elif ScoreManager.has_method("clear_score"): ScoreManager.clear_score()
		
	get_tree().paused = true
	get_tree().call_group("HUD", "atualizar_timer", 0.0)
	
	if result_ui and result_ui.has_method("show_result"):
		result_ui.show_result(success, mission_name_temp, points_earned, self)

func resume_open_world():
	current_mission = null
	active_portal = null
	get_tree().paused = false

func _restore_all_health_and_energy():
	var vehicles = get_tree().get_nodes_in_group("jogadores") + get_tree().get_nodes_in_group("inimigos")
	for v in vehicles:
		var stats = v.find_child("StatsComponent", true, false)
		if stats and "current_health" in stats and "MAX_HEALTH" in stats:
			stats.current_health = stats.MAX_HEALTH
			
		var ability = v.find_child("AbilityComponent", true, false)
		if ability and "current_energy" in ability and "MAX_ENERGY" in ability:
			ability.current_energy = ability.MAX_ENERGY
