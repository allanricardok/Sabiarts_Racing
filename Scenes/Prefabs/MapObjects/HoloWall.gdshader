shader_type spatial;
// Blend add cria o efeito luminoso "neon" que soma com o fundo
render_mode unshaded, blend_add, cull_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.0, 1.0); // Cor Dourada (pode mudar pra vermelho, azul...)
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float stripe_scale = 10.0; // Quantidade de listras

void fragment() {
	// Cria um padrão de listras de alerta (tipo caution tape)
	float pattern = step(0.5, fract((UV.x + UV.y) * stripe_scale));

	ALBEDO = glow_color.rgb;
	// A mágica: A barreira fica invisível quando intensity é 0.
	ALPHA = pattern * intensity * glow_color.a;
}