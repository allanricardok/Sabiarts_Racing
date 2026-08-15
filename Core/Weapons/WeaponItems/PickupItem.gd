extends Area3D
class_name PickupItem

@export_group("Conteúdo")
@export var weapon_to_give : WeaponResource 
@export var custom_mesh : Mesh 
@export var mesh_scale : Vector3 = Vector3.ONE
## Cor única para este tipo de item (não afetará outros que usem cores diferentes)
@export var item_color : Color = Color.WHITE

@export_group("Animação Arcade")
@export var rotation_speed : float = 2.0
@export var float_speed : float = 2.0
@export var float_amplitude : float = 0.2

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

var _start_y : float

func _ready():
	_start_y = position.y
	_update_visuals()
	
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _update_visuals():
	if not mesh_instance or not custom_mesh: return
	
	# 1. Define o mesh (compartilhado entre todos)
	mesh_instance.mesh = custom_mesh
	mesh_instance.scale = mesh_scale
	
	# ====================================================================
	# 2. O PULO DO GATO OTIMIZADO: Material Override
	# Puxamos o material base da memória e duplicamos para alterar a cor
	# isoladamente sem engasgar a engine compilando um shader do zero.
	# ====================================================================
	var cached_mat = MaterialCache.get_mat("WeaponPickupBase")
	var mat: StandardMaterial3D
	
	if cached_mat:
		mat = cached_mat.duplicate()
	else:
		mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 0.5
		
	mat.albedo_color = item_color
	mat.emission = item_color
	
	mesh_instance.material_override = mat

func _process(delta):
	rotate_y(rotation_speed * delta)
	position.y = _start_y + sin(Time.get_ticks_msec() * 0.001 * float_speed) * float_amplitude

func _on_body_entered(body):
	var weapon_manager = body.find_child("WeaponManager", true, false)
	if weapon_manager and weapon_manager.has_method("equip_special_weapon"):
		if weapon_to_give:
			weapon_manager.equip_special_weapon(weapon_to_give)
			_collect_effect()
		else:
			push_error("ERRO: O objeto '" + name + "' não tem um WeaponResource!")

func _collect_effect():
	# TODO: Efeito de coleta
	queue_free()
