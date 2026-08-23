extends Node
class_name StoryMissionMarkers

var ctrl: Node # Referência ao StoryModeController

func setup(controller: Node):
	ctrl = controller

# Função chamada toda vez que o progresso muda ou a missão inicia
func update_markers():
	if not ctrl.is_mission_running or not ctrl.current_mission:
		force_clear_all_markers()
		return

	match ctrl.current_mission.mission_type:
		StoryMissionData.MissionType.DELIVERY:
			_handle_delivery_rules()
		_:
			# Para as outras missões (Explore, Destroy, Collect), usa a regra genérica
			_handle_generic_rules()

# ====================================================================
# REGRA DE NEGÓCIO: DELIVERY
# ====================================================================
func _handle_delivery_rules():
	var held = ctrl.delivery_items_held
	var delivered = ctrl.delivery_items_delivered
	var meta = int(ctrl.current_mission.base_target_value)
	
	if not ctrl.current_mission.mission_tiers.is_empty():
		for tier in ctrl.current_mission.mission_tiers:
			if tier and delivered < int(tier.target_value):
				meta = int(tier.target_value)
				break
	
	# CORREÇÃO DO DELIVERY: A seta acende se você tiver QUALQUER item na mão (held > 0)
	var can_deliver = held > 0
	var active_nodes = _get_active_portal_nodes()
	
	for pointer in get_tree().get_nodes_in_group("mission_pointers"):
		if not is_instance_valid(pointer): continue
		
		if pointer.pointer_type == "dropoff":
			pointer.visible = can_deliver
		elif pointer.pointer_type == "collectable":
			pointer.visible = true
		elif pointer.pointer_type == "general":
			# Setas gerais no delivery respeitam a lista do portal
			pointer.visible = _is_node_linked(pointer, active_nodes)
		else:
			pointer.visible = true

# ====================================================================
# REGRA DE NEGÓCIO: GENÉRICA (Collect, Explore, Destroy, Gap, Radar)
# ====================================================================
func _handle_generic_rules():
	# Resgata tudo o que o Portal ativou no mapa
	var active_nodes = _get_active_portal_nodes()
	
	for pointer in get_tree().get_nodes_in_group("mission_pointers"):
		if not is_instance_valid(pointer): continue
		
		if pointer.pointer_type == "dropoff":
			pointer.visible = false
			
		elif pointer.pointer_type == "general":
			# A SUA MÁGICA ORIGINAL: Só aparece se a seta (ou o pai dela) estiver no array do Portal!
			pointer.visible = _is_node_linked(pointer, active_nodes)
			
		else:
			pointer.visible = true

# ====================================================================
# HELPERS: FILTRAGEM INTELIGENTE PELO PORTAL (RESTAURADOS!)
# ====================================================================
func _get_active_portal_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	if is_instance_valid(ctrl.active_portal) and "nodes_to_enable" in ctrl.active_portal:
		for path in ctrl.active_portal.nodes_to_enable:
			var n = ctrl.active_portal.get_node_or_null(path)
			if is_instance_valid(n):
				nodes.append(n)
	return nodes

func _is_node_linked(pointer: Node, active_nodes: Array[Node]) -> bool:
	if active_nodes.is_empty(): 
		return false
		
	var current = pointer
	
	while current != null and current != current.get_tree().root:
		if active_nodes.has(current):
			return true
		current = current.get_parent()
		
	return false

# ====================================================================
# HELPER: Controle Geral (Com a trava anti-crash de saída de mapa)
# ====================================================================
func force_clear_all_markers():
	if not is_inside_tree() or not get_tree(): 
		return
		
	for pointer in get_tree().get_nodes_in_group("mission_pointers"):
		if is_instance_valid(pointer):
			pointer.visible = false
