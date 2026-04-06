# SpeedRadar.gd
extends Area3D

## O ID deve ser exatamente o mesmo que você colocou no Resource (ex: "radar_120")
@export var radar_mission_id : String = "radar_120"
## Valor apenas para referência visual no Toast (cor verde se atingido)
@export var target_speed_reference : float = 120.0

func _ready():
	# Garante que o sinal de corpo está conectado (para o BlocoColisao físico)
		
	# MUDANÇA SÊNIOR: Conecta sinal de área para detectar a Hitbox grandona do carro
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
		
	print("[SpeedRadar] Pronto. ID: ", radar_mission_id)

func _on_area_entered(area):
	# Se a área que bateu for a VehicleHitbox, pegamos o carro que é dono dela
	var car = area.owner if area.owner else area.get_parent()
	if car is BaseVehicle:
		_process_radar(car)

func _process_radar(car: BaseVehicle):
	# Pegamos a velocidade em KM/H
	var speed_kmh = car.linear_velocity.length() * 2.3
	
	print("Radar: ", car.name, " passou a ", int(speed_kmh), " km/h")
	
	# Opcional: Dispara o flash da câmera para TODOS que passarem (Players e Bots)
	_visual_flash()
	
	# --- FILTRO DE BOT ---
	# Pega o Input para saber se é a IA dirigindo
	var input = car.get_node_or_null("%InputComponent")
	var is_bot = (input and "is_bot" in input and input.is_bot)
	
	if is_bot:
		return # Se for Bot, paramos a execução aqui. Nada de UI ou Missão!

	# 1. Avisa o MissionManager para checar se batemos a meta da missão (Apenas Jogadores)
	if is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.SPEED, speed_kmh, radar_mission_id)
		
	# 2. FIX MULTIPLAYER: Chama a HUD certa que divide o Viewport com este carro
	var my_hud = null
	for hud in get_tree().get_nodes_in_group("HUD"):
		if hud.get_viewport() == car.get_viewport():
			my_hud = hud
			break
			
	if my_hud and my_hud.has_method("criar_toast"):
		var cor = Color.WHITE
		if speed_kmh >= target_speed_reference:
			cor = Color.GREEN
			# --- NOVO: AVISA A CHECKLIST DO TUTORIAL ---
			get_tree().call_group("TutorialUI", "complete_task", "speedtrap")
		
		my_hud.criar_toast("SPEEDTRAP: " + str(int(speed_kmh)) + " KM/H", cor)

func _visual_flash():
	# TODO: Efeito de luz branca rápida para parecer uma foto de multa
	print("[SpeedRadar] Flash visual disparado.")
