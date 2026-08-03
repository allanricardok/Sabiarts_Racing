extends MeshInstance3D
class_name TrickBurstStreak

# ============================================================================
# Uma "labareda" individual de uma rajada (Fireball/Shockwave). Reciclada
# por uma pool — nunca criada/destruída em tempo real. A malha (mesh) é
# construída uma vez pelo FX pai e compartilhada entre todas as instâncias;
# aqui só cuidamos de orientar, escalar e apagar (fade) cada labareda.
# ============================================================================

var life_timer: float = 0.0
var duration: float = 0.3
var active: bool = false
var _mat: StandardMaterial3D = null

func launch(origin: Vector3, dir: Vector3, length: float, mesh_res: Mesh, tint: Color, seg_duration: float) -> void:
	duration = seg_duration
	life_timer = duration
	active = true
	visible = true
	set_process(true)
	
	mesh = mesh_res
	
	var y_axis := dir.normalized()
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.01:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	
	global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), origin)
	scale = Vector3(1.0, length, 1.0) # a malha já nasce com comprimento 1.0; só esticamos
	
	if not _mat:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = _mat
	_mat.albedo_color = tint
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
	_mat.albedo_color.a = clampf(life_timer / duration, 0.0, 1.0)
