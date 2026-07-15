extends Node2D
class_name LightningBolt

# Gera um raio fractal (tronco + branches recursivas) do tipo "raio de tempestade":
# fino, anguloso, com ramificações que vão diminuindo de espessura/comprimento.

var life_time: float = 0.3
var _elapsed: float = 0.0
var _segments: Array = [] # Array de {points: PackedVector2Array, width: float}
var color: Color = Color(0.5, 0.75, 1.0)
var flicker_seed: float = 0.0

func setup(origin: Vector2, target: Vector2, max_depth: int, bolt_color: Color, life: float):
	color = bolt_color
	life_time = life
	flicker_seed = randf() * 100.0
	_segments.clear()
	_generate_branch(origin, target, max_depth, 3.0)
	queue_redraw()

# Gera um caminho anguloso entre "from" e "to", com deslocamentos aleatórios
# perpendiculares ao segmento (jaggedness), e recursivamente cria sub-branches.
func _generate_branch(from: Vector2, to: Vector2, depth: int, width: float):
	var points := PackedVector2Array()
	points.append(from)

	var segment_count = randi_range(4, 7)
	var current = from
	var dir = (to - from)
	var total_len = dir.length()
	if total_len < 1.0:
		return
	dir = dir.normalized()
	var perp = Vector2(-dir.y, dir.x)

	for i in range(1, segment_count + 1):
		var t = float(i) / float(segment_count)
		var base_point = from.lerp(to, t)
		# Deslocamento perpendicular aleatório, maior no meio, ~0 nas pontas
		var jag_amount = total_len * 0.12 * randf_range(-1.0, 1.0)
		var taper = sin(t * PI) # 0 nas pontas, 1 no meio
		var offset = perp * jag_amount * taper
		var p = base_point + offset
		points.append(p)

		# Chance de nascer uma sub-branch neste ponto do caminho
		if depth > 0 and randf() < 0.45 and t > 0.15 and t < 0.9:
			var branch_dir = (p - current).normalized().rotated(randf_range(-0.9, 0.9))
			var branch_len = (total_len * (1.0 - t)) * randf_range(0.3, 0.6)
			var branch_end = p + branch_dir * branch_len
			_generate_branch(p, branch_end, depth - 1, width * 0.55)

		current = p

	_segments.append({"points": points, "width": max(0.6, width)})

func _process(delta):
	_elapsed += delta
	if _elapsed >= life_time:
		queue_free()
		return
	queue_redraw()

func _draw():
	# Flicker: pisca (opacidade oscila rápido) e fade out no final da vida
	var life_ratio = _elapsed / life_time
	var fade = 1.0 - smoothstep(0.6, 1.0, life_ratio) # começa a sumir nos últimos 40% da vida
	var flicker = 0.6 + 0.4 * sin((_elapsed * 60.0) + flicker_seed) # pisca rápido tipo eletricidade
	var alpha = clamp(fade * flicker, 0.0, 1.0)

	# Aparece quase instantâneo (bem rápido) logo no início
	var spawn_in = smoothstep(0.0, 0.06, _elapsed)
	alpha *= spawn_in

	for seg in _segments:
		var points: PackedVector2Array = seg["points"]
		var width: float = seg["width"]
		# Núcleo brilhante (quase branco) + halo colorido mais largo por baixo
		draw_polyline(points, Color(color.r, color.g, color.b, alpha * 0.35), width * 3.0, true)
		draw_polyline(points, Color(1.0, 1.0, 1.0, alpha * 0.9).lerp(color, 0.15), width, true)
