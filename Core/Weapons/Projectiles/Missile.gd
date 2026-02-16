# Missile.gd
extends Area3D

@export var speed = 80.0
@export var steering_force = 18.0 
var damage = 100.0

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : Node3D = null 
var can_explode : bool = false
var time_alive : float = 0.0

func setup(dmg, shooter_vel, source_car, incoming_target = null):
	damage = dmg
	target = incoming_target
	shooter = source_car
	
	# A frente do modelo é o Z positivo conforme discutido anteriormente
	var forward_dir = source_car.global_transform.basis.z 
	velocity = shooter_vel + (forward_dir * 15.0)
	
	if velocity.length() > 0.1:
		look_at(global_position + forward_dir, Vector3.UP)
	print("Missile: Localizado alvo: ", target.name if target else "Nenhum")

func _physics_process(delta):
	time_alive += delta
	if time_alive > 0.1: can_explode = true
	
	if time_alive > 5.0: 
		_explode()
		return
	
	if target and is_instance_valid(target):
		var target_pos = target.global_position
		
		# Proximidade para explosão via código (missile homing)
		if global_position.distance_to(target_pos) < 2.0:
			_on_impact(target)
			return

		var desired_dir = (target_pos - global_position).normalized()
		var steering = (desired_dir * speed - velocity) * steering_force * delta
		velocity += steering
	else:
		# Se perder o alvo, segue reto
		velocity = velocity.move_toward(velocity.normalized() * speed, delta * 100.0)
	
	global_position += velocity * delta
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

func _on_body_entered(body):
	if not can_explode or body == shooter: return
	_on_impact(body)

func _on_impact(body):
	# 1. Dano no alvo
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	# 2. Sistema de Pontos (Combo)
	if shooter and is_instance_valid(shooter):
		var ground_tricks = shooter.get_node_or_null("%GroundTrickManager")
		if ground_tricks:
			# Se o míssil destrói coisas grandes, você pode mudar para "DESTROY_OBJECT" se quiser
			ground_tricks.add_ground_action("HIT_OBJECT")
			print("Missile: Impacto registrado no combo de ", shooter.name)
			
	_explode()

func _explode():
	# TODO: Instanciar efeito de explosão aqui
	queue_free()
