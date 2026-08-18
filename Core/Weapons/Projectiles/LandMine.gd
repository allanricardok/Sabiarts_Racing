extends Area3D
class_name LandMine

# ============================================================================
# GERENCIAMENTO GLOBAL
# ============================================================================
static var active_mines: Array = []
static var active_bot_mines: Array = [] # NOVO: Lista exclusiva para bots desviarem
const MAX_MINES: int = 24

@export_group("Atributos da Mina")
@export var damage: float = 40.0
@export var explosion_radius: float = 12.0
@export var fuse_time: float = 0.2

@export_group("Ciclo de Vida")
@export var auto_explode_time: float = 60.0 

@export_group("Efeitos da Explosão Final")
@export var explosion_color : Color = Color(1.0, 0.5, 0.0)
@export var explosion_size : float = 15.0 
@export var explosion_particles : int = 15
@export var explosion_smoke_size : float = 20.0 
@export var explosion_smoke_color : Color = Color(0.1, 0.1, 0.1, 1.0)
@export var fire_duration : float = 1.0 
@export var shake_type: String = "HardLand"

@onready var red_accent = $RedAccent

var _is_armed: bool = false
var _is_triggered: bool = false
var shooter: Node3D = null

var _blink_timer: float = 0.0 
var _life_timer: float = 0.0  

func _ready():
	active_mines.append(self)
	
	if active_mines.size() > MAX_MINES:
		var oldest_mine = active_mines.pop_front()
		if is_instance_valid(oldest_mine) and not oldest_mine._is_triggered:
			print("[LandMine] Limite de 24 atingido! Detonando a mina mais antiga.")
			oldest_mine._explode()
			
	if is_instance_valid(red_accent):
		red_accent.visible = false
		
	# Registra a mina na lista de desvio caso o dono seja um Bot
	call_deferred("_register_if_bot")
		
	_drop_to_ground()
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	get_tree().create_timer(0.1, false).timeout.connect(_check_initial_arming)

func _register_if_bot():
	if is_instance_valid(shooter):
		var inp = shooter.get_node_or_null("%InputComponent")
		if inp and "is_bot" in inp and inp.is_bot:
			if not active_bot_mines.has(self):
				active_bot_mines.append(self)

func _exit_tree():
	if active_mines.has(self):
		active_mines.erase(self)
	if active_bot_mines.has(self):
		active_bot_mines.erase(self)

func _process(delta):
	if _is_armed and not _is_triggered:
		_life_timer += delta
		if _life_timer >= auto_explode_time:
			_explode()
			return 
			
		if is_instance_valid(red_accent):
			_blink_timer += delta
			if _blink_timer >= 1.1:
				red_accent.visible = false
				_blink_timer = 0.0
			elif _blink_timer >= 1.0:
				red_accent.visible = true

func _drop_to_ground():
	await get_tree().physics_frame
	if not is_inside_tree(): return
	
	var space_state = get_world_3d().direct_space_state
	var ray_start = global_position + Vector3(0, 1.0, 0) 
	var ray_end = global_position + (Vector3.DOWN * 100.0)
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [get_rid()] 
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var distance = global_position.distance_to(result.position)
		var fall_time = clamp(distance / 25.0, 0.1, 0.4) 
		var tween = create_tween()
		tween.tween_property(self, "global_position", result.position, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

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

func _on_body_entered(body: Node3D):
	if not _is_armed or _is_triggered: return
	
	# MANTIDA A TRAVA DE FOGO AMIGO: Caso ele bata na mina por estar muito rápido e não conseguir desviar, ele não explode o colega.
	if is_instance_valid(shooter) and shooter.is_in_group("inimigos") and body.is_in_group("inimigos"):
		return
	
	if body is VehicleBody3D and (body.is_in_group("jogadores") or body.is_in_group("inimigos")):
		_trigger_fuse()

func _trigger_fuse():
	_is_triggered = true
	if is_instance_valid(red_accent): red_accent.visible = true
	get_tree().create_timer(fuse_time, false).timeout.connect(_explode)

func _explode():
	_is_triggered = true 
	
	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(global_position, explosion_color, explosion_size, explosion_particles, 8.0, explosion_smoke_color, explosion_smoke_size, fire_duration)
		
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
					
			if target.has_method("play_camera_shake"): target.play_camera_shake(shake_type)
			if target.has_method("aplicar_perda_de_grip"): target.aplicar_perda_de_grip(3.0)
	
	queue_free()
