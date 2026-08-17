extends Area3D
class_name VoidKillPlane

func _ready():
	# Conecta o sinal de colisão via código para não precisar fazer pela interface
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	# 1. REGRA DE RESGATE: Carros (Jogadores e Bots)
	if body.is_in_group("jogadores"):
		_rescue_vehicle(body)
		
	# 2. REGRA DO LIXO: Qualquer outro objeto físico que cair no void é deletado
	elif body is RigidBody3D or body is VehicleBody3D:
		print("[VoidKillPlane] Objeto destruído no void: ", body.name)
		body.queue_free()

func _rescue_vehicle(car: Node3D):
	var teleport_markers = get_tree().get_nodes_in_group("AbilityTeleport")
	
	if teleport_markers.is_empty():
		push_error("[VoidKillPlane] Nenhum marker do grupo 'AbilityTeleport' encontrado!")
		return
		
	var closest_marker: Node3D = null
	var closest_dist_sq = INF
	
	# Procura o marker mais próximo usando distância quadrática (muito mais leve para a CPU)
	for marker in teleport_markers:
		var dist_sq = car.global_position.distance_squared_to(marker.global_position)
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			closest_marker = marker
			
	if closest_marker:
		print("[VoidKillPlane] Resgatando veículo para: ", closest_marker.name)
		
		# Move o carro
		car.global_transform = closest_marker.global_transform
		
		# Trava a física para ele não nascer voando com a inércia da queda
		if car is RigidBody3D or car is VehicleBody3D:
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			
		# Limpa a memória de manobras para evitar bugs de pontuação no ar
		var trick_manager = car.get_node_or_null("%TrickManager")
		if is_instance_valid(trick_manager) and trick_manager.has_method("reset_trick"):
			trick_manager.reset_trick()
