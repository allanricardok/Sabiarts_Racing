# StoryModeController.gd
extends Node
class_name StoryModeController

@export_group("Referências do Mapa")
@export var world_env: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var mission_ui: CanvasLayer 
@export var result_ui: CanvasLayer 
@export var bot_spawner: Node # <--- ARRASTE O SEU BOTSPAWNER PARA AQUI NO INSPECTOR!

# Salva o estado do Open World
var original_env: Environment
var original_sun_color: Color
var original_sun_energy: float

var current_mission: StoryMissionData
var active_portal: StoryMissionPortal
var mission_timer: float = 0.0
var is_mission_running: bool = false

# Variáveis de monitorização para as missões
var player_score_at_start: int = 0
var combat_targets: Array[Node] = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS 
	add_to_group("StoryController")
	
	if world_env: original_env = world_env.environment
	if sun_light:
		original_sun_color = sun_light.light_color
		original_sun_energy = sun_light.light_energy

func _process(delta):
	if not is_mission_running or get_tree().paused: return
	
	# 1. GERENCIAMENTO DE TEMPO (CRONÓMETRO)
	if current_mission.time_limit > 0:
		mission_timer -= delta
		if mission_timer <= 0:
			# Se for sobrevivência, o tempo chegar ao fim significa VITÓRIA!
			if current_mission.mission_type == StoryMissionData.MissionType.SURVIVAL:
				end_mission(true)
			else:
				end_mission(false) # Nos outros modos, deixar o tempo acabar é falha
			return

	# 2. CHECAGENS DE VITÓRIA POR TIPO DE MISSÃO
	match current_mission.mission_type:
		
		StoryMissionData.MissionType.SCORE_ATTACK:
			# Verifica a diferença de pontos ganha desde o início da missão
			var current_score = ScoreManager.get_total_score(0)
			if (current_score - player_score_at_start) >= current_mission.score_target:
				end_mission(true)
				
		StoryMissionData.MissionType.CLASSIC_OBJECTIVE:
			# Verifica se o script do Radar/Coletável marcou o MissionItem como concluído
			if current_mission.classic_objective and current_mission.classic_objective.is_completed:
				end_mission(true)
				
		StoryMissionData.MissionType.COMBAT_DESTROY:
			# Verifica se os inimigos listados ainda existem
			var all_destroyed = true
			for target in combat_targets:
				# Se o nó ainda é válido e não foi eliminado da árvore...
				if is_instance_valid(target) and not target.is_queued_for_deletion():
					# Checagem extra de segurança caso o seu inimigo use uma variável de estado
					if "_is_dead" in target and target._is_dead:
						continue 
					all_destroyed = false
					break
			
			# Se todos os alvos foram varridos e a lista não estava vazia no início
			if all_destroyed and combat_targets.size() > 0:
				end_mission(true)

# --- CHAMADO PELO PORTAL ---
func request_mission_start(portal: StoryMissionPortal, data: StoryMissionData):
	active_portal = portal
	current_mission = data
	
	print("[StoryController] Abrindo Ecrã de Aceitação de Missão...")
	if mission_ui and mission_ui.has_method("show_mission_prompt"):
		mission_ui.show_mission_prompt(data, self)
	else:
		push_error("[StoryController] UI da missão não configurada ou sem a função correta!")

# --- QUANDO O JOGADOR CLICA EM RECUSAR ---
func decline_mission():
	print("[StoryController] Missão Recusada. Voltando ao Open World.")
	current_mission = null
	active_portal = null
	get_tree().paused = false

# --- QUANDO O JOGADOR CLICA EM ACEITAR ---
func accept_mission():
	# Preparação dos dados de monitorização
	player_score_at_start = ScoreManager.get_total_score(0)
	combat_targets.clear()
	
	# Reseta a missão clássica para garantir que não estava completa de corridas passadas
	if current_mission.mission_type == StoryMissionData.MissionType.CLASSIC_OBJECTIVE and current_mission.classic_objective:
		current_mission.classic_objective.is_completed = false

	# 1. Esconde TODOS os portais de missão do mundo
	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.visible = false
		p.is_active = false
		p.set_deferred("monitoring", false)

	# 2. Muda a Atmosfera / Iluminação
	if current_mission.mission_environment and world_env:
		world_env.environment = current_mission.mission_environment
	if sun_light:
		sun_light.light_color = current_mission.mission_sun_color
		sun_light.light_energy = current_mission.mission_sun_energy

	# 3. SPAWN AUTOMÁTICO DE INIMIGOS (MODO COMBATE)
	if current_mission.mission_type == StoryMissionData.MissionType.COMBAT_DESTROY:
		if bot_spawner and bot_spawner.has_method("spawn_bot"):
			for i in range(current_mission.enemy_count):
				var enemy = bot_spawner.spawn_bot()
				if enemy:
					combat_targets.append(enemy)
		else:
			push_error("[StoryController] BotSpawner não configurado ou sem método spawn_bot!")

	# 4. Ativa os objetos/inimigos pré-carregados manuais desta missão
	for path in current_mission.nodes_to_enable:
		var node = get_node_or_null(path)
		if node:
			node.visible = true
			node.process_mode = Node.PROCESS_MODE_INHERIT
			
			# Se você arrastar um inimigo manual no Inspetor num modo Combate, ele também deve ser destruído
			if current_mission.mission_type == StoryMissionData.MissionType.COMBAT_DESTROY and not combat_targets.has(node):
				combat_targets.append(node)

	# 5. Inicia Timer e despausa
	mission_timer = current_mission.time_limit
	is_mission_running = true
	get_tree().paused = false
	print("[StoryController] Missão Iniciada! Tipo: ", current_mission.mission_type)

# --- GATILHO MANUAL DE VITÓRIA (Caso precise forçar via script externo) ---
func complete_current_mission():
	if is_mission_running:
		end_mission(true)

# --- QUANDO A MISSÃO TERMINA ---
func end_mission(success: bool):
	is_mission_running = false
	
	# REMOVE INIMIGOS SPAWNADOS AUTOMATICAMENTE PELA MISSÃO DE COMBATE
	if current_mission and current_mission.mission_type == StoryMissionData.MissionType.COMBAT_DESTROY:
		for target in combat_targets:
			if is_instance_valid(target) and not target.is_queued_for_deletion():
				target.queue_free()
	combat_targets.clear() # Limpa a memória
	
	if world_env: world_env.environment = original_env
	if sun_light:
		sun_light.light_color = original_sun_color
		sun_light.light_energy = original_sun_energy

	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.visible = true
		p.is_active = true
		p.set_deferred("monitoring", true)

	var mission_name_temp = "Missão"
	var points_earned = 0
	
	if current_mission:
		mission_name_temp = current_mission.mission_name
		if success:
			# Para todos os modos, vamos usar a variável "score_target" como a recompensa base de conclusão
			points_earned = current_mission.score_target
			Global.story_total_points += points_earned
			print("[StoryController] Ganhaste ", points_earned, " pontos! Progresso: ", Global.story_total_points)
			
		for path in current_mission.nodes_to_enable:
			var node = get_node_or_null(path)
			if node:
				node.visible = false
				node.process_mode = Node.PROCESS_MODE_DISABLED
	
	_restore_all_health_and_energy()
	get_tree().paused = true
	
	if result_ui and result_ui.has_method("show_result"):
		result_ui.show_result(success, mission_name_temp, points_earned, self)
	else:
		push_error("[StoryController] UI de Resultado não configurada!")

# --- RETORNO AO OPEN WORLD ---
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
