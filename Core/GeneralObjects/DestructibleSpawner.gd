extends Node3D
class_name DestructibleSpawner

@export_group("Configuração do Spawner")
@export var respawn_time : float = 15.0

@export_group("Objetos Destrutíveis")
## SE VOCÊ QUER UM OBJETO ESPECÍFICO: Coloque a cena (.tscn) dele aqui.
@export var specific_scene : PackedScene
## SE VOCÊ QUER ALEATÓRIO: Deixe a specific_scene vazia e adicione cenas (.tscn) aqui!
@export var random_pool : Array[PackedScene]

var current_object : Node3D = null
var timer : float = 0.0

func _ready():
	# Deleta o fantasma assim que o jogo começa
	if has_node("DebugMesh"):
		$DebugMesh.queue_free()

func _process(delta):
	# Se já tem um objeto vivo na base, não spawna outro e trava o timer
	if is_instance_valid(current_object):
		return
		
	# Se o objeto foi destruído (queue_free), começa a contar o tempo de respawn
	timer -= delta
	if timer <= 0:
		_spawn_object()
		timer = respawn_time

func _spawn_object():
	var scene_to_spawn : PackedScene = null
	
	# 1. Tenta pegar a cena específica
	if specific_scene:
		scene_to_spawn = specific_scene
	# 2. Se não tem específico, sorteia uma do Pool!
	elif random_pool.size() > 0:
		scene_to_spawn = random_pool.pick_random()
		
	if not scene_to_spawn:
		return # Spawner não configurado
		
	# Cria o objeto destrutível
	current_object = scene_to_spawn.instantiate()
	
	# =====================================================================
	# CORREÇÃO DA FÍSICA: Adiciona na cena PRIMEIRO, move DEPOIS!
	# =====================================================================
	get_tree().current_scene.add_child(current_object)
	
	# Passa o Transform completo (Posição, Rotação e Escala) de uma só vez
	current_object.global_transform = self.global_transform
