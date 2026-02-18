# GapArea.gd
extends Area3D

## O ID deve ser o mesmo do Resource (ex: "gap_balcony")
@export var gap_id : String = "gap_balcony"
## Se 'true', o jogador precisa ter feito pelo menos 1 manobra para o gap contar
@export var require_stunt : bool = true 

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body is BaseVehicle:
		# Checamos o TrickManager do carro para ver se ele está no ar
		var trick_manager = body.get_node_or_null("%TrickManager")
		
		if trick_manager and trick_manager.tracking_jump:
			var can_award = true
			
			# Se o gap exige manobra, checamos se a lista de manobras não está vazia
			if require_stunt and trick_manager.tricks_done.size() == 0:
				can_award = false
			
			if can_award:
				print("GAP CONCLUÍDO: ", gap_id)
				# Registra o progresso no MissionManager
				if is_instance_valid(MissionManager):
					MissionManager.notify_progress(MissionItem.Type.GAP, 1, gap_id)
				
				# Opcional: Avisar ao TrickManager para somar pontos extras pelo Gap
				trick_manager.add_external_action("GAP: " + gap_id, 500)
