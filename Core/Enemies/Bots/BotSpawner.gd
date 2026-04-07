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
		print("[BotSpawner] Modo de jogo sem bots detectado. Cancelando spawn.")
		return

	if car_prefabs.is_empty() or spawn_points.is_empty():
		print("[BotSpawner] Faltam prefabs ou spawn points!")
		return
		
	for i in range(spawn_points.size()):
		var spawn_pos = spawn_points[i]
		var random_car = car_prefabs.pick_random()
		
		var bot = random_car.instantiate()
		
		# --- CIRURGIA DE CÂMERA, ÁUDIO E UI ---
		# Feito ANTES do add_child() e usando .free() para eliminar sumariamente
		var cameras = bot.find_children("*", "Camera3D", true)
		for cam in cameras: cam.free()
			
		var listeners = bot.find_children("*", "AudioListener3D", true)
		for listener in listeners: listener.free()
			
		# Arranca qualquer CanvasLayer (HUD) que esteja colada no Bot
		var canvas_layers = bot.find_children("*", "CanvasLayer", true)
		for canvas in canvas_layers: canvas.free()
			
		# Se a sua HUD tiver "HUD" no nome, garantimos que ela seja deletada
		var hud_nodes = bot.find_children("*HUD*", "Control", true)
		for hud in hud_nodes: hud.free()
			
		# --- INJEÇÃO DA INTELIGÊNCIA ARTIFICIAL ---
		var brain = Node.new()
		brain.name = "BotBrain"
		brain.set_script(preload("res://Core/Enemies/Bots/BotBrain.gd")) 
		bot.add_child(brain)
		
		bot.global_position = spawn_pos.global_position
		bot.global_rotation = spawn_pos.global_rotation
		
		# --- INTEGRAÇÃO COM OS SEUS SISTEMAS ---
		bot.add_to_group("jogadores")
		
		# Damos um ID falso para a HUD e o Radar não quebrarem 
		if "id" in bot:
			bot.id = i + 2 
			
		bot.name = "BOT_" + str(bot.id)
		
		# Instancia o bot no mesmo nível do Spawner (na raiz da cena)
		get_parent().add_child(bot)
		
		print("[BotSpawner] Spawnou: ", bot.name, " com IA ativada e sem câmera/UI!")
