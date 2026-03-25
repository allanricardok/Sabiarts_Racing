# Grappling.gd
extends Area3D

@export_group("Movimento do Gancho")
@export var fly_speed = 170.0
@export var steering_force = 10.0
@export var finish_boost_force : float = 15.0 
@export var max_fly_time : float = 2 

@export_group("Física de Combate")
@export var knockback_force: float = 100.0

@export_group("Visuals")
@export var cable_color : Color = Color(0.2, 0.2, 0.2)
@export var cable_width : float = 0.05

var damage : float = 0.0

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : VehicleBody3D = null 
var is_tethered : bool = false
var time_alive : float = 0.0

var cable_mesh_instance : MeshInstance3D
var immediate_mesh : ImmediateMesh
var cable_material : StandardMaterial3D

var target_is_static : bool = false
var fixed_impact_point : Vector3 = Vector3.ZERO

var initial_distance : float = 0.0
var speed_multiplier : float = 1.0

func _ready():
	cable_mesh_instance = MeshInstance3D.new()
	immediate_mesh = ImmediateMesh.new()
	cable_material = StandardMaterial3D.new()
	
	cable_material.albedo_color = cable_color
	cable_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	
	cable_mesh_instance.mesh = immediate_mesh
	cable_mesh_instance.material_override = cable_material
	cable_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	get_tree().current_scene.add_child.call_deferred(cable_mesh_instance)
	
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup(dmg, shooter_vel, source_car, incoming_target = null):
	damage = dmg
	target = incoming_target
	shooter = source_car
	is_tethered = false # Garante estado limpo ao nascer
	
	var forward_dir = source_car.global_transform.basis.z 
	velocity = (forward_dir * fly_speed) + shooter_vel
	
	if velocity.dot(forward_dir) < 10.0:
		velocity = forward_dir * fly_speed
		
	look_at(global_position + forward_dir, Vector3.UP)

func _physics_process(delta):
	if not is_instance_valid(shooter):
		_cleanup_visuals()
		queue_free()
		return

	var real_delta = delta
	if shooter.is_in_group("jogadores"):
		real_delta = delta / Engine.time_scale

	if not is_tethered:
		_state_flying(real_delta)
	else:
		_state_tethered(real_delta)
	
	_update_cable_visual()

func _update_cable_visual():
	if not is_instance_valid(shooter) or not is_instance_valid(immediate_mesh): return
		
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(shooter.global_position + Vector3.UP * 0.5)
	immediate_mesh.surface_add_vertex(global_position)
	immediate_mesh.surface_end()

func _state_flying(delta):
	time_alive += delta
	if time_alive > max_fly_time: 
		_finish_grapple()
		return

	if target and is_instance_valid(target):
		var target_pos = target.global_position
		if global_position.distance_to(target_pos) < 2.5:
			_process_impact(target)
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

	var current_dist = shooter.global_position.distance_to(pull_target_pos)
	var progress = 1.0 - clamp(current_dist / initial_distance, 0.0, 1.0)
	
	var v_start = 40.0 * speed_multiplier
	var v_peak = 60.0 * speed_multiplier
	var ideal_speed : float = 0.0
	
	if progress < 0.7:
		ideal_speed = lerp(v_start, v_peak, progress / 0.7)
	else:
		ideal_speed = v_peak - (30.0 * ((progress - 0.7) / 0.3))

	var dir_to_target = (pull_target_pos - shooter.global_position).normalized()
	var target_vel_xz = Vector3(dir_to_target.x, 0, dir_to_target.z) * ideal_speed
	var current_vel_xz = Vector3(shooter.linear_velocity.x, 0, shooter.linear_velocity.z)
	
	var new_vel_xz = current_vel_xz.move_toward(target_vel_xz, 4.0)
	shooter.linear_velocity.x = new_vel_xz.x
	shooter.linear_velocity.z = new_vel_xz.z
	shooter.linear_velocity.y = lerp(shooter.linear_velocity.y, dir_to_target.y * ideal_speed, 0.15)

	var max_allowed_speed = v_peak * 1.1
	if shooter.linear_velocity.length() > max_allowed_speed:
		shooter.linear_velocity = shooter.linear_velocity.limit_length(max_allowed_speed)

	if current_dist < 10.0:
		_finish_grapple()

func _on_body_entered(body):
	if not is_tethered: _process_impact(body)

func _on_area_entered(area):
	if not is_tethered: _process_impact(area)

func _process_impact(target_node):
	# --- CADEADO DO GANCHO: Se já agarrou, ignora o resto! ---
	if is_tethered: return

	if not is_instance_valid(target_node): return
	if target_node.is_queued_for_deletion(): return

	# --- NOVO: REPELENTE DE HOLOGRAMA ---
	# Se o objeto atingido tiver essa tag (que colocamos na HoloWall), o gancho desiste e passa reto!
	if target_node.is_in_group("ignorar_gancho"):
		return

	var actual_target = target_node
	if target_node is Area3D:
		var dono = null
		if is_instance_valid(target_node.owner):
			dono = target_node.owner
		elif is_instance_valid(target_node.get_parent()):
			dono = target_node.get_parent()
		
		if dono and (dono.has_method("take_damage") or dono.is_in_group("jogadores") or dono.is_in_group("inimigos") or dono.is_in_group("destructibles")):
			actual_target = dono
		else:
			return 
		
	if is_instance_valid(shooter):
		if actual_target == shooter or actual_target == shooter.owner: 
			return
	
	if (actual_target is Marker3D) or ("SpawnPoint" in actual_target.name): return
		
	if actual_target.has_method("take_damage"):
		actual_target.take_damage(damage, self)
		
	_play_impact_explosion()
	_start_tether(actual_target)

func _play_impact_explosion():
	pass

func _start_tether(body):
	is_tethered = true # Tranca a porta!
	time_alive = 0.0 
	
	if body is StaticBody3D or body is GridMap:
		target_is_static = true
		fixed_impact_point = global_position
	else:
		target_is_static = false
		target = body
	
	var target_pos = fixed_impact_point if target_is_static else target.global_position
	initial_distance = shooter.global_position.distance_to(target_pos)
	
	speed_multiplier = max(1.0, (initial_distance / 2.8) / 60.0)
	if initial_distance < 1.0: initial_distance = 1.0

func _is_path_blocked(pull_target_pos) -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(shooter.global_position, pull_target_pos)
	query.exclude = [shooter.get_rid(), get_rid()]
	var result = space_state.intersect_ray(query)
	if result and result.collider != target:
		var dist_to_hit = shooter.global_position.distance_to(result.position)
		if dist_to_hit < shooter.global_position.distance_to(pull_target_pos) - 1.5:
			return true
	return false

func _cleanup_visuals():
	if is_instance_valid(cable_mesh_instance):
		cable_mesh_instance.queue_free()

func _finish_grapple():
	if is_tethered and is_instance_valid(shooter):
		var jump_dir = (Vector3.UP * 25 + shooter.global_transform.basis.z * 0.5).normalized()
		shooter.apply_central_impulse(jump_dir * finish_boost_force * shooter.mass)
		
		if not target_is_static and is_instance_valid(target):
			if target.has_method("take_damage"):
				target.take_damage(damage * 0.5, self)

	_cleanup_visuals()
	queue_free()
