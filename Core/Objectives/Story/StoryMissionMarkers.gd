extends Node

var ctrl: Node # Referência ao StoryModeController

func setup(controller: Node):
	ctrl = controller

# Função chamada toda vez que o progresso muda ou a missão inicia
func update_markers():
	if not ctrl.is_mission_running or not ctrl.current_mission:
		_set_all_pointers_visible(false)
		return

	match ctrl.current_mission.mission_type:
		StoryMissionData.MissionType.DELIVERY:
			_handle_delivery_rules()
		_:
			# Para as outras missões (Explore, Destroy, Collect), usa a regra inteligente
			_handle_generic_rules()

# ====================================================================
# REGRA DE NEGÓCIO: DELIVERY
# ====================================================================
func _handle_delivery_rules():
	var held = ctrl.delivery_items_held
	var delivered = ctrl.delivery_items_delivered

	# Descobre qual é o total de itens (meta) que a missão exige
	var meta = int(ctrl.current_mission.base_target_value)

	if not ctrl.current_mission.mission_tiers.is_empty():
		for tier in ctrl.current_mission.mission_tiers:
			if tier and delivered < int(tier.target_value):
				meta = int(tier.target_value)
				break

	# A base de entrega só acende se a soma do que você tem na mão 
	# com o que já foi entregue for maior ou igual à meta
	var can_deliver = (held + delivered) >= meta 

	for pointer in get_tree().get_nodes_in_group("mission_pointers"):
		if not is_instance_valid(pointer): continue

		if pointer.pointer_type == "dropoff":
			pointer.visible = can_deliver
		elif pointer.pointer_type == "collectable":
			pointer.visible = true
		else:
			pointer.visible = false # Apaga qualquer outra seta (fantasmas)

# ====================================================================
# REGRA DE NEGÓCIO: GENÉRICA (Collect, Explore, Destroy, etc)
# ====================================================================
func _handle_generic_rules():
	var current_mission_type = ctrl.current_mission.mission_type
	
	for pointer in get_tree().get_nodes_in_group("mission_pointers"):
		if not is_instance_valid(pointer): continue

		# 1. Começa apagando TUDO por padrão para esconder fantasmas
		pointer.visible = false 
		
		# 2. Acende APENAS o ponteiro que combina com o tipo de missão ativa!
		# (Verifique se os nomes dos pointer_type batem exatamente com as strings do seu jogo)
		
		if current_mission_type == StoryMissionData.MissionType.DEFEND and pointer.pointer_type == "defend":
			pointer.visible = true
			
		elif current_mission_type == StoryMissionData.MissionType.DESTROY and pointer.pointer_type == "destroy":
			pointer.visible = true
			
		elif current_mission_type == StoryMissionData.MissionType.COLLECT and pointer.pointer_type == "collectable":
			pointer.visible = true
			
		elif current_mission_type == StoryMissionData.MissionType.EXPLORE and pointer.pointer_type == "explore":
			pointer.visible = true

# ====================================================================
# HELPER: Controle Geral
# ====================================================================
func _set_all_pointers_visible(is_visible: bool):
	for pointer in get_tree().get_nodes_in_group("mission_pointers"):
		if is_instance_valid(pointer):
			pointer.visible = is_visible
