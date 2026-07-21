extends MeshInstance3D
class_name DebrisShard

# ============================================================================
# Fragmento de destruição estilo PS1/PS2.
# Não usa física real (RigidBody3D) — o movimento é simulado manualmente em
# _process(), o que é muito mais barato pra PCs fracos. O fragmento nunca
# colide com nada: ele desaparece (fade out) antes que isso faça diferença
# visualmente.
#
# Este nó é reciclado por DebrisManager (object pooling) — ele nunca é
# criado/destruído em tempo real durante o jogo, só "ligado" e "desligado".
# ============================================================================

var velocity: Vector3 = Vector3.ZERO
var spin: Vector3 = Vector3.ZERO
var life_timer: float = 0.0
var fade_time: float = 0.4
var gravity: float = 11.76 # 9.8 + 20%
var active: bool = false

var _mat: StandardMaterial3D = null

func launch(spawn_pos: Vector3, vel: Vector3, spin_speed: Vector3, lifetime: float, source_material: Material, shape_mesh: Mesh, size: float) -> void:
	global_position = spawn_pos
	rotation = Vector3(randf_range(0, TAU), randf_range(0, TAU), randf_range(0, TAU))
	
	# NOVO: cada fragmento recebe uma forma (triângulo/quadrilátero irregular)
	# e um tamanho sorteados pelo DebrisManager — a malha em si já vem pronta,
	# então isso não custa nada em tempo real.
	mesh = shape_mesh
	scale = Vector3.ONE * size
	
	velocity = vel
	spin = spin_speed
	life_timer = lifetime
	fade_time = min(0.4, lifetime * 0.35)
	active = true
	visible = true
	set_process(true)
	
	# Cada fragmento recebe sua própria cópia do material (senão o fade de um
	# fragmento afetaria todos os outros que compartilham o mesmo material).
	if source_material:
		_mat = source_material.duplicate() as StandardMaterial3D
	if not _mat:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color.WHITE
	
	# Truque de visual "PS1": desliga sombreamento suave, deixa mais cru/flat.
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color.a = 1.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED # vira igual de frente e de trás
	
	material_override = _mat

func _process(delta: float) -> void:
	if not active:
		return
	
	life_timer -= delta
	if life_timer <= 0.0:
		_deactivate()
		return
	
	# "Física" falsa: gravidade simples integrada manualmente.
	velocity.y -= gravity * delta
	global_position += velocity * delta
	
	rotate_x(spin.x * delta)
	rotate_y(spin.y * delta)
	rotate_z(spin.z * delta)
	
	if life_timer < fade_time and _mat:
		_mat.albedo_color.a = clamp(life_timer / fade_time, 0.0, 1.0)

func _deactivate() -> void:
	active = false
	visible = false
	set_process(false)
	material_override = null
