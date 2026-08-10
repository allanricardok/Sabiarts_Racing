# Grappling.gd
extends BaseProjectile

@export_group("Movimento do Gancho")
@export var fly_speed = 170.0
@export var steering_force = 10.0
@export var finish_boost_force : float = 10.0 
@export var max_fly_time : float = 2.0 
@export var low_target_height_boost : float = 2.0 

# ============================================================================
# EFEITOS VISUAIS
# ============================================================================
@export_group("Efeitos da Explosão Final (Gancho)")
@export var explosion_color : Color = Color(0.8, 0.8, 0.8) # Fagulhas de metal
@export var explosion_size : float = 4.0 
@export var explosion_particles : int = 5
@export var explosion_smoke_size : float = 5.0 
@export var explosion_smoke_color : Color = Color(0.2, 0.2, 0.2, 1.0)
@export var fire_duration : float = 0.4

@export_group("Efeitos de Lançamento")
@export var launch_smoke_size : float = 2.0
@export var launch_smoke_color : Color = Color(0.5, 0.5, 0.5, 1.0)

@export_group("Visuals")
@export var cable_color : Color = Color(0.2, 0.2, 0.2)
@export var cable_width : float = 0.05

var target : Node3D = null
var is_tethered : bool = false
var time_alive : float = 0.0

var cable_mesh_instance : MeshInstance3D
var immediate_mesh : ImmediateMesh
var cable_material : StandardMaterial3D

var target_is_static : bool = false
var fixed_impact_point : Vector3 = Vector3.ZERO

var initial_distance : float = 0.0
var speed_multiplier : float = 1.0

var muzzle_start_height : float = 0.0
var anchor_offset_y : float = 0.0

func _ready():
	cable_mesh_instance = MeshInstance3D.new()
	immediate_mesh = ImmediateMesh.new()
	cable_material = StandardMaterial3D.new()
	
	cable_material.albedo_color = cable_color
	cable_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	cable_mesh_instance.mesh = immediate_mesh
	cable_mesh_instance.material_override = cable_material
	cable_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	get_tree().current_scene.add_child.call_deferred(cable_mesh_instance)
	
	super._ready()

func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 170.0, incoming_target: Node3D = null):
	super.setup(dmg_value, car_velocity, source_car, propulsion_speed)
	
	# NOVO: Garante que a linha volte a aparecer quando renascer do Pool
	if is_instance_valid(cable_mesh_instance):
		cable_mesh_instance.visible = true
	
	is_tethered = false 
	time_alive = 0.0
	muzzle_start_height = global_position.y
	anchor_offset_y = 0.0
	
	target = incoming_target if (is_instance_valid(incoming_target) and not incoming_target.is_queued_for_deletion()) else null

	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(
			global_position, 
			launch_smoke_color, 
			0.0, 
			3, 
			0.0, 
			launch_smoke_color, 
			launch_smoke_size,
			0.2
		)

func _physics_process(delta):
	# NOVO: Trava de segurança. Se o gancho está invisível no Pool, não faz nada!
	if not visible: return

	if not is_instance_valid(shooter):
		_cleanup_visuals()
		_deactivate_and_pool()
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

	if target and is_instance_valid(target) and not target.is_queued_for_deletion():
		var target_pos = target.global_position
		if global_position.distance_to(target_pos) < 2.5:
			_on_impact(target)
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
		if is_instance_valid(target) and not target.is_queued_for_deletion():
			pull_target_pos = target.global_position
		else:
			_finish_grapple()
			return

	pull_target_pos.y += anchor_offset_y
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

# ============================================================================
# LÓGICA DE IMPACTO REESCRITA PARA BURLAR O BASE PROJECTILE
# ============================================================================
func _on_impact(target_node):
	if is_tethered: return

	if not is_instance_valid(target_node) or target_node.is_queued_for_deletion(): return
	if target_node.is_in_group("ignorar_gancho"): return

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
		
	_play_impact_vfx()
	_start_tether(actual_target)

func _play_impact_vfx():
	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(
			global_position, 
			explosion_color,         
			explosion_size,          
			explosion_particles,     
			3.0, # Pouca luz para o gancho prendendo
			explosion_smoke_color,   
			explosion_smoke_size,
			fire_duration            
		)

func _start_tether(body):
	# =================================================================
	# TRAVA DE SEGURANÇA 1: O atirador ainda existe? (Pode ser um bot morto!)
	# =================================================================
	if not is_instance_valid(shooter):
		queue_free()
		return
		
	is_tethered = true
	time_alive = 0.0 
	
	if body is StaticBody3D or body is GridMap:
		target_is_static = true
		fixed_impact_point = global_position
	else:
		target_is_static = false
		target = body
		# =================================================================
		# TRAVA DE SEGURANÇA 2: O alvo foi destruído exatamente no mesmo frame?
		# =================================================================
		if not is_instance_valid(target):
			queue_free()
			return
	
	var target_pos = fixed_impact_point if target_is_static else target.global_position
	
	var space_state = get_world_3d().direct_space_state
	var q_car = PhysicsRayQueryParameters3D.create(shooter.global_position, shooter.global_position + Vector3.DOWN * 20.0)
	q_car.exclude = [shooter.get_rid(), get_rid()]
	var res_car = space_state.intersect_ray(q_car)
	
	var q_tgt = PhysicsRayQueryParameters3D.create(target_pos + Vector3.UP * 1.0, target_pos + Vector3.DOWN * 20.0)
	q_tgt.exclude = [shooter.get_rid(), get_rid()]
	
	if not target_is_static and is_instance_valid(target):
		q_tgt.exclude.append(target.get_rid())
		
	var res_tgt = space_state.intersect_ray(q_tgt)
	
	if res_car and res_tgt:
		var diff_floor = abs(res_car.position.y - res_tgt.position.y)
		if diff_floor < 2.5 and target_pos.y < (res_car.position.y + 1.0):
			anchor_offset_y = max(0.0, (muzzle_start_height - target_pos.y) + low_target_height_boost)

	var final_target_pos = target_pos + Vector3(0, anchor_offset_y, 0)
	initial_distance = shooter.global_position.distance_to(final_target_pos)
	
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
	if is_instance_valid(immediate_mesh):
		immediate_mesh.clear_surfaces()
	# Esconde o nó que está solto na cena
	if is_instance_valid(cable_mesh_instance):
		cable_mesh_instance.visible = false

# ============================================================================
# CICLO DE VIDA E LIMPEZA
# ============================================================================

# Sobrescrevemos a reciclagem para apagar o cabo antes de guardar a bala
func _deactivate_and_pool():
	_cleanup_visuals()
	super._deactivate_and_pool()

# Previne vazamento de memória: se a fase acabar ou o jogo fechar, o cabo é destruído
func _exit_tree():
	if is_instance_valid(cable_mesh_instance):
		cable_mesh_instance.queue_free()

func _finish_grapple():
	if is_tethered and is_instance_valid(shooter):
		var jump_dir = (Vector3.UP + shooter.global_transform.basis.z * 0.2).normalized()
		shooter.apply_central_impulse(jump_dir * finish_boost_force * shooter.mass)
		
		if not target_is_static and is_instance_valid(target) and not target.is_queued_for_deletion():
			if target.has_method("take_damage"):
				target.take_damage(damage, self)

	# NOVO: Destrava a variável para ele não tentar arrastar o carro da memória
	is_tethered = false 
	_cleanup_visuals()
	
	# Devolve o gancho pro Pool!
	_deactivate_and_pool()
