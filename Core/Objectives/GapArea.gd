# GapArea.gd
extends Area3D

@export_group("Mission Config")
## ID que deve bater com o que está no Mission Resource (ex: "gap_balcony")
@export var gap_id : String = "gap_balcony"

@export_group("Display & Score")
## Nome que aparecerá no HUD em azul (ex: "GAP DA SACADA")
@export var gap_name : String = "NICE GAP"
## Pontuação base deste gap
@export var gap_points : int = 500

func _ready():
	# Conecta o sinal de entrada de corpos
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# Verifica se quem entrou foi o carro do jogador
	if body is BaseVehicle:
		_award_gap(body)

func _award_gap(player_vehicle: Node3D):
	# 1. Tenta encontrar o TrickManager para registrar no combo visual
	var trick_manager = player_vehicle.get_node_or_null("%TrickManager")
	if trick_manager:
		# Chamamos a função passando o nome, os pontos e a cor azul (#00aaff)
		# Essa função add_external_action vamos atualizar no próximo script
		trick_manager.add_external_action(gap_name, gap_points, "#00aaff")
	
	# 2. Notifica o MissionManager para marcar o checklist
	if is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.GAP, 1, gap_id)
	
	# 3. Feedback no console para debug
	print("GAP ATINGIDO: ", gap_name, " (+", gap_points, " pts)")
	
	# 4. Desativa o Gap para não contar duas vezes no mesmo pulo/visita
	# Ele será "resetado" se você recarregar a cena ou se você implementar um reset
	monitoring = false 
	
	# Opcional: Efeito sonoro de 'Bling' de Gap aqui
	_play_gap_sound()

func _play_gap_sound():
	# TODO: Tocar som específico de Gap
	pass
