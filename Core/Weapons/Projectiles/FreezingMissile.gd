# FreezingMissile.gd
extends Area3D

@export_group("Física de Combate")
@export var speed = 80.0
@export var steering_force = 8.0 
@export var knockback_force: float = 1500.0

var damage = 0.0 # Míssil de gelo não dá dano base

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : Node3D = null 
var can_explode : bool = false
var time_alive : float = 0.0
var has_exploded : bool = false 

# --- RECEBE A ORDEM DO WEAPON MANAGER ---
var is_shot_backwards: bool = false 

func _ready():
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup(dmg, shooter_vel, source_car, incoming_target = null):
	damage = dmg 
	has_exploded = false 
	
	if is_instance_valid(incoming_target) and not incoming_target.is_queued_for_deletion():
		target = incoming_target
	else:
		target = null 
		
	if is_instance_valid(source_car):
		shooter = source_car
		
		# --- CORREÇÃO DO EIXO ---
		var forward_dir = -global_transform.basis.z.normalized()
		var right_dir = global_transform.basis.x.normalized()
		
		# --- INCLINAÇÃO ZERADA COMO PEDIDO ---
		var tilt_angle = deg_to_rad(0) if not is_shot_backwards else deg_to_rad(0)
		forward_dir = forward_dir.rotated(right_dir, tilt_angle).normalized()
		
		var propulsion = forward_dir * speed
		
		# --- FÍSICA LIMPA ---
		if is_shot_backwards:
			velocity = propulsion
		else:
			velocity = propulsion + shooter_vel
			
		if velocity.length() > 0.1:
			look_at(global_position + velocity.normalized(), Vector3.UP)
		
		var ignore_slowmo = source_car.is_in_group("jogadores")
		get_tree().create_timer(5.0, false, false, ignore_slowmo).timeout.connect(_explode)
	else:
		queue_free()

func _physics_process(delta):
	var real_delta = delta
	if is_instance_valid(shooter) and shooter.is_in_group("jogadores"):
		real_delta = delta / Engine.time_scale

	time_alive += real_delta
	if time_alive > 0.1: can_explode = true
	
	if target and is_instance_valid(target):
		var target_pos = target.global_position
		if global_position.distance_to(target_pos) < 2.0:
			_on_impact(target) 
			return

		var desired_dir = (target_pos - global_position).normalized()
		var steering = (desired_dir * speed - velocity) * steering_force * real_delta
		velocity += steering
	else:
		velocity = velocity.move_toward(velocity.normalized() * speed, real_delta * 100.0)
	
	global_position += velocity * real_delta
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

func _on_body_entered(body):
	if not can_explode: return
	_on_impact(body)

func _on_area_entered(area):
	if not can_explode: return
	_on_impact(area)

func _on_impact(target_node):
	if has_exploded: return
	if not is_instance_valid(target_node): return
	if target_node.is_queued_for_deletion(): return
	
	var actual_target = target_node
	if target_node is Area3D:
		if is_instance_valid(target_node.owner):
			actual_target = target_node.owner
		elif is_instance_valid(target_node.get_parent()):
			actual_target = target_node.get_parent()
		
	if is_instance_valid(shooter):
		if actual_target == shooter or actual_target == shooter.owner: 
			return

	has_exploded = true

	# --- MÁGICA DO GELO ---
	if actual_target.has_method("aplicar_congelamento"):
		actual_target.aplicar_congelamento(2.0)
		
	# --- APLICA O DANO ---
	if actual_target.has_method("take_damage"):
		actual_target.take_damage(damage, self)
		
	_explode()
	
func _explode():
	if not is_inside_tree() or not visible: return
	set_deferred("monitoring", false)
	visible = false
	# TODO: Instanciar efeito de explosão de GELO aqui
	queue_free()
