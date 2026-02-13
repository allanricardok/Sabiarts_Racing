# DestructibleProp.gd
extends RigidBody3D

@export var health : float = 20.0
@export var energy_reward : float = 25.0 # Quanta energia ele devolve

func take_damage(amount):
	health -= amount
	
	# Feedback visual (Piscar transparência)
	var tween = create_tween()
	var mesh = $MeshInstance3D
	tween.tween_property(mesh, "transparency", 0.8, 0.05)
	tween.tween_property(mesh, "transparency", 0.0, 0.05)
	
	if health <= 0:
		_morrer()

func _morrer():
	# 1. Procuramos o jogador mais próximo para dar a recompensa 
	# (Ou você pode passar quem atirou via argumento no take_damage)
	var players = get_tree().get_nodes_in_group("jogadores")
	for p in players:
		if p.global_position.distance_to(global_position) < 20.0:
			if p.has_node("AbilityComponent"):
				p.get_node("AbilityComponent").adicionar_energia(energy_reward)
	
	# 2. Efeito de sumir
	queue_free()
