extends CharacterBody3D

var is_dead: bool = false

@export_group("Pedestrian Settings")
@export var base_speed: float = 6.0
@export var is_invincible: bool = false
@export var energy_on_death: float = 5.0
@export var blood_splash_distance: float = 3.0

@export_group("Efeitos Visuais")
@export var blood_stain_scale: float = 2.0

@export_group("Wander Settings")
@export var max_wander_radius: float = 30.0
@export var sleep_distance: float = 300.0 # Reduzido para 300 metros!

var current_direction: Vector3 = Vector3.ZERO
var panic_timer: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO

# === VARIÁVEIS PARA SALVAR A COLISÃO ORIGINAL ===
var _initial_layer: int
var _initial_mask: int

# ==============================================================================
# OTIMIZAÇÃO MAXIMA: VARIÁVEIS ESTÁTICAS E CULLING DE IA
# ==============================================================================
static var _shared_blood_tex: ImageTexture = null
static var _shared_gore_mat: StandardMaterial3D = null
static var _shared_gore_mesh: BoxMesh = null

var _dodge_timer: float = 0.0
var _cached_dodge_vel: Vector3 = Vector3.ZERO

# --- SISTEMA DE LOD (LEVEL OF DETAIL) LÓGICO ---
var _is_sleeping: bool = false
var _sleep_timer: float = 0.0
var _sleep_dist_sq: float = 90000.0 # 300 * 300
var _dist_to_closest_player_sq: float = 999999.0

# --- SISTEMA DE FRAME SKIPPING (TIME-SLICING) ---
var _skipped_frames: int = 0
var _target_skip: int = 0

func _ready():
	add_to_group("pedestrians")
	
	_initial_layer = collision_layer
	_initial_mask = collision_mask
	
	_sleep_dist_sq = sleep_distance * sleep_distance
	
	# Desincroniza a checagem inicial para não estressar a CPU no frame 1
	_sleep_timer = randf_range(0.0, 1.5)

func _physics_process(delta):
	if is_dead: return 
	
	# ====================================================================
	# 1. ATUALIZAÇÃO DO ESTADO DE LOD
	# ====================================================================
	_sleep_timer -= delta
	if _sleep_timer <= 0:
		_sleep_timer = randf_range(1.0, 1.5) 
		_check_sleep_state()
		
	# Se estiver muito longe (>300m), ignora cálculos de gravidade e colisão!
	if _is_sleeping: return
	
	# ====================================================================
	# 2. FRAME SKIPPING (Pula cálculos físicos pesados se estiver longe)
	# ====================================================================
	if _skipped_frames < _target_skip:
		_skipped_frames += 1
		return
		
	# Multiplicador de tempo baseado nos frames que pulamos
	var time_mult = float(_skipped_frames + 1)
	var real_delta = delta * time_mult
	
	if not is_on_floor():
		velocity.y -= 9.8 * real_delta
		
	panic_timer -= real_delta
	if panic_timer <= 0:
		_pick_new_direction()
		
	var move_vel = current_direction * base_speed
	
	# Só processa esquiva se o jogador estiver num raio de ~50 metros
	if is_invincible and _dist_to_closest_player_sq < 2500.0:
		_dodge_timer -= real_delta
		if _dodge_timer <= 0:
			_dodge_timer = 0.2 
			_cached_dodge_vel = Vector3.ZERO
			
			var players = get_tree().get_nodes_in_group("jogadores")
			for p in players:
				if not is_instance_valid(p) or p.is_queued_for_deletion(): continue
				
				if global_position.distance_squared_to(p.global_position) < 64.0:
					var away_dir = (global_position - p.global_position).normalized()
					away_dir.y = 0
					_cached_dodge_vel = away_dir * 30.0 
					break

	velocity.x = move_vel.x + _cached_dodge_vel.x
	velocity.z = move_vel.z + _cached_dodge_vel.z
	
	# ====================================================================
	# 3. COMPENSAÇÃO DE MOVIMENTO E DESLIZAMENTO
	# ====================================================================
	if _skipped_frames > 0:
		# Multiplica a velocidade temporariamente para cobrir a distância dos frames perdidos
		velocity *= time_mult
		move_and_slide()
		# Restaura a velocidade real (mantendo os zeramentos de impacto feitos pela engine)
		velocity /= time_mult
	else:
		move_and_slide()
		
	_skipped_frames = 0

