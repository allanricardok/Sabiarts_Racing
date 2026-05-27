# BotSpawner.gd
extends Node3D
class_name BotSpawner

@export var car_prefabs: Array[PackedScene] # Coloque os carros aqui no Inspector
@export var spawn_points: Array[Marker3D] # Coloque os Markers aqui

func _ready():
	# Dá um pequeno delay para garantir que a HUD e o mapa carregaram primeiro
	call_deferred("_spawn_all_bots")

func _spawn_all_bots():
	# --- TRAVA DE SEGURANÇA ---
	# Se o Global diz que não é para ter bots, o Spawner encerra aqui sem fazer nada.
	if not Global.spawn_bots:
		print("[BotSpawner] Modo de jogo sem bots detectado. Cancelando spawn automático inicial.")
		return

	if car_prefabs.is_empty() or spawn_points.is_empty():
		print("[BotSpawner] Faltam prefabs ou spawn points!")
		return
		
	for i in range(spawn_points.size()):
		var spawn_pos = spawn_points[i]
		_create_bot_at_position(spawn_pos, i)

# --- NOVA FUNÇÃO: SPAWN INDIVIDUAL PARA O MODO HISTÓRIA ---
# Esta função ignora a trava global porque é invocada pelo controlador de missões
func spawn_single_bot(index_fallback: int = 0) -> Node:
	if car_prefabs.is_empty() or spawn_points.is_empty():
		print("[BotSpawner] Falha no spawn individual: car_prefabs ou spawn_points vazios!")
		return null
		
	# Escolhe um ponto de spawn baseado no índice ou um aleatório para não sobrepor
	var point_index = index_fallback % spawn_points.size()
	var spawn_pos = spawn_points[point_index]
	
	return _create_bot_at_position(spawn_pos, index_fallback)

# --- FUNÇÃO INTERNA COMPARTILHADA DE CRIAÇÃO ---
func _create_bot_at_position(spawn_pos: Marker3D, bot_id: int) -> Node:
	var random_car = car_prefabs.pick_random()
	var bot = random_car.instantiate()
	
	# --- CIRURGIA DE CÂMERA, ÁUDIO E UI ---
	var cameras = bot.find_children("*", "Camera3D", true)
	for cam in cameras: cam.free()
		
	var listeners = bot.find_children("*", "AudioListener3D", true)
	for listener in listeners: listener.free()
		
	var canvas_layers = bot.find_children("*", "CanvasLayer", true)
	for canvas in canvas_layers: canvas.free()
		
	var hud_nodes = bot.find_children("*HUD*", "Control", true)
	for hud in hud_nodes: hud.free()
		
	# --- INJEÇÃO DA INTELIGÊNCIA ARTIFICIAL ---
	var brain = Node.new()
	brain.name = "BotBrain"
	brain.set_script(preload("res://Core/Enemies/Bots/BotBrain.gd")) 
	bot.add_child(brain)
	
	# --- INTEGRAÇÃO COM OS SEUS SISTEMAS ---
	bot.add_to_group("jogadores")
	bot.add_to_group("inimigos") # Garante compatibilidade com o grupo de alvos
	
	if "id" in bot:
		bot.id = bot_id + 2 
		
	bot.name = "BOT_STORY_" + str(bot.id)
	
	# Instancia o bot no mesmo nível do Spawner (na raiz da cena)
	get_parent().add_child(bot)
	
	bot.global_position = spawn_pos.global_position
	bot.global_rotation = spawn_pos.global_rotation
	
	print("[BotSpawner] Spawnou dinamicamente: ", bot.name)
	return bot
