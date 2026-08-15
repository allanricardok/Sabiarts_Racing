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

func launch(origin: Vector3, dir: Vector3, length: float, mesh_res: Mesh, tint: Color, seg_duration: float) -> void:
	duration = seg_duration
	life_timer = duration
	active = true
	visible = true
	set_process(true)
	
	# A malha vinda do pai JÁ POSSUI o material do MaterialCache!
	mesh = mesh_res
	
	var y_axis := dir.normalized()
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.01:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	
	global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), origin)
	scale = Vector3(1.0, length, 1.0) 
	
	# Restaura a opacidade da instância (0.0 = totalmente opaco/visível)
	transparency = 0.0

func _process(delta: float) -> void:
	if not active:
		return
		
	life_timer -= delta
	if life_timer <= 0.0:
		active = false
		visible = false
		set_process(false)
		return
		
	# ====================================================================
	# OTIMIZAÇÃO MAXIMA: Transparência por Instância!
	# Em vez de alterar o alpha do material (o que quebraria o compartilhamento), 
	# nós alteramos a propriedade 'transparency' nativa do Node3D.
	# ====================================================================
	var alpha = clampf(life_timer / duration, 0.0, 1.0)
	transparency = 1.0 - alpha
