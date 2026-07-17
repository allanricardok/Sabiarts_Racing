# StoryModeController.gd
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

# --- VARIÁVEL QUE VAI SALVAR A SUA VIDA ---
var current_tracked_score: float = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS 
	add_to_group("StoryController")
	
	if world_env: original_env = world_env.environment
	if sun_light:
		original_sun_color = sun_light.light_color
		original_sun_energy = sun_light.light_energy
		
	# Conecta diretamente ao ScoreManager sem precisar adivinhar o nome da variável
	if is_instance_valid(ScoreManager) and ScoreManager.has_signal("score_changed"):
		ScoreManager.score_changed.connect(_on_global_score_changed)
		
	call_deferred("_setup_inicial_seguro")
	call_deferred("_check_next_map_unlock")

# Toda vez que você fizer um trick, o ScoreManager avisa aqui, e nós guardamos!
func _on_global_score_changed(_player_id: int, new_score: int):
	current_tracked_score = float(new_score)

func _setup_inicial_seguro():
	get_tree().call_group("HUD", "atualizar_timer", 0.0)
	get_tree().call_group("HUD", "esconder_timer")
	get_tree().call_group("HUD", "esconder_missao_ativa")

func _process(delta):
	if get_tree().paused: return
	if _check_player_death(): return
	
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
			# BLINDAGEM DO ITEM SECRETO: 
			# Se tiver Tiers (Missão de Score), ignora o fato de o MissionManager 
			# achar que acabou a missão porque você pegou um item secreto solto no mapa.
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
		var prog = 0.0
		if active_classic_objective and "current_progress" in active_classic_objective:
			prog = float(active_classic_objective.current_progress)
			
		# Usa o Score rastreado perfeitamente pelo Sinal, sem adivinhação!
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

func _restore_all_health_and_energy():
	var vehicles = get_tree().get_nodes_in_group("jogadores") + get_tree().get_nodes_in_group("inimigos")
	for v in vehicles:
		if is_instance_valid(v) and v.has_method("revive"):
			v.revive()

func request_mission_start(portal: StoryMissionPortal, data: StoryMissionData):
	active_portal = portal
	current_mission = data
	
	if mission_ui and mission_ui.has_method("show_mission_prompt"):
		mission_ui.show_mission_prompt(data, self)
	else:
		push_error("[StoryController] UI da missão não configurada!")

func decline_mission():
	for p in get_tree().get_nodes_in_group("mission_portals"):
		if p.has_method("activate_portal_safely"):
			p.activate_portal_safely()
		
	current_mission = null
	active_portal = null
	get_tree().paused = false

func accept_mission():
	last_played_mission = current_mission
	last_played_portal = active_portal
	combat_targets.clear()
	spawned_bots.clear()
	active_classic_objective = null
	completed_tiers_this_run.clear()
	current_tracked_score = 0.0 # Zera o score da missão ao aceitar
	
	if is_instance_valid(ScoreManager):
		if ScoreManager.has_method("reset_score"): ScoreManager.reset_score()
		elif ScoreManager.has_method("clear_score"): ScoreManager.clear_score()
	get_tree().call_group("HUD", "clear_combo_display")

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

	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.visible = false
		p.is_active = false
		p.set_deferred("monitoring", false)
		p.set_deferred("monitorable", false)
		
	for p in get_tree().get_nodes_in_group("next_map_portals"):
		p.visible = false
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
					var stats = enemy.find_child("StatsComponent*", true, false)
					if stats:
						if "damage_dealt_multiplier" in stats:
							stats.damage_dealt_multiplier = current_mission.enemy_damage_dealt_mult if "enemy_damage_dealt_mult" in current_mission else 1.0
						if "damage_received_multiplier" in stats:
							stats.damage_received_multiplier = current_mission.enemy_damage_received_mult if "enemy_damage_received_mult" in current_mission else 1.0
					
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

	get_tree().call_group("HUD", "mostrar_missao_ativa_com_tiers", current_mission.mission_name, current_mission.mission_tiers)
	
	if current_mission.time_limit <= 0:
		get_tree().call_group("HUD", "atualizar_timer", 0.0)
		get_tree().call_group("HUD", "esconder_timer")
	else:
		get_tree().call_group("HUD", "mostrar_timer")

	mission_timer = current_mission.time_limit
	is_mission_running = true
	get_tree().paused = false

func complete_current_mission():
	if is_mission_running: end_mission(true)

func abort_current_mission():
	if is_mission_running: end_mission(false)

