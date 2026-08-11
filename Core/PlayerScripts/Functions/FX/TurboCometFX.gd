extends Node3D
class_name TurboCometFX

@export_group("Spawns (Markers)")
@export var spawn_markers : Array[NodePath]
@export var flip_marker_direction : bool = false

@export_group("Labaredas do Turbo")
@export var streak_count : int = 8
@export var streak_length_min : float = 4.0
@export var streak_length_max : float = 9.0
@export var streak_width : float = 2.0
@export var streak_duration : float = 0.7
@export var spread_degrees : float = 10.0
@export var random_roll_degrees : float = 180.0

@export var color_hot : Color = Color(0.68, 0.93, 1.0)
@export var color_mid : Color = Color(1.0, 0.6, 0.0)
@export var color_tip : Color = Color(1.0, 0.5, 0.0, 0.0)
@export var width_curve : Curve
@export_range(3, 15, 1) var streak_segments : int = 6

const POOL_SIZE := 32

var _pool: Array[TrickBurstStreak] = []
var _shared_mesh: ArrayMesh

# ============================================================================
# OTIMIZAÇÃO: MEMÓRIA CACHE
# ============================================================================
var _cached_markers: Array[Node3D] = []
var _is_bot: bool = false

func _ready() -> void:
	_build_shared_mesh()
	
	for i in range(POOL_SIZE):
		var s := TrickBurstStreak.new()
		add_child(s)
		s.visible = false
		s.set_process(false)
		_pool.append(s)
		
	# Validação atrasada para garantir que o cérebro do Bot já configurou o Input
	call_deferred("_late_setup")

func _late_setup() -> void:
	# 1. Cache da identidade (Bot ou Humano) com o método otimizado
	var car = owner
	if is_instance_valid(car):
		var input_comp = car.get_node_or_null("%InputComponent")
		if is_instance_valid(input_comp) and "is_bot" in input_comp:
			_is_bot = input_comp.is_bot

	# 2. Cache dos marcadores de escapamento (Evita get_node em tempo de execução)
	for path in spawn_markers:
		var node = get_node_or_null(path)
		if node is Node3D:
			_cached_markers.append(node)

func burst_fire_sequenced(total_size_multiplier: float) -> void:
	# DESCOMENTE A LINHA ABAIXO SE QUISER QUE BOTS NÃO TENHAM VISUAL DE TURBO (Poupa muita GPU)
	# if _is_bot: return

	if _cached_markers.is_empty():
		return
		
	var streaks_per_marker = max(1, streak_count / _cached_markers.size())
	
	for marker in _cached_markers:
		if is_instance_valid(marker):
			var dir = marker.global_transform.basis.z
			if flip_marker_direction:
				dir = -dir
				
			_spawn_streaks_sequenced(marker.global_position, dir.normalized(), streaks_per_marker, total_size_multiplier)

func _spawn_streaks_sequenced(origin: Vector3, base_dir: Vector3, count: int, overall_multiplier: float) -> void:
	for i in range(count):
		var s := _get_free_streak()
		if not s: continue
		var dir := _jitter_direction(base_dir, spread_degrees)
		
		var original_length := randf_range(streak_length_min, streak_length_max)
		var final_length := original_length * overall_multiplier
		
		s.launch(origin, dir, final_length, _shared_mesh, Color(1, 1, 1, 1), streak_duration * randf_range(0.85, 1.15))
		
		s.scale.x = overall_multiplier
		s.scale.z = overall_multiplier
		
		var roll = deg_to_rad(randf_range(-random_roll_degrees, random_roll_degrees))
		s.rotate_object_local(Vector3.UP, roll)

func _get_free_streak() -> TrickBurstStreak:
	for s in _pool:
		if not s.active:
			return s
	return null

func _jitter_direction(base_dir: Vector3, cone_degrees: float) -> Vector3:
	var right := base_dir.cross(Vector3.UP)
	
	# OTIMIZAÇÃO: length_squared() poupa raiz quadrada
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
		
		var v4 = Vector3(0, t1, -w1)
		var v5 = Vector3(0, t1, w1)
		var v6 = Vector3(0, t2, -w2)
		var v7 = Vector3(0, t2, w2)
		
		var base_idx = verts.size()
		verts.append_array([v0, v1, v2, v3, v4, v5, v6, v7])
		
		colors.append_array([col, col, col, col, col, col, col, col])
		
		indices.append_array([
			base_idx, base_idx+1, base_idx+2, base_idx+1, base_idx+3, base_idx+2, 
			base_idx+4, base_idx+5, base_idx+6, base_idx+5, base_idx+7, base_idx+6  
		])
		
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	_shared_mesh = ArrayMesh.new()
	_shared_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
