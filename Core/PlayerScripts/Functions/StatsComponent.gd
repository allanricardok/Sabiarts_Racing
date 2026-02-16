# StatsComponent.gd
extends Node
class_name StatsComponent

@export var jump_multiplier: float = 1.0 
var is_invulnerable: bool = false

signal health_depleted
signal shield_broken
signal stats_changed

@export_group("Survival")
@export var max_health: float = 100.0
@export var max_shield: float = 50.0

@onready var current_health: float = max_health
@onready var current_shield: float = max_shield

@export_group("Physics Multipliers")
@export var speed_multiplier: float = 1.0
@export var weight_multiplier: float = 1.0

## Recebe dano e opcionalmente o atacante para crédito de pontos
func take_damage(amount: float, attacker: Node = null):
	if is_invulnerable:
		print("StatsComponent: Dano bloqueado!")
		return
	
	# Lógica de Escudo
	if current_shield > 0:
		var shield_damage = min(current_shield, amount)
		current_shield -= shield_damage
		amount -= shield_damage
		if current_shield <= 0:
			shield_broken.emit()
			print("StatsComponent: Escudo quebrado!")
	
	# Lógica de Vida
	if amount > 0:
		current_health -= amount
		_check_damage_state()
		
	# Lógica de Destruição
	if current_health <= 0:
		if attacker:
			# Tenta encontrar o GroundTrickManager no atacante (ou em seus filhos via Unique Name)
			var g_manager = attacker.get_node_or_null("%GroundTrickManager")
			if g_manager:
				g_manager.add_ground_action("DESTROY_OBJECT")
				print("StatsComponent: Destruição creditada ao atacante: ", attacker.name)
		
		health_depleted.emit()

func _check_damage_state():
	var parent = get_parent()
	if not parent.has_method("update_visual_damage"): return
	
	# Passa a porcentagem para o carro ou objeto decidir o visual
	var percent = (current_health / max_health) * 100
	parent.update_visual_damage(percent)

func heal(amount: float):
	current_health = min(current_health + amount, max_health)
	_check_damage_state()
	stats_changed.emit()

func add_shield(amount: float):
	current_shield = min(current_shield + amount, max_shield)
	stats_changed.emit()
