extends MeshInstance3D
class_name ExplosionSmokePuff

# ============================================================================
# "Bolinha" de fumaça da explosão — um quad billboard que sobe devagar,
# desacelera, cresce um pouco ao longo da vida e desaparece. Movimento
# simulado manualmente (sem física real), igual ao DebrisShard.
# Reciclado por ExplosionManager (pool).
# ============================================================================

var velocity: Vector3 = Vector3.ZERO
var life_timer: float = 0.0
var duration: float = 1.0
var active: bool = false

var _mat: StandardMaterial3D = null

func _ensure_material() -> void:
	if not _mat:
		# ====================================================================
		# OTIMIZAÇÃO: Puxa o material base do cache e duplica para permitir
		# fumaças de cores e texturas diferentes simultaneamente.
		# ====================================================================
		var cached_mat = MaterialCache.get_mat("ExplosionSmokeBase")
		if cached_mat:
			_mat = cached_mat.duplicate()
		else:
			_mat = StandardMaterial3D.new()
			_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX 
			_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			_mat.billboard_keep_scale = true 
			_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			
		material_override = _mat

func launch(pos: Vector3, vel: Vector3, color: Color, size: float, puff_duration: float) -> void:
	global_position = pos
	velocity = vel
	duration = puff_duration
	life_timer = duration
	active = true
	visible = true
	scale = Vector3.ONE * size
	set_process(true)
	
	_ensure_material()
	
	_mat.albedo_color = color
	_mat.albedo_color.a = 0.85

func _process(delta: float) -> void:
	if not active:
		return
	
	life_timer -= delta
	if life_timer <= 0.0:
		active = false
		visible = false
		set_process(false)
		return
	
	velocity *= 0.96 # arrasto simples, desacelera com o tempo
	global_position += velocity * delta
	scale += Vector3.ONE * delta * 0.3 # fumaça "infla" lentamente
	
	var t := life_timer / duration
	_mat.albedo_color.a = clamp(t * 0.85, 0.0, 0.85)

func set_texture(tex: Texture2D) -> void:
	_ensure_material()
	_mat.albedo_texture = tex
