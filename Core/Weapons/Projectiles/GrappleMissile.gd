# GrapplingProjectile.gd
extends Area3D

@export var fly_speed = 170.0
@export var steering_force = 10.0

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : VehicleBody3D = null 
var is_tethered : bool = false
var time_alive : float = 0.0

# --- VARIÁVEIS DE REFINAMENTO ---
var target_is_static : bool = false
var fixed_impact_point : Vector3 = Vector3.ZERO

# --- VARIÁVEIS DE VELOCIDADE DINÂMICA ---
var initial_distance : float = 0.0
var speed_multiplier : float = 1.0

func setup(_dmg, shooter_vel, source_car, incoming_target = null):
	target = incoming_target
	shooter = source_car
	
	var forward_dir = source_car.global_transform.basis.z 
	velocity = shooter_vel + (forward_dir * 10.0)
	look_at(global_position + forward_dir, Vector3.UP)

func _physics_process(delta):
	if not is_instance_valid(shooter):
		queue_free()
		return

	if not is_tethered:
		_state_flying(delta)
	else:
		_state_tethered(delta)

func _state_flying(delta):
	time_alive += delta
	if time_alive > 5.0: queue_free()

	if target and is_instance_valid(target):
		var target_pos = target.global_position
		if global_position.distance_to(target_pos) < 2.5:
			_start_tether(target)
			return

		var desired_dir = (target_pos - global_position).normalized()
		var steering = (desired_dir * fly_speed - velocity) * steering_force * delta
		velocity += steering
	else:
		velocity = velocity.move_toward(velocity.normalized() * fly_speed, delta * 50.0)
	
	global_position += velocity * delta
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

func _state_tethered(delta):
	time_alive += delta
	
	if time_alive > 3.0:
		_finish_grapple()
		return

	var pull_target_pos = fixed_impact_point
	if not target_is_static:
		if is_instance_valid(target):
			pull_target_pos = target.global_position
		else:
			_finish_grapple()
			return

	global_position = pull_target_pos

	if time_alive > 0.2:
		if _is_path_blocked(pull_target_pos):
			_finish_grapple()
			return

	# 1. CÁLCULO DA VELOCIDADE IDEAL
	var current_dist = shooter.global_position.distance_to(pull_target_pos)
	var progress = 1.0 - clamp(current_dist / initial_distance, 0.0, 1.0)
	
	var v_start = 40.0 * speed_multiplier
	var v_peak = 60.0 * speed_multiplier
	var ideal_speed : float = 0.0
	
	if progress < 0.7:
		var t = progress / 0.7
		ideal_speed = lerp(v_start, v_peak, t)
	else:
		var t = (progress - 0.7) / 0.3
		ideal_speed = v_peak - (30.0 * t)

	# 2. FÍSICA HÍBRIDA (Decomposição e Controle)
	var dir_to_target = (pull_target_pos - shooter.global_position).normalized()
	
	# --- EIXO XZ (HORIZONTAL) ---
	# Usamos move_toward para dar o feeling de "trilho" que não deixa acelerar infinito
	var target_vel_xz = Vector3(dir_to_target.x, 0, dir_to_target.z) * ideal_speed
	var current_vel_xz = Vector3(shooter.linear_velocity.x, 0, shooter.linear_velocity.z)
	
	# Se o carro já estiver mais rápido que o ideal_speed, o move_toward vai freá-lo
	# O valor '4.0' controla a "força" com que ele te puxa para a velocidade ideal
	var new_vel_xz = current_vel_xz.move_toward(target_vel_xz, 4.0)
	shooter.linear_velocity.x = new_vel_xz.x
	shooter.linear_velocity.z = new_vel_xz.z

	# --- EIXO Y (VERTICAL) ---
	# Mantemos mecânico para vencer a gravidade, mas com teto
	var target_vel_y = dir_to_target.y * ideal_speed
	# O lerp aqui suaviza a subida sem deixar criar o efeito slingshot
	shooter.linear_velocity.y = lerp(shooter.linear_velocity.y, target_vel_y, 0.15)

	# --- TRAVA DE SEGURANÇA (SPEED CAP) ---
	# Garante que a velocidade TOTAL nunca ultrapasse o v_peak calculado para o trajeto
	# Adicionamos uma margem de 10% para não parecer uma parede invisível
	var max_allowed_speed = v_peak * 1.1
	if shooter.linear_velocity.length() > max_allowed_speed:
		shooter.linear_velocity = shooter.linear_velocity.limit_length(max_allowed_speed)

	# 3. CONDIÇÃO DE TÉRMINO
	if current_dist < 6.0:
		_finish_grapple()

func _start_tether(body):
	is_tethered = true
	time_alive = 0.0 
	
	if body is StaticBody3D or body is GridMap:
		target_is_static = true
		fixed_impact_point = global_position
	else:
		target_is_static = false
		target = body
	
	var target_pos = fixed_impact_point if target_is_static else target.global_position
	initial_distance = shooter.global_position.distance_to(target_pos)
	
	var required_avg_speed = initial_distance / 2.8 
	var default_avg_speed = 60.0
	
	speed_multiplier = max(1.0, required_avg_speed / default_avg_speed)
	
	if initial_distance < 1.0: initial_distance = 1.0

func _on_body_entered(body):
	if not is_tethered and body != shooter:
		_start_tether(body)

func _is_path_blocked(pull_target_pos) -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(shooter.global_position, pull_target_pos)
	query.exclude = [shooter.get_rid(), get_rid()]
	var result = space_state.intersect_ray(query)
	if result:
		var hit_node = result.collider
		if hit_node != target:
			var dist_to_hit = shooter.global_position.distance_to(result.position)
			var dist_to_grapple = shooter.global_position.distance_to(pull_target_pos)
			if dist_to_hit < dist_to_grapple - 1.5:
				return true
	return false

func _finish_grapple():
	queue_free()
