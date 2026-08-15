extends Node
class_name BotDriverV2

var car: BaseVehicle
var input: Node 

# --- OTIMIZAÇÃO (LOD) ---
var current_lod_level: int = 0 # 0 = Perto, 1 = Médio, 2 = Longe (Desliga Raycasts)

var ray_left : RayCast3D
var ray_center : RayCast3D
var ray_right : RayCast3D
var ray_length : float = 20.0

var stuck_timer: float = 0.0 
var reverse_time: float = 0.0 
var doing_stunt_timer: float = 0.0 

# --- VARIÁVEIS DO ANTI-LOOP E PULO INSTINTIVO ---
var timer_tentativa_alinhamento : float = 0.0
var is_in_anti_loop : bool = false
var stuck_jump_count : int = 0
var stuck_jump_cooldown : float = 0.0
var stunt_cooldown: float = 0.0

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
	
	# Colisão com o cenário/obstáculos
	ray_left.collision_mask = 1
	ray_center.collision_mask = 1
	ray_right.collision_mask = 1
	
	ray_left.add_exception(car)
	ray_center.add_exception(car)
	ray_right.add_exception(car)

func processar_manobras_travantes(delta: float) -> bool:
	# Se estiver no meio de um mortal/manobra, trava o volante da IA
	if doing_stunt_timer > 0:
		doing_stunt_timer -= delta
		input.throttle = 1.0
		input.pitch = 1.0 
		input.is_action_pressed = true 
		return true
	return false

# ==============================================================================
# NAVEGAÇÃO VETORIAL PURA (Sem Táticas, Apenas Física)
# ==============================================================================
func navegar_para_ponto(target_pos: Vector3, delta: float) -> Dictionary:
	var flat_car_pos = Vector3(car.global_position.x, 0, car.global_position.z)
	var flat_target_pos = Vector3(target_pos.x, 0, target_pos.z)
	var flat_dir = (flat_target_pos - flat_car_pos).normalized()
	var flat_forward = Vector3(car.global_transform.basis.z.x, 0, car.global_transform.basis.z.z).normalized()
	
	var steer = clamp(flat_forward.cross(flat_dir).y * 3.0, -1.0, 1.0)
	var throttle = 1.0
	var should_jump = false 
	var should_handbrake = false
	var force_straight = false
	
	var dot_p = flat_forward.dot(flat_dir)
	var flat_dist_sq = flat_car_pos.distance_squared_to(flat_target_pos)
	var y_diff = target_pos.y - car.global_position.y
	var speed = car.linear_velocity.length()
	var speed_kmh = speed * 3.6
	
	if stuck_jump_cooldown > 0: stuck_jump_cooldown -= delta

	# 1. SISTEMA ANTI-LOOP (Evita que o carro fique girando em círculos feito um cachorro)
	if flat_dist_sq < 400.0 and dot_p < 0.6 and speed_kmh < 10.0:
		timer_tentativa_alinhamento += delta
	else:
		timer_tentativa_alinhamento = 0.0

	if timer_tentativa_alinhamento > 3.0: is_in_anti_loop = true

	if is_in_anti_loop:
		if dot_p > 0.90:
			is_in_anti_loop = false
			timer_tentativa_alinhamento = 0.0
		else:
			# --- 180 RECOVER (Burnout Anti-Loop) ---
			var turn_dir = 1.0 if flat_forward.cross(flat_dir).y > 0 else -1.0
			return {
				"steering": turn_dir,
				"throttle": 1.0,
				"jump": false,
				"force_straight": false,
				"handbrake": true,
				"brake": 1.0,
				"ignore_avoidance": true
			}

	# 2. TRAVA DE MIRA RETA (Alinhamento perfeito)
	if dot_p > 0.99:
		steer = 0.0
		force_straight = true

	# Se o alvo está atrás do carro, freia/dá ré suavemente
	if dot_p < 0.0: throttle = 0.5 

	# 3. CONTROLE DE VELOCIDADE POR ALTURA E DISTÂNCIA
	if flat_dist_sq > 400.0:
		throttle = 1.0 
	else:
		# Pulo instintivo para subir paredes ou degraus
		if flat_dist_sq < 64.0 and speed_kmh < 15.0 and dot_p < 0.5 and y_diff > 3.0:
			if stuck_jump_count < 3:
				throttle = 0.0 
				steer = 0.0
				force_straight = true
				if stuck_jump_cooldown <= 0:
					should_jump = true
					stuck_jump_count += 1
					stuck_jump_cooldown = 1.5
			else:
				throttle = -1.0
				steer = 1.0
		else:
			if y_diff >= -1.0 and y_diff <= 4.0:
				throttle = 0.8
			elif y_diff > 4.0 and y_diff <= 18.0:
				var real_dist = sqrt(flat_dist_sq)
				var required_speed = real_dist / 1.45
				
				if speed < required_speed - 2.0: throttle = 1.0
				elif speed > required_speed + 5.0: throttle = 0.0
				else: throttle = 0.8
				
				if flat_dist_sq <= 25.0: should_jump = true
			
			elif y_diff > 18.0:
				throttle = 1.0

	return {"steering": steer, "throttle": throttle, "jump": should_jump, "force_straight": force_straight, "handbrake": should_handbrake}

