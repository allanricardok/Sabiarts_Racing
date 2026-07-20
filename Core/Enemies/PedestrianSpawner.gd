# PedestrianSpawner.gd
extends Node3D

@export var pedestrian_scene: PackedScene
@export var spawn_interval: float = 3.0
@export var max_alive: int = 5
@export var pool_size: int = 15

var timer: float = 0.0

var active_peds: Array = []
var inactive_peds: Array = [] 

func _ready():
	if not pedestrian_scene: return
	
	for i in range(pool_size):
		var ped = pedestrian_scene.instantiate()
		ped.process_mode = Node.PROCESS_MODE_DISABLED
		ped.visible = false
		
		add_child(ped)
		# Inicializa no cemitério para não pesar nem interferir em nada
		ped.global_position = Vector3(0, -1000, 0) 
		inactive_peds.append(ped)

	call_deferred("_spawn_initial_batch")

func _spawn_initial_batch():
	for i in range(max_alive):
		_try_spawn(true)
		
	timer = randf_range(1.0, spawn_interval)

func _process(delta):
	timer -= delta
	if timer <= 0:
		timer = spawn_interval
		_try_spawn(false)

func _try_spawn(is_initial: bool = false):
	if active_peds.size() >= max_alive: return
	
	if not is_initial:
		var all_peds_alive = 0
		var peds = get_tree().get_nodes_in_group("pedestrians")
		for p in peds:
			if not p.is_dead: all_peds_alive += 1
		if all_peds_alive >= 75: return 

	var ped = null
	if inactive_peds.size() > 0:
		ped = inactive_peds.pop_back()
	
	if not is_instance_valid(ped): return

	var random_offset = Vector3(0, 0.5, 0)
	if is_initial:
		random_offset = Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(-4.0, 4.0))
	
	var spawn_pos = self.global_position + random_offset
	ped.reset(spawn_pos)
	
	active_peds.append(ped)

func recycle_pedestrian(ped_node: Node3D):
	if active_peds.has(ped_node):
		active_peds.erase(ped_node)
		
	if not inactive_peds.has(ped_node):
		inactive_peds.append(ped_node)
