# StatusChangerPickup.gd
extends Area3D
class_name StatusChangerPickup

@export_group("Efeitos de Status")
## Quantidade de vida a curar (0 = não cura)
@export var health_amount: float = 0.0
## Quantidade de escudo a restaurar (0 = não restaura)
@export var shield_amount: float = 0.0

@export_group("Visual")
@export var custom_mesh : Mesh 
@export var mesh_scale : Vector3 = Vector3.ONE
## Cor da malha e do brilho (Ex: Verde para Vida, Azul para Escudo)
@export var item_color : Color = Color.GREEN

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
	
	mesh_instance.mesh = custom_mesh
	mesh_instance.scale = mesh_scale
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = item_color
	mat.emission_enabled = true
	mat.emission = item_color
	mat.emission_energy_multiplier = 0.5
	
	mesh_instance.material_override = mat

func _process(delta):
	rotate_y(rotation_speed * delta)
	position.y = _start_y + sin(Time.get_ticks_msec() * 0.001 * float_speed) * float_amplitude

func _on_body_entered(body):
	# Procura o StatsComponent no carro que encostou
	var stats = body.find_child("StatsComponent*", true, false)
	
	if stats:
		var applied_effect = false
		
		# Se o item dá vida, chama a função repair
		if health_amount > 0 and stats.has_method("repair"):
			stats.repair(health_amount)
			applied_effect = true
			
		# Se o item dá escudo, chama a função restore_shield
		if shield_amount > 0 and stats.has_method("restore_shield"):
			stats.restore_shield(shield_amount)
			applied_effect = true
			
		# Se o carro pegou pelo menos um benefício, deletamos o item
		if applied_effect:
			_collect_effect()

func _collect_effect():
	# TODO: Instanciar som de cura ou partículas de "+ Vida"
	print("[Pickup] Item de Status coletado!")
	queue_free()
