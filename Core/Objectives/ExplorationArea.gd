# ExplorationArea.gd
extends Area3D

@export var explore_id : String = ""

func _ready():
	# --- A MÁGICA ---
	# Fica invisível para os projéteis, mas continua "vendo" o carro!
	monitorable = false 
	
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body is BaseVehicle:
		if is_instance_valid(MissionManager):
			MissionManager.notify_progress(MissionItem.Type.EXPLORE, 1.0, explore_id)
		
		print("Lugar Secreto Encontrado: ", explore_id)
		get_tree().call_group("TutorialUI", "complete_task", "cross_map")
		queue_free()
