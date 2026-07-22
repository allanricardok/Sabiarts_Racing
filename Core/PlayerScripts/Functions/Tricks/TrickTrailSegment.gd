extends MeshInstance3D
class_name TrickTrailSegment

# ============================================================================
# Um segmento de "faixa luminosa" do rastro de manobra. Representa o
# deslocamento de um ponto do anel entre o frame anterior e o atual — quanto
# mais rápido o carro gira, maior a distância percorrida por frame, e
# portanto maior (mais esticado) esse segmento fica. O comprimento do quad
# É a velocidade da manobra, sem precisar calcular nada à parte.
#
# Reciclado por TrickTrailFX (pool) — nunca criado/destruído em tempo real.
# ============================================================================

var life_timer: float = 0.0
var duration: float = 0.18
var active: bool = false

var _mat: StandardMaterial3D = null

func launch(from_pos: Vector3, to_pos: Vector3, width: float, color: Color, seg_duration: float) -> void:
	duration = seg_duration
	life_timer = duration
	active = true
	visible = true
	set_process(true)
	
	var dir := to_pos - from_pos
	var length := dir.length()
	
	if length < 0.001:
		# Carro quase parado nesse instante — desenha um segmento mínimo
		# em vez de tentar orientar uma direção de comprimento zero.
		length = 0.02
		dir = Vector3.UP
	
	var y_axis := dir.normalized()
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.01:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	
	var mid := (from_pos + to_pos) * 0.5
	global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), mid)
	scale = Vector3(width, length, 1.0)
	
	if not _mat:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = _mat
	
	_mat.albedo_color = color
	_mat.albedo_color.a = 1.0

func _process(delta: float) -> void:
	if not active:
		return
	
	life_timer -= delta
	if life_timer <= 0.0:
		active = false
		visible = false
		set_process(false)
		return
	
	_mat.albedo_color.a = clamp(life_timer / duration, 0.0, 1.0)
