extends Node
class_name RageComponent

signal rage_updated(rage_value: float, tier: int, t3_timer: float)
signal tier_changed(new_tier: int)

var current_rage : float = 0.0
var current_tier : int = 0
var tier3_timer : float = 0.0

@export_group("Configuração Geral")
@export var DRAIN_RATE : float = 1.0
@export var TIER3_DURATION : float = 8.0

@export_group("Ganhos Base (Rage)")
@export var base_hit_object_rage : float = 1.0
@export var base_hit_character_rage : float = 3.0
@export var collision_damage_multiplier : float = 0.6
@export var trick_count_multiplier : float = 4.0
@export var special_weapon_damage_multiplier : float = 0.8

@export_group("Multiplicadores de Catch-up")
@export var catchup_mult_tier0 : float = 2.0
@export var catchup_mult_tier1 : float = 1.5
@export var catchup_mult_tier2 : float = 1.0

# --- SISTEMA DE ANTI-SPAM (DIMINISHING RETURNS) ---
var _last_hit_target: Node = null
var _consecutive_hits: int = 0
var _ui_update_timer : float = 0.0

func _process(delta):
	var needs_ui_update = false
	
	if current_tier == 3:
		tier3_timer -= delta
		needs_ui_update = true 
		
		if tier3_timer <= 0:
			current_rage = 285.0 
			_update_tier()
	else:
		if current_rage > 0:
			current_rage -= DRAIN_RATE * delta
			if current_rage < 0: current_rage = 0
			needs_ui_update = true 
			_update_tier()
			
	if needs_ui_update:
		_ui_update_timer -= delta
		if _ui_update_timer <= 0:
			_ui_update_timer = 0.05
			rage_updated.emit(current_rage, current_tier, tier3_timer)

# --- FUNÇÕES DE GANHO DE RAGE ---

func add_hit(target: Node = null, damage_dealt: float = 0.0, is_special: bool = false):
	if is_instance_valid(target) and target.is_in_group("ignorar_rage"):
		return
		
	var hit_value = base_hit_object_rage
	
	if is_instance_valid(target):
		if target.is_in_group("jogadores") or target.is_in_group("inimigos"):
			hit_value = base_hit_character_rage
			
		if target == _last_hit_target:
			_consecutive_hits += 1
		else:
			_last_hit_target = target
			_consecutive_hits = 0
			
		var decay_multiplier = max(0.1, 1.0 - (_consecutive_hits * 0.05))
		hit_value *= decay_multiplier
		
		if is_special:
			hit_value += (damage_dealt * special_weapon_damage_multiplier)
			
	else:
		_last_hit_target = null
		_consecutive_hits = 0
		
	_add_rage(hit_value)

func add_collision_damage(amount: float):
	_add_rage(amount * collision_damage_multiplier)

func add_trick(count: int):
	_add_rage(float(count) * trick_count_multiplier)

func _add_rage(base_amount: float):
	if current_tier == 3:
		tier3_timer = TIER3_DURATION 
		return
		
	var multiplier = catchup_mult_tier2
	if current_rage < 100: multiplier = catchup_mult_tier0
	elif current_rage < 200: multiplier = catchup_mult_tier1
		
	current_rage += (base_amount * multiplier)
	
	if current_rage >= 300:
		current_rage = 300
		tier3_timer = TIER3_DURATION 
		
	_update_tier()
	
	rage_updated.emit(current_rage, current_tier, tier3_timer)
	_ui_update_timer = 0.05

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

func get_ability_recovery_mult() -> float:
	match current_tier:
		2: return 1.2
		3: return 1.5
		_: return 1.0
