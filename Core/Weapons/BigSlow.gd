extends RigidBody3D

var damage = 25.0
var hit_done = false

func _ready():
	# Velocidade inicial (Big Slow costuma ser pesada e lenta)
	linear_velocity = -global_transform.basis.z * 40.0 
	body_entered.connect(_on_impact)

func setup(dmg):
	damage = dmg

func _on_impact(body):
	if hit_done or body is VehicleBody3D: return
	hit_done = true
	
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	# Para, espera 0.1s e some
	freeze = true
	linear_velocity = Vector3.ZERO
	await get_tree().create_timer(0.1).timeout
	queue_free()
