extends Node2D
class_name RageLightningLayer

# Config por tier: [raios_por_segundo, distancia_max_do_centro (0-1 da tela), max_depth_branch]
var tier_config := {
	1: {"rate": 5.0, "reach": 0.42, "depth": 2},
	2: {"rate": 10.0, "reach": 0.585, "depth": 3},
	3: {"rate": 18.0, "reach": 0.7475, "depth": 3},
}

const COLOR_BLUE = Color(0.45, 0.7, 1.0)
const COLOR_YELLOW = Color(1.0, 0.85, 0.3)

var current_tier: int = 0
var _spawn_accum: float = 0.0
var _bolt_counter: int = 0 # pra regra de "1 em cada 10 é amarelo"

func set_tier(tier: int):
	current_tier = tier

func _process(delta):
	if current_tier <= 0 or not tier_config.has(current_tier):
		return

	var cfg = tier_config[current_tier]
	var rate: float = cfg["rate"]
	_spawn_accum += delta * rate

	while _spawn_accum >= 1.0:
		_spawn_accum -= 1.0
		_spawn_bolt(cfg)

func _spawn_bolt(cfg: Dictionary):
	var viewport_size = get_viewport_rect().size
	var center = viewport_size * 0.5
	var max_radius = viewport_size.length() * 0.5

	# Origem: um ponto aleatório na borda da tela
	var edge_angle = randf() * TAU
	var origin = center + Vector2(cos(edge_angle), sin(edge_angle)) * max_radius

	# Destino: entra em direção ao centro até uma distância proporcional ao "reach" do tier
	var reach: float = cfg["reach"]
	var travel_dist = max_radius * reach * randf_range(0.7, 1.0)
	var target = origin + (center - origin).normalized() * travel_dist

	var bolt = LightningBolt.new()
	add_child(bolt)

	_bolt_counter += 1
	var bolt_color = COLOR_BLUE
	if _bolt_counter % 8 == 0:
		bolt_color = COLOR_YELLOW

	var life = randf_range(0.15, 0.3)
	bolt.setup(origin, target, cfg["depth"], bolt_color, life)
