# LevelController.gd
extends Node

@export var map_missions : MapMissionData

func _ready():
	if map_missions:
		# Inicializa o Singleton com os dados deste mapa
		MissionManager.setup_map(map_missions)
		
		# Exemplo: Conectar o sinal para saber quando uma missão foi feita
		MissionManager.mission_completed.connect(_on_mission_done)
	else:
		print("ERRO: Nenhuma missão configurada no Inspector do LevelController!")

func _on_mission_done(mission: MissionItem):
	# Aqui você pode tocar um som global de 'Sucesso'
	print("LevelController: Interface deve mostrar: ", mission.description)

# Se quiser testar o Gap via código ou monitorar o tempo, faça aqui
