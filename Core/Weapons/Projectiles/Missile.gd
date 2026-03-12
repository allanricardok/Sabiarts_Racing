# Missile.gd
extends Area3D

@export_group("Física de Combate")
@export var speed = 80.0
@export var steering_force = 18.0 
## Define a força do solavanco que o alvo sofre ao ser atingido pelo míssil
@export var knockback_force: float = 1500.0

var damage = 1.0

var velocity = Vector3.ZERO
var target : Node3D = null
var shooter : Node3D = null 
var can_explode : bool = false
var time_alive : float = 0.0

# --- NOVO: A Trava de Segurança ---
var has_exploded : bool = false 

func _ready():
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func setup(dmg, shooter_vel, source_car, incoming_target = null):
	damage = dmg
	target = incoming_target
	shooter = source_car
	has_exploded = false # Garante que nasce destrancado
	
	var forward_dir = source_car.global_transform.basis.z 
	
	velocity = (forward_dir * speed) + shooter_vel
	
	if velocity.dot(forward_dir) < 5.0:
		velocity = forward_dir * speed

	var ignore_slowmo = source_car.is_in_group("jogadores")
	get_tree().create_timer(5.0, false, false, ignore_slowmo).timeout.connect(_explode)

	look_at(global_position + forward_dir, Vector3.UP)

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
	# --- CADEADO ATIVADO: Ignora impactos fantasmas ---
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

	# TRANCA A PORTA PARA OS PRÓXIMOS HITS DO MESMO FRAME!
	has_exploded = true

	if actual_target.has_method("take_damage"):
		actual_target.take_damage(damage, self)
		
	_explode()

func _explode():
	if not is_inside_tree() or not visible: return
	set_deferred("monitoring", false)
	visible = false
	# TODO: Instanciar efeito de explosão aqui
	queue_free()