func _check_sleep_state():
	var players = get_tree().get_nodes_in_group("jogadores")
	var should_sleep = true
	
	_dist_to_closest_player_sq = _sleep_dist_sq + 10.0 # Reseta para longe
	
	for p in players:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			var dist_sq = global_position.distance_squared_to(p.global_position)
			if dist_sq < _dist_to_closest_player_sq:
				_dist_to_closest_player_sq = dist_sq
				
	if _dist_to_closest_player_sq < _sleep_dist_sq:
		should_sleep = false
				
	# Define a taxa de atualização física (FPS do Pedestre) baseada na distância
	if _dist_to_closest_player_sq < 2500.0: # < 50m
		_target_skip = 0 # Processa todos os frames
	elif _dist_to_closest_player_sq < 10000.0: # < 100m
		_target_skip = 2 # Pula 2 frames (roda a ~20fps)
	else: # 100m a 300m
		_target_skip = 5 # Pula 5 frames (roda a ~10fps)
				
	if should_sleep != _is_sleeping:
		_is_sleeping = should_sleep
		
		if _is_sleeping:
			collision_layer = 0
			collision_mask = 0
			var anim = find_child("AnimatedSprite3D")
			if anim and anim.is_playing(): anim.stop()
		else:
			collision_layer = _initial_layer
			collision_mask = _initial_mask
			var anim = find_child("AnimatedSprite3D")
			if anim and not anim.is_playing(): anim.play()

func _pick_new_direction():
	var max_rad_sq = max_wander_radius * max_wander_radius
	
	if global_position.distance_squared_to(spawn_position) > max_rad_sq:
		var random_center = spawn_position + Vector3(randf_range(-8.0, 8.0), 0, randf_range(-8.0, 8.0))
		current_direction = (random_center - global_position).normalized()
	else:
		var random_angle = randf() * TAU 
		current_direction = Vector3(cos(random_angle), 0, sin(random_angle)).normalized()
		
	panic_timer = randf_range(1.5, 4.0)

func _on_hitbox_body_entered(body):
	if body is VehicleBody3D or body.is_in_group("jogadores"):
		if is_invincible: return 
		take_damage(100.0, body)

func take_damage(amount: float, attacker: Node3D = null):
	if is_invincible or is_dead: 
		return 
	
	var death_pos = global_position 
	is_dead = true
	
	var actual_shooter = attacker
	var is_projectile = false
	
	if attacker and "shooter" in attacker and is_instance_valid(attacker.shooter):
		actual_shooter = attacker.shooter
		is_projectile = true 
	
	var impact_dir = Vector3.ZERO
	if is_instance_valid(actual_shooter):
		if "linear_velocity" in actual_shooter:
			impact_dir = actual_shooter.linear_velocity
		else:
			impact_dir = -actual_shooter.global_transform.basis.z 
			
	# --- CULLING DE GRÁFICOS GERADOS POR CPU (Otimização) ---
	var closest_human_sq = 9999999.0
	for p in get_tree().get_nodes_in_group("jogadores"):
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			var inp = p.get_node_or_null("%InputComponent")
			# Checa se é um jogador humano (não-bot)
			if inp and "is_bot" in inp and not inp.is_bot:
				var d_sq = death_pos.distance_squared_to(p.global_position)
				if d_sq < closest_human_sq:
					closest_human_sq = d_sq

	# 40000.0 é o equivalente a 200m ao quadrado (200 * 200)
	var is_far_from_human = (closest_human_sq > 40000.0)

	# Só gera partículas pesadas e poças de sangue se o humano estiver a menos de 200m
	if not is_far_from_human:
		_spawn_gore_visuals(death_pos, impact_dir)
		_spawn_blood_stain(death_pos)
		
	var trigger_splash = false
	if not is_projectile:
		trigger_splash = true
	else:
		var splash_sq = blood_splash_distance * blood_splash_distance
		if is_instance_valid(actual_shooter) and death_pos.distance_squared_to(actual_shooter.global_position) <= splash_sq:
			trigger_splash = true
			
	if trigger_splash and not is_far_from_human:
		_trigger_blood_splash_ui(actual_shooter)
	
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	
	collision_layer = 0
	collision_mask = 0
	
	if is_in_group("pedestrians"):
		remove_from_group("pedestrians")
		
	velocity = Vector3.ZERO
	global_position = Vector3(0, -1000, 0) 
	
	if attacker is VehicleBody3D or attacker is RigidBody3D:
		attacker.linear_velocity *= 0.88 
		
	if is_instance_valid(actual_shooter):
		var ability = actual_shooter.get_node_or_null("%AbilityComponent")
		if ability:
			ability.current_energy = min(ability.current_energy + energy_on_death, ability.MAX_ENERGY)
			
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("HIT_OBJECT")
			
		var input_comp = actual_shooter.get_node_or_null("%InputComponent")
		var is_bot = (input_comp and "is_bot" in input_comp and input_comp.is_bot)
		
		if not is_bot:
			if "pedestrians_killed" in actual_shooter:
				actual_shooter.pedestrians_killed += 1

			if is_instance_valid(GameStats) and GameStats.has_method("add_pedestrian_kill"):
				GameStats.add_pedestrian_kill()
				
			if input_comp:
				var hud = get_tree().get_first_node_in_group("HUD" + input_comp.suffix)
				if not hud: hud = get_tree().get_first_node_in_group("HUD")
				if hud and hud.has_method("criar_toast"):
					hud.criar_toast("💥 ROADKILL!", Color.RED)

	get_tree().call_group("TutorialUI", "complete_task", "pedestrian")
	get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.ROADKILL, 1.0, "")
	
	var parent_spawner = get_parent()
	if parent_spawner and parent_spawner.has_method("recycle_pedestrian"):
		parent_spawner.recycle_pedestrian(self)
	else:
		queue_free()

