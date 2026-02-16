extends Area3D

@export var speed = 80.0
@export var steering_force = 18.0 
@export var damage = 100

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : Node3D = null
var lifetime = 5.0

var can_explode : bool = false
var time_alive : float = 0.0

func setup(dmg, shooter_vel, incoming_target, source_car):
	damage = dmg
	target = incoming_target
	shooter = source_car
	
	var forward_dir = source_car.global_transform.basis.z 
	velocity = shooter_vel + (forward_dir * 15.0)
	
	look_at(global_position + forward_dir, Vector3.UP)

func _physics_process(delta):
	time_alive += delta
	if time_alive > 0.1: can_explode = true
	
	lifetime -= delta
	if lifetime <= 0: _explode()
	
	if target and is_instance_valid(target):
		var target_pos = target.global_position
		if global_position.distance_to(target_pos) < 2.0:
			_on_target_hit(target) # Fusível de proximidade
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
	if not can_explode or body == shooter: return
	
	if body.has_method("take_damage"):
		# PASSANDO O ATIRADOR PARA O COMBO
		body.take_damage(damage, shooter)
	
	_explode()

func _on_target_hit(body):
	if body.has_method("take_damage"):
		# PASSANDO O ATIRADOR PARA O COMBO
		body.take_damage(damage, shooter)
	_explode()

func _explode():
	queue_free()
