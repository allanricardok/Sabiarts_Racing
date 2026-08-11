extends Node

# LootDropManager.gd (Configurar como Autoload)

## Gera um loot arremessado em arco.
## origin_pos: De onde o item sai (ex: posição do carro).
## forward_dir: Para onde o item deve ser arremessado (vetor normalizado).
## drop_scene: A cena PackedScene da caixa/arma.
## drop_resource: O WeaponResource ou ItemData.
## throw_distance: Quão longe a arma será arremessada (Padrão 5.0 metros).
func spawn_ejected_loot(origin_pos: Vector3, forward_dir: Vector3, drop_scene: PackedScene, drop_resource: Resource, throw_distance: float = 5.0):
	if not drop_scene or not drop_resource:
		push_warning("[LootDropManager] Tentativa de drop falhou: Cena ou Recurso nulos.")
		return

	var space_state = get_tree().root.get_world_3d().direct_space_state
	
	# 1. Calcula onde o item deveria cair no chão plano (apenas X e Z)
	var dir_flat = forward_dir
	dir_flat.y = 0 
	if dir_flat.length_squared() < 0.1:
		# Se não tiver direção (atirou perfeitamente pra cima ou pra baixo), joga pra frente
		dir_flat = Vector3(0, 0, 1) 
		
	dir_flat = dir_flat.normalized()
	var target_xz = origin_pos + (dir_flat * throw_distance)
	
	# 2. Lança um RayCast bem do alto do ponto de destino para achar o chão real (montanhas, rampas)
	var ray_start = target_xz + Vector3(0, 20.0, 0)
	var ray_end = target_xz + Vector3(0, -100.0, 0)
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	
	var result = space_state.intersect_ray(query)
	var final_pos = target_xz
	
	if result:
		# Pousa exatamente no chão com a margem de 1.5 metros de flutuação
		final_pos = result.position + Vector3(0, 1.5, 0) 
	else:
		final_pos.y = origin_pos.y # Fallback de segurança se não achar chão
	
# 3. Cria o "Elevador Fantasma" (Carrier)
	var drop_carrier = Node3D.new()
	
	# CORREÇÃO: Adiciona à cena ANTES de alterar a global_position!
	get_tree().current_scene.add_child(drop_carrier)
	drop_carrier.global_position = origin_pos
	
	var drop = drop_scene.instantiate()
	drop.position = Vector3.ZERO 
	
	if "weapon_resource" in drop:
		drop.weapon_resource = drop_resource
	elif "item_data" in drop:
		drop.item_data = drop_resource
		
	drop_carrier.add_child(drop)
	
	drop.tree_exited.connect(func():
		if is_instance_valid(drop_carrier):
			drop_carrier.queue_free()
	)
	
	# 4. Animação de Arremesso (Parábola)
	var distance = origin_pos.distance_to(final_pos)
	var throw_time = clamp(distance / 15.0, 0.4, 1.0) # Ajusta o tempo pelo espaço, máx de 1s
	var apex_height = max(origin_pos.y, final_pos.y) + 3.5 # Altura máxima do arco
	
	# Tween Horizontal (Linear para deslizar no ar)
	var xz_tween = get_tree().create_tween().set_parallel(true)
	xz_tween.tween_property(drop_carrier, "global_position:x", final_pos.x, throw_time).set_trans(Tween.TRANS_LINEAR)
	xz_tween.tween_property(drop_carrier, "global_position:z", final_pos.z, throw_time).set_trans(Tween.TRANS_LINEAR)
	
	# Tween Vertical (Sobe perdendo força, desce ganhando força)
	var y_tween = get_tree().create_tween()
	var up_time = throw_time * 0.45
	var down_time = throw_time * 0.55
	
	y_tween.tween_property(drop_carrier, "global_position:y", apex_height, up_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	y_tween.tween_property(drop_carrier, "global_position:y", final_pos.y, down_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# Efeito visual de girar no ar enquanto cai (opcional e dá um charme)
	var rot_tween = get_tree().create_tween()
	rot_tween.tween_property(drop_carrier, "rotation:y", deg_to_rad(360 * 2), throw_time)
