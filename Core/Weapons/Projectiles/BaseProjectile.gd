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

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_impact)
	get_tree().create_timer(4.0).timeout.connect(queue_free)

func _on_impact(target_node):
	if hit_done: return
	
	# --- MUDANÇA SÊNIOR: Identifica de quem é a Hitbox para evitar fogo amigo ---
	var actual_target = target_node
	if target_node is Area3D:
		actual_target = target_node.owner if target_node.owner else target_node.get_parent()
		
	# Se a bala colidiu com o carro que atirou (ou sua hitbox), ignora e continua voando
	if actual_target == shooter: 
		return
		
	hit_done = true
	
	if target_node.has_method("take_damage"):
		target_node.take_damage(damage, shooter) # Passa o shooter para o GroundTrickManager
	
	_play_impact_vfx()

func _play_impact_vfx():
	freeze = true
	visible = false
	await get_tree().create_timer(0.1).timeout
	queue_free()
