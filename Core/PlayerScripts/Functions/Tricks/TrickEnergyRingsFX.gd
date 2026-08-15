extends Node3D
class_name TrickEnergyRingsFX

@onready var car = owner as VehicleBody3D

@export_group("Anéis de Energia (Stunt)")
@export var ring_diameter : float = 2.4
@export var ring_gradient : Gradient 
@export_range(4, 32, 1) var ring_segments : int = 12 
@export var ring_count : int = 2
@export_range(60.0, 360.0, 1.0) var ring_arc_degrees : float = 300.0
@export var ring_band_width : float = 0.25
@export var ring_vertical_offset : float = 0.0
@export var ring_tilt_variation : float = 35.0
@export var fade_speed : float = 8.0

@export_group("Velocidade de Giro")
@export var ring_spin_speed_start : float = 900.0
@export var ring_spin_speed_end : float = 240.0
@export var ring_spin_decel_time : float = 0.6
@export var ring_spin_decel_curve : Curve

@export_group("Formato do Anel")
@export_range(0.3, 1.0, 0.01) var ring_oval_ratio : float = 0.7
@export var ring_tip_misalign_radial : float = 0.25
@export var ring_tip_misalign_vertical : float = 0.2

@export_group("Espessura ao Longo do Trajeto")
@export var ring_thickness_curve : Curve

@export_group("Variação Orgânica")
@export_range(0.0, 1.0, 0.01) var organic_variation : float = 0.3
@export_range(0.0, 0.3, 0.005) var organic_mesh_noise : float = 0.06

var _rings: Array = [] 
var _ring_spin_data: Array[Dictionary] = []
var _air_move: Node = null
var _built: bool = false
var _current_alpha: float = 0.0
var _default_thickness_curve: Curve = null
var _was_spinning: bool = false
var _stunt_elapsed: float = 0.0

func _ready() -> void:
	top_level = true
	
	if not ring_gradient:
		ring_gradient = Gradient.new()
		ring_gradient.set_color(0, Color(0.1, 0.9, 1.0, 0.0)) 
		ring_gradient.set_color(1, Color(0.1, 0.9, 1.0, 1.0)) 
	
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
			"segments": ring_segments,
			"oval_ratio": oval,
			"tip_radial": tip_r,
			"tip_vertical": tip_v,
			"noise_amount": organic_mesh_noise,
			"noise_freq_a": randf_range(2.5, 5.0),
			"noise_phase_a": randf_range(0.0, TAU),
			"noise_freq_b": randf_range(5.0, 9.0),
			"noise_phase_b": randf_range(0.0, TAU),
		}
		
		var ring_mesh := _build_arc_ring_ps1(cfg)
		var spin_sign := 1.0 if i % 2 == 0 else -1.0
		var spin_start := _jitter_mult(ring_spin_speed_start, 0.25) * spin_sign
		var spin_end := _jitter_mult(ring_spin_speed_end, 0.25) * spin_sign
		
		var ring = EnergyRing.new() 
		ring.spin_speed_deg = spin_start
		ring.setup(ring_mesh, Color.WHITE) 
		ring.visible = false
		ring.set_fade(0.0)
		pivot.add_child(ring)
		
		_rings.append(ring)
		_ring_spin_data.append({"start": spin_start, "end": spin_end})

func _process(delta: float) -> void:
	if is_instance_valid(car): global_position = car.global_position
	if not is_instance_valid(_air_move): return
	
	var is_spinning: bool = _air_move.get("is_doing_stunt") == true
	
	if is_spinning and not _was_spinning: _stunt_elapsed = 0.0
	if is_spinning: _stunt_elapsed += delta
	_was_spinning = is_spinning
	
	var progress := clampf(_stunt_elapsed / maxf(ring_spin_decel_time, 0.001), 0.0, 1.0)
	var eased := _ease_decel(progress)
	
	var target_alpha := 1.0 if is_spinning else 0.0
	_current_alpha = move_toward(_current_alpha, target_alpha, fade_speed * delta)
	
	for i in range(_rings.size()):
		var r = _rings[i]
		var data: Dictionary = _ring_spin_data[i]
		r.spin_speed_deg = lerp(float(data["start"]), float(data["end"]), eased)
		r.visible = _current_alpha > 0.001
		if r.has_method("set_fade"): r.set_fade(_current_alpha)

