# BaseProjectile.gd
extends Area3D
class_name BaseProjectile

@export_group("Física de Combate")
@export var knockback_force: float = 50.0 

var damage: float = 0.0
var shooter: Node3D = null
var hit_done: bool = false
var velocity: Vector3 = Vector3.ZERO 

# Variáveis do Pool
var pool_key: String = ""
var life_timer: float = 0.0

# Setup é chamado toda vez que a bala "nasce" (ou renasce do Pool)
func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 50.0):
	damage = dmg_value
	shooter = source_car
	
	var propulsion = -global_transform.basis.z * propulsion_speed
	velocity = car_velocity + propulsion
	
	# --- RESET DO POOL (ACORDA A BALA) ---
	hit_done = false
	visible = true
	set_deferred("monitoring", true)
	life_timer = 4.0 # 4 Segundos de vida até voltar pro pool

func _ready():
	if not body_entered.is_connected(_on_impact):
		body_entered.connect(_on_impact)
	if not area_entered.is_connected(_on_impact):
		area_entered.connect(_on_impact)

func _physics_process(delta):
	var real_delta = delta
	if is_instance_valid(shooter) and shooter.is_in_group("jogadores"):
		real_delta = delta / Engine.time_scale
		
	# --- CRONÔMETRO SEM LIXO DE MEMÓRIA ---
	if life_timer > 0:
		life_timer -= real_delta
		if life_timer <= 0:
			_deactivate_and_pool()
			return
			
	if hit_done: return # Congela o movimento se bateu

	global_position += velocity * real_delta

func _on_impact(target_node):
	if hit_done: return
	
	if not is_instance_valid(target_node) or target_node.is_queued_for_deletion(): return
	
	var actual_target = target_node
	if target_node is Area3D:
		if is_instance_valid(target_node.owner): actual_target = target_node.owner
		elif is_instance_valid(target_node.get_parent()): actual_target = target_node.get_parent()
		
	if is_instance_valid(shooter):
		if actual_target == shooter or actual_target == shooter.owner: return
			
	hit_done = true
	
	if actual_target.has_method("take_damage"):
		actual_target.take_damage(damage, self) 
	
	_play_impact_vfx()

func _play_impact_vfx():
	set_deferred("monitoring", false)
	visible = false
	velocity = Vector3.ZERO # Freia a bala no ar
	
	# Reaproveita o cronômetro para dar um micro delay antes de guardar a bala
	# (Útil caso a bala tenha um rastro/trail que precisa terminar de sumir)
	life_timer = 0.1 

func _deactivate_and_pool():
	set_deferred("monitoring", false)
	visible = false
	velocity = Vector3.ZERO
	
	# Devolve a bala pro almoxarifado em vez de jogar no lixo!
	if ProjectilePool.has_method("return_projectile"):
		ProjectilePool.return_projectile(self)
	else:
		queue_free()
