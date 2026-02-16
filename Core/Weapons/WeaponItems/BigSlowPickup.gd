extends Area3D

@export var weapon_to_give : WeaponResource # Arraste o BigSlow.tres aqui no Inspector
@export var rotation_speed : float = 2.0
@export var float_speed : float = 2.0
@export var float_amplitude : float = 0.2

var _start_y : float

func _ready():
	_start_y = position.y
	# Conecta o sinal de colisão
	body_entered.connect(_on_body_entered)

func _process(delta):
	# Efeito visual: Girar e Flutuar (estilo Arcade)
	rotate_y(rotation_speed * delta)
	position.y = _start_y + sin(Time.get_ticks_msec() * 0.001 * float_speed) * float_amplitude

func _on_body_entered(body):
	# Verifica se quem entrou na área é um veículo e tem o WeaponManager
	# Procuramos no 'body' ou nos filhos dele pelo WeaponManager
	var weapon_manager = body.find_child("WeaponManager", true, false)
	
	if weapon_manager and weapon_manager.has_method("equip_special_weapon"):
		if weapon_to_give:
			weapon_manager.equip_special_weapon(weapon_to_give)
			_collect_effect()
		else:
			# Isso vai imprimir o NOME exato do objeto que deu erro e a posição dele no mapa
			print("ERRO: O objeto '", name, "' em ", global_position, " está vazio!")

func _collect_effect():
	# TODO: Tocar um som de "Power Up" aqui
	# Por enquanto, apenas desativa e some
	queue_free()
