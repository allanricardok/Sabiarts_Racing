extends Node3D
class_name TrickCometTailFX

# ============================================================================
# Cauda de cometa/bola de fogo pro trick FIREBALL.
# ============================================================================

@onready var car = owner as VehicleBody3D

@export_group("Direção")
@export var flip_forward_axis : bool = false
@export var spread_degrees : float = 13.0
@export var origin_offset : Vector3 = Vector3(0, -0.3, 0)

@export_group("Labaredas")
@export var streak_count : int = 4
@export var streak_length_min : float = 3.5
@export var streak_length_max : float = 8.0
@export var streak_width : float = 2.0
@export var streak_duration : float = 0.7
@export var color_hot : Color = Color(0.68, 0.93, 1.0)
@export var color_mid : Color = Color(1.0, 0.6, 0.0)
@export var color_tip : Color = Color(1.0, 0.5, 0.0, 0.0)
@export var width_curve : Curve

@export_range(3, 15, 1) var streak_segments : int = 6
const POOL_SIZE := 24

var _pool: Array[TrickBurstStreak] = []
var _shared_mesh: ArrayMesh
var _stunt_processor: Node = null

func _ready() -> void:
	top_level = true 
	_build_shared_mesh()
	
	for i in range(POOL_SIZE):
		var s := TrickBurstStreak.new()
		add_child(s)
		s.visible = false
		s.set_process(false)
		_pool.append(s)
	
	call_deferred("_conectar_sinais_com_atraso")

func _conectar_sinais_com_atraso() -> void:
	if is_instance_valid(car):
		# OTIMIZAÇÃO: Busca O(1) pelo Unique Node, sem fallback lento.
		var air_move = car.get_node_or_null("%AirMovementComponent")
			
		if is_instance_valid(air_move):
			_stunt_processor = air_move.get("stunt_processor")
			if is_instance_valid(_stunt_processor) and _stunt_processor.has_signal("special_trick_triggered"):
				_stunt_processor.special_trick_triggered.connect(_on_special_trick)

func _process(_delta: float) -> void:
	if is_instance_valid(car):
		global_position = car.global_position

func _on_special_trick(trick_id: String) -> void:
	if trick_id != "FIREBALL":
		return
	_burst()

func _burst() -> void:
	if not is_instance_valid(car):
		return
	
	var back: Vector3 = car.global_transform.basis.z if not flip_forward_axis else -car.global_transform.basis.z
	back.y = 0
	
	# OTIMIZAÇÃO: length_squared() poupa o processador
	if back.length_squared() < 0.000001:
		back = Vector3.FORWARD
		
	back = back.normalized()
	var base_dir: Vector3 = (back + Vector3.DOWN).normalized() 

	var origin: Vector3 = car.global_position + car.global_transform.basis * origin_offset
	for i in range(streak_count):
		var s := _get_free_streak()
		if not s: continue
		var dir := _jitter_direction(base_dir, spread_degrees)
		var length := randf_range(streak_length_min, streak_length_max)
		s.launch(origin, dir, length, _shared_mesh, Color(1, 1, 1, 1), streak_duration * randf_range(0.85, 1.15))

func _get_free_streak() -> TrickBurstStreak:
	for s in _pool:
		if not s.active:
			return s
	return null

func _jitter_direction(base_dir: Vector3, cone_degrees: float) -> Vector3:
	var right := base_dir.cross(Vector3.UP)
	
	# OTIMIZAÇÃO: length_squared() novamente!
	if right.length_squared() < 0.0001:
		right = base_dir.cross(Vector3.RIGHT)
		
	right = right.normalized()
	var up := right.cross(base_dir).normalized()
	
	var yaw := deg_to_rad(randf_range(-cone_degrees, cone_degrees))
	var pitch := deg_to_rad(randf_range(-cone_degrees, cone_degrees))
	
	var dir := base_dir.rotated(up, yaw)
	dir = dir.rotated(right, pitch)
	return dir.normalized()

func _build_shared_mesh() -> void:
	var curve := width_curve
	if not curve:
		curve = Curve.new()
		curve.add_point(Vector2(0.0, 0.55))
		curve.add_point(Vector2(0.1, 1.0))
		curve.add_point(Vector2(0.4, 0.6))
		curve.add_point(Vector2(1.0, 0.0))
	
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	for i in range(streak_segments):
		var t1 := float(i) / float(streak_segments)
		var t2 := float(i + 1) / float(streak_segments)
		
		var t_mid := (t1 + t2) * 0.5
		
		var w1: float = (curve.sample(t1) * streak_width) * 0.5
		var w2: float = (curve.sample(t2) * streak_width) * 0.5
		
		var col: Color
		if t_mid < 0.5:
			col = color_hot.lerp(color_mid, t_mid * 2.0)
		else:
			col = color_mid.lerp(color_tip, (t_mid - 0.5) * 2.0)
		
		var v0 = Vector3(-w1, t1, 0)
		var v1 = Vector3(w1, t1, 0)
		var v2 = Vector3(-w2, t2, 0)
		var v3 = Vector3(w2, t2, 0)
		
		var base_idx = verts.size()
		verts.append_array([v0, v1, v2, v3])
		
		colors.append_array([col, col, col, col])
		
		indices.append_array([base_idx, base_idx+1, base_idx+2, base_idx+1, base_idx+3, base_idx+2])
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	_shared_mesh = ArrayMesh.new()
	_shared_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# ==============================================================
	# OTIMIZAÇÃO: Busca o material pronto no Autoload
	# ==============================================================
	var mat = MaterialCache.get_mat("FireballTail")
	if mat:
		_shared_mesh.surface_set_material(0, mat)
