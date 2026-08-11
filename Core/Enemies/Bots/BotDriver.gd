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
var last_target_dist_sq : float = 999999.0 
var tempo_buscando_coletavel : float = 0.0

# --- VARIÁVEIS DO ANTI-LOOP E PULO ---
var timer_tentativa_alinhamento : float = 0.0
var is_in_anti_loop : bool = false
var stuck_jump_count : int = 0
var stuck_jump_cooldown : float = 0.0

func setup(_car: BaseVehicle, _input: Node):
	car = _car
	input = _input
	_criar_sensores()

func _criar_sensores():
	ray_left = RayCast3D.new()
	ray_center = RayCast3D.new()
	ray_right = RayCast3D.new()
	
	car.call_deferred("add_child", ray_left)
	car.call_deferred("add_child", ray_center)
	car.call_deferred("add_child", ray_right)
	
	var eye_height = Vector3(0, 1.0, 0)
	ray_left.position = eye_height
	ray_center.position = eye_height
	ray_right.position = eye_height
	
	var tilt_up = ray_length * 0.35 
	var tilt_up_sides = (ray_length * 0.8) * 0.35
	
	ray_center.target_position = Vector3(0, tilt_up, ray_length) 
	ray_left.target_position = Vector3(-ray_length * 0.7, tilt_up_sides, ray_length * 0.8)
	ray_right.target_position = Vector3(ray_length * 0.7, tilt_up_sides, ray_length * 0.8)
	
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
	var flat_car_pos = Vector3(car.global_position.x, 0, car.global_position.z)
	var flat_alvo_pos = Vector3(alvo.global_position.x, 0, alvo.global_position.z)
	var flat_dir = (flat_alvo_pos - flat_car_pos).normalized()
	var flat_forward = Vector3(car.global_transform.basis.z.x, 0, car.global_transform.basis.z.z).normalized()
	
	var steer = clamp(flat_forward.cross(flat_dir).y * 3.0, -1.0, 1.0)
	var throttle = 1.0
	var should_jump = false 
	var force_straight = false
	
	var dot_p = flat_forward.dot(flat_dir)
	var flat_dist_sq = flat_car_pos.distance_squared_to(flat_alvo_pos)
	var y_diff = alvo.global_position.y - car.global_position.y
	var speed = car.linear_velocity.length()
	var speed_kmh = speed * 3.6
	
	if stuck_jump_cooldown > 0:
		stuck_jump_cooldown -= delta

	# ==========================================================
	# 1. SISTEMA ANTI-LOOP (Girar em Falso)
	# OTIMIZAÇÃO: 400.0 é 20 metros ao quadrado
	# ==========================================================
	if flat_dist_sq < 400.0 and dot_p < 0.6 and speed_kmh < 10.0:
		timer_tentativa_alinhamento += delta
	else:
		timer_tentativa_alinhamento = 0.0

	if timer_tentativa_alinhamento > 3.0:
		is_in_anti_loop = true

	if is_in_anti_loop:
		if dot_p > 0.90:
			is_in_anti_loop = false
			timer_tentativa_alinhamento = 0.0
		else:
			steer = 1.0 if flat_forward.cross(flat_dir).y > 0 else -1.0
			if speed_kmh > 5.0: throttle = -1.0 
			else: throttle = 0.5 
			return {"steering": steer, "throttle": throttle, "jump": false, "force_straight": false}

	# ==========================================================
	# 2. TRAVA DE MIRA ABSOLUTA (> 0.99)
	# ==========================================================
	if dot_p > 0.99:
		steer = 0.0
		force_straight = true

	if dot_p < 0.0: throttle = 0.5 

	# ==========================================================
	# 3. SISTEMA DE DESISTÊNCIA RÁPIDA (Falhou na passagem)
	# OTIMIZAÇÃO: Comparações ao quadrado onde possível
	# ==========================================================
	if alvo_coletavel_atual != alvo:
		alvo_coletavel_atual = alvo
		last_target_dist_sq = flat_dist_sq
		stuck_jump_count = 0
	else:
		if flat_dist_sq > last_target_dist_sq + 1.0 and last_target_dist_sq < 225.0 and speed_kmh > 15.0:
			radar.ignorar_item(alvo, 10.0) 
			alvo_coletavel_atual = null
			last_target_dist_sq = 999999.0
			return {"steering": 0.0, "throttle": 1.0, "jump": false, "force_straight": false}
		last_target_dist_sq = flat_dist_sq

	# ==========================================================
	# 4. SITUAÇÃO D: ITEM MUITO ALTO (> 18m)
	# ==========================================================
	if y_diff > 18.0:
		radar.ignorar_item(alvo, 10.0)
		alvo_coletavel_atual = null
		return {"steering": 0.0, "throttle": 1.0, "jump": false, "force_straight": false}

	# ==========================================================
	# FASE 1: APROXIMAÇÃO DISTANTE (> 20 metros)
	# ==========================================================
	if flat_dist_sq > 400.0:
		throttle = 1.0 
		if dot_p > 0.99:
			steer = 0.0
			force_straight = true
	# ==========================================================
	# FASE 2: PREPARAÇÃO FINA (<= 20 metros)
	# ==========================================================
	else:
		if flat_dist_sq < 64.0 and speed_kmh < 15.0 and dot_p < 0.5 and y_diff > 3.0:
			if stuck_jump_count < 3:
				throttle = 0.0 
				steer = 0.0
				force_straight = true
				if stuck_jump_cooldown <= 0:
					should_jump = true
					stuck_jump_count += 1
					stuck_jump_cooldown = 1.5
					print("[DEBUG BOT] ", car.name, " Pulo de resgate na parede: ", stuck_jump_count, "/3")
			else:
				throttle = -1.0
				steer = 1.0
		else:
			if y_diff >= -1.0 and y_diff <= 4.0:
				throttle = 0.8
				if dot_p > 0.99:
					steer = 0.0
					force_straight = true

			elif y_diff > 4.0 and y_diff <= 8.0:
				if dot_p > 0.95:
					steer = 0.0
					force_straight = true

				# Apenas extrai a raiz quadrada se realmente precisar calcular os tempos lineares
				var real_dist = sqrt(flat_dist_sq)
				var apex_time = 1.45 
				var required_speed = real_dist / apex_time

				if speed < required_speed - 2.0: throttle = 1.0
				elif speed > required_speed + 5.0: throttle = 0.0
				else: throttle = 0.8

				var time_to_reach = real_dist / max(speed, 0.1)
				if time_to_reach <= apex_time and speed > 5.0:
					should_jump = true

				if flat_dist_sq <= 16.0: should_jump = true

			elif y_diff > 8.0 and y_diff <= 18.0:
				steer = 0.0
				force_straight = true
				throttle = 1.0
				
				if flat_dist_sq <= 25.0: 
					should_jump = true

	# ==========================================================
	# 5. TIMER GERAL DE DESISTÊNCIA
	# ==========================================================
	tempo_buscando_coletavel += delta
	if tempo_buscando_coletavel > 25.0: 
		radar.ignorar_item(alvo, 10.0)
		alvo_coletavel_atual = null
		tempo_buscando_coletavel = 0.0
			
	return {"steering": steer, "throttle": throttle, "jump": should_jump, "force_straight": force_straight}

