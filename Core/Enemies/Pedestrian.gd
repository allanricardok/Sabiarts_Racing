# Pedestrian.gd
extends CharacterBody3D

var is_dead: bool = false

@export_group("Pedestrian Settings")
@export var base_speed: float = 6.0
@export var is_invincible: bool = false
@export var energy_on_death: float = 5.0
## Distância máxima (em metros) para sujar a tela de sangue caso a morte seja por tiro
@export var blood_splash_distance: float = 3.0

@export_group("Efeitos Visuais")
@export var blood_stain_scale: float = 2.0 # Multiplicador de tamanho da mancha de sangue

@export_group("Wander Settings")
@export var max_wander_radius: float = 30.0



var current_direction: Vector3 = Vector3.ZERO
var panic_timer: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO

func _ready():
	add_to_group("pedestrians")

func _physics_process(delta):
	if is_dead: return 
	
	if not is_on_floor():
		velocity.y -= 9.8 * delta
		
	panic_timer -= delta
	if panic_timer <= 0:
		_pick_new_direction()
		
	var move_vel = current_direction * base_speed
	var dodge_vel = Vector3.ZERO
	
	if is_invincible:
		var players = get_tree().get_nodes_in_group("jogadores")
		for p in players:
			if not is_instance_valid(p): continue
			var dist = global_position.distance_to(p.global_position)
			
			if dist < 8.0:
				var away_dir = (global_position - p.global_position).normalized()
				away_dir.y = 0
				dodge_vel = away_dir * 30.0 
				break

	velocity.x = move_vel.x + dodge_vel.x
	velocity.z = move_vel.z + dodge_vel.z
	
	move_and_slide()

func _pick_new_direction():
	var dist_from_spawn = global_position.distance_to(spawn_position)
	
	if dist_from_spawn > max_wander_radius:
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
	
	# Grava a posição imediatamente antes de qualquer coisa acontecer
	var death_pos = global_position 
	is_dead = true
	
	var actual_shooter = attacker
	var is_projectile = false
	
	if attacker and "shooter" in attacker and is_instance_valid(attacker.shooter):
		actual_shooter = attacker.shooter
		is_projectile = true 
	
	# =================================================================
	# CHAMA OS EFEITOS COM AS NOVAS REGRAS E DISTÂNCIA CUSTOMIZÁVEL
	# =================================================================
	var impact_dir = Vector3.ZERO
	if is_instance_valid(actual_shooter):
		if "linear_velocity" in actual_shooter:
			impact_dir = actual_shooter.linear_velocity
		else:
			impact_dir = -actual_shooter.global_transform.basis.z 
			
	_spawn_gore_visuals(death_pos, impact_dir)
	_spawn_blood_stain(death_pos)
		
	var trigger_splash = false
	if not is_projectile:
		trigger_splash = true # Atropelamento direto sempre suja a tela
	else:
		# Valida a distância usando a nova variável exportada
		if is_instance_valid(actual_shooter) and death_pos.distance_to(actual_shooter.global_position) <= blood_splash_distance:
			trigger_splash = true
			
	if trigger_splash:
		_trigger_blood_splash_ui(actual_shooter)
	
	# =================================================================
	
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	
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
			
		var input = actual_shooter.get_node_or_null("%InputComponent")
		var is_bot = (input and "is_bot" in input and input.is_bot)
		
		if not is_bot:
			if "pedestrians_killed" in actual_shooter:
				actual_shooter.pedestrians_killed += 1
				
			if is_instance_valid(MissionManager):
				MissionManager.notify_progress(MissionItem.Type.ROADKILL, 1.0, "")
				
			if is_instance_valid(GameStats) and GameStats.has_method("add_pedestrian_kill"):
				GameStats.add_pedestrian_kill()
				
			if input:
				var hud = get_tree().get_first_node_in_group("HUD" + input.suffix)
				if not hud: hud = get_tree().get_first_node_in_group("HUD")
				if hud and hud.has_method("criar_toast"):
					hud.criar_toast("💥 ROADKILL!", Color.RED)
			
	get_tree().call_group("TutorialUI", "complete_task", "pedestrian")
	
	var parent_spawner = get_parent()
	if parent_spawner and parent_spawner.has_method("recycle_pedestrian"):
		parent_spawner.recycle_pedestrian(self)
	else:
		queue_free()


