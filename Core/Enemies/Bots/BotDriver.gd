extends Node
class_name BotDriver

var car: BaseVehicle
var input: Node 

var ray_left : RayCast3D
var ray_center : RayCast3D
var ray_right : RayCast3D
var ray_length : float = 20.0

var stuck_timer: float = 0.0 
var reverse_time: float = 0.0 
var doing_stunt_timer: float = 0.0 

var alvo_coletavel_atual : Node3D = null
var tempo_buscando_coletavel : float = 0.0

func setup(_car: BaseVehicle, _input: Node):
	car = _car
	input = _input
	_criar_sensores()

func _criar_sensores():
	ray_left = RayCast3D.new()
	ray_center = RayCast3D.new()
	ray_right = RayCast3D.new()
	car.add_child(ray_left)
	car.add_child(ray_center)
	car.add_child(ray_right)
	
	var eye_height = Vector3(0, 1.0, 0)
	ray_left.position = eye_height
	ray_center.position = eye_height
	ray_right.position = eye_height
	
	ray_center.target_position = Vector3(0, 0, ray_length) 
	ray_left.target_position = Vector3(-ray_length * 0.7, 0, ray_length * 0.8)
	ray_right.target_position = Vector3(ray_length * 0.7, 0, ray_length * 0.8)
	
	# ROLLBACK: Voltando apenas para a Layer 1!
	ray_left.collision_mask = 1
	ray_center.collision_mask = 1
	ray_right.collision_mask = 1
	
	ray_left.add_exception(car)
	ray_center.add_exception(car)
	ray_right.add_exception(car)

func processar_manobra_pendente(delta: float) -> bool:
	if doing_stunt_timer > 0:
		doing_stunt_timer -= delta
		input.throttle = 1.0
		input.pitch = 1.0 
		input.is_action_pressed = true 
		return true
	return false

func direcionar_para_coletavel(alvo: Node3D, delta: float, radar: BotRadar) -> Dictionary:
	var forward = car.global_transform.basis.z
	var dir = (alvo.global_position - car.global_position).normalized()
	var dist = car.global_position.distance_to(alvo.global_position)
	
	var steer = clamp(forward.cross(dir).y * 3.0, -1.0, 1.0)
	var throttle = 1.0
	var should_jump = false 
	
	var dot_p = forward.dot(dir)
	if dot_p < 0.2: throttle = 0.4
	elif dist < 12.0: throttle = 0.6
	
	# --- CÁLCULO DE INTERCEPTAÇÃO AÉREA (COM RÉ E EMBALO) ---
	var y_diff = alvo.global_position.y - car.global_position.y
	
	# Se a caixa estiver alta (entre 3m e 20m)
	if y_diff > 3.0 and y_diff <= 20.0: 
		var flat_dist = Vector2(car.global_position.x, car.global_position.z).distance_to(Vector2(alvo.global_position.x, alvo.global_position.z))
		var speed = car.linear_velocity.length()
		
		# SÍNDROME DO RODOANEL: Se caiu embaixo da caixa e tá sem velocidade, dá RÉ pra pegar embalo!
		if flat_dist < 12.0 and speed < 5.0 and dot_p < 0.5:
			throttle = -1.0
			steer = 0.0 # Segura o volante reto pra não rodar
			
		# ALINHAMENTO: Se tá pegando embalo e mirando, controla a velocidade pra não passar voando
		elif flat_dist < 30.0 and dot_p > 0.6:
			throttle = 0.7 
			
		# PULO MATEMÁTICO: O pulo leva ~1.2s para atingir o ápice. 
		if speed > 4.0 and dot_p > 0.6: 
			var time_to_reach = flat_dist / speed
			# Pula exatamente quando faltar entre 0.8s e 1.4s para passar por baixo da caixa!
			if time_to_reach >= 0.8 and time_to_reach <= 1.4:
				should_jump = true
				
		# PULO DE DESESPERO: Se estiver encostando na caixa
		if flat_dist < 4.0:
			should_jump = true
		
	# --- TIMER DE DESISTÊNCIA ---
	if alvo_coletavel_atual != alvo:
		alvo_coletavel_atual = alvo
		tempo_buscando_coletavel = 0.0
	else:
		tempo_buscando_coletavel += delta
		# AUMENTADO PARA 25 SEGUNDOS: Manobras aéreas dão trabalho e levam tempo!
		if tempo_buscando_coletavel > 25.0: 
			radar.itens_ignorados.append(alvo)
			alvo_coletavel_atual = null
			tempo_buscando_coletavel = 0.0
			
	return {"steering": steer, "throttle": throttle, "jump": should_jump}

func calcular_volante_para_alvo(alvo_pos: Vector3) -> float:
	var forward = car.global_transform.basis.z
	var dir_to_alvo = (alvo_pos - car.global_position).normalized()
	return forward.cross(dir_to_alvo).y * 2.0

func iniciar_manobra_chao():
	doing_stunt_timer = 1.0 
	
	var ability = car.get_node_or_null("%AbilityComponent")
	if ability and ability.current_energy >= ability.COST_JUMP and ability.current_cooldown <= 0:
		ability._execute_jump()
	else:
		if car.has_method("apply_central_impulse"):
			car.apply_central_impulse(Vector3.UP * car.mass * 15.0) 
			
	var t = car.get_tree().create_timer(0.2)
	t.timeout.connect(func():
		if is_instance_valid(car):
			var sp = car.find_child("StuntProcessor*", true, false)
			if sp and sp.has_method("initiate_stunt"):
				sp.initiate_stunt(Vector3(1, 0, 0), "BACKFLIP")
	)

func processar_direcao_final(delta: float, intencao_throttle: float, intencao_steering: float):
	var speed = car.linear_velocity.length()
	
	if speed < 2.0 and intencao_throttle > 0.5: stuck_timer += delta
	else: stuck_timer = 0.0
		
	if stuck_timer > 1.5:
		reverse_time = 1.5
		stuck_timer = 0.0
		
	if reverse_time > 0:
		reverse_time -= delta
		input.throttle = -1.0
		input.steering = 1.0 
		return 
		
	var steer_final = intencao_steering
	var is_avoiding = false
	var final_throttle = intencao_throttle
	
	ray_left.force_raycast_update()
	ray_center.force_raycast_update()
	ray_right.force_raycast_update()
	
	if ray_center.is_colliding():
		is_avoiding = true
		final_throttle = 0.4 
		if not ray_left.is_colliding(): steer_final = -1.0 
		elif not ray_right.is_colliding(): steer_final = 1.0 
		else: steer_final = 1.0 
	elif ray_left.is_colliding():
		is_avoiding = true
		steer_final = 1.0 
	elif ray_right.is_colliding():
		is_avoiding = true
		steer_final = -1.0 

	input.throttle = final_throttle
	if is_avoiding: input.steering = lerp(input.steering, steer_final, delta * 8.0)
	else: input.steering = clamp(steer_final, -1.0, 1.0)
