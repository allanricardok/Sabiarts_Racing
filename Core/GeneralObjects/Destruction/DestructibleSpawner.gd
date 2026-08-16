extends Node3D
class_name DestructibleSpawner

enum RespawnMode {
	TIME_ONLY,          # Ignora distância, revive cravado no tempo (Mobilidade)
	DISTANCE_AND_TIME   # Espera o tempo E o player humano se afastar (Missões)
}

@export_group("Configuração do Spawner")
@export var respawn_mode : RespawnMode = RespawnMode.DISTANCE_AND_TIME
@export var respawn_time : float = 15.0
@export var min_respawn_distance : float = 150.0 # Raio de segurança (usado só no modo DISTANCE)

@export_group("Objetos Destrutíveis")
## SE VOCÊ QUER UM OBJETO ESPECÍFICO: Coloque a cena (.tscn) dele aqui.
@export var specific_scene : PackedScene
## SE VOCÊ QUER ALEATÓRIO: Deixe a specific_scene vazia e adicione cenas (.tscn) aqui!
@export var random_pool : Array[PackedScene]

var current_object : Node3D = null
var timer : float = 0.0
var _min_dist_sq : float = 0.0

func _ready():
	if has_node("DebugMesh"):
		$DebugMesh.queue_free()
		
	# OTIMIZAÇÃO: Guarda a distância ao quadrado para não calcular raiz na física
	_min_dist_sq = min_respawn_distance * min_respawn_distance
	timer = respawn_time

func _process(delta):
	# CENÁRIO 1: Objeto não existe na memória (levou queue_free ou não foi criado)
	if not is_instance_valid(current_object):
		_tick_timer_and_spawn(delta)
		return
		
	# CENÁRIO 2: Objeto existe. Está vivo ou morto/invisível?
	var is_dead = false
	if "is_dead" in current_object and current_object.get("is_dead") == true:
		is_dead = true
	elif current_object.has_method("is_destroyed") and current_object.is_destroyed():
		is_dead = true
	elif not current_object.visible:
		is_dead = true

	if is_dead:
		if _can_respawn():
			timer -= delta
			if timer <= 0:
				_revive_or_respawn()
				timer = respawn_time
	else:
		# Se está vivinho, reseta o cronômetro
		timer = respawn_time

func _tick_timer_and_spawn(delta):
	if _can_respawn():
		timer -= delta
		if timer <= 0:
			_spawn_object()
			timer = respawn_time

# O centralizador de decisões
func _can_respawn() -> bool:
	if respawn_mode == RespawnMode.TIME_ONLY:
		return true
	return not _is_human_player_too_close()

func _is_human_player_too_close() -> bool:
	var players = get_tree().get_nodes_in_group("jogadores")
	for p in players:
		if is_instance_valid(p):
			# === NOVA CHECAGEM: IGNORAR BOTS ===
			var input_comp = p.get_node_or_null("%InputComponent")
			if input_comp and "is_bot" in input_comp and input_comp.is_bot:
				continue # Se for bot, pula pra próxima checagem e ignora ele!
				
			if p.global_position.distance_squared_to(global_position) < _min_dist_sq:
				return true
	return false

func _spawn_object():
	var scene_to_spawn : PackedScene = null
	
	if specific_scene:
		scene_to_spawn = specific_scene
	elif random_pool.size() > 0:
		scene_to_spawn = random_pool.pick_random()
		
	if not scene_to_spawn:
		return
		
	current_object = scene_to_spawn.instantiate()
	get_tree().current_scene.add_child(current_object)
	current_object.global_transform = self.global_transform

func _revive_or_respawn():
	# Preserva o ID de Missão se o objeto suportar ressurreição
	if current_object.has_method("revive"):
		current_object.revive()
		current_object.global_transform = self.global_transform
	else:
		current_object.queue_free()
		current_object = null
		_spawn_object()
