extends Node3D
class_name TrickEnergyRingsFX

# ============================================================================
# SUBSTITUI o TrickTrailFX.gd. Anexe como nó filho DIRETO do carro (irmão de
# "Scripts", NUNCA dentro dela).
#
# Desenha 2+ arcos de energia ovais, cada um com sua própria variação
# orgânica (posição, formato e velocidade de giro levemente diferentes),
# que giram numa velocidade que começa rápida e desacelera. O efeito é
# TOP-LEVEL: segue a POSIÇÃO do carro, mas nunca a rotação — não tomba
# junto com o carro durante frontflip/backflip.
# ============================================================================

@onready var car = owner as VehicleBody3D

@export_group("Anéis de Energia (Stunt)")
## Diâmetro dos anéis ao redor do carro (eixo maior do oval)
@export var ring_diameter : float = 2.4
## Cor da energia
@export var ring_color : Color = Color(0.1, 0.9, 1.0)
## Quantos anéis sobrepostos (2 já dá o efeito; 3 fica mais "cheio")
@export var ring_count : int = 2
## Quantos graus do círculo cada anel cobre.
@export_range(60.0, 360.0, 1.0) var ring_arc_degrees : float = 300.0
## Espessura BASE da faixa do anel — a curva de espessura abaixo multiplica
## este valor ao longo do trajeto
@export var ring_band_width : float = 0.25
## Deslocamento vertical do centro dos anéis em relação ao centro do carro
@export var ring_vertical_offset : float = 0.0
## Variação de inclinação entre os anéis, em graus
@export var ring_tilt_variation : float = 35.0
## Velocidade do fade-in/fade-out ao começar/terminar uma manobra
@export var fade_speed : float = 8.0

@export_group("Velocidade de Giro")
## Velocidade de giro logo no início da manobra (graus/seg) — o "arranque"
@export var ring_spin_speed_start : float = 900.0
## Velocidade de giro depois de estabilizar (graus/seg)
@export var ring_spin_speed_end : float = 240.0
## Tempo (segundos) pra ir da velocidade inicial até a final
@export var ring_spin_decel_time : float = 0.6
## Curva de desaceleração opcional (eixo X = progresso 0-1, eixo Y = 0-1).
## Se vazio, usa um ease-out cúbico padrão.
@export var ring_spin_decel_curve : Curve

@export_group("Formato do Anel")
## 1.0 = círculo perfeito. Menor que 1.0 achata o anel num oval
@export_range(0.3, 1.0, 0.01) var ring_oval_ratio : float = 0.7
## Desalinhamento lateral das pontas (início/fim do arco)
@export var ring_tip_misalign_radial : float = 0.25
## Desalinhamento vertical das pontas
@export var ring_tip_misalign_vertical : float = 0.2

@export_group("Espessura ao Longo do Trajeto")
## Curva de multiplicador de espessura: X = progresso do arco (0-1),
## Y = multiplicador de ring_band_width. Vazio = default 0%→0, 20%→2,
## 50%→1, 80%→2, 100%→0.
@export var ring_thickness_curve : Curve

@export_group("Variação Orgânica")
## 0 = tudo matematicamente perfeito e simétrico (comportamento antigo).
## 1 = variação forte em quase todo parâmetro entre os anéis.
@export_range(0.0, 1.0, 0.01) var organic_variation : float = 0.3
## Quanto a LINHA do anel ondula em relação a um oval perfeito (fração do
## raio). Faz o traçado parecer desenhado à mão em vez de geométrico.
@export_range(0.0, 0.3, 0.005) var organic_mesh_noise : float = 0.06

const SEGMENTS := 24

var _rings: Array[EnergyRing] = []
var _ring_spin_data: Array[Dictionary] = []
var _air_move: Node = null
var _built: bool = false
var _current_alpha: float = 0.0
var _default_thickness_curve: Curve = null
var _was_spinning: bool = false
var _stunt_elapsed: float = 0.0

