# PedestrianSpawner.gd
extends Node3D

@export var pedestrian_scene: PackedScene
@export var spawn_interval: float = 3.0
@export var max_alive: int = 5

var current_alive: int = 0
var timer: float = 0.0

func _process(delta):
	if not pedestrian_scene: return
	
	timer -= delta
	if timer <= 0:
		timer = spawn_interval
		_try_spawn()

func _try_spawn():
	# Limpa instâncias que já morreram da contagem
	var peds = get_tree().get_nodes_in_group("pedestrians")
	
	if peds.size() >= 30: return 
	
	var ped = pedestrian_scene.instantiate()
	
	# 1. A MÁGICA: Definimos a posição LOCAL bruta antes dele existir no mundo.
	# Assim, quando ele "nascer", ele já nasce na porta do prédio, e nunca no (0,0,0)!
	ped.position = self.global_position
	
	# 2. Agora sim, jogamos ele no mapa com a posição já corrigida.
	get_tree().current_scene.add_child(ped)