func calcular_volante_para_alvo(alvo_pos: Vector3) -> float:
	var flat_car_pos = Vector3(car.global_position.x, 0, car.global_position.z)
	var flat_alvo_pos = Vector3(alvo_pos.x, 0, alvo_pos.z)
	var flat_forward = Vector3(car.global_transform.basis.z.x, 0, car.global_transform.basis.z.z).normalized()
	var dir_to_alvo = (flat_alvo_pos - flat_car_pos).normalized()
	
	var steer = flat_forward.cross(dir_to_alvo).y * 2.0
	if flat_forward.dot(dir_to_alvo) > 0.99: return 0.0
	return steer

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

func processar_direcao_final(delta: float, intencao_throttle: float, intencao_steering: float, force_straight: bool = false):
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
	
	# ==========================================================
	# A CORREÇÃO MESTRA: O GODOT JÁ ATUALIZA OS RAIOS POR VOCÊ
	# ==========================================================
	# REMOVIDO: ray_left.force_raycast_update()
	# REMOVIDO: ray_center.force_raycast_update()
	# REMOVIDO: ray_right.force_raycast_update()

	var col_center = ray_center.get_collider()
	var col_left = ray_left.get_collider()
	var col_right = ray_right.get_collider()

	var ignore_center = col_center and col_center.is_in_group("rampas")
	var ignore_left = col_left and col_left.is_in_group("rampas")
	var ignore_right = col_right and col_right.is_in_group("rampas")
	
	if not force_straight:
		if ray_center.is_colliding() and not ignore_center:
			is_avoiding = true
			final_throttle = 0.4 
			if not ray_left.is_colliding() or ignore_left: steer_final = -1.0 
			elif not ray_right.is_colliding() or ignore_right: steer_final = 1.0 
			else: steer_final = 1.0 
		elif ray_left.is_colliding() and not ignore_left:
			is_avoiding = true
			steer_final = 1.0 
		elif ray_right.is_colliding() and not ignore_right:
			is_avoiding = true
			steer_final = -1.0 

	input.throttle = final_throttle
	if is_avoiding: input.steering = lerp(input.steering, steer_final, delta * 8.0)
	else: input.steering = clamp(steer_final, -1.0, 1.0)
