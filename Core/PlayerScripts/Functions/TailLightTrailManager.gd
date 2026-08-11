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
@export var neon_power: float = 4.0 

var _left_pivot: Node3D
var _right_pivot: Node3D
var _material: StandardMaterial3D

@onready var car = owner as VehicleBody3D

# OTIMIZAÇÃO: Flag para colocar o script para dormir quando o carro parar
var _is_active: bool = false

func _ready():
	_setup_material()
	
	if left_light_marker:
		_left_pivot = Node3D.new()
		_left_pivot.scale.z = 0.0
		left_light_marker.add_child(_left_pivot)
		var left_mesh = _create_trail_mesh()
		_left_pivot.add_child(left_mesh)
		
	if right_light_marker:
		_right_pivot = Node3D.new()
		_right_pivot.scale.z = 0.0
		right_light_marker.add_child(_right_pivot)
		var right_mesh = _create_trail_mesh()
		_right_pivot.add_child(right_mesh)

func _setup_material():
	_material = StandardMaterial3D.new()
	
	# BLINDAGEM DE COMPARTILHAMENTO: Garante que este material é único deste carro
	_material.resource_local_to_scene = true 
	
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	
	# CLONE DA COR: Evita alterar o ponteiro da variável exportada
	var mat_color = trail_color
	mat_color.a = 0.0 
	_material.albedo_color = mat_color
	
	_material.emission_enabled = true
	_material.emission = trail_color
	_material.emission_energy_multiplier = 0.0 

func _create_trail_mesh() -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var prism = PrismMesh.new()
	prism.size = Vector3(0.25, 1.0, 0.1) 
	mesh_inst.mesh = prism
	mesh_inst.material_override = _material
	
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
	var target_alpha = 0.0
	var target_glow = 0.0
	
	if speed_kmh > min_speed_kmh:
		var factor = clamp((speed_kmh - min_speed_kmh) / (max_speed_kmh - min_speed_kmh), 0.0, 1.0)
		var power_factor = factor * factor 
		
		target_scale = lerp(0.0, max_trail_length, power_factor)
		target_alpha = lerp(0.0, 0.2, power_factor)
		target_glow = target_alpha * neon_power 
		
		# Acorda o script
		_is_active = true
	else:
		# OTIMIZAÇÃO MÁXIMA: Se a velocidade está baixa e a escala visual já diminuiu para quase zero,
		# nós cravamos os valores em 0.0 e cortamos a execução da matemática neste frame!
		if _is_active and is_instance_valid(_left_pivot) and _left_pivot.scale.z < 0.01:
			_is_active = false
			if is_instance_valid(_left_pivot): _left_pivot.scale.z = 0.0
			if is_instance_valid(_right_pivot): _right_pivot.scale.z = 0.0
			if is_instance_valid(_material):
				_material.albedo_color.a = 0.0
				_material.emission_energy_multiplier = 0.0
			return
		elif not _is_active:
			# Carro já está parado e apagado, apenas ignora o resto do frame
			return
		
	if is_instance_valid(_left_pivot):
		_left_pivot.scale.z = lerp(_left_pivot.scale.z, target_scale, delta * 12.0)
		
	if is_instance_valid(_right_pivot):
		_right_pivot.scale.z = lerp(_right_pivot.scale.z, target_scale, delta * 12.0)
		
	if is_instance_valid(_material):
		_material.albedo_color.a = lerp(_material.albedo_color.a, target_alpha, delta * 15.0)
		_material.emission_energy_multiplier = lerp(_material.emission_energy_multiplier, target_glow, delta * 15.0)
