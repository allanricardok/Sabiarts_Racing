extends Area3D

@export var fly_speed = 170.0
@export var steering_force = 10.0
@export var cable_color : Color = Color(0.2, 0.2, 0.2) # Cor de cabo de aço
@export var cable_width : float = 0.05

# --- NOVA VARIÁVEL PARA O PULO FINAL ---
@export var finish_boost_force : float = 15.0 

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : VehicleBody3D = null 
var is_tethered : bool = false
var time_alive : float = 0.0

# --- REFERÊNCIAS VISUAIS ---
var cable_mesh_instance : MeshInstance3D
var immediate_mesh : ImmediateMesh
var cable_material : StandardMaterial3D

# --- VARIÁVEIS DE REFINAMENTO ---
var target_is_static : bool = false
var fixed_impact_point : Vector3 = Vector3.ZERO

# --- VARIÁVEIS DE VELOCIDADE DINÂMICA ---
var initial_distance : float = 0.0
var speed_multiplier : float = 1.0

func _ready():
	# Inicialização do sistema de cabo visual
	cable_mesh_instance = MeshInstance3D.new()
	immediate_mesh = ImmediateMesh.new()
	cable_material = StandardMaterial3D.new()
	
	cable_material.albedo_color = cable_color
	cable_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED # Garante visibilidade
	
	cable_mesh_instance.mesh = immediate_mesh
	cable_mesh_instance.material_override = cable_material
	cable_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Adicionamos ao root da cena para que as coordenadas globais funcionem sem herdar rotação
	get_tree().current_scene.add_child.call_deferred(cable_mesh_instance)
	print("[Grappling] Cabo visual inicializado")

func setup(_dmg, shooter_vel, source_car, incoming_target = null):
	target = incoming_target
	shooter = source_car
	
	var forward_dir = source_car.global_transform.basis.z 
	
	# Usamos a velocidade de voo (fly_speed) para garantir o disparo frontal
	velocity = (forward_dir * fly_speed) + shooter_vel
	
	# Trava de segurança para ré
	if velocity.dot(forward_dir) < 10.0:
		velocity = forward_dir * fly_speed
		
	look_at(global_position + forward_dir, Vector3.UP)

func _physics_process(delta):
	if not is_instance_valid(shooter):
		# Se o atirador sumiu, apenas deletamos o cabo sem boost
		_cleanup_visuals()
		queue_free()
		return

	if not is_tethered:
		_state_flying(delta)
	else:
		_state_tethered(delta)
	
	_update_cable_visual()

func _update_cable_visual():
	if not is_instance_valid(shooter) or not is_instance_valid(immediate_mesh):
		return
		
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Ponto A: O carro (Atirador)
	var start_point = shooter.global_position + Vector3.UP * 0.5
	
	# Ponto B: O próprio projétil
	var end_point = global_position
	
	immediate_mesh.surface_add_vertex(start_point)
	immediate_mesh.surface_add_vertex(end_point)
	immediate_mesh.surface_end()

func _state_flying(delta):
	time_alive += delta
	if time_alive > 4.0: _finish_grapple()

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
	
	if time_alive > 3.2:
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
	var target_vel_xz = Vector3(dir_to_target.x, 0, dir_to_target.z) * ideal_speed
	var current_vel_xz = Vector3(shooter.linear_velocity.x, 0, shooter.linear_velocity.z)
	
	var new_vel_xz = current_vel_xz.move_toward(target_vel_xz, 4.0)
	shooter.linear_velocity.x = new_vel_xz.x
	shooter.linear_velocity.z = new_vel_xz.z

	# --- EIXO Y (VERTICAL) ---
	var target_vel_y = dir_to_target.y * ideal_speed
	shooter.linear_velocity.y = lerp(shooter.linear_velocity.y, target_vel_y, 0.15)

	# --- TRAVA DE SEGURANÇA (SPEED CAP) ---
	var max_allowed_speed = v_peak * 1.1
	if shooter.linear_velocity.length() > max_allowed_speed:
		shooter.linear_velocity = shooter.linear_velocity.limit_length(max_allowed_speed)

	# 3. CONDIÇÃO DE TÉRMINO
	if current_dist < 10.0:
		_finish_grapple()

func _start_tether(body):
	is_tethered = true
	time_alive = 0.0 
	print("[Grappling] Gancho conectado a: ", body.name)
	
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
		# BUSCA O COMPONENTE DE STATS NO ALVO
		var target_stats = body.get_node_or_null("StatsComponent")
		if target_stats and target_stats.has_method("take_damage"):
			# Aplica um dano base (ex: 10) e passa o shooter para o ScoreManager saber quem atirou
			target_stats.take_damage(10.0, shooter)
			print("[Grappling] Dano aplicado em: ", body.name)
		
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

# --- FUNÇÃO DE LIMPEZA AUXILIAR ---
func _cleanup_visuals():
	if is_instance_valid(cable_mesh_instance):
		cable_mesh_instance.queue_free()

func _finish_grapple():
	# Só aplicamos o "pulo" se o gancho estava de fato puxando o jogador
	if is_tethered and is_instance_valid(shooter):
		# Direção do pulo: Para cima e um pouco para frente do carro
		var jump_dir = (Vector3.UP * 25 + shooter.global_transform.basis.z * 0.5).normalized()
		
		# Aplicamos o impulso central
		shooter.apply_central_impulse(jump_dir * finish_boost_force * shooter.mass)
		print("[Grappling] Pulo de finalização aplicado!")

	_cleanup_visuals()
	print("[Grappling] Gancho finalizado e cabo removido")
	queue_free()
