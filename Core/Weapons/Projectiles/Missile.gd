# Missile.gd
extends Area3D

@export var speed = 80.0
@export var steering_force = 18.0 
var damage = 100.0

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : Node3D = null # Essencial para os pontos!
var can_explode : bool = false
var time_alive : float = 0.0

func setup(dmg, shooter_vel, source_car, incoming_target = null):
	damage = dmg
	target = incoming_target
	shooter = source_car
	
	var forward_dir = source_car.global_transform.basis.z 
	
	# CORREÇÃO: Em vez de um empurrão de 15.0, usamos a 'speed' total do míssil.
	# Somamos shooter_vel apenas para herdar a inércia lateral/vertical, 
	# mas garantimos que a força frontal seja absoluta.
	velocity = (forward_dir * speed) + shooter_vel
	
	# Se ainda assim a velocidade resultante apontar para trás (devido a uma ré extrema),
	# forçamos ela a ser pelo menos a direção frontal.
	if velocity.dot(forward_dir) < 5.0:
		velocity = forward_dir * speed

	look_at(global_position + forward_dir, Vector3.UP)

func _physics_process(delta):
	time_alive += delta
	if time_alive > 0.1: can_explode = true
	
	if time_alive > 5.0: _explode() # Substitui o lifetime antigo
	
	if target and is_instance_valid(target):
		var target_pos = target.global_position
		if global_position.distance_to(target_pos) < 2.0:
			_on_impact(target) # Unificamos o nome da função
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
	_on_impact(body)

func _on_impact(body):
	if body.has_method("take_damage"):
		# CORREÇÃO CRÍTICA: Passando o shooter para o GroundTrickManager
		body.take_damage(damage, shooter)
	_explode()

func _explode():
	# TODO: Instanciar explosão
	queue_free()
