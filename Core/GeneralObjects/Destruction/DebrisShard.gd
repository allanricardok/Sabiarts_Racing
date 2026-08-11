extends MeshInstance3D
class_name DebrisShard

var velocity: Vector3 = Vector3.ZERO
var spin: Vector3 = Vector3.ZERO
var life_timer: float = 0.0
var fade_time: float = 0.4
var gravity: float = 15 
var active: bool = false

func launch(spawn_pos: Vector3, vel: Vector3, spin_speed: Vector3, lifetime: float, source_material: Material, shape_mesh: Mesh, size: float) -> void:
	global_position = spawn_pos
	rotation = Vector3(randf_range(0, TAU), randf_range(0, TAU), randf_range(0, TAU))
	
	mesh = shape_mesh
	scale = Vector3.ONE * size
	
	velocity = vel
	spin = spin_speed
	life_timer = lifetime
	fade_time = min(0.4, lifetime * 0.35)
	active = true
	visible = true
	set_process(true)
	
	# OTIMIZAÇÃO GIGANTE: Usamos o material direto do Manager, sem NENHUM duplicate()
	material_override = source_material
	
	# Zera a transparência da instância (0.0 = visível, 1.0 = totalmente invisível)
	transparency = 0.0 

func _process(delta: float) -> void:
	if not active: return
	
	life_timer -= delta
	if life_timer <= 0.0:
		_deactivate()
		return
	
	velocity.y -= gravity * delta
	global_position += velocity * delta
	
	rotate_x(spin.x * delta)
	rotate_y(spin.y * delta)
	rotate_z(spin.z * delta)
	
	if life_timer < fade_time:
		# Faz o fade out usando a propriedade nativa da instância, preservando a memória!
		transparency = 1.0 - clamp(life_timer / fade_time, 0.0, 1.0)

func _deactivate() -> void:
	active = false
	visible = false
	set_process(false)
	material_override = null
