extends Area3D

@export var explore_id : String = ""

func _ready():
	# --- A MÁGICA ---
	# Fica invisível para os projéteis, mas continua "vendo" o carro!
	monitorable = false 
	
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body is BaseVehicle:
		print("Lugar Secreto Encontrado: ", explore_id)
		get_tree().call_group("TutorialUI", "complete_task", "cross_map")
		
		# --- NOVO: AVISA A MISSÃO DE EXPLORAÇÃO ---
		if explore_id != "":
			get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.EXPLORE, 1.0, explore_id)
			
		queue_free()
