# RageUI.gd
extends Control

@onready var vignette = $Vignette
@onready var title = $Title
@onready var multiplier_label = $Multiplier
@onready var bar = $Bar
@onready var seconds_label = $Seconds

# Cores dos Tiers
const COLOR_T0 = Color.WHITE
const COLOR_T1 = Color.YELLOW
const COLOR_T2 = Color(1.0, 0.5, 0.0) # Laranja
const COLOR_T3 = Color(1.0, 0.2, 0.2) # <--- Vermelho mais claro/vivo para máximo contraste

# Shader modificado para "Vermelho Sangue Escuro"
var shader_code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 2.0;
	float alpha = smoothstep(0.8 - (intensity * 0.2), 1.0, dist);
	// RGB(0.55, 0.0, 0.0) cria um vermelho sangue bem profundo e opaco
	COLOR = vec4(0.55, 0.0, 0.0, alpha * intensity * 0.95);
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
	
	match tier:
		0:
			target_color = COLOR_T0
			vignette_intensity = 0.0
			if bar: bar.value = rage_value
			if seconds_label: seconds_label.text = ""
		1:
			target_color = COLOR_T1
			vignette_intensity = 0.3
			if bar: bar.value = rage_value - 100.0
			if seconds_label: seconds_label.text = ""
		2:
			target_color = COLOR_T2
			vignette_intensity = 0.6
			if bar: bar.value = rage_value - 200.0
			if seconds_label: seconds_label.text = ""
		3:
			target_color = COLOR_T3
			vignette_intensity = 1.0
			if bar: bar.value = 100.0 
			if seconds_label: seconds_label.text = "%.1fsec" % t3_timer
			
	multiplier_label.add_theme_color_override("font_color", target_color)
	
	if bar:
		bar.modulate = target_color
	
	if vignette.material:
		vignette.material.set_shader_parameter("intensity", vignette_intensity)
