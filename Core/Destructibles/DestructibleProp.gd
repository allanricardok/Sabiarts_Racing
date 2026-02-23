# DestructibleProp.gd
extends RigidBody3D

@export_group("Mission Settings")
@export var mission_id : String = ""

@export_group("Stats & Rewards")
@export var health : float = 20.0
## Quantos pontos este objeto dá ao ser destruído
@export var points_reward : int = 500
## Se marcado, o objeto recarrega a energia do carro ao morrer
@export var give_energy : bool = true
## Quanto de energia será restaurado no AbilityComponent
@export var energy_reward_amount : float = 25.0

func take_damage(amount: float, attacker: Node3D = null):
	if health <= 0: return 
	health -= amount
	
	if attacker:
		var gtm = attacker.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("HIT_OBJECT")
	
	if health <= 0:
		_morrer(attacker)

func _morrer(attacker: Node3D):
	if attacker:
		# 1. PONTUAÇÃO E MISSÃO
		var gtm = attacker.get_node_or_null("%GroundTrickManager")
		if gtm:
			# Passamos os pontos customizados para o combo
			gtm.add_ground_action("DESTROY_OBJECT", points_reward)
			
			if mission_id != "" and is_instance_valid(MissionManager):
				MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
		
		# 2. RECOMPENSA DE ENERGIA (Agora enviando para o AbilityComponent)
		if give_energy:
			var ability = attacker.get_node_or_null("%AbilityComponent")
			if ability and ability.has_method("add_energy"):
				ability.add_energy(energy_reward_amount)

	# Adicione seu VFX de explosão aqui antes do queue_free
	queue_free()
