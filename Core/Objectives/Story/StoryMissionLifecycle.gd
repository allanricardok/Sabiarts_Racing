extends Node
class_name StoryMissionLifecycle

var ctrl: Node # Referência ao StoryModeController

func setup(controller: Node):
	ctrl = controller

func accept_mission():
	ctrl.last_played_mission = ctrl.current_mission
	ctrl.last_played_portal = ctrl.active_portal
	ctrl.combat_targets.clear()
	ctrl.spawned_bots.clear()
	ctrl.completed_tiers_this_run.clear()
	ctrl.current_tracked_score = 0.0 
	ctrl.current_tracked_progress = 0.0 # Zera o rastreador de coletáveis, velocidade, etc.
	ctrl.multitask_progress.clear()
	
	if is_instance_valid(ScoreManager):
		if ScoreManager.has_method("reset_score"): ScoreManager.reset_score()
		elif ScoreManager.has_method("clear_score"): ScoreManager.clear_score()
	get_tree().call_group("HUD", "clear_combo_display")

	# Esconde portais
	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.visible = false
		p.is_active = false
		p.set_deferred("monitoring", false)
		p.set_deferred("monitorable", false)
		
	for p in get_tree().get_nodes_in_group("next_map_portals"):
		p.visible = false
		p.set_deferred("monitoring", false)
		p.set_deferred("monitorable", false)

	# Atmosfera
	if ctrl.current_mission.mission_environment and ctrl.world_env:
		ctrl.world_env.environment = ctrl.current_mission.mission_environment
	if ctrl.sun_light:
		ctrl.sun_light.light_color = ctrl.current_mission.mission_sun_color
		ctrl.sun_light.light_energy = ctrl.current_mission.mission_sun_energy

	# =========================================================
	# Gera Bots de Combate para QUALQUER missão que peça inimigos
	# =========================================================
	if ctrl.current_mission.enemy_count > 0:
		# ====================================================================
		# CORREÇÃO: Acessando a variável atualizada 'bot_spawnerV2' do Controller
		# ====================================================================
		if ctrl.bot_spawnerV2 and ctrl.bot_spawnerV2.has_method("spawn_single_bot"):
			for i in range(ctrl.current_mission.enemy_count):
				var enemy = ctrl.bot_spawnerV2.spawn_single_bot(i)
				if enemy:
					var stats = enemy.find_child("StatsComponent*", true, false)
					if stats:
						if "damage_dealt_multiplier" in stats:
							stats.damage_dealt_multiplier = ctrl.current_mission.enemy_damage_dealt_mult if "enemy_damage_dealt_mult" in ctrl.current_mission else 1.0
						if "damage_received_multiplier" in stats:
							stats.damage_received_multiplier = ctrl.current_mission.enemy_damage_received_mult if "enemy_damage_received_mult" in ctrl.current_mission else 1.0
					
					# --- NOVO: INJETA O OBJETIVO DA MISSÃO NO CÉREBRO DO BOT ---
					var brain = enemy.find_child("BotBrain*", true, false)
					if brain:
						if "mission_target_collect_id" in brain:
							brain.mission_target_collect_id = ctrl.current_mission.bot_target_collect_id
						if "mission_target_destroy_id" in brain:
							brain.mission_target_destroy_id = ctrl.current_mission.bot_target_destroy_id
					
					ctrl.combat_targets.append(enemy)
					ctrl.spawned_bots.append(enemy)

	# Liga os objetos da missão (coletáveis, rampas especiais, alvos)
	for path in ctrl.current_mission.nodes_to_enable:
		var node = ctrl.get_node_or_null(path)
		if not node:
			var node_name = String(path).split("/")[-1]
			node = get_tree().current_scene.find_child(node_name, true, false)
			
		if node:
			if not ctrl.original_transforms.has(node):
				ctrl.original_transforms[node] = node.global_transform
			
			node.global_transform = ctrl.original_transforms[node]
			node.visible = true
			node.process_mode = Node.PROCESS_MODE_INHERIT
			
			if node.has_method("reset"):
				node.reset()
				
			if ctrl.current_mission.mission_type == StoryMissionData.MissionType.COMBAT_DESTROY and not ctrl.combat_targets.has(node):
				ctrl.combat_targets.append(node)

	get_tree().call_group("HUD", "mostrar_missao_ativa_com_tiers", ctrl.current_mission.mission_name, ctrl.current_mission.mission_tiers)
	
	if ctrl.current_mission.time_limit <= 0:
		get_tree().call_group("HUD", "atualizar_timer", 0.0)
		get_tree().call_group("HUD", "esconder_timer")
	else:
		get_tree().call_group("HUD", "mostrar_timer")

	ctrl.mission_timer = ctrl.current_mission.time_limit
	ctrl.is_mission_running = true
	get_tree().paused = false
	
	ctrl.markers.update_markers()

