# DestructibleProp.gd
extends RigidBody3D

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
	
	queue_free()
