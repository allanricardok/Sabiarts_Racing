# StatsComponent.gd
extends Node
class_name StatsComponent

@export var jump_multiplier: float = 1.0 # Adicione esta linha!
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

func take_damage(amount: float):
	if is_invulnerable:
		print("Dano bloqueado pelo escudo!")
		return
	if current_shield > 0:
		var shield_damage = min(current_shield, amount)
		current_shield -= shield_damage
		amount -= shield_damage
		if current_shield <= 0: shield_broken.emit()
	
	if amount > 0:
		current_health -= amount
		_check_damage_state() # Aqui chamamos a troca de skin do carro
		
	if current_health <= 0:
		health_depleted.emit()

func _check_damage_state():
	var parent = get_parent()
	if not parent.has_method("update_visual_damage"): return
	
	# Passa a porcentagem para o carro decidir qual mesh usar
	var percent = (current_health / max_health) * 100
	parent.update_visual_damage(percent)

func repair(amount: float):
	current_health = clamp(current_health + amount, 0, max_health)
	_check_damage_state()
