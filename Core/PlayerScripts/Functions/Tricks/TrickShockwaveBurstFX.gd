extends Node3D
class_name TrickShockwaveBurstFX

# ============================================================================
# Rajada de energia pro trick SHOCKWAVE — mesmo sistema de labaredas do
# TrickCometTailFX, mas apontando 90° reto pra CIMA (o carro é empurrado
# com força pra baixo nesse trick). Filho DIRETO do carro.
# ============================================================================

@onready var car = owner as VehicleBody3D

@export_group("Labaredas")
@export var streak_count : int = 9
@export var streak_length_min : float = 1.5
@export var streak_length_max : float = 2.6
@export var streak_width : float = 0.2
@export var streak_duration : float = 0.25
@export var spread_degrees : float = 22.0
@export var origin_offset : Vector3 = Vector3(0, -0.2, 0)
@export var color_hot : Color = Color(0.75, 0.95, 1.0)
@export var color_mid : Color = Color(0.2, 0.6, 1.0)
@export var color_tip : Color = Color(0.05, 0.15, 0.5, 0.0)
@export var width_curve : Curve

const SEGMENTS := 10
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
	
	# =====================================================================
	# CORREÇÃO: Joga a busca pelo componente para o final do frame!
	# Garante que o AirMovementComponent já configurou o stunt_processor.
	# =====================================================================
	call_deferred("_conectar_sinais_com_atraso")

func _conectar_sinais_com_atraso() -> void:
	if is_instance_valid(car):
		var air_move = car.get_node_or_null("%AirMovementComponent")
		if not air_move:
			air_move = car.find_child("AirMovementComponent", true, false)
			
		if is_instance_valid(air_move):
			_stunt_processor = air_move.get("stunt_processor")
			if is_instance_valid(_stunt_processor) and _stunt_processor.has_signal("special_trick_triggered"):
				# Se chegou aqui, a conexão está garantida!
				_stunt_processor.special_trick_triggered.connect(_on_special_trick)

func _process(_delta: float) -> void:
	if is_instance_valid(car):
		global_position = car.global_position

func _on_special_trick(trick_id: String) -> void:
	if trick_id != "SHOCKWAVE":
		return
	_burst()

func _burst() -> void:
	if not is_instance_valid(car):
		return
	
	var base_dir := Vector3.UP
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
	var right := base_dir.cross(Vector3.RIGHT) # base_dir já é UP, então cruza com RIGHT pra não zerar
	if right.length() < 0.01:
		right = base_dir.cross(Vector3.FORWARD)
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
		curve.add_point(Vector2(0.0, 0.6))
		curve.add_point(Vector2(0.12, 1.0))
		curve.add_point(Vector2(0.45, 0.5))
		curve.add_point(Vector2(1.0, 0.0))
	
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		var w: float = (curve.sample(t) * streak_width) * 0.5
		
		var col: Color
		if t < 0.5:
			col = color_hot.lerp(color_mid, t * 2.0)
		else:
			col = color_mid.lerp(color_tip, (t - 0.5) * 2.0)
		
		verts.append(Vector3(-w, t, 0))
		verts.append(Vector3(w, t, 0))
		colors.append(col)
		colors.append(col)
	
	for i in range(SEGMENTS):
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
	
	_shared_mesh = ArrayMesh.new()
	_shared_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
