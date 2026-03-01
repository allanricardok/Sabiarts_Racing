# Missile.gd
extends Area3D

@export var speed = 80.0
@export var steering_force = 18.0 
var damage = 1.0

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : Node3D = null # Essencial para os pontos!
var can_explode : bool = false
var time_alive : float = 0.0

func _ready():
	# Conexões automáticas para garantir a detecção
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup(dmg, shooter_vel, source_car, incoming_target = null):
	damage = dmg
	target = incoming_target
	shooter = source_car
	
	var forward_dir = source_car.global_transform.basis.z 
	
	velocity = (forward_dir * speed) + shooter_vel
	
	if velocity.dot(forward_dir) < 5.0:
		velocity = forward_dir * speed

	look_at(global_position + forward_dir, Vector3.UP)

func _physics_process(delta):
	time_alive += delta
	if time_alive > 0.1: can_explode = true
	
	if time_alive > 5.0: _explode() 
	
	if target and is_instance_valid(target):
		var target_pos = target.global_position
		if global_position.distance_to(target_pos) < 2.0:
			_on_impact(target) 
			return

		var desired_dir = (target_pos - global_position).normalized()
		var steering = (desired_dir * speed - velocity) * steering_force * delta
		velocity += steering
	else:
		velocity = velocity.move_toward(velocity.normalized() * speed, delta * 100.0)
	
	global_position += velocity * delta
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

func _on_body_entered(body):
	if not can_explode: return
	_on_impact(body)

func _on_area_entered(area):
	if not can_explode: return
	_on_impact(area)

func _on_impact(target_node):
	# Proteção contra fogo amigo usando a propriedade owner da Hitbox
	var actual_target = target_node
	if target_node is Area3D:
		actual_target = target_node.owner if target_node.owner else target_node.get_parent()
		
	if actual_target == shooter: 
		return

	if target_node.has_method("take_damage"):
		target_node.take_damage(damage, shooter)
	_explode()

func _explode():
	# TODO: Instanciar explosão
	queue_free()