func _ease_decel(t: float) -> float:
	if ring_spin_decel_curve: return ring_spin_decel_curve.sample(t)
	return 1.0 - pow(1.0 - t, 3.0)

func _jitter_mult(base: float, max_frac: float) -> float: return base * (1.0 + randf_range(-max_frac, max_frac) * organic_variation)
func _jitter_add(max_span: float) -> float: return randf_range(-max_span, max_span) * organic_variation

func _get_thickness_curve() -> Curve:
	if ring_thickness_curve: return ring_thickness_curve
	if not _default_thickness_curve:
		_default_thickness_curve = Curve.new()
		_default_thickness_curve.add_point(Vector2(0.0, 0.0))
		_default_thickness_curve.add_point(Vector2(0.2, 2.0))
		_default_thickness_curve.add_point(Vector2(0.5, 1.0))
		_default_thickness_curve.add_point(Vector2(0.8, 2.0))
		_default_thickness_curve.add_point(Vector2(1.0, 0.0))
	return _default_thickness_curve

func _calc_point(t: float, cfg: Dictionary) -> Dictionary:
	var angle := t * deg_to_rad(float(cfg["arc_degrees"]))
	var wobble := sin(angle * cfg["noise_freq_a"] + cfg["noise_phase_a"]) * 0.65 + sin(angle * cfg["noise_freq_b"] + cfg["noise_phase_b"]) * 0.35
	var r := float(cfg["radius"]) * (1.0 + wobble * float(cfg["noise_amount"]))
	
	var ellipse_pos := Vector3(cos(angle) * r, sin(angle) * r * float(cfg["oval_ratio"]), 0.0)
	var dir := ellipse_pos.normalized() if ellipse_pos.length() > 0.001 else Vector3(cos(angle), sin(angle), 0.0)
	var center := ellipse_pos
	
	var tip_zone := 0.18
	var tip_t := 0.0
	var tip_side := 0.0
	if t < tip_zone:
		tip_t = 1.0 - (t / tip_zone)
		tip_side = -1.0
	elif t > 1.0 - tip_zone:
		tip_t = (t - (1.0 - tip_zone)) / tip_zone
		tip_side = 1.0
	
	center += dir * (float(cfg["tip_radial"]) * tip_t * tip_side)
	center.z += float(cfg["tip_vertical"]) * tip_t * tip_side
	
	return {"center": center, "dir": dir}

func _build_arc_ring_ps1(cfg: Dictionary) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	var segments: int = cfg["segments"]
	var band_width: float = cfg["band_width"]
	var curve := _get_thickness_curve()
	
	for i in range(segments):
		var t1 := float(i) / float(segments)
		var t2 := float(i + 1) / float(segments)
		var t_mid := (t1 + t2) * 0.5
		
		var p1 = _calc_point(t1, cfg)
		var p2 = _calc_point(t2, cfg)
		var thickness_mult: float = curve.sample(t_mid)
		var half_w: float = band_width * 0.5 * maxf(thickness_mult, 0.0)
		var col: Color = ring_gradient.sample(t_mid)
		
		var v0 = p1["center"] + p1["dir"] * half_w
		var v1 = p1["center"] - p1["dir"] * half_w
		var v2 = p2["center"] + p2["dir"] * half_w
		var v3 = p2["center"] - p2["dir"] * half_w
		
		var base_idx = verts.size()
		verts.append_array([v0, v1, v2, v3])
		colors.append_array([col, col, col, col])
		indices.append_array([base_idx, base_idx+1, base_idx+2, base_idx+1, base_idx+3, base_idx+2])
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# ==============================================================
	# OTIMIZAÇÃO: Busca o material pronto no Autoload
	# ==============================================================
	var mat = MaterialCache.get_mat("EnergyRings")
	if mat:
		array_mesh.surface_set_material(0, mat)
	
	return array_mesh