func restart_current_mission():
	if not ctrl.is_mission_running or not ctrl.current_mission: return
	
	ctrl.is_mission_running = false
	
	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.is_active = false
		p.set_deferred("monitoring", false)
	
	for bot in ctrl.spawned_bots:
		if is_instance_valid(bot) and not bot.is_queued_for_deletion():
			bot.queue_free()
	ctrl.spawned_bots.clear()
	ctrl.combat_targets.clear()
	
	for path in ctrl.current_mission.nodes_to_enable:
		var node = ctrl.get_node_or_null(path)
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
				
	if is_instance_valid(true_player) and is_instance_valid(ctrl.active_portal):
		true_player.freeze = true
		true_player.set_physics_process(false)
		
		var direcao_frente = ctrl.active_portal.global_transform.basis.z.normalized()
		var spawn_pos = ctrl.active_portal.global_position + (direcao_frente * 4.5)
		spawn_pos.y += 1.2 
		
		var z_axis = direcao_frente
		z_axis.y = 0.0
		if z_axis.length_squared() < 0.01: z_axis = ctrl.active_portal.global_transform.basis.x.cross(Vector3.UP)
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

func decline_mission():
	for p in get_tree().get_nodes_in_group("mission_portals"):
		if p.has_method("activate_portal_safely"):
			p.activate_portal_safely()
		
	ctrl.current_mission = null
	ctrl.active_portal = null
	get_tree().paused = false

func end_mission(success: bool):
	if not ctrl.is_mission_running:
		return
	ctrl.is_mission_running = false
	
	get_tree().call_group("HUD", "atualizar_timer", 0.0)
	get_tree().call_group("HUD", "atualizar_status_missao", success)
	
	await get_tree().create_timer(.5).timeout

	for bot in ctrl.spawned_bots:
		if is_instance_valid(bot) and not bot.is_queued_for_deletion():
			bot.queue_free()
	ctrl.spawned_bots.clear()
	ctrl.combat_targets.clear()
	
	if ctrl.world_env: ctrl.world_env.environment = ctrl.original_env
	if ctrl.sun_light:
		ctrl.sun_light.light_color = ctrl.original_sun_color
		ctrl.sun_light.light_energy = ctrl.original_sun_energy

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
	
	if ctrl.current_mission:
		mission_name_temp = ctrl.current_mission.mission_name
		
		if success:
			var m_id = ctrl.current_mission.mission_id
			if m_id == null or m_id == "":
				m_id = ctrl.current_mission.resource_path if ctrl.current_mission.resource_path != "" else ("unnamed_" + ctrl.current_mission.mission_name)
			
			if ctrl.current_mission.mission_tiers.is_empty():
				is_all_tiers_completed = true
				var is_first_time = not Global.completed_story_missions.has(m_id)
				var already_repeated = Global.missions_repeated_this_run.has(m_id)
				
				var rew_pts = ctrl.current_mission.get("mission_reward_points")
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
				is_all_tiers_completed = ctrl.completed_tiers_this_run.size() == ctrl.current_mission.mission_tiers.size()
				for tier_index in ctrl.completed_tiers_this_run:
					var tier_data = ctrl.current_mission.mission_tiers[tier_index]
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
				if ctrl.active_portal and ctrl.active_portal.has_method("is_fully_completed"):
					if ctrl.active_portal.is_fully_completed():
						ctrl.active_portal.make_semitransparent()
			elif won_repeated_tier:
				status_tipo = "REPEATED"
			else:
				status_tipo = "LOCKED"

			if tokens_earned > 0:
				Global.total_tokens += tokens_earned
				if Global.has_method("save_player_profile"): Global.save_player_profile()
			
		var deve_esconder = not (ctrl.current_mission.mission_type in [
			StoryMissionData.MissionType.DEFEND, 
			StoryMissionData.MissionType.DESTROY
		])
		
		if deve_esconder:
			for path in ctrl.current_mission.nodes_to_enable:
				var node = ctrl.get_node_or_null(path)
				if not node:
					var node_name = String(path).split("/")[-1]
					node = get_tree().current_scene.find_child(node_name, true, false)
				if node:
					node.visible = false
					node.process_mode = Node.PROCESS_MODE_DISABLED
	
	ctrl.physics.restore_all_health_and_energy()
	
	if is_instance_valid(ScoreManager):
		if ScoreManager.has_method("reset_score"): ScoreManager.reset_score()
		elif ScoreManager.has_method("clear_score"): ScoreManager.clear_score()
		
	get_tree().call_group("HUD", "esconder_missao_ativa")
	get_tree().call_group("HUD", "esconder_timer")
	
	ctrl._check_next_map_unlock()
	get_tree().paused = true
	
	if success and ctrl.current_mission:
		var token_ui = ctrl.get_node_or_null("TokenRewardUI") as TokenRewardUI
		if not token_ui:
			token_ui = get_tree().current_scene.find_child("TokenRewardUI", true, false) as TokenRewardUI
			
		if token_ui:
			token_ui.exibir_extrato(mission_name_temp, status_tipo, tokens_earned, ctrl)
			return 
	
	if ctrl.result_ui and ctrl.result_ui.has_method("show_result_with_tiers"):
		ctrl.result_ui.show_result_with_tiers(success, is_all_tiers_completed, mission_name_temp, points_earned, ctrl)
