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
			pointer.visible = true

# ====================================================================
# REGRA DE NEGÓCIO: GENÉRICA (Collect, Explore, Destroy, etc)
# ====================================================================
func _handle_generic_rules():
	for pointer in get_tree().get_nodes_in_group("mission_pointers"):
		if not is_instance_valid(pointer): continue
		
		# A CORREÇÃO ESTÁ AQUI:
		# Se a missão atual NÃO é de Delivery, as bases de entrega NUNCA devem acender!
		if pointer.pointer_type == "dropoff":
			pointer.visible = false
		else:
			# Coletáveis, Alvos ou Gerais podem acender normalmente
			pointer.visible = true

# ====================================================================
# HELPER: Controle Geral
# ====================================================================
func _set_all_pointers_visible(is_visible: bool):
	for pointer in get_tree().get_nodes_in_group("mission_pointers"):
		if is_instance_valid(pointer):
			pointer.visible = is_visible
