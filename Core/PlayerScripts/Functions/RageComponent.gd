# RageComponent.gd
extends Node
class_name RageComponent

signal rage_updated(rage_value: float, tier: int, t3_timer: float)
signal tier_changed(new_tier: int)

var current_rage : float = 0.0
var current_tier : int = 0
var tier3_timer : float = 0.0

const DRAIN_RATE : float = 1.0

# --- SISTEMA DE ANTI-SPAM (DIMINISHING RETURNS) ---
var _last_hit_target: Node = null
var _consecutive_hits: int = 0

func _process(delta):
	if current_tier == 3:
		tier3_timer -= delta
		if tier3_timer <= 0:
			current_rage = 285.0 
			_update_tier()
	else:
		if current_rage > 0:
			current_rage -= DRAIN_RATE * delta
			if current_rage < 0: current_rage = 0
			_update_tier()
			
	rage_updated.emit(current_rage, current_tier, tier3_timer)

# --- FUNÇÕES DE GANHO DE RAGE ---

func add_hit(target: Node = null):
	var hit_value = 1.0
	
	if is_instance_valid(target):
		if target == _last_hit_target:
			_consecutive_hits += 1
		else:
			_last_hit_target = target
			_consecutive_hits = 0
			
		# Calcula a penalidade de 10% (0.1) por acerto consecutivo. 
		# O max(0.1, ...) garante que o valor nunca caia pra zero ou negativo.
		var decay_multiplier = max(0.1, 1.0 - (_consecutive_hits * 0.05))
		hit_value *= decay_multiplier
		
		# (Opcional) Descomente a linha abaixo se quiser ver a matemática no Output
		# print("[RAGE ANTI-SPAM] Acerto no mesmo alvo: ", _consecutive_hits, " | Valor ganho: ", hit_value)
	else:
		# Se por acaso a função for chamada sem alvo, reseta a memória
		_last_hit_target = null
		_consecutive_hits = 0
		
	_add_rage(hit_value)

func add_collision_damage(amount: float):
	_add_rage(amount * 0.5)

func add_trick(count: int):
	_add_rage(float(count))

func _add_rage(base_amount: float):
	if current_tier == 3:
		tier3_timer = 5.0 
		return
		
	var multiplier = 1.0
	if current_rage < 100: multiplier = 2.0
	elif current_rage < 200: multiplier = 1.5
		
	current_rage += (base_amount * multiplier)
	
	if current_rage >= 300:
		current_rage = 300
		tier3_timer = 5.0 
		
	_update_tier()

func _update_tier():
	var old_tier = current_tier
	
	if current_rage >= 300: current_tier = 3
	elif current_rage >= 200: current_tier = 2
	elif current_rage >= 100: current_tier = 1
	else: current_tier = 0
	
	if current_tier != old_tier:
		tier_changed.emit(current_tier)

# --- GETTERS DE BUFFS (Para outros scripts lerem) ---

func get_score_mult() -> float:
	match current_tier:
		1: return 1.2
		2: return 1.4
		3: return 1.5
		_: return 1.0

func get_damage_mult() -> float:
	match current_tier:
		1: return 1.1
		2: return 1.2
		3: return 1.3
		_: return 1.0

func get_speed_mult() -> float:
	match current_tier:
		2: return 1.2
		3: return 1.4
		_: return 1.0

func get_impact_mult() -> float:
	match current_tier:
		2: return 1.2
		3: return 1.4
		_: return 1.0

func get_fire_rate_mult() -> float:
	return 1.5 if current_tier == 3 else 1.0
