extends Control

@onready var vignette = $Vignette
@onready var title = $Title
@onready var multiplier_label = $Multiplier
@onready var bar = $Bar
@onready var seconds_label = $Seconds
@onready var lightning_layer: RageLightningLayer = $LightningLayer

# Cores dos Tiers (texto/UI)
const COLOR_T0 = Color.WHITE
const COLOR_T1 = Color.YELLOW
const COLOR_T2 = Color(1.0, 0.5, 0.0) # Laranja
const COLOR_T3 = Color(1.0, 0.2, 0.2)

# Shader do fundo: apenas a vinheta azulada suave, sem raios geométricos
# (os raios agora são desenhados pela RageLightningLayer, fractais e reais).
var shader_code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aberration_strength : hint_range(0.0, 0.05) = 0.0;
uniform float saturation_boost : hint_range(0.0, 2.0) = 0.0;
uniform float warp_strength : hint_range(0.0, 0.02) = 0.0;
uniform float pulse_speed : hint_range(0.0, 40.0) = 10.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 2.0;
	vec2 dir = normalize(uv + 0.0001);

	float edge_mask = smoothstep(0.85 - (intensity * 0.25), 1.15, dist);

	// Pulso bem mais agressivo: amplitude maior + soma de duas frequências
	// pra parecer instabilidade elétrica errática, não só um seno liso
	float pulse = 1.0 + 0.35 * sin(TIME * pulse_speed) + 0.15 * sin(TIME * pulse_speed * 2.7);

	float angle = atan(uv.y, uv.x);
	float warp_wave = sin(angle * 6.0 + TIME * 2.0) * warp_strength * edge_mask;
	vec2 warped_dir = dir + vec2(-dir.y, dir.x) * warp_wave;

	float shift = aberration_strength * edge_mask * pulse;
	vec2 screen_uv = SCREEN_UV;

	float r = texture(SCREEN_TEXTURE, screen_uv + warped_dir * shift * 1.0).r;
	float g = texture(SCREEN_TEXTURE, screen_uv - warped_dir * shift * 0.4).g;
	float b = texture(SCREEN_TEXTURE, screen_uv - warped_dir * shift * 1.4).b;

	vec3 aberrated = vec3(r, g, b);

	float luma = dot(aberrated, vec3(0.299, 0.587, 0.114));
	vec3 saturated = mix(vec3(luma), aberrated, 1.0 + saturation_boost * edge_mask);
	saturated = clamp(saturated, 0.0, 1.0);

	// Escurece a borda proporcionalmente à intensidade do rage
	saturated *= (1.0 - edge_mask * intensity * 0.35);

	vec3 tint = vec3(0.03, 0.09, 0.28); // tom mais escuro que antes
	vec3 final_color = mix(saturated, tint, edge_mask * intensity * 0.55);

	COLOR = vec4(final_color, edge_mask * intensity * 0.9);
}
"""

func _ready():
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = shader_code
	mat.shader = shader
	vignette.material = mat
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if bar:
		bar.max_value = 100.0
		bar.value = 0.0

	if seconds_label:
		seconds_label.text = ""

func _on_rage_updated(rage_value: float, tier: int, t3_timer: float):
	multiplier_label.text = str(tier) + "X"

	var target_color = COLOR_T0
	var vignette_intensity = 0.0
	var aberration = 0.0
	var saturation = 0.0
	var warp = 0.0
	var pulse_spd = 10.0

	match tier:
		0:
			target_color = COLOR_T0
			vignette_intensity = 0.0
			aberration = 0.0
			saturation = 0.0
			warp = 0.0
			if bar: bar.value = rage_value
			if seconds_label: seconds_label.text = ""
		1:
			target_color = COLOR_T1
			vignette_intensity = 0.45
			aberration = 0.015
			saturation = 1.05
			warp = 0.0108
			pulse_spd = 16.0
			if bar: bar.value = rage_value - 100.0
			if seconds_label: seconds_label.text = ""
		2:
			target_color = COLOR_T2
			vignette_intensity = 0.7
			aberration = 0.022
			saturation = 1.56
			warp = 0.01755
			pulse_spd = 26.0
			if bar: bar.value = rage_value - 200.0
			if seconds_label: seconds_label.text = ""
		3:
			target_color = COLOR_T3
			vignette_intensity = 1.0
			aberration = 0.034
			saturation = 1.7
			warp = 0.0195
			pulse_spd = 40.0
			if bar: bar.value = 100.0
			if seconds_label: seconds_label.text = "%.1fsec" % t3_timer

	multiplier_label.add_theme_color_override("font_color", COLOR_T0)

	if bar:
		bar.modulate = target_color

	if vignette.material:
		vignette.material.set_shader_parameter("intensity", vignette_intensity)
		vignette.material.set_shader_parameter("aberration_strength", aberration)
		vignette.material.set_shader_parameter("saturation_boost", saturation)
		vignette.material.set_shader_parameter("warp_strength", warp)
		vignette.material.set_shader_parameter("pulse_speed", pulse_spd)

	if lightning_layer:
		lightning_layer.set_tier(tier)
