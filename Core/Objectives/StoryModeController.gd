# StoryModeController.gd
extends Node
class_name StoryModeController

@export_group("Referências do Mapa")
@export var world_env: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var mission_ui: CanvasLayer # ARRASTE A CENA DA SUA UI PARA AQUI NO INSPECTOR!

# Salva o estado do Open World
var original_env: Environment
var original_sun_color: Color
var original_sun_energy: float

var current_mission: StoryMissionData
var active_portal: StoryMissionPortal
var mission_timer: float = 0.0
var is_mission_running: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS 
	add_to_group("StoryController")
	
	if world_env: original_env = world_env.environment
	if sun_light:
		original_sun_color = sun_light.light_color
		original_sun_energy = sun_light.light_energy

func _process(delta):
	if is_mission_running and current_mission.time_limit > 0:
		if not get_tree().paused:
			mission_timer -= delta
			if mission_timer <= 0:
				end_mission(false) 

# --- 1. CHAMADO PELO PORTAL ---
func request_mission_start(portal: StoryMissionPortal, data: StoryMissionData):
	active_portal = portal
	current_mission = data
	
	print("[StoryController] Abrindo Tela de Aceitação de Missão...")
	if mission_ui and mission_ui.has_method("show_mission_prompt"):
		mission_ui.show_mission_prompt(data, self)
	else:
		push_error("[StoryController] UI da missão não configurada ou sem a função correta!")

# --- 2. QUANDO O JOGADOR CLICA EM RECUSAR ---
func decline_mission():
	print("[StoryController] Missão Recusada. Voltando ao Open World.")
	current_mission = null
	active_portal = null
	get_tree().paused = false # Apenas despausa e segue a vida

# --- 3. QUANDO O JOGADOR CLICA EM ACEITAR ---
func accept_mission():
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

	# 3. Ativa os objetos/inimigos pré-carregados desta missão
	for path in current_mission.nodes_to_enable:
		var node = get_node_or_null(path)
		if node:
			node.visible = true
			node.process_mode = Node.PROCESS_MODE_INHERIT

	# 4. Inicia Timer e despausa
	mission_timer = current_mission.time_limit
	is_mission_running = true
	get_tree().paused = false
	print("[StoryController] Missão Iniciada sem loading!")

# --- 4. QUANDO A MISSÃO TERMINA ---
func end_mission(success: bool):
	is_mission_running = false
	
	if world_env: world_env.environment = original_env
	if sun_light:
		sun_light.light_color = original_sun_color
		sun_light.light_energy = original_sun_energy

	for p in get_tree().get_nodes_in_group("mission_portals"):
		p.visible = true
		p.is_active = true
		p.set_deferred("monitoring", true)

	if current_mission:
		for path in current_mission.nodes_to_enable:
			var node = get_node_or_null(path)
			if node:
				node.visible = false
				node.process_mode = Node.PROCESS_MODE_DISABLED
	
	_restore_all_health_and_energy()
	
	var msg = "SUCESSO!" if success else "TEMPO ESGOTADO / FALHA!"
	print("[StoryController] Missão Encerrada: ", msg)
	
	current_mission = null
	
	get_tree().paused = true
	# Aqui no futuro chamaremos a tela de Vitória/Derrota, igual acabamos de fazer com a de Aceitar!

func _restore_all_health_and_energy():
	var vehicles = get_tree().get_nodes_in_group("jogadores") + get_tree().get_nodes_in_group("inimigos")
	for v in vehicles:
		var stats = v.find_child("StatsComponent", true, false)
		if stats and "current_health" in stats and "MAX_HEALTH" in stats:
			stats.current_health = stats.MAX_HEALTH
			
		var ability = v.find_child("AbilityComponent", true, false)
		if ability and "current_energy" in ability and "MAX_ENERGY" in ability:
			ability.current_energy = ability.MAX_ENERGY
