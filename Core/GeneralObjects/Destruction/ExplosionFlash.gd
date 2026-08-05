extends MeshInstance3D
class_name ExplosionFlash

# ============================================================================
# Bola de fogo achatada, estilo PS1/PS2: um quad sempre de frente pra câmera
# (billboard) que nasce pequeno, "estoura" rápido até o tamanho máximo, e
# desaparece. Nenhuma física real — tudo animado à mão em _process().
# Reciclado por ExplosionManager (pool), nunca criado/destruído em tempo real.
# ============================================================================

var life_timer: float = 0.0
var duration: float = 0.3
var max_scale: float = 1.0
var active: bool = false

var _mat: StandardMaterial3D = null

func launch(pos: Vector3, color: Color, size: float, flash_duration: float) -> void:
	global_position = pos
	duration = flash_duration
	max_scale = size
	life_timer = duration
	active = true
	visible = true
	scale = Vector3.ONE * (size * 0.2)
	set_process(true)
	
	if not _mat:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
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
	
	var t := 1.0 - (life_timer / duration) # 0 -> 1 ao longo da vida
	# Cresce rápido no começo (efeito "pop") e desacelera perto do fim
	var eased := 1.0 - pow(1.0 - t, 3.0)
	scale = Vector3.ONE * lerp(max_scale * 0.2, max_scale, eased)
	_mat.albedo_color.a = clamp(1.0 - t, 0.0, 1.0)

func set_texture(tex: Texture2D) -> void:
	if not _mat:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD 
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		
		# O SEGREDO DO TAMANHO: Impede o billboard de ignorar a escala do Node
		_mat.billboard_keep_scale = true 
		
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material_override = _mat
		
	_mat.albedo_texture = tex