func _ready() -> void:
	# Top-level: este nó para de herdar a transform do carro. Nós mesmos
	# sincronizamos a posição no _process, e NUNCA tocamos na rotação —
	# é isso que impede o efeito de "tombar" durante flips.
	top_level = true
	
	if is_instance_valid(car):
		_air_move = car.get_node_or_null("%AirMovementComponent")
		if not _air_move:
			_air_move = car.find_child("AirMovementComponent", true, false)
	_build_rings()

func _build_rings() -> void:
	if _built: return
	_built = true
	
	_ring_spin_data.clear()
	
	for i in range(ring_count):
		var pivot := Node3D.new()
		add_child(pivot)
		
		# --- Cada anel puxa parâmetros levemente diferentes, então nada
		# fica perfeitamente simétrico/repetido entre eles ---
		var radius := _jitter_mult(ring_diameter * 0.5, 0.25)
		var arc_deg := _jitter_mult(ring_arc_degrees, 0.15)
		var oval := _jitter_mult(ring_oval_ratio, 0.2)
		var tip_r := _jitter_mult(ring_tip_misalign_radial, 0.3)
		var tip_v := _jitter_mult(ring_tip_misalign_vertical, 0.3)
		
		var base_tilt := (ring_tilt_variation * i) - (ring_tilt_variation * (ring_count - 1) * 0.5)
		var tilt := base_tilt + _jitter_add(20.0)
		
		var base_phase := (360.0 / float(max(ring_count, 1))) * i
		var phase := base_phase + _jitter_add(40.0)
		
		var vert_offset := ring_vertical_offset + _jitter_add(ring_diameter * 0.15)
		
		pivot.position = Vector3(0, vert_offset, 0)
		pivot.rotation_degrees = Vector3(90.0 + tilt, 0, 0)
		pivot.rotate_object_local(Vector3.BACK, deg_to_rad(phase))
		
		var cfg := {
			"radius": radius,
			"arc_degrees": arc_deg,
			"band_width": ring_band_width,
			"segments": SEGMENTS,
			"oval_ratio": oval,
			"tip_radial": tip_r,
			"tip_vertical": tip_v,
			"noise_amount": organic_mesh_noise,
			"noise_freq_a": randf_range(2.5, 5.0),
			"noise_phase_a": randf_range(0.0, TAU),
			"noise_freq_b": randf_range(5.0, 9.0),
			"noise_phase_b": randf_range(0.0, TAU),
		}
		var ring_mesh := _build_arc_ring(cfg)
		
		var spin_sign := 1.0 if i % 2 == 0 else -1.0
		var spin_start := _jitter_mult(ring_spin_speed_start, 0.25) * spin_sign
		var spin_end := _jitter_mult(ring_spin_speed_end, 0.25) * spin_sign
		
		var ring := EnergyRing.new()
		ring.spin_speed_deg = spin_start
		ring.setup(ring_mesh, ring_color)
		ring.visible = false
		ring.set_fade(0.0)
		pivot.add_child(ring)
		
		_rings.append(ring)
		_ring_spin_data.append({"start": spin_start, "end": spin_end})

func _process(delta: float) -> void:
	if is_instance_valid(car):
		global_position = car.global_position
	
	if not is_instance_valid(_air_move):
		return
	
	var is_spinning: bool = _air_move.get("is_doing_stunt") == true
	
	# Reinicia o timer de desaceleração toda vez que uma manobra começa
	if is_spinning and not _was_spinning:
		_stunt_elapsed = 0.0
	if is_spinning:
		_stunt_elapsed += delta
	_was_spinning = is_spinning
	
	var progress := clampf(_stunt_elapsed / maxf(ring_spin_decel_time, 0.001), 0.0, 1.0)
	var eased := _ease_decel(progress)
	
	var target_alpha := 1.0 if is_spinning else 0.0
	_current_alpha = move_toward(_current_alpha, target_alpha, fade_speed * delta)
	
	for i in range(_rings.size()):
		var r := _rings[i]
		var data: Dictionary = _ring_spin_data[i]
		r.spin_speed_deg = lerp(float(data["start"]), float(data["end"]), eased)
		r.visible = _current_alpha > 0.001
		r.set_fade(_current_alpha)

