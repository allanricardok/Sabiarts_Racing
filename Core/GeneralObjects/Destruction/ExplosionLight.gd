extends OmniLight3D
class_name ExplosionLight

# ============================================================================
# Luz de flash da explosão. Acende no máximo instantaneamente e decai até
# zero ao longo de duration — dá o efeito de "a explosão iluminou a cena
# por um instante" sem precisar de nenhum sistema de iluminação avançado.
# Reciclada por ExplosionManager (pool).
# ============================================================================

var life_timer: float = 0.0
var duration: float = 0.3
var max_energy: float = 8.0
var active: bool = false

func launch(pos: Vector3, color: Color, energy: float, light_duration: float, light_range: float) -> void:
	global_position = pos
	light_color = color
	max_energy = energy
	duration = light_duration
	omni_range = light_range
	life_timer = duration
	active = true
	visible = true
	light_energy = max_energy
	set_process(true)

func _process(delta: float) -> void:
	if not active:
		return
	
	life_timer -= delta
	if life_timer <= 0.0:
		active = false
		visible = false
		light_energy = 0.0
		set_process(false)
		return
	
	light_energy = max_energy * (life_timer / duration)
