extends MeshInstance3D
class_name EnergyRing

# ============================================================================
# Um anel/arco de energia. Diferente do sistema de rastro anterior, este NÃO
# reage à velocidade real de rotação do carro — ele gira sozinho, numa
# velocidade constante configurável, dando a sensação de "energia viva"
# ajudando o veículo, e não de um efeito passivo que só reage ao movimento.
#
# A malha (um arco, não um círculo fechado) é montada uma única vez pelo
# TrickEnergyRingsFX e reaproveitada — aqui só cuidamos da rotação e do fade.
# ============================================================================

var spin_speed_deg: float = 480.0
var _mat: StandardMaterial3D = null

func setup(mesh_res: Mesh, color: Color) -> void:
	mesh = mesh_res
	
	if not _mat:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Blend aditivo: onde os dois anéis se cruzam, a luz "soma" e fica
		# mais brilhante — é o que dá aquela cara neon/energia das imagens.
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = _mat
	
	_mat.albedo_color = color

## alpha multiplica o degradê já embutido nos vértices do arco — usado pelo
## FX pai pra fazer fade-in/fade-out suave ao começar/terminar uma manobra.
func set_fade(alpha: float) -> void:
	if _mat:
		_mat.albedo_color.a = alpha

func _process(delta: float) -> void:
	if not visible:
		return
	rotate_object_local(Vector3.BACK, deg_to_rad(spin_speed_deg) * delta)
