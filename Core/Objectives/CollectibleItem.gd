# CollectibleItem.gd
extends Area3D

## O ID deve ser o mesmo do Resource (ex: "briefcase")
@export var collectible_id : String = "briefcase"
## Valor individual (geralmente 1)
@export var value : float = 1.0

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body is BaseVehicle:
		print("Coletou: ", collectible_id)
		
		# Avisa o MissionManager
		if is_instance_valid(MissionManager):
			MissionManager.notify_progress(MissionItem.Type.COLLECT, value, collectible_id)
		
		# Efeito sonoro/partícula aqui antes de sumir
		_collect_effects()
		
		# Remove a maleta do mapa
		queue_free()

func _collect_effects():
	# TODO: Tocar som de "bling"
	pass
