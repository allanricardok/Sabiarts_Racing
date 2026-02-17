# SpeedRadar.gd
extends Area3D

## O ID deve ser exatamente o mesmo que você colocou no Resource (ex: "radar_120")
@export var radar_mission_id : String = "radar_120"

func _ready():
	# Garante que o sinal está conectado
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body is BaseVehicle:
		# Pegamos a velocidade em KM/H (linear_velocity.length() * 2 no seu sistema)
		var speed_kmh = body.linear_velocity.length() * 2
		
		print("Radar: ", body.name, " passou a ", int(speed_kmh), " km/h")
		
		# Avisa o MissionManager para checar se batemos a meta
		if is_instance_valid(MissionManager):
			MissionManager.notify_progress(MissionItem.Type.SPEED, speed_kmh, radar_mission_id)
			
		# Opcional: Aqui você pode disparar um efeito de "Flash" de câmera no radar
		_visual_flash()

func _visual_flash():
	# TODO: Efeito de luz branca rápida para parecer uma foto de multa
	pass
