shader_type canvas_item;

// Cores e densidade
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_count : hint_range(10.0, 200.0) = 80.0;
uniform float line_density : hint_range(0.0, 1.0) = 0.2;
uniform float animation_speed : hint_range(0.0, 20.0) = 8.0;

// O buraco no centro (para não cobrir o carro)
uniform float mask_radius : hint_range(0.0, 1.0) = 0.15;
uniform float mask_smoothness : hint_range(0.0, 1.0) = 0.3;

// A variável que o GDScript vai controlar (0.0 = invisível, 1.0 = força total)
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

// Função de gerar números aleatórios
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void fragment() {
	// Centraliza o ponto de origem (0.0, 0.0 no meio da tela)
    vec2 centered_uv = UV - 0.5;
    float radius = length(centered_uv);
    float angle = atan(centered_uv.y, centered_uv.x);

    // Trava os ângulos para criar listras retas em vez de um gradiente
    float angle_snapped = floor(angle * line_count);

    // Cria a variação aleatória de cada listra
    float rand_val = random(vec2(angle_snapped, 1.0));

    // Faz as linhas piscarem/movimentarem com o tempo
    float animated_noise = fract(rand_val + (TIME * animation_speed * random(vec2(angle_snapped, 2.0))));

    // Transforma o ruído em linhas sólidas
    float is_line = step(1.0 - line_density, animated_noise);

    // Apaga o centro da tela suavemente
    float mask = smoothstep(mask_radius, mask_radius + mask_smoothness, radius);

    // Pinta na tela combinando a cor, a máscara central e a intensidade do carro
    COLOR = line_color;
    COLOR.a = is_line * mask * intensity * line_color.a;
}