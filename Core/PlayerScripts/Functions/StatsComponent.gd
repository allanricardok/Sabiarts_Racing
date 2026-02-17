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

# --- TRAVA DE SEGURANÇA POR COLISOR ---
var _hit_history: Dictionary = {}

## Recebe dano e o objeto que causou a batida (source)
func take_damage(amount: float, source: Node = null):
	# Se o objeto já estiver morto, ignora novos hits
	if current_health <= 0: 
		return

	# REGRA: Trava de 1 segundo para o MESMO objeto que encostou
	if source:
		var id = source.get_instance_id()
		var now = Time.get_ticks_msec()
		
		if _hit_history.has(id):
			if now - _hit_history[id] < 1000: # 1000ms = 1 segundo
				return # Bloqueia hits repetidos deste colisor específico
		
		# Registra o tempo do hit para este colisor
		_hit_history[id] = now

	if is_invulnerable:
		return
		
	# Lógica de Escudo
	if current_shield > 0:
		var shield_damage = min(current_shield, amount)
		current_shield -= shield_damage
		amount -= shield_damage
		if current_shield <= 0: 
			shield_broken.emit()
	
	# Lógica de Vida
	if amount > 0:
		current_health -= amount
		_check_damage_state()
		
		# --- GERAÇÃO DE PONTUAÇÃO ---
		if source:
			_process_scoring(source)
		
	if current_health <= 0:
		health_depleted.emit()

func _process_scoring(source: Node):
	# Tenta encontrar quem é o atacante (se for bala, pega o shooter/carro)
	var attacker = source
	if "shooter" in source and source.shooter != null:
		attacker = source.shooter
	
	# Procura o manager de manobras no atacante
	var g_manager = attacker.get_node_or_null("%GroundTrickManager")
	if g_manager:
		# Adiciona o hit no multiplicador
		g_manager.add_ground_action("HIT_OBJECT")
		
		# Se o golpe foi o fatal, adiciona bônus de destruição
		if current_health <= 0:
			g_manager.add_ground_action("DESTROY_OBJECT")

func _check_damage_state():
	var parent = get_parent()
	if not parent.has_method("update_visual_damage"): return
	
	var percent = (current_health / max_health) * 100
	parent.update_visual_damage(percent)

func repair(amount: float):
	current_health = clamp(current_health + amount, 0, max_health)
	_check_damage_state()
