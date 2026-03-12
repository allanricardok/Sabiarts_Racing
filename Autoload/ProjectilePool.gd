# ProjectilePool.gd
extends Node

var pools : Dictionary = {}

func get_projectile(scene: PackedScene) -> Node3D:
	if not scene: return null
	
	var key = scene.resource_path
	if not pools.has(key):
		pools[key] = []
		
	var proj = null
	
	# --- A BLINDAGEM CONTRA FANTASMAS ---
	# Fica puxando da fila até achar uma bala que esteja realmente VIVA
	while pools[key].size() > 0:
		proj = pools[key].pop_back()
		if is_instance_valid(proj) and not proj.is_queued_for_deletion():
			break # Achou uma boa! Para de procurar.
		else:
			proj = null # Era fantasma, joga fora e tenta a próxima
			
	# Se a fila acabou ou só tinha fantasma, fabrica uma nova
	if not is_instance_valid(proj):
		proj = scene.instantiate()
		proj.set_meta("pool_key", key) # Carimba usando MetaData (funciona em qualquer nó!)
		get_tree().current_scene.add_child(proj)
		
	return proj

func return_projectile(proj: Node3D):
	if proj.has_meta("pool_key"):
		var key = proj.get_meta("pool_key")
		if pools.has(key):
			pools[key].append(proj)
			return
			
	proj.queue_free() # Fallback de emergência