func _ease_decel(t: float) -> float:
	if ring_spin_decel_curve:
		return ring_spin_decel_curve.sample(t)
	return 1.0 - pow(1.0 - t, 3.0) # ease-out cúbico padrão

func _jitter_mult(base: float, max_frac: float) -> float:
	return base * (1.0 + randf_range(-max_frac, max_frac) * organic_variation)

func _jitter_add(max_span: float) -> float:
	return randf_range(-max_span, max_span) * organic_variation

func _get_thickness_curve() -> Curve:
	if ring_thickness_curve:
		return ring_thickness_curve
	if not _default_thickness_curve:
		_default_thickness_curve = Curve.new()
		_default_thickness_curve.add_point(Vector2(0.0, 0.0))
		_default_thickness_curve.add_point(Vector2(0.2, 2.0))
		_default_thickness_curve.add_point(Vector2(0.5, 1.0))
		_default_thickness_curve.add_point(Vector2(0.8, 2.0))
		_default_thickness_curve.add_point(Vector2(1.0, 0.0))
	return _default_thickness_curve

# Monta um arco OVAL, com pontas desalinhadas, espessura variável e um
# leve "wobble" orgânico no raio (soma de 2 senoides com freq/fase
# aleatórias, únicas por anel — é o que faz cada linha parecer única).
func _build_arc_ring(cfg: Dictionary) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	var radius: float = cfg["radius"]
	var arc_rad := deg_to_rad(float(cfg["arc_degrees"]))
	var oval_ratio: float = cfg["oval_ratio"]
	var tip_radial: float = cfg["tip_radial"]
	var tip_vertical: float = cfg["tip_vertical"]
	var band_width: float = cfg["band_width"]
	var noise_amount: float = cfg["noise_amount"]
	var noise_freq_a: float = cfg["noise_freq_a"]
	var noise_phase_a: float = cfg["noise_phase_a"]
	var noise_freq_b: float = cfg["noise_freq_b"]
	var noise_phase_b: float = cfg["noise_phase_b"]
	var segments: int = cfg["segments"]
	var curve := _get_thickness_curve()
	var tip_zone := 0.18
	
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var angle := t * arc_rad
		
		var wobble := sin(angle * noise_freq_a + noise_phase_a) * 0.65 \
			+ sin(angle * noise_freq_b + noise_phase_b) * 0.35
		var r := radius * (1.0 + wobble * noise_amount)
		
		var ellipse_pos := Vector3(cos(angle) * r, sin(angle) * r * oval_ratio, 0.0)
		var dir := ellipse_pos.normalized() if ellipse_pos.length() > 0.001 else Vector3(cos(angle), sin(angle), 0.0)
		var center := ellipse_pos
		
		var tip_t := 0.0
		var tip_side := 0.0
		if t < tip_zone:
			tip_t = 1.0 - (t / tip_zone)
			tip_side = -1.0
		elif t > 1.0 - tip_zone:
			tip_t = (t - (1.0 - tip_zone)) / tip_zone
			tip_side = 1.0
		
		center += dir * (tip_radial * tip_t * tip_side)
		center.z += tip_vertical * tip_t * tip_side
		
		var color_alpha := 1.0 - pow(t, 1.5)
		
		var thickness_mult: float = curve.sample(t)
		var half_w: float = band_width * 0.5 * maxf(thickness_mult, 0.0)
		
		verts.append(center + dir * half_w)
		verts.append(center - dir * half_w)
		colors.append(Color(1, 1, 1, color_alpha))
		colors.append(Color(1, 1, 1, color_alpha))
	
	for i in range(segments):
		var a := i * 2
		var b := i * 2 + 1
		var c := (i + 1) * 2
		var d := (i + 1) * 2 + 1
		indices.append_array([a, b, c, b, d, c])
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh
