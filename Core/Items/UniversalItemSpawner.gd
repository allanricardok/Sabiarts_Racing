extends Node3D
class_name ItemSpawner

@export_group("Configuração do Spawner")
## A cena base do UniversalPickup.tscn
@export var pickup_scene : PackedScene 
@export var respawn_time : float = 15.0

@export_group("Loot / Recompensas")
## SE VOCÊ QUER UM ITEM ESPECÍFICO: Coloque o .tres dele aqui.
@export var specific_item : Resource
## SE VOCÊ QUER ALEATÓRIO: Deixe o specific_item vazio e adicione .tres aqui!
@export var random_pool : Array[Resource]

var current_pickup : Node3D = null
var timer : float = 0.0

func _process(delta):
	if not pickup_scene: return
	
	# Se já tem um item vivo na base, não spawna outro e trava o timer
	if is_instance_valid(current_pickup):
		return
		
	# Se o item foi pego, começa a contar o tempo de respawn
	timer -= delta
	if timer <= 0:
		_spawn_item()
		timer = respawn_time

func _spawn_item():
	var resource_to_give = null
	
	# 1. Tenta pegar o item específico
	if specific_item:
		resource_to_give = specific_item
	# 2. Se não tem específico, sorteia um do Pool!
	elif random_pool.size() > 0:
		resource_to_give = random_pool.pick_random()
		
	if not resource_to_give:
		return # Spawner não configurado
		
	# Cria a caixa genérica
	current_pickup = pickup_scene.instantiate()
	current_pickup.position = self.global_position
	
	# INJETA O DADO! A mágica acontece aqui.
	current_pickup.item_data = resource_to_give
	
	get_tree().current_scene.add_child(current_pickup)
