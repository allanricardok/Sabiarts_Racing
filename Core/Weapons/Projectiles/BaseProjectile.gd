# BaseProjectile.gd
extends RigidBody3D
class_name BaseProjectile

var damage: float = 0.0
var shooter: Node3D = null
var hit_done: bool = false

# Setup padrão para a maioria dos tiros
func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 50.0):
	damage = dmg_value
	shooter = source_car
	
	var propulsion = -global_transform.basis.z * propulsion_speed
	linear_velocity = car_velocity + propulsion
	print("Projectile: Disparado por ", shooter.name, " com dano ", damage)

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_impact)
	get_tree().create_timer(4.0).timeout.connect(queue_free)

func _on_impact(body):
	if hit_done or body == shooter: return
	hit_done = true
	
	# 1. Aplica dano no alvo
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	# 2. Registra pontos no atirador (Combo System)
	if shooter and is_instance_valid(shooter):
		var ground_tricks = shooter.get_node_or_null("%GroundTrickManager")
		if ground_tricks:
			ground_tricks.add_ground_action("HIT_OBJECT")
			print("Projectile: Pontos de impacto enviados para ", shooter.name)
	
	_play_impact_vfx()

func _play_impact_vfx():
	freeze = true
	visible = false
	# Pequeno delay para garantir que sinais de física terminem
	await get_tree().create_timer(0.1).timeout
	queue_free()
