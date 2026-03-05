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
	
	# --- CORREÇÃO: BLINDAGEM DUPLA (LIMBO DO QUEUE_FREE) ---
	# 1. Verifica se a memória existe
	if not is_instance_valid(target_node): return
	# 2. Verifica se ele já está com o "pé na cova" (esperando o fim do frame para sumir)
	if target_node.is_queued_for_deletion(): return
	
	# Identifica de quem é a Hitbox para evitar fogo amigo
	var actual_target = target_node
	if target_node is Area3D:
		# Camada extra de segurança antes de acessar a hierarquia
		if is_instance_valid(target_node.owner):
			actual_target = target_node.owner
		elif is_instance_valid(target_node.get_parent()):
			actual_target = target_node.get_parent()
		
	# Previne atirar em si mesmo
	if actual_target == shooter or actual_target == shooter.owner: 
		return
		
	hit_done = true
	
	# A própria bala se apresenta como o 'source' do impacto!
	if target_node.has_method("take_damage"):
		target_node.take_damage(damage, self) 
	
	_play_impact_vfx()
	
	_play_impact_vfx()

func _play_impact_vfx():
	# O Area3D fica cego e para de colidir instantaneamente.
	set_deferred("monitoring", false)
	visible = false
	
	await get_tree().create_timer(0.1).timeout
	queue_free()
	
