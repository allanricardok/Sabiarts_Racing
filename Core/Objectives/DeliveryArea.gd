extends Area3D

func _ready():
	# Conecta o sinal de colisão automaticamente
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# Se quem bateu foi o carro
	if body is BaseVehicle:
		var controller = get_tree().get_first_node_in_group("StoryController")
		
		# Verifica se a missão ativa é de entrega
		if is_instance_valid(controller) and controller.get("is_mission_running"):
			if controller.current_mission.mission_type == StoryMissionData.MissionType.DELIVERY:
				var itens_no_carro = controller.delivery_items_held
				
				# Se o jogador tiver carga, descarrega!
				if itens_no_carro > 0:
					print("[Delivery] Carro entrou na zona com ", itens_no_carro, " itens. Descarregando!")
					
					# Avisa o controlador
					get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.DELIVERY, 1.0, "dropoff")
					
					# Toca a animação visual
					_play_drop_animation(body, itens_no_carro)

func _play_drop_animation(carro: Node3D, quantidade: int):
	# Cria cubinhos (caixas) voando do porta-malas simulando a entrega
	for i in range(quantidade):
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 0.5)
		mesh_inst.mesh = box
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.ORANGE
		box.surface_set_material(0, mat)
		
		get_tree().current_scene.add_child(mesh_inst)
		
		var start_pos = carro.global_position - (carro.global_transform.basis.z * 2.0) + Vector3(0, 1.5, 0)
		mesh_inst.global_position = start_pos
		
		var target_pos = start_pos + Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		
		var tween = get_tree().create_tween().set_parallel(true)
		tween.tween_property(mesh_inst, "global_position:x", target_pos.x, 0.6)
		tween.tween_property(mesh_inst, "global_position:z", target_pos.z, 0.6)
		tween.tween_property(mesh_inst, "rotation", Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI)), 0.6)
		
		var y_tween = get_tree().create_tween()
		y_tween.tween_property(mesh_inst, "global_position:y", start_pos.y + 2.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		y_tween.tween_property(mesh_inst, "global_position:y", start_pos.y - 1.0, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		
		var fade_tween = get_tree().create_tween()
		fade_tween.tween_interval(0.5)
		fade_tween.tween_property(mesh_inst, "scale", Vector3.ZERO, 0.2)
		fade_tween.chain().tween_callback(mesh_inst.queue_free)
