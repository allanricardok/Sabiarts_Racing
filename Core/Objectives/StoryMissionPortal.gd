# StoryMissionPortal.gd
extends Area3D
class_name StoryMissionPortal

@export var mission_data: StoryMissionData
var is_active: bool = true

func _ready():
	add_to_group("mission_portals")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if not is_active: return
	
	if body.is_in_group("jogadores"):
		if not mission_data:
			push_error("[StoryPortal] Portal sem Mission Data configurado!")
			return
		
		# Desativa temporariamente a colisão para não disparar duas vezes seguidas
		set_deferred("monitoring", false)
		# Dispara a missão de forma segura no próximo frame livre da engine
		_trigger_mission.call_deferred()

func _trigger_mission():
	print("[StoryPortal] Jogador entrou no portal da missão: ", mission_data.mission_name)
	
	# Encontra o controlador do Modo História que colocamos na raiz do jogo
	var story_controller = get_tree().get_first_node_in_group("StoryController")
	if story_controller:
		# Pausa o jogo primeiro
		get_tree().paused = true
		# Entrega os dados para o controlador abrir a interface
		story_controller.request_mission_start(self, mission_data)
	else:
		push_error("[StoryPortal] StoryModeController não foi encontrado na raiz da cena!")
		# Reativa o monitoramento caso falhe
		set_deferred("monitoring", true)
