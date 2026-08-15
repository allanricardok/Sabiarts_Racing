extends Node2D
class_name LightningBolt

var life_time: float = 0.3
var _elapsed: float = 0.0
var _segments: Array = [] 
var color: Color = Color(0.5, 0.75, 1.0)
var flicker_seed: float = 0.0

var _base_core_color: Color

func setup(origin: Vector2, target: Vector2, max_depth: int, bolt_color: Color, life: float):
	color = bolt_color
	life_time = life
	flicker_seed = randf() * 100.0
	
	_base_core_color = Color(1.0, 1.0, 1.0, 1.0).lerp(color, 0.15)
	
	_segments.clear()
	_generate_branch(origin, target, max_depth, 3.0)
	
	# O _draw() agora é invocado APENAS UMA VEZ!
	queue_redraw()

func _generate_branch(from: Vector2, to: Vector2, depth: int, width: float):
	var points := PackedVector2Array()
	points.append(from)

	var dir = (to - from)
	var total_len = dir.length()
	if total_len < 1.0:
		return
		
	var segment_count = randi_range(4, 7)
	var current = from
	dir = dir.normalized()
	var perp = Vector2(-dir.y, dir.x)

	for i in range(1, segment_count + 1):
		var t = float(i) / float(segment_count)
		var base_point = from.lerp(to, t)
		var jag_amount = total_len * 0.12 * randf_range(-1.0, 1.0)
		var taper = sin(t * PI) 
		var offset = perp * jag_amount * taper
		var p = base_point + offset
		points.append(p)

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
		
	# ====================================================================
	# OTIMIZAÇÃO: GPU MODULATION
	# Em vez de redesenhar a linha, calculamos o alpha e aplicamos no nó inteiro.
	# A placa de vídeo processa isso sem precisar engasgar a CPU.
	# ====================================================================
	var life_ratio = _elapsed / life_time
	var fade = 1.0 - smoothstep(0.6, 1.0, life_ratio) 
	var flicker = 0.6 + 0.4 * sin((_elapsed * 60.0) + flicker_seed) 
	var alpha = clamp(fade * flicker, 0.0, 1.0)

	var spawn_in = smoothstep(0.0, 0.06, _elapsed)
	alpha *= spawn_in
	
	self.modulate.a = alpha

func _draw():
	# Desenhamos o raio base com opacidade total relativa (0.35 e 0.9).
	# Ele fica gravado na memória gráfica e apenas pisca pelo modulate do _process.
	var halo_color = color
	halo_color.a = 0.35
	
	var core_color = _base_core_color
	core_color.a = 0.9

	for seg in _segments:
		var points: PackedVector2Array = seg["points"]
		var width: float = seg["width"]
		
		draw_polyline(points, halo_color, width * 3.0, true)
		draw_polyline(points, core_color, width, true)