func has_active_mission() -> bool:
	return is_mission_running

func restart_current_mission():
	if not is_mission_running or not current_mission: return
	
	is_mission_running = false
	
	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.is_active = false
		p.set_deferred("monitoring", false)
	
	for bot in spawned_bots:
		if is_instance_valid(bot) and not bot.is_queued_for_deletion():
			bot.queue_free()
	spawned_bots.clear()
	combat_targets.clear()
	
	for path in current_mission.nodes_to_enable:
		var node = get_node_or_null(path)
		if not node:
			var node_name = String(path).split("/")[-1]
			node = get_tree().current_scene.find_child(node_name, true, false)
		if node:
			node.visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
	
	var true_player = null
	for p in get_tree().get_nodes_in_group("jogadores"):
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			var is_bot = false
			var ic = p.get_node_or_null("%InputComponent")
			if not ic: ic = p.find_child("InputComponent*", true, false)
			
			if ic and "is_bot" in ic and ic.is_bot: is_bot = true
			if not is_bot:
				true_player = p
				break
				
	if is_instance_valid(true_player) and is_instance_valid(active_portal):
		true_player.freeze = true
		true_player.set_physics_process(false)
		
		var direcao_frente = active_portal.global_transform.basis.z.normalized()
		var spawn_pos = active_portal.global_position + (direcao_frente * 4.5)
		spawn_pos.y += 1.2 
		
		var z_axis = direcao_frente
		z_axis.y = 0.0
		if z_axis.length_squared() < 0.01: z_axis = active_portal.global_transform.basis.x.cross(Vector3.UP)
		z_axis = z_axis.normalized()
		var y_axis = Vector3.UP
		var x_axis = y_axis.cross(z_axis).normalized()
		
		true_player.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), spawn_pos)
		true_player.linear_velocity = Vector3.ZERO
		true_player.angular_velocity = Vector3.ZERO
		
		await get_tree().process_frame
		
		if is_instance_valid(true_player) and true_player.has_method("revive"):
			true_player.revive()
	
	await get_tree().create_timer(0.2).timeout
	accept_mission()

func _check_player_death() -> bool:
	var players = get_tree().get_nodes_in_group("jogadores")
	if players.is_empty(): return false
	
	for p1 in players:
		if not is_instance_valid(p1): continue
		
		var is_dead = false
		if "_is_dead" in p1 and p1._is_dead:
			is_dead = true
		elif p1.find_child("StatsComponent", true, false) and p1.find_child("StatsComponent", true, false).get("current_health") <= 0:
			is_dead = true
				
		if is_dead:
			_executar_reset_fisico_veiculo(p1)
			if is_mission_running:
				is_mission_running = false
				end_mission(false)
			return true
			
	return false

func _executar_reset_fisico_veiculo(vehicle: Node3D):
	var spawn_transform : Transform3D
	
	if is_mission_running and is_instance_valid(active_portal):
		var z_axis = active_portal.global_transform.basis.z
		var spawn_pos = active_portal.global_position + (z_axis * 15.0)
		spawn_pos.y += 2.0 
		
		z_axis.y = 0.0
		if z_axis.length_squared() < 0.01: z_axis = active_portal.global_transform.basis.x.cross(Vector3.UP)
		z_axis = z_axis.normalized()
		var y_axis = Vector3.UP
		var x_axis = y_axis.cross(z_axis).normalized()
		
		spawn_transform = Transform3D(Basis(x_axis, y_axis, z_axis), spawn_pos)
	else:
		var spawn_point = get_tree().get_first_node_in_group("SpawnPoint")
		if not spawn_point:
			var container_spawns = get_tree().current_scene.find_child("SpawnPoints", true, false)
			if container_spawns and container_spawns.get_child_count() > 0:
				spawn_point = container_spawns.get_child(0)
		
		if spawn_point:
			spawn_transform = spawn_point.global_transform
		else:
			spawn_transform = vehicle.global_transform
	
	vehicle.freeze = true
	vehicle.global_transform = spawn_transform
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.freeze = false
	
	if vehicle.has_method("revive"):
		vehicle.revive()

