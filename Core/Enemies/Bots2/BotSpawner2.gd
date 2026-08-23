extends Node3D
class_name BotSpawnerV2

@export var car_prefabs: Array[PackedScene] # Coloque os carros aqui no Inspector
@export var spawn_points: Array[Marker3D] # Agora isso é apenas um backup!
var current_vip_node: Node3D = null

# --- VARIÁVEIS INJETADAS PELO CONTROLADOR DE MISSÃO ---
var current_focus_base: float = 10.0
var current_focus_variance: float = 33.0
var current_bot_hostility_base: float = 100.0
var current_bot_hostility_variance: float = 0.0

var current_bot_initial_ammo: int = 8
var current_bot_ammo_regen_rate: float = 3.0
var current_bot_max_damage_per_target: float = 50.0
# NOVO: Lista injetada pela missão
var current_specific_prefabs: Array[PackedScene] = []

# ====================================================================
# NOVO: Contador infalível de Spawns para rodízio de vagas
# ====================================================================
var _spawn_counter: int = 0

func _ready():
	_spawn_counter = 0 # Zera sempre que a fase inicia
	call_deferred("_spawn_all_bots")

# FUNÇÃO SALVA-VIDAS: Evita referências fantasmas lendo direto da cena!
func _get_active_spawn_points() -> Array:
	var container = get_node_or_null("%SpawnPoints")
	if container and container.get_child_count() > 0:
		return container.get_children()
		
	# Fallback caso o nó %SpawnPoints não exista no mapa atual
	return spawn_points

func _spawn_all_bots():
	if not Global.spawn_bots:
		print("[BotSpawnerV2] Modo de jogo sem bots detectado. Cancelando spawn automático inicial.")
		return

	var active_points = _get_active_spawn_points()
	
	if car_prefabs.is_empty() or active_points.is_empty():
		print("[BotSpawnerV2] Faltam prefabs ou spawn points!")
		return
		
	for i in range(active_points.size()):
		var spawn_pos = active_points[i]
		_create_bot_at_position(spawn_pos, i)
		_spawn_counter += 1

func spawn_single_bot(index_fallback: int = -1) -> Node:
	# AGORA USAMOS A LISTA FILTRADA EM VEZ DE TODOS OS PONTOS
	var active_points = _get_spawn_points_near_vip(4) # Pega os 4 mais próximos
	
	if car_prefabs.is_empty() or active_points.is_empty():
		print("[BotSpawnerV2] Falha no spawn individual: car_prefabs ou spawn_points vazios!")
		return null
		
	# Usa o contador interno do Spawner para fazer um rodízio APENAS
	# entre os pontos próximos selecionados.
	var point_index = _spawn_counter % active_points.size() #[cite: 2]
	var spawn_pos = active_points[point_index] #[cite: 2]
	
	var bot_id = _spawn_counter
	if index_fallback >= 0:
		bot_id = index_fallback
		
	_spawn_counter += 1
	
	return _create_bot_at_position(spawn_pos, bot_id) #[cite: 2]

func _create_bot_at_position(spawn_pos: Node3D, bot_id: int) -> Node:
	var random_car: PackedScene = null
	
	# 1. Verifica se a Missão exigiu carros específicos
	if current_specific_prefabs.size() > 0:
		# Usa o bot_id para pegar o carro na ordem. 
		# O % garante que se pedir 3 inimigos e tiver só 1 Boss na lista, ele repete o Boss.
		var index = bot_id % current_specific_prefabs.size()
		random_car = current_specific_prefabs[index]
	else:
		# 2. Se a missão não exigiu nada, usa a roleta aleatória padrão do mapa
		random_car = car_prefabs.pick_random()
		
	if not random_car: return null # Prevenção de crash
		
	var bot = random_car.instantiate()
	
	var cameras = bot.find_children("*", "Camera3D", true)
	for cam in cameras: cam.free()
		
	var listeners = bot.find_children("*", "AudioListener3D", true)
	for listener in listeners: listener.free()
		
	var canvas_layers = bot.find_children("*", "CanvasLayer", true)
	for canvas in canvas_layers: canvas.free()
		
	var hud_nodes = bot.find_children("*HUD*", "Control", true)
	for hud in hud_nodes: hud.free()
		
	var brain = Node.new()
	brain.name = "BotBrainV2" 
	brain.set_script(preload("res://Core/Enemies/Bots2/BotBrain2.gd")) 
	
	brain.set("player_focus_base", current_focus_base)
	brain.set("player_focus_variance", current_focus_variance)
	brain.set("bot_hostility_base", current_bot_hostility_base)
	brain.set("bot_hostility_variance", current_bot_hostility_variance)
	
	brain.set("bot_initial_ammo", current_bot_initial_ammo)
	brain.set("bot_ammo_regen_rate", current_bot_ammo_regen_rate)
	brain.set("bot_max_damage_per_target", current_bot_max_damage_per_target)
	
	bot.add_child(brain)
	
	bot.add_to_group("jogadores")
	bot.add_to_group("inimigos") 
	
	if "id" in bot:
		bot.id = bot_id + 2 
		
	bot.name = "BOT_STORY_" + str(bot.id)
	
	get_parent().add_child(bot)
	
	# Puxando do spawn_pos que TEMOS CERTEZA que está na árvore!
	bot.global_position = spawn_pos.global_position
	bot.global_rotation = spawn_pos.global_rotation
	
	return bot

func _get_spawn_points_near_vip(max_vagas: int = 4) -> Array:
	var todos_pontos = _get_active_spawn_points() #[cite: 2]
	
	# Se não tiver VIP definido ou se o VIP foi destruído, usa a lógica antiga (todos os pontos)
	if not is_instance_valid(current_vip_node):
		return todos_pontos
		
	var dist_array = []
	var vip_pos = current_vip_node.global_position
	
	# Calcula a distância de todos os Spawn Points até o VIP
	for p in todos_pontos:
		if is_instance_valid(p):
			var d_sq = p.global_position.distance_squared_to(vip_pos)
			dist_array.append({"ponto": p, "distancia": d_sq})
			
	# Ordena do mais perto pro mais longe (ordem crescente de distância)
	dist_array.sort_custom(func(a, b): return a["distancia"] < b["distancia"])
	
	# Retorna apenas os 'max_vagas' mais próximos (ex: os 4 pontos mais perto do VIP)
	var pontos_proximos = []
	for i in range(min(max_vagas, dist_array.size())):
		pontos_proximos.append(dist_array[i]["ponto"])
		
	return pontos_proximos
