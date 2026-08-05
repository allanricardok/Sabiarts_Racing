# FreezingMissile.gd
extends BaseProjectile

@export_group("Física do Míssil de Gelo")
@export var speed = 80.0
@export var steering_force = 8.0 

# ============================================================================
# EFEITOS VISUAIS (TEMA GELO)
# ============================================================================
@export_group("Efeitos da Explosão Final (Gelo)")
@export var explosion_color : Color = Color(0.0, 0.8, 1.0) # Ciano/Azul claro brilhante
@export var explosion_size : float = 15.0 
@export var explosion_particles : int = 15
@export var explosion_smoke_size : float = 20.0 
@export var explosion_smoke_color : Color = Color(0.8, 0.9, 1.0, 1.0) # Fumaça esbranquiçada/azulada
@export var fire_duration : float = 1.0 

@export_group("Efeitos de Lançamento")
@export var launch_smoke_size : float = 4.0
@export var launch_smoke_color : Color = Color(0.8, 0.9, 1.0, 1.0)

var target : Node3D = null

func _ready():
	super._ready()

func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 80.0, incoming_target: Node3D = null):
	# Zera o dano garantindo a característica descrita de não dar dano base
	super.setup(0.0, car_velocity, source_car, propulsion_speed)
	
	target = incoming_target if (is_instance_valid(incoming_target) and not incoming_target.is_queued_for_deletion()) else null
		
	# === EFEITO DE LANÇAMENTO (Fumaça de Gelo) ===
	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(
			global_position, 
			launch_smoke_color, 
			0.0,                
			4,                  
			0.0,                
			launch_smoke_color, 
			launch_smoke_size,
			0.2
		)

func _physics_process(delta):
	var real_delta = delta
	if is_instance_valid(shooter) and shooter.is_in_group("jogadores"):
		real_delta = delta / Engine.time_scale

	if life_timer > 0:
		life_timer -= real_delta
		if life_timer <= 0:
			_deactivate_and_pool()
			return
			
	if hit_done: return 
	
	# --- LÓGICA DE TELEGUIDO (HOMING) ---
	if target and is_instance_valid(target) and not target.is_queued_for_deletion():
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

# ============================================================================
# INTERCEPTADOR DE IMPACTO (Aplica o Gelo antes de repassar para o Pai)
# ============================================================================
func _on_impact(target_node):
	if hit_done: return
	
	if not is_instance_valid(target_node) or target_node.is_queued_for_deletion(): return
	
	var actual_target = target_node
	if target_node is Area3D:
		if is_instance_valid(target_node.owner): actual_target = target_node.owner
		elif is_instance_valid(target_node.get_parent()): actual_target = target_node.get_parent()
		
	if is_instance_valid(shooter):
		if actual_target == shooter or actual_target == shooter.owner: return

	# --- MÁGICA DO GELO ---
	if actual_target.has_method("aplicar_congelamento"):
		actual_target.aplicar_congelamento(2.0)
		
	# Chama o BaseProjectile para finalizar (Screenshake, aplicar Dano, VFX, Pool)
	super._on_impact(target_node)

func _play_impact_vfx():
	# === A GRANDE EXPLOSÃO DO IMPACTO (GELO) ===
	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(
			global_position, 
			explosion_color,         
			explosion_size,          
			explosion_particles,     
			8.0,                     
			explosion_smoke_color,   
			explosion_smoke_size,
			fire_duration            
		)
		
	super._play_impact_vfx()
