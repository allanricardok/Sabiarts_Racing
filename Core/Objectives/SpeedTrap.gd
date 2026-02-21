# SpeedRadar.gd
extends Area3D

## O ID deve ser exatamente o mesmo que você colocou no Resource (ex: "radar_120")
@export var radar_mission_id : String = "radar_120"
## Valor apenas para referência visual no Toast (cor verde se atingido)
@export var target_speed_reference : float = 120.0

func _ready():
	# Garante que o sinal está conectado
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	print("[SpeedRadar] Pronto. ID: ", radar_mission_id)

func _on_body_entered(body):
	if body is BaseVehicle:
		# Pegamos a velocidade em KM/H (linear_velocity.length() * 2 no seu sistema)
		var speed_kmh = body.linear_velocity.length() * 2
		
		print("Radar: ", body.name, " passou a ", int(speed_kmh), " km/h")
		
		# 1. Avisa o MissionManager para checar se batemos a meta da missão
		if is_instance_valid(MissionManager):
			MissionManager.notify_progress(MissionItem.Type.SPEED, speed_kmh, radar_mission_id)
			
		# 2. Chama a HUD para mostrar a velocidade no Toast SEMPRE
		var hud = get_tree().get_first_node_in_group("HUD")
		if hud and hud.has_method("criar_toast"):
			var cor = Color.WHITE
			if speed_kmh >= target_speed_reference:
				cor = Color.GREEN
			
			hud.criar_toast("SPEEDTRAP: " + str(int(speed_kmh)) + " KM/H", cor)
		
		# Opcional: Aqui você pode disparar um efeito de "Flash" de câmera no radar
		_visual_flash()

func _visual_flash():
	# TODO: Efeito de luz branca rápida para parecer uma foto de multa
	print("[SpeedRadar] Flash visual disparado.")
