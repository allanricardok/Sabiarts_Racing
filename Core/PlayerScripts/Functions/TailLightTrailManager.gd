# TaillightTrailManager.gd
extends Node
class_name TaillightTrailManager

@export_group("Referências")
@export var left_light_marker: Marker3D
@export var right_light_marker: Marker3D

@export_group("Configurações do Rastro")
@export var invert_direction: bool = true # Ative se a luz estiver indo para dentro do carro!
@export var min_speed_kmh: float = 50.0
@export var max_speed_kmh: float = 140.0
@export var max_trail_length: float = 10.0

@export_group("Visual Neon")
@export var trail_color := Color(1.0, 0.1, 0.1, 1.0) # Vermelho neon
@export var neon_power: float = 4.0 # Força do brilho emissivo

var _left_mesh: MeshInstance3D
var _right_mesh: MeshInstance3D
var _left_pivot: Node3D
var _right_pivot: Node3D
var _material: StandardMaterial3D

@onready var car = owner as VehicleBody3D

func _ready():
	_setup_material()
	
	_left_pivot = Node3D.new()
	_right_pivot = Node3D.new()
	
	# ZERA O TAMANHO INICIAL PARA NÃO COMEÇAR GRANDE
	_left_pivot.scale.z = 0.0
	_right_pivot.scale.z = 0.0
	
	if left_light_marker:
		left_light_marker.add_child(_left_pivot)
		_left_mesh = _create_trail_mesh()
		_left_pivot.add_child(_left_mesh)
		
	if right_light_marker:
		right_light_marker.add_child(_right_pivot)
		_right_mesh = _create_trail_mesh()
		_right_pivot.add_child(_right_mesh)

func _setup_material():
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	
	# O SEGREDO DO NEON: Habilitar Emissão (Luz Própria)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.albedo_color = trail_color
	_material.albedo_color.a = 0.0 # Começa totalmente invisível
	
	_material.emission_enabled = true
	_material.emission = trail_color
	_material.emission_energy_multiplier = 0.0 # O brilho começa apagado

func _create_trail_mesh() -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# FORMATO DE CONE/TRIÂNGULO PARA TER A PONTA FINA
	var prism = PrismMesh.new()
	prism.size = Vector3(0.25, 1.0, 0.02) # Largura da lanterna, Comprimento 1m, Espessura fina
	mesh_inst.mesh = prism
	mesh_inst.material_override = _material
	
	# CORREÇÃO DE DIREÇÃO E ANCORAGEM
	var dir_mod = -1.0 if invert_direction else 1.0
	
	# Gira o triângulo 90 graus para deitá-lo e fazê-lo apontar para trás (ou para frente se invertido)
	mesh_inst.rotation.x = (PI / 2.0) * dir_mod
	
	# Desloca a base do triângulo perfeitamente para o centro do pivô
	mesh_inst.position = Vector3(0, 0, 0.5 * dir_mod) 
	
	return mesh_inst

func _process(delta):
	if not is_instance_valid(car): return
	
	var speed_kmh = car.linear_velocity.length() * 3.6
	
	var target_scale = 0.0
	var target_alpha = 0.0
	var target_glow = 0.0
	
	if speed_kmh > min_speed_kmh:
		var factor = clamp((speed_kmh - min_speed_kmh) / (max_speed_kmh - min_speed_kmh), 0.0, 1.0)
		var power_factor = factor * factor # Ease-in (Estica exponencialmente com o boost)
		
		target_scale = lerp(0.0, max_trail_length, power_factor)
		target_alpha = lerp(0.0, 0.5, power_factor)
		target_glow = target_alpha * neon_power # O brilho aumenta junto com o tamanho
		
	if is_instance_valid(_left_pivot):
		_left_pivot.scale.z = lerp(_left_pivot.scale.z, target_scale, delta * 12.0)
		
	if is_instance_valid(_right_pivot):
		_right_pivot.scale.z = lerp(_right_pivot.scale.z, target_scale, delta * 12.0)
		
	if is_instance_valid(_material):
		# Interpola a cor...
		_material.albedo_color.a = lerp(_material.albedo_color.a, target_alpha, delta * 15.0)
		# ...E também interpola a força do Neon!
		_material.emission_energy_multiplier = lerp(_material.emission_energy_multiplier, target_glow, delta * 15.0)
