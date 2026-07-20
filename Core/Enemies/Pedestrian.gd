# Pedestrian.gd
extends CharacterBody3D

var is_dead: bool = false

@export_group("Pedestrian Settings")
@export var base_speed: float = 6.0
@export var is_invincible: bool = false
@export var energy_on_death: float = 5.0

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
	
	is_dead = true
	
	# Desliga a mente do pedestre para economizar CPU
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false
	
	if is_in_group("pedestrians"):
		remove_from_group("pedestrians")
		
	velocity = Vector3.ZERO
	# Joga o corpo lá para baixo (O Cemitério). Sem mexer na colisão!
	global_position = Vector3(0, -1000, 0) 
	
	if attacker is VehicleBody3D or attacker is RigidBody3D:
		attacker.linear_velocity *= 0.88 
	
	var actual_shooter = attacker
	if attacker and "shooter" in attacker and is_instance_valid(attacker.shooter):
		actual_shooter = attacker.shooter
		
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