# ==============================================================================
# MANOBRAS DE AÇÃO IMEDIATA
# ==============================================================================
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

# ==============================================================================
# APLICAÇÃO FÍSICA E REFLEXOS (Avoidance)
# ==============================================================================
func aplicar_inputs_finais(delta: float, intencoes: Dictionary):
	input.pitch = 0.0
	input.is_attribute_pressed = false
	input.ability_up = false
	input.ability_down = false
	
	var steer_final = intencoes.get("steering", 0.0)
	var throttle_final = intencoes.get("throttle", 1.0)
	var force_straight = intencoes.get("force_straight", false)
	var ignore_avoidance = intencoes.get("ignore_avoidance", false)
	
	# Funde o handbrake no freio normal
	var freio_final = intencoes.get("brake", 0.0)
	if intencoes.get("handbrake", false): 
		freio_final = 1.0 
		
	if "brake" in input: input.brake = freio_final
	if "handbrake" in input: input.handbrake = intencoes.get("handbrake", false)
	
	stunt_cooldown -= delta
	
	# --- GATILHO UNIVERSAL DE MANOBRAS ---
	if intencoes.get("jump", false) and doing_stunt_timer <= 0.0 and stunt_cooldown <= 0.0:
		iniciar_manobra_chao()
		stunt_cooldown = 4.0 
		
	# --- ANTI-STUCK (Ré Automática) ---
	var speed = car.linear_velocity.length()
	if ignore_avoidance:
		stuck_timer = 0.0
	else:
		if speed < 2.0 and throttle_final > 0.5: stuck_timer += delta
		else: stuck_timer = 0.0
		
	if stuck_timer > 0.5:
		reverse_time = 1.5
		stuck_timer = 0.0
		stuck_jump_count = 0 
		
	if reverse_time > 0:
		reverse_time -= delta
		input.throttle = -1.0
		input.steering = 1.0 
		_atualizar_botoes_do_carro()
		return 
		
	# ==========================================================
	# OTIMIZAÇÃO: CULLING DE RAYCASTS
	# ==========================================================
	var usar_raycasts = (current_lod_level < 2)
	ray_center.enabled = usar_raycasts
	ray_left.enabled = usar_raycasts
	ray_right.enabled = usar_raycasts

	var is_avoiding = false
	
	if usar_raycasts and not force_straight and not ignore_avoidance:
		var col_center = ray_center.get_collider()
		var col_left = ray_left.get_collider()
		var col_right = ray_right.get_collider()

		var ignore_center = col_center and col_center.is_in_group("rampas")
		var ignore_left = col_left and col_left.is_in_group("rampas")
		var ignore_right = col_right and col_right.is_in_group("rampas")
		
		if ray_center.is_colliding() and not ignore_center:
			is_avoiding = true
			throttle_final = 0.4 
			if not ray_left.is_colliding() or ignore_left: steer_final = -1.0 
			elif not ray_right.is_colliding() or ignore_right: steer_final = 1.0 
			else: steer_final = 1.0 
		elif ray_left.is_colliding() and not ignore_left:
			is_avoiding = true
			steer_final = 1.0 
		elif ray_right.is_colliding() and not ignore_right:
			is_avoiding = true
			steer_final = -1.0 

	input.throttle = throttle_final
	
	var steer_speed = clamp(speed * 0.5, 8.0, 20.0)
	if is_avoiding: input.steering = lerp(input.steering, steer_final, delta * steer_speed)
	elif ignore_avoidance: input.steering = steer_final # Trava volante no 180 sem lerp
	else: input.steering = clamp(steer_final, -1.0, 1.0)
	
	_atualizar_botoes_do_carro()

# --- TRADUÇÃO DE EIXOS PARA BOTÕES DO VEÍCULO ---
func _atualizar_botoes_do_carro():
	if "is_accelerating" in input:
		input.is_accelerating = input.throttle > 0.1
		
	if "is_braking" in input:
		var tem_freio = false
		if "brake" in input: tem_freio = input.brake > 0.1
			
		var tem_handbrake = false
		if "handbrake" in input: tem_handbrake = input.handbrake
			
		var quer_frear = tem_freio or tem_handbrake or (input.throttle < -0.1)
		input.is_braking = quer_frear
