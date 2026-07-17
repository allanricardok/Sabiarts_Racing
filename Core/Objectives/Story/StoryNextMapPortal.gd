# StoryNextMapPortal.gd
extends Area3D
class_name StoryNextMapPortal

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