func _spawn_gore_visuals(pos: Vector3, impact_dir: Vector3 = Vector3.ZERO):
	var anim_sprite = find_child("AnimatedSprite3D")
	if not anim_sprite or not anim_sprite.sprite_frames: return
	
	var current_tex = anim_sprite.sprite_frames.get_frame_texture(anim_sprite.animation, anim_sprite.frame)
	if not current_tex: return
	
	# ====================================================================
	# OTIMIZAÇÃO: Busca o material estático direto do Cache Central
	# ====================================================================
	if _shared_gore_mat == null:
		_shared_gore_mat = MaterialCache.get_mat("PedestrianGore")
		_shared_gore_mesh = BoxMesh.new()
		_shared_gore_mesh.size = Vector3(0.12, 0.12, 0.12)
		_shared_gore_mesh.surface_set_material(0, _shared_gore_mat)
	
	var tex_w = current_tex.get_width()
	var tex_h = current_tex.get_height()
	
	var base_dir = impact_dir
	if base_dir.length_squared() < 0.01:
		base_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	else:
		base_dir = base_dir.normalized()
		base_dir.y = 0 
	
	for i in range(5):
		var chunk = Sprite3D.new()
		chunk.texture = current_tex
		chunk.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		chunk.pixel_size = anim_sprite.pixel_size * 1.76 
		
		chunk.region_enabled = true
		var chunk_w = tex_w * randf_range(0.3, 0.6)
		var chunk_h = tex_h * randf_range(0.3, 0.6)
		var rx = randf_range(0, tex_w - chunk_w)
		var ry = randf_range(0, tex_h - chunk_h)
		chunk.region_rect = Rect2(rx, ry, chunk_w, chunk_h)
		
		var rastro_sangue = CPUParticles3D.new()
		rastro_sangue.amount = 8
		rastro_sangue.lifetime = 0.35
		rastro_sangue.local_coords = false
		
		rastro_sangue.mesh = _shared_gore_mesh
		rastro_sangue.direction = Vector3(0, -1, 0)
		rastro_sangue.spread = 30.0
		rastro_sangue.initial_velocity_min = 0.5
		rastro_sangue.initial_velocity_max = 1.5
		chunk.add_child(rastro_sangue)
		
		get_tree().current_scene.add_child(chunk)
		
		var start_pos = pos + Vector3(randf_range(-0.5, 0.5), randf_range(0.1, 0.5), randf_range(-0.5, 0.5))
		chunk.global_position = start_pos
		
		var spread_angle = deg_to_rad(randf_range(-45.0, 45.0))
		var final_dir = base_dir.rotated(Vector3.UP, spread_angle).normalized()
		
		var distance = randf_range(5.0, 12.0) 
		var target_pos = start_pos + (final_dir * distance)
		
		var peak_y = start_pos.y
		if randf() > 0.8:
			peak_y += randf_range(2.0, 3.5) 
		else:
			peak_y += randf_range(0.2, 1.2) 
			
		var floor_y = start_pos.y - randf_range(0.0, 1.0)
		var fly_time = randf_range(0.4, 0.8)
		
		var tween = get_tree().create_tween().set_parallel(true)
		tween.tween_property(chunk, "global_position:x", target_pos.x, fly_time)
		tween.tween_property(chunk, "global_position:z", target_pos.z, fly_time)
		tween.tween_property(chunk, "rotation", Vector3(randf_range(-TAU*3, TAU*3), randf_range(-TAU*3, TAU*3), randf_range(-TAU*3, TAU*3)), fly_time)
		
		var y_tween = get_tree().create_tween()
		var up_time = fly_time * 0.35
		var down_time = fly_time * 0.65
		y_tween.tween_property(chunk, "global_position:y", peak_y, up_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		y_tween.tween_property(chunk, "global_position:y", floor_y, down_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		
		var alpha_tween = get_tree().create_tween()
		alpha_tween.tween_property(chunk, "modulate:a", 0.0, 0.2).set_delay(fly_time - 0.1)
		alpha_tween.chain().tween_callback(chunk.queue_free)

func _trigger_blood_splash_ui(shooter: Node3D):
	if not shooter: return
	var input_comp = shooter.get_node_or_null("%InputComponent")
	
	if input_comp and not input_comp.is_bot:
		var hud = get_tree().get_first_node_in_group("HUD" + input_comp.suffix)
		if not hud: hud = get_tree().get_first_node_in_group("HUD")
		
		if hud and hud.has_method("splatter_blood_on_lens"):
			hud.splatter_blood_on_lens()

func _get_shared_blood_texture() -> ImageTexture:
	if _shared_blood_tex != null:
		return _shared_blood_tex
		
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var base_color = Color("7d0000f2") 
	var r = 20.0
	
	for x in range(64):
		for y in range(64):
			var dx = (x - 32.0)
			var dy = (y - 32.0)
			if (dx * dx + dy * dy) <= (r * r):
				img.set_pixel(x, y, base_color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				
	_shared_blood_tex = ImageTexture.create_from_image(img)
	return _shared_blood_tex

func _spawn_blood_stain(pos: Vector3):
	var tex = _get_shared_blood_texture()
	
	var ray_start = pos + Vector3(0, 0.2, 0)
	var ray_end = pos + Vector3(0, -5.0, 0)
	var space_state = get_tree().root.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	
	if self is CollisionObject3D:
		query.exclude = [self.get_rid()]
		
	var result = space_state.intersect_ray(query)
	var floor_pos = pos
	if result:
		floor_pos = result.position
		
	for i in range(3):
		var stain = Sprite3D.new()
		stain.texture = tex
		stain.transparent = true
		stain.axis = Vector3.AXIS_Y
		stain.pixel_size = randf_range(0.015, 0.02) * blood_stain_scale
		stain.rotation.y = randf_range(0, TAU)
		stain.render_priority = 1
		
		stain.scale.x = randf_range(0.7, 1.3)
		stain.scale.z = randf_range(0.7, 1.3)
		
		stain.modulate.a = 0.0 
		
		get_tree().current_scene.add_child(stain)
		
		var offset = Vector3(randf_range(-0.4, 0.4), 0.05 + (i * 0.001), randf_range(-0.4, 0.4)) * blood_stain_scale
		stain.global_position = floor_pos + offset
		
		var delay_aparecimento = (i + 1) * 0.1 
		
		var tween = get_tree().create_tween()
		tween.tween_interval(delay_aparecimento)
		tween.tween_property(stain, "modulate:a", 1.0, 0.01)
		tween.tween_interval(5.0)
		tween.tween_property(stain, "modulate:a", 0.0, 1.0)
		tween.chain().tween_callback(stain.queue_free)

	var blood_trigger = Area3D.new()
	blood_trigger.collision_layer = 0 
	blood_trigger.collision_mask = 4294967295 
	
	var col_shape = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	
	shape.radius = 0.8 * blood_stain_scale
	shape.height = 4.0 
	
	col_shape.shape = shape
	col_shape.position.y = 1.5 
	
	blood_trigger.add_child(col_shape)
	get_tree().current_scene.add_child(blood_trigger)
	blood_trigger.global_position = floor_pos
	
	blood_trigger.body_entered.connect(func(body):
		if body is VehicleBody3D:
			var manager = body.find_child("TireBloodManager", true, false)
			if is_instance_valid(manager):
				if manager.has_method("infect_tires"):
					manager.infect_tires()
	)
	
	var kill_timer = get_tree().create_timer(6.5)
	kill_timer.timeout.connect(func():
		if is_instance_valid(blood_trigger):
			blood_trigger.queue_free()
	)
		
func reset(new_global_pos: Vector3):
	is_dead = false
	
	collision_layer = _initial_layer
	collision_mask = _initial_mask
	
	if not is_in_group("pedestrians"):
		add_to_group("pedestrians")
	
	global_position = new_global_pos
	spawn_position = new_global_pos
	velocity = Vector3.ZERO
	
	_is_sleeping = false
	_sleep_timer = randf_range(0.0, 1.5) 
	_skipped_frames = 0
	
	_pick_new_direction()
	
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	
	var anim = find_child("AnimatedSprite3D")
	if anim: anim.play()
