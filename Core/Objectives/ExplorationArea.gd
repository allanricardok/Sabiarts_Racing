# ExplorationArea.gd
extends Area3D

## ID da missão de exploração no Resource (ex: "secret_place")
@export var explore_id : String = ""

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body is BaseVehicle:
		if is_instance_valid(MissionManager):
			# Avisa o Manager que o lugar foi explorado
			MissionManager.notify_progress(MissionItem.Type.EXPLORE, 1.0, explore_id)
		
		# Opcional: Efeito visual/sonoro de descoberta aqui
		print("Lugar Secreto Encontrado: ", explore_id)
		
		# Remove a área para não disparar novamente
		queue_free()
