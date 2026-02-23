# CollectibleItem.gd (Script genérico para itens)
extends Area3D

@export var mission_id: String = "briefcase" # Deve bater com o ID no Resource
@export var score_points: int = 500

func _ready():
	# Espera um frame para garantir que o MissionManager carregou o save
	await get_tree().process_frame
	
	# Se a missão deste item já foi concluída no passado, o item se remove da cena
	if MissionManager.is_mission_completed(mission_id):
		print("[Item] Missão '", mission_id, "' já está completa. Removendo item do mapa.")
		queue_free()
		return

	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body is BaseVehicle:
		_collect()

func _collect():
	print("[Item] Coletou: ", mission_id)

	# Notifica o MissionManager
	MissionManager.notify_progress(MissionItem.Type.COLLECT, 1.0, mission_id)
	
	# Efeito visual/sonoro antes de sumir
	# spawn_particles()
	
	queue_free()
