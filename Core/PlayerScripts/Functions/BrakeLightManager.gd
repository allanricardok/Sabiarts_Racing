# BrakeLightManager.gd
extends Node
class_name BrakeLightManager

@export_group("Referências")
@export var left_taillight: MeshInstance3D
@export var right_taillight: MeshInstance3D

@export_group("Cores e Brilho")
@export var color_idle: Color = Color("8b0000") 
@export var energy_idle: float = 0.0

@export var color_brake: Color = Color("ff0000") 
@export var energy_brake: float = 20.0

var _left_mat: StandardMaterial3D
var _right_mat: StandardMaterial3D

@onready var car = owner as VehicleBody3D
@onready var input = car.get_node_or_null("%InputComponent")

func _ready():
	if left_taillight:
		_left_mat = _setup_material(left_taillight)
	if right_taillight:
		_right_mat = _setup_material(right_taillight)

func _setup_material(mesh_inst: MeshInstance3D) -> StandardMaterial3D:
	var mat = mesh_inst.get_active_material(0)
	
	if mat:
		mat = mat.duplicate()
	else:
		mat = StandardMaterial3D.new()
		
	mat.emission_enabled = true
	mesh_inst.set_surface_override_material(0, mat)
	
	return mat as StandardMaterial3D

func _process(delta):
	if not is_instance_valid(car) or not is_instance_valid(input): return
	
	var is_braking = false
	
	# === LÊ APENAS O DEDO DO JOGADOR NO CONTROLE/TECLADO ===
	# Verifica se a variável booleana direta de freio está ativa
	if "is_braking" in input and input.is_braking:
		is_braking = true
	# Ou verifica se o eixo do acelerador (throttle) está sendo puxado para trás (freio/ré)
	elif "throttle" in input and input.throttle < -0.1:
		is_braking = true
		
	var target_color = color_brake if is_braking else color_idle
	var target_energy = energy_brake if is_braking else energy_idle
	
	var lerp_speed = 18.0 * delta
	
	if is_instance_valid(_left_mat):
		_left_mat.albedo_color = _left_mat.albedo_color.lerp(target_color, lerp_speed)
		_left_mat.emission = _left_mat.emission.lerp(target_color, lerp_speed)
		_left_mat.emission_energy_multiplier = lerp(_left_mat.emission_energy_multiplier, target_energy, lerp_speed)
		
	if is_instance_valid(_right_mat):
		_right_mat.albedo_color = _right_mat.albedo_color.lerp(target_color, lerp_speed)
		_right_mat.emission = _right_mat.emission.lerp(target_color, lerp_speed)
		_right_mat.emission_energy_multiplier = lerp(_right_mat.emission_energy_multiplier, target_energy, lerp_speed)
