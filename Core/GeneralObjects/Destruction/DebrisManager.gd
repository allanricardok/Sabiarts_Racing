extends Node

const POOL_SIZE := 48
const SHAPE_VARIANTS := 14
const GLOBAL_SPEED_MULTIPLIER := 1.2

var pool: Array[DebrisShard] = []
var _shard_shapes: Array[Mesh] = []

# OTIMIZAÇÃO: Cache de Materiais PS1
var _ps1_material_cache: Dictionary = {}

func _ready() -> void:
	for i in range(SHAPE_VARIANTS):
		_shard_shapes.append(_build_random_shard_mesh())
	
	for i in range(POOL_SIZE):
		var shard := DebrisShard.new()
		shard.visible = false
		shard.set_process(false)
		add_child(shard)
		pool.append(shard)

func _build_random_shard_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	
	var is_quad := randf() > 0.35 
	var point_count := 4 if is_quad else 3
	
	var base_angle := randf_range(0.0, TAU) 
	for i in range(point_count):
		base_angle += (TAU / float(point_count)) * randf_range(0.6, 1.4)
		var dist := randf_range(0.32, 0.55)
		var p := Vector3(cos(base_angle) * dist, sin(base_angle) * dist, 0.0)
		verts.append(p)
		uvs.append(Vector2(p.x + 0.5, p.y + 0.5))
	
	if is_quad:
		indices.append_array([0, 1, 2, 0, 2, 3])
	else:
		indices.append_array([0, 1, 2])
	
	var normals := PackedVector3Array()
	for i in range(verts.size()):
		normals.append(Vector3(0, 0, 1))
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh

func _get_free_shard() -> DebrisShard:
	for s in pool:
		if not s.active:
			return s
	return null

# MÁQUINA DE CACHE: Transforma o material em PS1 apenas uma vez e salva na memória
func _get_ps1_material(base: Material) -> Material:
	if not base: return null
	
	if _ps1_material_cache.has(base):
		return _ps1_material_cache[base]
		
	var new_mat = base.duplicate() as StandardMaterial3D
	if new_mat:
		new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ps1_material_cache[base] = new_mat
		return new_mat
		
	return base

func explode(
	origin: Vector3,
	base_material: Material,
	shard_count: int = 10,
	force: float = 4.0,
	upward_bias: float = 3.5,
	lifetime: float = 1.1,
	scatter_radius: float = 0.25,
	min_size: float = 0.15,
	max_size: float = 0.35
) -> void:
	
	# Pega o material processado direto do cache
	var cached_mat = _get_ps1_material(base_material)
	
	for i in range(shard_count):
		var shard := _get_free_shard()
		if shard == null:
			break
		
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.1, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var vel := dir * force * randf_range(0.6, 1.4)
		vel.y += upward_bias * randf_range(0.7, 1.3)
		vel *= GLOBAL_SPEED_MULTIPLIER
		
		var spin := Vector3(
			randf_range(-9.0, 9.0),
			randf_range(-9.0, 9.0),
			randf_range(-9.0, 9.0)
		)
		
		var spawn_pos := origin + Vector3(
			randf_range(-scatter_radius, scatter_radius),
			randf_range(-scatter_radius, scatter_radius),
			randf_range(-scatter_radius, scatter_radius)
		)
		
		var shape := _shard_shapes[randi() % _shard_shapes.size()]
		var size := randf_range(min_size, max(min_size, max_size))
		
		shard.launch(spawn_pos, vel, spin, lifetime * randf_range(0.8, 1.2), cached_mat, shape, size)

func warmup(materials: Array) -> void:
	if materials.is_empty(): return
	
	var viewport = get_viewport()
	var cam = viewport.get_camera_3d() if viewport else null
	var warm_pos: Vector3 = (cam.global_position + cam.global_transform.basis.z * -2.0) if cam else Vector3.ZERO
	
	for mat in materials:
		var shard := _get_free_shard()
		if shard == null: break
		
		var cached_mat = _get_ps1_material(mat)
		var shape := _shard_shapes[0] if not _shard_shapes.is_empty() else null
		shard.launch(warm_pos, Vector3.ZERO, Vector3.ZERO, 0.05, cached_mat, shape, 0.25)
