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
		
	# Usamos call_deferred para dar tempo de a HUD nascer antes de mandar apagar!
	call_deferred("_setup_inicial_seguro")
	call_deferred("_check_next_map_unlock")

func _setup_inicial_seguro():
	# Oculta de forma segura a interface inteira de missão quando o Free Roam começa
	get_tree().call_group("HUD", "atualizar_timer", 0.0)
	get_tree().call_group("HUD", "esconder_timer")
	get_tree().call_group("HUD", "esconder_missao_ativa")

func _process(delta):
	if not is_mission_running or get_tree().paused: return
	
	# --- 3. VERIFICAÇÃO DE MORTE DO JOGADOR ---
	if _check_player_death():
		return
	
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
						
					var target_stats = target.find_child("StatsComponent", true, false)
					if target_stats and "is_dead" in target_stats and target_stats.is_dead:
						continue
						
					all_destroyed = false
					break
			
			if all_destroyed and combat_targets.size() > 0:
				end_mission(true)

func _restore_all_health_and_energy():
	var vehicles = get_tree().get_nodes_in_group("jogadores") + get_tree().get_nodes_in_group("inimigos")
	for v in vehicles:
		if not is_instance_valid(v): continue
		if v.has_method("revive"):
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
		
	# --- 1. Esconde o portal de SAÍDA do mapa durante a missão ---
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
					# =========================================================
					# INJETA OS BUFFS DE DIFICULDADE DIRETAMENTE NO BOT CRIADO
					var stats = enemy.find_child("StatsComponent*", true, false)
					if stats:
						# Verifica se a missão tem os valores configurados, senão usa 1.0 padrão
						var dealt = current_mission.enemy_damage_dealt_mult if "enemy_damage_dealt_mult" in current_mission else 1.0
						var received = current_mission.enemy_damage_received_mult if "enemy_damage_received_mult" in current_mission else 1.0
						
						if "damage_dealt_multiplier" in stats:
							stats.damage_dealt_multiplier = dealt
						if "damage_received_multiplier" in stats:
							stats.damage_received_multiplier = received
					# =========================================================
					
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

	get_tree().call_group("HUD", "mostrar_missao_ativa", current_mission.mission_name)
	
	# --- 2. Controle do Timer na HUD ---
	if current_mission.time_limit <= 0:
		get_tree().call_group("HUD", "atualizar_timer", 0.0)
		get_tree().call_group("HUD", "esconder_timer")
	else:
		get_tree().call_group("HUD", "mostrar_timer")

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

func restart_current_mission():
	if not is_mission_running or not current_mission: return
	
	# Desliga a flag para o sistema de morte não se intrometer
	is_mission_running = false
	
	# 1. Limpa a arena antiga
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
	
	# 2. LÓGICA DE TELEPORTE COM FILTRO DE PLAYER REAL
	var true_player = null
	var todos_jogadores = get_tree().get_nodes_in_group("jogadores")
	
	for p in todos_jogadores:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			var is_bot = false
			var ic = p.get_node_or_null("%InputComponent")
			if not ic: ic = p.find_child("InputComponent*", true, false)
			
			if ic and "is_bot" in ic and ic.is_bot:
				is_bot = true
				
			if not is_bot:
				true_player = p
				break
				
	if is_instance_valid(true_player) and is_instance_valid(active_portal):
		# Simula a morte desligando a física
		true_player.freeze = true
		true_player.set_physics_process(false)
		
		# Matemática da posição do portal
		var spawn_pos = active_portal.global_position + (active_portal.global_transform.basis.z * 5.0)
		spawn_pos.y += 2.0 
		var z_axis = active_portal.global_transform.basis.z
		z_axis.y = 0.0
		if z_axis.length_squared() < 0.01: z_axis = active_portal.global_transform.basis.x.cross(Vector3.UP)
		z_axis = z_axis.normalized()
		var y_axis = Vector3.UP
		var x_axis = y_axis.cross(z_axis).normalized()
		
		# Teleporte imediato forçado
		true_player.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), spawn_pos)
		true_player.linear_velocity = Vector3.ZERO
		true_player.angular_velocity = Vector3.ZERO
		
		# Garante que a Engine registrou a mudança antes de continuar
		await get_tree().process_frame
		
		# CHECAGEM DE SEGURANÇA: Só revive se o nó não tiver sumido neste 1 frame
		if is_instance_valid(true_player) and true_player.has_method("revive"):
			true_player.revive()
	
	# 3. O SEGREDO FINAL: Esperar 0.2 segundos ANTES de gerar os bots.
	await get_tree().create_timer(0.2).timeout
	
	# Reconstrói a missão
	accept_mission()

# --- SISTEMA DE MORTE E CHECKPOINT ---
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
			print("[StoryController] Jogador morreu em combate! Resetando para o portal...")
			
			# Desliga a flag antes de limpar para não bugar a checagem no frame da morte
			is_mission_running = false
			
			if is_instance_valid(active_portal):
				_executar_reset_fisico_veiculo(p1)
			
			end_mission(false)
			return true
			
	return false

func _executar_reset_fisico_veiculo(vehicle: Node3D):
	var spawn_pos = active_portal.global_position + (active_portal.global_transform.basis.z * 5.0)
	spawn_pos.y += 2.0 
	
	var z_axis = active_portal.global_transform.basis.z
	z_axis.y = 0.0
	if z_axis.length_squared() < 0.01: z_axis = active_portal.global_transform.basis.x.cross(Vector3.UP)
	z_axis = z_axis.normalized()
	var y_axis = Vector3.UP
	var x_axis = y_axis.cross(z_axis).normalized()
	var safe_basis = Basis(x_axis, y_axis, z_axis)
	
	vehicle.freeze = true
	vehicle.global_transform = Transform3D(safe_basis, spawn_pos)
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
				
				if Global.has_method("save_story_progress"):
					Global.save_story_progress()
				
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
	
	# Cura e revive os carros forçadamente!
	_restore_all_health_and_energy()
	
	if is_instance_valid(ScoreManager):
		if ScoreManager.has_method("reset_score"): ScoreManager.reset_score()
		elif ScoreManager.has_method("clear_score"): ScoreManager.clear_score()
		
	get_tree().call_group("HUD", "esconder_missao_ativa")
	get_tree().call_group("HUD", "esconder_timer")
	
	_check_next_map_unlock()

	get_tree().paused = true
	
	if result_ui and result_ui.has_method("show_result"):
		result_ui.show_result(success, mission_name_temp, points_earned, self)

func resume_open_world():
	current_mission = null
	active_portal = null
	get_tree().paused = false

func _check_next_map_unlock():
	if is_instance_valid(Global) and "story_total_points" in Global and "points_to_next_city" in Global:
		if Global.story_total_points >= Global.points_to_next_city:
			# Acorda todos os portais do próximo mapa!
			get_tree().call_group("next_map_portals", "activate_portal")
			
			# Garante que eles voltem a estar visíveis e interagíveis
			for p in get_tree().get_nodes_in_group("next_map_portals"):
				p.visible = true
				p.set_deferred("monitoring", true)
				p.set_deferred("monitorable", true)
