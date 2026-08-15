extends Node
class_name TaillightTrailManager

@export_group("Referências")
@export var left_light_marker: Marker3D
@export var right_light_marker: Marker3D

@export_group("Configurações do Rastro")
@export var invert_direction: bool = true 
@export var min_speed_kmh: float = 50.0
@export var max_speed_kmh: float = 140.0
@export var max_trail_length: float = 10.0

@export_group("Visual Neon")
@export var trail_color := Color(1.0, 0.1, 0.1, 1.0) 

var _left_pivot: Node3D
var _right_pivot: Node3D

# Referências diretas às malhas para mudar a transparência localmente
var _left_mesh: MeshInstance3D
var _right_mesh: MeshInstance3D

@onready var car = owner as VehicleBody3D
var _is_active: bool = false
var _is_bot: bool = false
var _trail_material: StandardMaterial3D = null

func _ready():
	var input = car.get_node_or_null("%InputComponent")
	if is_instance_valid(input) and "is_bot" in input:
		_is_bot = input.is_bot
		
	_setup_shared_material()
	
	if left_light_marker:
		_left_pivot = Node3D.new()
		_left_pivot.scale.z = 0.0
		left_light_marker.add_child(_left_pivot)
		_left_mesh = _create_trail_mesh()
		_left_pivot.add_child(_left_mesh)
		
	if right_light_marker:
		_right_pivot = Node3D.new()
		_right_pivot.scale.z = 0.0
		right_light_marker.add_child(_right_pivot)
		_right_mesh = _create_trail_mesh()
		_right_pivot.add_child(_right_mesh)

func _setup_shared_material():
	if _trail_material != null:
		return
		
	# ====================================================================
	# OTIMIZAÇÃO: Puxa do Cache e Duplica!
	# Duplicar não causa engasgo de compilação, mas permite que cada carro
	# tenha seu próprio Alpha e Cor no rastro da lanterna.
	# ====================================================================
	var cached_mat = MaterialCache.get_mat("BaseNeon")
	if cached_mat:
		_trail_material = cached_mat.duplicate()
	else:
		_trail_material = StandardMaterial3D.new()
		_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	_trail_material.albedo_color = trail_color
	_trail_material.albedo_color.a = 0.0

func _create_trail_mesh() -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var prism = PrismMesh.new()
	prism.size = Vector3(0.25, 1.0, 0.1) 
	
	prism.material = _trail_material 
	mesh_inst.mesh = prism
	
	var dir_mod = -1.0 if invert_direction else 1.0
	mesh_inst.rotation.x = (PI / 2.0) * dir_mod
	mesh_inst.position = Vector3(0, 0, 0.5 * dir_mod) 
	
	return mesh_inst

func _process(delta):
	if not is_instance_valid(car): 
		set_process(false)
		return
	
	var speed_kmh = car.linear_velocity.length() * 3.6
	
	var target_scale = 0.0
	var target_alpha = 0.0 # Controlamos o ALPHA (0.0 = Invisível)
	
	if speed_kmh > min_speed_kmh:
		var factor = clamp((speed_kmh - min_speed_kmh) / (max_speed_kmh - min_speed_kmh), 0.0, 1.0)
		var power_factor = factor * factor 
		
		target_scale = lerp(0.0, max_trail_length, power_factor)
		
		# Fade in (0.6 = 60% visível, misturando aditivamente)
		target_alpha = lerp(0.0, 0.6, power_factor) 
		
		if _is_bot:
			target_alpha = lerp(0.0, 0.5, power_factor)
			
		_is_active = true
	else:
		if _is_active and is_instance_valid(_left_pivot) and _left_pivot.scale.z < 0.01:
			_is_active = false
			if is_instance_valid(_left_pivot): _left_pivot.scale.z = 0.0
			if is_instance_valid(_right_pivot): _right_pivot.scale.z = 0.0
			# Zera o alpha via material
			if is_instance_valid(_trail_material): _trail_material.albedo_color.a = 0.0
			return
		elif not _is_active: return
		
	# APLICA AS INTERPOLAÇÕES
	if is_instance_valid(_left_pivot): 
		_left_pivot.scale.z = lerp(_left_pivot.scale.z, target_scale, delta * 12.0)
			
	if is_instance_valid(_right_pivot): 
		_right_pivot.scale.z = lerp(_right_pivot.scale.z, target_scale, delta * 12.0)
		
	# APLICA O FADE NO MATERIAL, PRESERVANDO O BLEND_MODE_ADD
	if is_instance_valid(_trail_material):
		_trail_material.albedo_color.a = lerp(_trail_material.albedo_color.a, target_alpha, delta * 15.0)
