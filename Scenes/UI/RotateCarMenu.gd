# Anexe isso no nó CarSpawnPoint de cada slot
extends Node3D

@export var rotation_speed: float = 1.0

func _process(delta):
	# Gira o "palco" no eixo Y. Tudo que for filho dele (o carro instanciado) gira junto!
	rotation.y += rotation_speed * delta
