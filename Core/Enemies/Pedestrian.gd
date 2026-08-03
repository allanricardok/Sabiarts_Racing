# Pedestrian.gd
extends CharacterBody3D

var is_dead: bool = false

@export_group("Pedestrian Settings")
@export var base_speed: float = 6.0
@export var is_invincible: bool = false
@export var energy_on_death: float = 5.0
## Distância máxima (em metros) para sujar a tela de sangue caso a morte seja por tiro
@export var blood_splash_distance: float = 3.0

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
		is_projectile = true # Confirma que foi morto por um tiro/explosão
	
	# =================================================================
	# CHAMA OS EFEITOS COM AS NOVAS REGRAS E DISTÂNCIA CUSTOMIZÁVEL
	# =================================================================
	_spawn_gore_visuals(death_pos)
	
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
func _spawn_gore_visuals(pos: Vector3):
	var anim_sprite = find_child("AnimatedSprite3D")
	if not anim_sprite or not anim_sprite.sprite_frames: return
	
	var current_tex = anim_sprite.sprite_frames.get_frame_texture(anim_sprite.animation, anim_sprite.frame)
	if not current_tex: return
	
	var tex_w = current_tex.get_width()
	var tex_h = current_tex.get_height()
	
	for i in range(5):
		var chunk = Sprite3D.new()
		chunk.texture = current_tex
		
		# Removi o Billboard! Agora os pedaços giram totalmente em 3D (visual incrível de papel/PS1 voando)
		chunk.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		
		# Reduzido em 20% (Antigo era 2.2, agora é 1.76)
		chunk.pixel_size = anim_sprite.pixel_size * 1.76 
		
		chunk.region_enabled = true
		var chunk_w = tex_w * randf_range(0.3, 0.6)
		var chunk_h = tex_h * randf_range(0.3, 0.6)
		var rx = randf_range(0, tex_w - chunk_w)
		var ry = randf_range(0, tex_h - chunk_h)
		chunk.region_rect = Rect2(rx, ry, chunk_w, chunk_h)
		
		# Partículas
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
		
		# Adiciona diretamente na cena global
		get_tree().current_scene.add_child(chunk)
		
		# Posição de origem bagunçada em volta do impacto
		var start_pos = pos + Vector3(randf_range(-0.5, 0.5), randf_range(0.5, 1.2), randf_range(-0.5, 0.5))
		chunk.global_position = start_pos
		
		# === ANIMAÇÃO DE FÍSICA FAKE (TWEEN) ===
		var dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var distance = randf_range(3.0, 8.0) # O quão longe voam
		var target_pos = start_pos + (dir * distance)
		
		var peak_y = start_pos.y + randf_range(2.0, 5.0) # O quão alto voam
		var floor_y = start_pos.y - randf_range(0.0, 1.0) # Onde caem
		var fly_time = randf_range(0.6, 1.0)
		
		var tween = get_tree().create_tween().set_parallel(true)
		
		# 1. Movimento Horizontal (X e Z)
		tween.tween_property(chunk, "global_position:x", target_pos.x, fly_time)
		tween.tween_property(chunk, "global_position:z", target_pos.z, fly_time)
		
		# 2. Rotação caótica total
		tween.tween_property(chunk, "rotation", Vector3(randf_range(-TAU*3, TAU*3), randf_range(-TAU*3, TAU*3), randf_range(-TAU*3, TAU*3)), fly_time)
		
		# 3. Movimento Vertical (Parábola Perfeita de pulo e queda)
		var y_tween = get_tree().create_tween()
		var up_time = fly_time * 0.4
		var down_time = fly_time * 0.6
		y_tween.tween_property(chunk, "global_position:y", peak_y, up_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		y_tween.tween_property(chunk, "global_position:y", floor_y, down_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		
		# 4. Fade-out e Destruição
		var alpha_tween = get_tree().create_tween()
		alpha_tween.tween_property(chunk, "modulate:a", 0.0, 0.2).set_delay(fly_time - 0.2)
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
