# PedestrianSpawner.gd
extends Node3D

@export var pedestrian_scene: PackedScene
@export var spawn_interval: float = 3.0
@export var max_alive: int = 5

var timer: float = 0.0
var spawned_peds: Array = []

func _ready():
	# --- A SOLUÇÃO DO BLOQUEIO ---
	# call_deferred diz: "Rode essa função assim que a árvore do jogo estiver 100% destrancada."
	call_deferred("_spawn_initial_batch")

func _spawn_initial_batch():
	# População instantânea com o mapa já liberado!
	for i in range(max_alive):
		_try_spawn(true)
		
	# Só depois começa a contar o tempo normal
	timer = randf_range(1.0, spawn_interval)

func _process(delta):
	if not pedestrian_scene: return
	
	timer -= delta
	if timer <= 0:
		timer = spawn_interval
		_try_spawn(false)

func _try_spawn(is_initial: bool = false):
	# 1. Limpa os mortos
	for i in range(spawned_peds.size() - 1, -1, -1):
		if not is_instance_valid(spawned_peds[i]):
			spawned_peds.remove_at(i)
			
	# 2. Checa limite local
	if spawned_peds.size() >= max_alive: return
	
	# 3. Checa limite global
	var all_peds = get_tree().get_nodes_in_group("pedestrians")
	if not is_initial and all_peds.size() >= 75: return 
	
	var ped = pedestrian_scene.instantiate()
	
	# Espalha eles num raio de 4 metros se nascerem todos ao mesmo tempo
	var random_offset = Vector3.ZERO
	if is_initial:
		random_offset = Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
	
	# 4. Agora é 100% seguro definir a posição e dar o add_child normal!
	ped.position = self.global_position + random_offset
	get_tree().current_scene.add_child(ped)
	
	spawned_peds.append(ped)
