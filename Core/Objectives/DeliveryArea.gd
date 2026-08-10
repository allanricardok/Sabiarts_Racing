extends Area3D

# Trava de segurança para impedir múltiplas ativações simultâneas
var is_processing_delivery: bool = false

func _ready():
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if is_processing_delivery: return
	
	if body is BaseVehicle:
		# =========================================================
		# TRAVA ANTI-BOT: Bloqueia a entrega se quem bateu não for humano
		# =========================================================
		var input = body.get_node_or_null("%InputComponent")
		if input and "is_bot" in input and input.is_bot:
			print("[Delivery] Bot tentou entregar carga, bloqueado!")
			return
		
		# =========================================================
		# O RESTO DA FUNÇÃO CONTINUA NORMAL...
		# =========================================================
		var controller = get_tree().get_first_node_in_group("StoryController")
		
		if is_instance_valid(controller) and controller.get("is_mission_running"):
			if controller.current_mission.mission_type == StoryMissionData.MissionType.DELIVERY:
				var itens_no_carro = controller.delivery_items_held
				
				if itens_no_carro > 0:
					is_processing_delivery = true
					print("[Delivery] Descarregando ", itens_no_carro, " itens...")
					
					var malha_do_item = _get_mission_mesh(controller)
					
					# =================================================================
					# A MÁGICA AQUI: O 'await' pausa esta função até a animação terminar!
					# =================================================================
					await _play_drop_animation(body, itens_no_carro, malha_do_item)
					
					# Depois que todas as caixas caíram, validamos e computamos os pontos!
					# (Checamos is_mission_running de novo caso o tempo tenha acabado durante a animação)
					if is_instance_valid(controller) and controller.get("is_mission_running"):
						get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.DELIVERY, 1.0, "dropoff")
						
					is_processing_delivery = false

func _get_mission_mesh(controller: Node) -> Mesh:
	if controller.current_mission and not controller.current_mission.nodes_to_enable.is_empty():
		var path = controller.current_mission.nodes_to_enable[0]
		var node = controller.get_node_or_null(path)
		
		if not node:
			var node_name = String(path).split("/")[-1]
			node = get_tree().current_scene.find_child(node_name, true, false)
		
		if node:
			var mesh_inst = node.find_child("*MeshInstance3D*", true, false) as MeshInstance3D
			if mesh_inst and mesh_inst.mesh:
				return mesh_inst.mesh
				
	return null

func _play_drop_animation(carro: Node3D, quantidade: int, custom_mesh: Mesh):
	for i in range(quantidade):
		# Prevenção caso o carro exploda ou suma no meio do processo
		if not is_instance_valid(carro):
			break 
			
		var mesh_inst = MeshInstance3D.new()
		
		if custom_mesh:
			mesh_inst.mesh = custom_mesh
		else:
			var box = BoxMesh.new()
			box.size = Vector3(0.5, 0.5, 0.5)
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.ORANGE
			box.surface_set_material(0, mat)
			mesh_inst.mesh = box
			
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
		
		# --- GESTÃO DE TEMPO ---
		if i < quantidade - 1:
			# Pausa 1 segundo entre as caixas
			await get_tree().create_timer(1.0).timeout
		else:
			# Na última caixa, espera ela tocar o chão (0.6s) antes de declarar vitória!
			await get_tree().create_timer(0.6).timeout
