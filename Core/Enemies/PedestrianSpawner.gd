# PedestrianSpawner.gd
extends Node3D

@export var pedestrian_scene: PackedScene
@export var spawn_interval: float = 3.0
## Quantidade máxima de pedestres que ESTE spawner pode manter vivos ao mesmo tempo
@export var max_alive: int = 5

var timer: float = 0.0

# NOVA VARIÁVEL: Guarda a lista de quem este spawner colocou no mapa
var spawned_peds: Array = []

func _process(delta):
	if not pedestrian_scene: return
	
	timer -= delta
	if timer <= 0:
		timer = spawn_interval
		_try_spawn()

func _try_spawn():
	# 1. Limpa da lista os pedestres que já morreram (foram atropelados/baleados)
	for i in range(spawned_peds.size() - 1, -1, -1):
		if not is_instance_valid(spawned_peds[i]):
			spawned_peds.remove_at(i)
			
	# 2. Checa o limite LOCAL (Se este spawner já atingiu a cota dele, aborta!)
	if spawned_peds.size() >= max_alive:
		return
	
	# 3. Checa o limite GLOBAL de performance (opcional, para não fritar o PC)
	var all_peds = get_tree().get_nodes_in_group("pedestrians")
	if all_peds.size() >= 30: return 
	
	var ped = pedestrian_scene.instantiate()
	
	# Definimos a posição LOCAL bruta antes dele existir no mundo
	ped.position = self.global_position
	
	get_tree().current_scene.add_child(ped)
	
	# 4. Registra o novo pedestre na lista de controle deste spawner
	spawned_peds.append(ped)
