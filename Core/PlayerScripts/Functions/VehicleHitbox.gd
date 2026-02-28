# VehicleHitbox.gd
extends Area3D
class_name VehicleHitbox

func _ready():
	# Conecta os sinais via código para não precisarmos fazer no Inspetor
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _on_body_entered(body):
	# Captura balas físicas (Metralhadora, BigSlow - RigidBody3D)
	if body.has_method("_on_impact"):
		body._on_impact(self)

func _on_area_entered(area):
	# Captura mísseis e outros projéteis em área (Area3D)
	if area.has_method("_on_impact"):
		area._on_impact(self)

# Recebe o dano do projétil e repassa para a raiz (BaseVehicle)
func take_damage(amount: float, attacker: Node = null):
	var main_vehicle = owner if owner else get_parent()
	if main_vehicle and main_vehicle.has_method("take_damage"):
		main_vehicle.take_damage(amount, attacker)
