// BulletShader.gdshader
shader_type spatial;
// Render mode unshaded faz o objeto ignorar a luz do mapa e ser 100% "aceso".
// blend_add faz ele clarear o que estiver atrás, parecendo luz pura.
render_mode unshaded, blend_add, depth_draw_never;

// Variavel ajustavel no Inspector para a cor e intensidade
uniform vec4 albedo : source_color = vec4(1.0, 0.9, 0.3, 1.0); // Amarelo claro
uniform float power : hint_range(1.0, 20.0) = 8.0; // Intensidade do brilho

void fragment() {
	// ALBEDO final é a cor multiplicada pela intensidade.
	// Se tiver 'Glow' ativado no WorldEnvironment, isso vai explodir em brilho.
	ALBEDO = albedo.rgb * power;
	ALPHA = albedo.a;
}