extends Area3D
class_name StoryNextMapPortal

## Pontuação necessária para ESTE mapa liberar o portal de avanço.
## Cada cena de mapa configura seu próprio valor aqui, em vez de usar
## um número fixo compartilhado em Global.
@export var points_required: int = 7000

## ID de uma missão (o mesmo "Mission ID" configurado no Mission Data de um
## StoryMissionPortal) que precisa estar completa antes deste portal liberar,
## além da pontuação. Deixe vazio se este mapa não tiver missão obrigatória.
@export var required_mission_id: String = ""

var is_active: bool = false

func _ready():
	add_to_group("next_map_portals")
	body_entered.connect(_on_body_entered)
	
	# Garante que o portal nasça desligado e invisível
	visible = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func activate_portal():
	if not is_active:
		is_active = true
		visible = true
		set_deferred("monitoring", true)
		set_deferred("monitorable", true)
		print("[NextMapPortal] Pontuação atingida! Portal de avanço liberado no mapa.")

# NOVO: chamado pelo StoryModeController a cada checagem, comparando a
# pontuação atual do jogador contra o requisito PRÓPRIO deste portal
# (em vez do controller comparar direto com um valor fixo em Global).
# Também exige, se configurado, que required_mission_id já esteja
# completa em Global.completed_story_missions.
func try_activate(current_points: int) -> void:
	if current_points < points_required:
		return
	
	if required_mission_id != "":
		if not is_instance_valid(Global) or not Global.completed_story_missions.has(required_mission_id):
			return
	
	activate_portal()

func _on_body_entered(body):
	if not is_active: return
	
	if body is BaseVehicle or body.is_in_group("jogadores"):
		# Desliga a colisão para não engatilhar duas vezes
		set_deferred("monitoring", false)
		
		print("[NextMapPortal] Jogador entrou no portal final! Encerrando run...")
		
		# Procura o controlador da fase e engatilha o fim do jogo
		var level_controller = get_tree().get_first_node_in_group("LevelController")
		if level_controller and level_controller.has_method("encerrar_partida"):
			# Podemos despausar caso algo esteja travado e encerramos
			get_tree().paused = false 
			level_controller.encerrar_partida()
		else:
			push_error("[NextMapPortal] ERRO: LevelController não encontrado para encerrar a partida!")
