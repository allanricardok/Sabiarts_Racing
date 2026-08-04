shader_type canvas_item;

uniform vec2 Resolution = vec2(320.0, 240.0);
uniform float Color_Depth = 15.0;
uniform sampler2D screen_texture: hint_screen_texture, filter_nearest;
uniform float dither_amount: hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float dither_scale = 2.0;

const mat4 bayer_matrix = (1.0 / 16.0) * mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 9.0)
) - 0.5;

void fragment() {
	vec2 uv = floor(SCREEN_UV * Resolution) / Resolution;
	vec3 color = texture(screen_texture, uv).rgb;

	ivec2 dither_uv = ivec2(FRAGCOORD.xy / dither_scale);
	vec3 dithered_color = color + bayer_matrix[dither_uv.x % 4][dither_uv.y % 4] / Color_Depth * dither_amount;
	vec3 quantized_color = round(dithered_color * Color_Depth) / Color_Depth;

	COLOR = vec4(quantized_color, 1.0);
}