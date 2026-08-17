extends Area3D
class_name LandMine

@export_group("Atributos da Mina")
@export var damage: float = 40.0
@export var explosion_radius: float = 12.0
@export var fuse_time: float = 0.2

# ============================================================================
# EFEITOS VISUAIS
# ============================================================================
@export_group("Efeitos da Explosão Final")
@export var explosion_color : Color = Color(1.0, 0.5, 0.0)
@export var explosion_size : float = 15.0 
@export var explosion_particles : int = 15
@export var explosion_smoke_size : float = 20.0 
@export var explosion_smoke_color : Color = Color(0.1, 0.1, 0.1, 1.0)
@export var fire_duration : float = 1.0 
@export var shake_type: String = "HardLand"

# --- REFERÊNCIA AO NOVO MESH ---
@onready var red_accent = $RedAccent

var _is_armed: bool = false
var _is_triggered: bool = false
var shooter: Node3D = null

var _blink_timer: float = 0.0 # Cronômetro para a luz piscar

func _ready():
	# Garante que a luz nasça apagada
	if is_instance_valid(red_accent):
		red_accent.visible = false
		
	_snap_to_ground()
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	get_tree().create_timer(0.1, false).timeout.connect(_check_initial_arming)

# ====================================================================
# LÓGICA DO PISCA-PISCA
# ====================================================================
func _process(delta):
	if _is_armed and not _is_triggered and is_instance_valid(red_accent):
		_blink_timer += delta
		
		# Aos 1.0s, acende. Aos 1.1s (duração de 0.1s), apaga e zera o ciclo.
		if _blink_timer >= 1.1:
			red_accent.visible = false
			_blink_timer = 0.0
		elif _blink_timer >= 1.0:
			red_accent.visible = true

func _snap_to_ground():
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + (Vector3.DOWN * 50.0))
	query.exclude = [get_rid()] 
	
	var result = space_state.intersect_ray(query)
	if result:
		global_position = result.position

func _check_initial_arming():
	if not is_instance_valid(shooter):
		_is_armed = true
		return
		
	var overlapping = get_overlapping_bodies()
	if not overlapping.has(shooter):
		_is_armed = true

func _on_body_exited(body: Node3D):
	if not _is_armed and body == shooter:
		_is_armed = true
		print("[LandMine] Jogador saiu da área. Mina armada e pronta!")

func _on_body_entered(body: Node3D):
	if not _is_armed or _is_triggered: return
	
	if body is VehicleBody3D and (body.is_in_group("jogadores") or body.is_in_group("inimigos")):
		_trigger_fuse()

func _trigger_fuse():
	_is_triggered = true
	
	# Trava a luz como acesa no momento pré-explosão para dar aquele charme!
	if is_instance_valid(red_accent):
		red_accent.visible = true
		
	print("[LandMine] Inimigo detectado! Detonando...")
	get_tree().create_timer(fuse_time, false).timeout.connect(_explode)

func _explode():
	# 1. VISUAL DA EXPLOSÃO
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
		
	# 2. CALCULA DANO FÍSICO E TREMOR DE TELA
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = global_transform
	
	var hits = space_state.intersect_shape(query)
	for hit in hits:
		var target = hit.collider
		if is_instance_valid(target):
			
			if target.has_method("take_damage"):
				var dist = global_position.distance_to(target.global_position)
				var damage_percent = 1.0 - (dist / explosion_radius)
				var final_damage = max(damage * damage_percent, 10.0)
				
				target.take_damage(final_damage, shooter)
				
				if target is RigidBody3D or target is VehicleBody3D:
					var push_dir = (target.global_position - global_position).normalized()
					push_dir.y = 1.5 
					target.apply_central_impulse(push_dir * (final_damage * 100))
					
			if target.has_method("play_camera_shake"):
				target.play_camera_shake(shake_type)
				
			# ACIONA O EFEITO DE PNEU FURADO
			if target.has_method("aplicar_perda_de_grip"):
				target.aplicar_perda_de_grip(3.0)
	
	# 3. Destrói a mina fisicamente
	queue_free()
