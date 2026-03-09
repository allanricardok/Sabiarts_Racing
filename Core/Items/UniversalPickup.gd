@tool
extends Area3D
class_name UniversalPickup

@export_group("Conteúdo")
## Arraste um WeaponResource OU um StatusResource aqui!
@export var item_data : Resource:
	set(value):
		item_data = value
		if is_inside_tree(): 
			_update_visuals()

@export_group("Animação Arcade")
@export var rotation_speed : float = 2.0
@export var float_speed : float = 2.0
@export var float_amplitude : float = 0.2
@export var preview_animacao: bool = false

var _start_y : float

func _ready():
	_start_y = position.y
	_update_visuals()
	
	if not Engine.is_editor_hint():
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)

func _update_visuals():
	var mesh_inst = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not item_data or not mesh_inst: return
	
	# Verifica se o Resource tem os dados visuais antes de tentar aplicar
	if "custom_mesh" in item_data and item_data.custom_mesh:
		mesh_inst.mesh = item_data.custom_mesh
		
		# --- A CURA DO BUG INVISÍVEL ---
		# Força o manequim a ficar visível não importa como a cena foi salva!
		mesh_inst.visible = true 
		
		if "mesh_scale" in item_data:
			mesh_inst.scale = item_data.mesh_scale
			
		var mat = StandardMaterial3D.new()
		if "item_color" in item_data:
			mat.albedo_color = item_data.item_color
			mat.emission_enabled = true
			mat.emission = item_data.item_color
			mat.emission_energy_multiplier = 0.5
		
		mesh_inst.material_override = mat

func _process(delta):
	if Engine.is_editor_hint() and not preview_animacao:
		_start_y = position.y 
		return
		
	rotate_y(rotation_speed * delta)
	position.y = _start_y + sin(Time.get_ticks_msec() * 0.001 * float_speed) * float_amplitude

func _on_body_entered(body):
	if not item_data: return
	
	var collected = false
	
	# --- CENA 1: É UMA ARMA? ---
	# Duck typing: se o resource tem a variável de arma (ex: 'weapon_id' ou 'damage')
	if item_data is WeaponResource or "weapon_name" in item_data:
		var weapon_manager = body.find_child("WeaponManager", true, false)
		if weapon_manager and weapon_manager.has_method("equip_special_weapon"):
			weapon_manager.equip_special_weapon(item_data)
			collected = true
			
	# --- CENA 2: É UM STATUS (Vida/Escudo)? ---
	elif item_data is StatusResource or "health_amount" in item_data:
		var stats = body.find_child("StatsComponent*", true, false)
		if stats:
			if item_data.health_amount > 0 and stats.has_method("repair"):
				stats.repair(item_data.health_amount)
				collected = true
			if item_data.shield_amount > 0 and stats.has_method("restore_shield"):
				stats.restore_shield(item_data.shield_amount)
				collected = true

	if collected:
		_collect_effect()

func _collect_effect():
	# TODO: Instanciar som e partículas
	queue_free()