func end_mission(success: bool):
	is_mission_running = false
	active_classic_objective = null
	
	get_tree().call_group("HUD", "atualizar_timer", 0.0)
	get_tree().call_group("HUD", "atualizar_status_missao", success)
	
	await get_tree().create_timer(.5).timeout
	
	if is_instance_valid(MissionManager): MissionManager.current_map_data = null
	
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
		if p.has_method("activate_portal_safely"):
			p.activate_portal_safely()

	var mission_name_temp = "Missão"
	var points_earned = 0
	var tokens_earned = 0 
	var status_tipo = "LOCKED" 
	
	var is_all_tiers_completed = false
	var won_first_time_tier = false
	var won_repeated_tier = false
	
	if current_mission:
		mission_name_temp = current_mission.mission_name
		
		if success:
			var m_id = current_mission.mission_id
			
			if current_mission.mission_tiers.is_empty():
				is_all_tiers_completed = true
				var is_first_time = not Global.completed_story_missions.has(m_id)
				var already_repeated = Global.missions_repeated_this_run.has(m_id)
				
				var rew_pts = current_mission.get("mission_reward_points")
				if rew_pts == null: rew_pts = 0
				
				if is_first_time:
					won_first_time_tier = true
					points_earned += rew_pts
					tokens_earned += int(rew_pts * 0.20)
					Global.completed_story_missions.append(m_id)
				elif not already_repeated:
					won_repeated_tier = true
					tokens_earned += int(rew_pts * 0.10)
					Global.missions_repeated_this_run.append(m_id)
			else:
				is_all_tiers_completed = completed_tiers_this_run.size() == current_mission.mission_tiers.size()
				for tier_index in completed_tiers_this_run:
					var tier_data = current_mission.mission_tiers[tier_index]
					var tier_key = m_id + "_tier_" + str(tier_index)
					
					var is_tier_first_time = not Global.completed_mission_tiers.has(tier_key)
					var already_repeated_this_run = Global.missions_repeated_this_run.has(tier_key)
					
					if is_tier_first_time:
						won_first_time_tier = true
						points_earned += tier_data.reward_points
						tokens_earned += int(tier_data.reward_points * 0.20)
						Global.completed_mission_tiers.append(tier_key)
					elif not already_repeated_this_run:
						won_repeated_tier = true
						tokens_earned += int(tier_data.reward_points * 0.10)
						Global.missions_repeated_this_run.append(tier_key)
				
				if is_all_tiers_completed and not Global.completed_story_missions.has(m_id):
					Global.completed_story_missions.append(m_id)

			if points_earned > 0:
				Global.story_total_points += points_earned
				
			if won_first_time_tier:
				status_tipo = "FIRST_TIME"
				if Global.has_method("save_story_progress"): 
					Global.save_story_progress()
				if active_portal and active_portal.has_method("is_fully_completed"):
					if active_portal.is_fully_completed():
						active_portal.make_semitransparent()
			elif won_repeated_tier:
				status_tipo = "REPEATED"
			else:
				status_tipo = "LOCKED"

			if tokens_earned > 0:
				Global.total_tokens += tokens_earned
				if Global.has_method("save_player_profile"): Global.save_player_profile()
			
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
		
	get_tree().call_group("HUD", "esconder_missao_ativa")
	get_tree().call_group("HUD", "esconder_timer")
	
	_check_next_map_unlock()
	get_tree().paused = true
	
	if success and current_mission:
		var token_ui = get_node_or_null("TokenRewardUI") as TokenRewardUI
		if not token_ui:
			token_ui = get_tree().current_scene.find_child("TokenRewardUI", true, false) as TokenRewardUI
			
		if token_ui:
			token_ui.exibir_extrato(mission_name_temp, status_tipo, tokens_earned, self)
			return 
	
	if result_ui and result_ui.has_method("show_result_with_tiers"):
		result_ui.show_result_with_tiers(success, is_all_tiers_completed, mission_name_temp, points_earned, self)

func resume_open_world():
	is_mission_running = false
	current_mission = null
	active_portal = null
	get_tree().paused = false

func _check_next_map_unlock():
	if is_mission_running:
		return

	for p in get_tree().get_nodes_in_group("mission_portals"):
		if p.has_method("activate_portal_safely"):
			p.activate_portal_safely()
			
	if is_instance_valid(Global) and "story_total_points" in Global and "points_to_next_city" in Global:
		if Global.story_total_points >= Global.points_to_next_city:
			get_tree().call_group("next_map_portals", "activate_portal")
			for p in get_tree().get_nodes_in_group("next_map_portals"):
				p.visible = true
				p.set_deferred("monitoring", true)
				p.set_deferred("monitorable", true)

func start_last_played_mission():
	if not last_played_mission or not is_instance_valid(last_played_portal): 
		return
	
	current_mission = last_played_mission
	active_portal = last_played_portal
	is_mission_running = true 
	
	restart_current_mission()
