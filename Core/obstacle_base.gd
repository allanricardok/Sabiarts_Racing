extends RigidBody3D
class_name DestructibleCube

@export var hp: float = 100.0
@onready var explosion_scene = preload("res://new folder/explosao.tscn")

var is_exploding: bool = false # Proteção contra chamadas duplas

func _ready():
	add_to_group("obstacles")

func take_damage(amount: float):
	# Se já está explodindo, ignora qualquer dano extra
	if is_exploding: 
		return
		
	hp -= amount
	print("Cube HP: ", hp, " Damage: ", amount)
	
	if hp <= 0:
		explode()

func explode():
	is_exploding = true # Trava o barril agora!
	
	# 1. Instancia a explosão
	var explosion = explosion_scene.instantiate()
	
	# 2. Adiciona a explosão na cena ANTES de tirar o barril do mapa
	# Usamos a global_position do barril enquanto ele ainda está vivo
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = self.global_position
	
	# 3. Adeus, barril!
	queue_free()