# ============================================================================
# NOVO GORE VISUAL (0% Física, 100% Tweens e Matemática)
# ============================================================================
func _spawn_gore_visuals(pos: Vector3, impact_dir: Vector3 = Vector3.ZERO):
	var anim_sprite = find_child("AnimatedSprite3D")
	if not anim_sprite or not anim_sprite.sprite_frames: return
	
	var current_tex = anim_sprite.sprite_frames.get_frame_texture(anim_sprite.animation, anim_sprite.frame)
	if not current_tex: return
	
	var tex_w = current_tex.get_width()
	var tex_h = current_tex.get_height()
	
	# Garante que temos uma direção base. Se não passar nada, espalha aleatoriamente.
	var base_dir = impact_dir
	if base_dir.length() < 0.1:
		base_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	else:
		base_dir = base_dir.normalized()
		base_dir.y = 0 # Achata a direção para não voar pro céu se o carro estiver numa rampa
	
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
		
		# Partículas (mantidas iguais)
		var rastro_sangue = CPUParticles3D.new()
		rastro_sangue.amount = 8
		rastro_sangue.lifetime = 0.35
		rastro_sangue.local_coords = false
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.65, 0.0, 0.0) 
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED 
		
		var blood_mesh = BoxMesh.new()
		blood_mesh.size = Vector3(0.12, 0.12, 0.12)
		blood_mesh.surface_set_material(0, mat)
		
		rastro_sangue.mesh = blood_mesh
		rastro_sangue.direction = Vector3(0, -1, 0)
		rastro_sangue.spread = 30.0
		rastro_sangue.initial_velocity_min = 0.5
		rastro_sangue.initial_velocity_max = 1.5
		chunk.add_child(rastro_sangue)
		
		get_tree().current_scene.add_child(chunk)
		
		# REDUZIDO: Posição de origem mais próxima do chão/centro do corpo
		var start_pos = pos + Vector3(randf_range(-0.5, 0.5), randf_range(0.1, 0.5), randf_range(-0.5, 0.5))
		chunk.global_position = start_pos
		
		# === ANIMAÇÃO DE FÍSICA FAKE (TWEEN) CORRIGIDA ===
		
		# Espalha os pedaços em um "cone" de ~60 graus a partir da direção do impacto
		var spread_angle = deg_to_rad(randf_range(-45.0, 45.0))
		var final_dir = base_dir.rotated(Vector3.UP, spread_angle).normalized()
		
		# Voam mais longe para frente agora
		var distance = randf_range(5.0, 12.0) 
		var target_pos = start_pos + (final_dir * distance)
		
		# Lógica de altura: Apenas 1 em cada 5 (20% de chance) voa bem alto
		var peak_y = start_pos.y
		if randf() > 0.8:
			peak_y += randf_range(2.0, 3.5) # Pedaço dramático alto
		else:
			peak_y += randf_range(0.2, 1.2) # Pedaço rasteiro rápido (melhor para câmera do capô)
			
		var floor_y = start_pos.y - randf_range(0.0, 1.0)
		
		# Pedaços que voam baixo caem mais rápido (dá mais impacto)
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
# ============================================================================
# LÓGICA DE COMUNICAÇÃO DO SPLASH NA TELA
# ============================================================================
func _trigger_blood_splash_ui(shooter: Node3D):
	if not shooter: return
	var input = shooter.get_node_or_null("%InputComponent")
	
	if input and not input.is_bot:
		# Encontra o HUD correto do jogador que atropelou
		var hud = get_tree().get_first_node_in_group("HUD" + input.suffix)
		if not hud: hud = get_tree().get_first_node_in_group("HUD")
		
		if hud and hud.has_method("splatter_blood_on_lens"):
			hud.splatter_blood_on_lens()

func _spawn_blood_stain(pos: Vector3):
	# =========================================================
	# 1. TEXTURA (Geramos apenas 1 forma oval para reciclar)
	# =========================================================
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var base_color = Color(0.49, 0.0, 0.0, 0.949) # Sua cor atualizada
	
	var r = randf_range(16.0, 24.0)
	var oval_x = randf_range(0.7, 1.3)
	var oval_y = randf_range(0.7, 1.3)
	
	for x in range(64):
		for y in range(64):
			var dx = (x - 32.0) * oval_x
			var dy = (y - 32.0) * oval_y
			if (dx * dx + dy * dy) <= (r * r):
				img.set_pixel(x, y, base_color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				
	var tex = ImageTexture.create_from_image(img)
	
	# =========================================================
	# 2. RAYCAST (Feito apenas 1x para achar o chão)
	# =========================================================
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
		
	# =========================================================
	# 3. CRIAÇÃO DAS 3 MANCHAS EM SEQUÊNCIA
	# =========================================================
	for i in range(3):
		var stain = Sprite3D.new()
		stain.texture = tex
		stain.transparent = true
		stain.axis = Vector3.AXIS_Y
		stain.pixel_size = randf_range(0.015, 0.02) * blood_stain_scale
		stain.rotation.y = randf_range(0, TAU)
		stain.render_priority = 1
		
		# Começam 100% invisíveis (no momento 0 segundo)
		stain.modulate.a = 0.0 
		
		get_tree().current_scene.add_child(stain)
		
		# Espalha as 3 manchas levemente ao redor do centro do corpo.
		# A altura Y recebe um micro-ajuste (i * 0.001) para uma mancha não bugar
		# entrando dentro da outra (Z-fighting).
		var offset = Vector3(randf_range(-0.4, 0.4), 0.05 + (i * 0.001), randf_range(-0.4, 0.4)) * blood_stain_scale
		stain.global_position = floor_pos + offset
		
		# --- LÓGICA DO TEMPO ---
		# i = 0 -> 0.1s | i = 1 -> 0.2s | i = 2 -> 0.3s
		var delay_aparecimento = (i + 1) * 0.1 
		
		var tween = get_tree().create_tween()
		tween.tween_interval(delay_aparecimento)
		
		# Mancha aparece instantaneamente no seu exato momento
		tween.tween_property(stain, "modulate:a", 1.0, 0.01)
		
		# Fica no chão por 5 segundos
		tween.tween_interval(5.0)
		
		# Apaga suavemente ao longo de 1 segundo
		tween.tween_property(stain, "modulate:a", 0.0, 1.0)
		tween.chain().tween_callback(stain.queue_free)
		
func reset(new_global_pos: Vector3):
	is_dead = false
	
	if not is_in_group("pedestrians"):
		add_to_group("pedestrians")
	
	global_position = new_global_pos
	spawn_position = new_global_pos
	velocity = Vector3.ZERO
	
	_pick_new_direction()
	
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	
	var anim = find_child("AnimatedSprite3D")
	if anim: anim.play()
