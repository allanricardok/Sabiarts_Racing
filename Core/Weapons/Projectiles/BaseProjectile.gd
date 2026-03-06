# BaseProjectile.gd
extends Area3D
class_name BaseProjectile

@export_group("Física de Combate")
## Define o quão forte essa arma empurra o alvo fisicamente ao bater (Independente do dano!)
@export var knockback_force: float = 50.0 

var damage: float = 0.0
var shooter: Node3D = null
var hit_done: bool = false
var velocity: Vector3 = Vector3.ZERO 

# Setup padrão para a maioria dos tiros
func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 50.0):
	damage = dmg_value
	shooter = source_car
	
	# Calcula a direção do tiro
	var propulsion = -global_transform.basis.z * propulsion_speed
	
	# O tiro herda a velocidade do carro somada à velocidade da arma
	velocity = car_velocity + propulsion

func _ready():
	# Conectamos para detectar tanto Corpos Físicos (Carros/Paredes) quanto outras Áreas (Hitboxes)
	if not body_entered.is_connected(_on_impact):
		body_entered.connect(_on_impact)
	if not area_entered.is_connected(_on_impact):
		area_entered.connect(_on_impact)
		
	get_tree().create_timer(4.0).timeout.connect(queue_free)

func _physics_process(delta):
	var real_delta = delta
	
	# Se quem atirou foi o jogador, anulamos o efeito do slow-motion!
	if is_instance_valid(shooter) and shooter.is_in_group("jogadores"):
		real_delta = delta / Engine.time_scale
		
	# Move o projétil usando o delta corrigido
	global_position += velocity * real_delta

func _on_impact(target_node):
	if hit_done: return
	
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
			
	hit_done = true
	
	# Pode remover os logs de debug agora se quiser!
	#print("[ARMA DEBUG] O Tiro básico encostou no objeto: ", actual_target.name)
	
	# --- A GRANDE CORREÇÃO: Usar actual_target em vez de target_node ---
	if actual_target.has_method("take_damage"):
		actual_target.take_damage(damage, self) 
	
	_play_impact_vfx()

func _play_impact_vfx():
	# O Area3D fica cego e para de colidir instantaneamente.
	set_deferred("monitoring", false)
	visible = false
	
	await get_tree().create_timer(0.1).timeout
	queue_free()
	
