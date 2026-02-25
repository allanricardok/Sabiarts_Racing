# DestructibleProp.gd
extends RigidBody3D

@export_group("Mission Settings")
## Escreva aqui o ID para as missões (ex: barril, enemy_car)
@export var mission_id : String = ""

@export var health : float = 20.0
@export var energy_reward : float = 25.0

func take_damage(amount: float, attacker: Node3D = null):
	if health <= 0: return 
	health -= amount
	
	if attacker:
		var gtm = attacker.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("HIT_OBJECT")
	
	# VFX de piscar...
	
	if health <= 0:
		_morrer(attacker) # Passamos o atacante para a função de morte

func _morrer(attacker: Node3D):
	if attacker:
		# IMPORTANTE: Usar o % para achar o manager no carro que destruiu
		var gtm = attacker.get_node_or_null("%GroundTrickManager")
		if gtm:
			print("OBJETO DESTRUIDO: Pontos para ", attacker.name)
			gtm.add_ground_action("DESTROY_OBJECT")
			# Se este objeto tiver uma etiqueta de missão, avisamos o Manager
			if mission_id != "" and is_instance_valid(MissionManager):
		# O tipo DESTROY no MissionManager vai procurar por este 'mission_id'
				MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
	
	queue_free()
