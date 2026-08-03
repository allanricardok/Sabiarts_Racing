extends Node
class_name DrunkEffect

# Variáveis que serão preenchidas pelo coletável
var time_left: float = 10.0
var max_intensity: float = 1.0
var fade_time: float = 2.0
var camera: Camera3D

# Referências internas
var canvas: CanvasLayer
var material: ShaderMaterial
var intensity: float = 0.0
var is_fading_out: bool = false

func _ready():
	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
	uniform float intensity : hint_range(0.0, 5.0) = 1.0;
	
	void fragment() {
		vec2 uv = SCREEN_UV;
		
		// 1. ONDULAÇÃO (Sway / Tontura)
		uv.x += sin(TIME * 2.0 + uv.y * 6.0) * 0.03 * intensity;
		uv.y += cos(TIME * 1.5 + uv.x * 6.0) * 0.03 * intensity;
		
		vec4 col = texture(screen_texture, uv);
		
		// 2. ABERRAÇÃO CROMÁTICA (Visão dupla / Cores separadas)
		col.r = texture(screen_texture, uv + vec2(0.015 * intensity, 0.0)).r;
		col.b = texture(screen_texture, uv - vec2(0.015 * intensity, 0.0)).b;
		
		// 3. BLUR CASEIRO (Desfoque)
		float b = 0.003 * intensity;
		vec4 blur = texture(screen_texture, uv + vec2(b, b)) +
					texture(screen_texture, uv + vec2(-b, -b)) +
					texture(screen_texture, uv + vec2(b, -b)) +
					texture(screen_texture, uv + vec2(-b, b));
					
		COLOR = mix(col, blur / 4.0, clamp(intensity * 0.85, 0.0, 1.0));
	}
	"""
	material = ShaderMaterial.new()
	material.shader = shader
	
	canvas = CanvasLayer.new()
	canvas.layer = 90 
	
	var rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.material = material
	canvas.add_child(rect)
	
	add_child(canvas)
	
	# =========================================================================
	# FADE-IN SUAVE
	# =========================================================================
	var t = create_tween()
	t.tween_property(self, "intensity", max_intensity, fade_time).set_ease(Tween.EASE_OUT)

func _process(delta):
	# Gerencia o tempo de duração da bebida apenas se não estiver apagando
	if not is_fading_out:
		time_left -= delta
		if time_left <= 0:
			_end_effect()
			
	# Atualiza o visual continuamente, mesmo durante o fade-out!
	if is_instance_valid(material):
		material.set_shader_parameter("intensity", intensity)
		
	if is_instance_valid(camera):
		var time = Time.get_ticks_msec() / 1000.0
		camera.h_offset = sin(time * 2.5) * 0.4 * intensity
		camera.v_offset = cos(time * 1.8) * 0.3 * intensity

func _end_effect():
	is_fading_out = true
	
	# =========================================================================
	# FADE-OUT SUAVE
	# Reduz a intensidade até zero e, só depois que acabar, deleta o nó!
	# =========================================================================
	var t = create_tween()
	t.tween_property(self, "intensity", 0.0, fade_time).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(self.queue_free)
