# StatsComponent.gd
extends Node
class_name StatsComponent

@export var jump_multiplier: float = 1.0 
var is_invulnerable: bool = false

signal health_depleted(attacker: Node)
signal shield_broken
signal stats_changed
signal took_damage(attacker: Node)

@export_group("Combat Multipliers")
@export var damage_received_multiplier: float = 1.0
@export var damage_dealt_multiplier: float = 1.0

@export_group("Survival")
@export var max_health: float = 100.0
@export var max_shield: float = 50.0

@onready var current_health: float = max_health
@onready var current_shield: float = max_shield

@export_group("UI Integration")
@export var health_bar : ProgressBar
@export var shield_bar : ProgressBar

# ==========================================
# VARIÁVEIS DO SISTEMA DE CURA POR MANOBRA
# ==========================================
@export_group("Heal By Score")
@export var HEAL_SCORE_MAX: float = 5000.0   
@export var HEAL_AMOUNT: float = 5.0         
@export var HEAL_COOLDOWN_MAX: float = 5.0   

var heal_score_current: float = 0.0
var heal_cooldown_timer: float = 0.0

var heal_score_bar: Range
var score_cooldown_bar: Range
var cooldown_label: Label
var heal_score_text: Label
# ==========================================

@export_group("Physics Multipliers")
@export var speed_multiplier: float = 1.0
@export var weight_multiplier: float = 1.0

@export_group("Mission Settings")
@export var mission_id : String = ""

var _health_stylebox : StyleBoxFlat = null
var has_teleportkey : bool = false

func _ready():
	_initialize_ui()
	call_deferred("_auto_link_hud")

func _auto_link_hud():
	if health_bar and shield_bar and heal_score_bar:
		return
		
	var my_viewport = get_viewport()
	
	if not health_bar:
		health_bar = my_viewport.find_child("HealthBar", true, false) as ProgressBar
	if not shield_bar:
		shield_bar = my_viewport.find_child("ShieldBar", true, false) as ProgressBar
		
	if not heal_score_bar:
		heal_score_bar = my_viewport.find_child("HealthScoreBar", true, false) as Range
	if not score_cooldown_bar:
		score_cooldown_bar = my_viewport.find_child("ScoreCooldown", true, false) as Range
	if not cooldown_label:
		cooldown_label = my_viewport.find_child("CooldownText2", true, false) as Label
	if not heal_score_text:
		heal_score_text = my_viewport.find_child("ScoreText", true, false) as Label

	if heal_score_bar:
		heal_score_bar.max_value = HEAL_SCORE_MAX
		heal_score_bar.value = 0.0
		
	if score_cooldown_bar:
		score_cooldown_bar.visible = true
		score_cooldown_bar.max_value = HEAL_COOLDOWN_MAX
		score_cooldown_bar.value = 0.0
		
	if health_bar or shield_bar:
		_initialize_ui()

func _initialize_ui():
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
		
		var current_style = health_bar.get_theme_stylebox("fill")
		if current_style is StyleBoxFlat:
			_health_stylebox = current_style.duplicate()
		else:
			_health_stylebox = StyleBoxFlat.new()
			_health_stylebox.corner_radius_top_left = 4
			_health_stylebox.corner_radius_top_right = 4
			_health_stylebox.corner_radius_bottom_right = 4
			_health_stylebox.corner_radius_bottom_left = 4
			
		health_bar.add_theme_stylebox_override("fill", _health_stylebox)
		
	if shield_bar:
		shield_bar.max_value = max_shield
		shield_bar.value = current_shield

func _process(delta):
	if heal_cooldown_timer > 0:
		heal_cooldown_timer -= delta
		
	_update_ui_bars()

func _update_ui_bars():
	if health_bar:
		health_bar.value = lerp(health_bar.value, current_health, 0.2)
		var pct = (health_bar.value / max_health) * 100.0
		var current_color = _get_health_color(pct)
		if _health_stylebox: _health_stylebox.bg_color = current_color
		else: health_bar.modulate = current_color
			
	if shield_bar:
		shield_bar.value = lerp(shield_bar.value, current_shield, 0.2)
		
	if heal_score_bar:
		heal_score_bar.min_value = 0.0
		heal_score_bar.max_value = HEAL_SCORE_MAX
		heal_score_bar.step = 0.0 
		heal_score_bar.value = heal_score_current
		
	if heal_score_text:
		var current_str = ScoreManager.format_score_with_dots(int(heal_score_current))
		var max_str = ScoreManager.format_score_with_dots(int(HEAL_SCORE_MAX))
		heal_score_text.text = current_str + " / " + max_str
		
	if score_cooldown_bar:
		score_cooldown_bar.max_value = HEAL_COOLDOWN_MAX
		score_cooldown_bar.value = heal_cooldown_timer
		
	if heal_cooldown_timer > 0:
		if cooldown_label:
			cooldown_label.visible = true
			cooldown_label.text = str(ceil(heal_cooldown_timer)) + "s"
	else:
		if cooldown_label: 
			cooldown_label.visible = true
			cooldown_label.text = "Cooldown"

# =========================================================
# FUNÇÕES DE PONTUAÇÃO, CURA E ANIMAÇÕES
# =========================================================
func add_heal_score(amount: int):
	if heal_cooldown_timer > 0: return 
		
	heal_score_current += amount
	_shake_score_bar() # Treme a barrinha!
	
	if heal_score_current >= HEAL_SCORE_MAX:
		heal_score_current = 0.0 
		heal_cooldown_timer = HEAL_COOLDOWN_MAX 
		repair(HEAL_AMOUNT) 

func _shake_score_bar():
	if not is_instance_valid(heal_score_bar): return
	
	# Salva a posição original no primeiro tremor para a UI não fugir do lugar
	if not heal_score_bar.has_meta("base_pos_x"):
		heal_score_bar.set_meta("base_pos_x", heal_score_bar.position.x)
		
	var base_x = heal_score_bar.get_meta("base_pos_x")
	
	# Se já estiver tremendo, mata o tremor antigo antes de iniciar o novo
	if heal_score_bar.has_meta("shake_tween"):
		var old_tween = heal_score_bar.get_meta("shake_tween")
		if is_instance_valid(old_tween) and old_tween.is_running():
			old_tween.kill()
			
	var tween = get_tree().create_tween()
	heal_score_bar.set_meta("shake_tween", tween)
	
	var shake_str = 6.0 # Força do balanço em pixels
	tween.tween_property(heal_score_bar, "position:x", base_x + shake_str, 0.03)
	tween.tween_property(heal_score_bar, "position:x", base_x - shake_str, 0.03)
	tween.tween_property(heal_score_bar, "position:x", base_x + (shake_str / 2.0), 0.03)
	tween.tween_property(heal_score_bar, "position:x", base_x - (shake_str / 2.0), 0.03)
	tween.tween_property(heal_score_bar, "position:x", base_x, 0.03)

func _trigger_heal_flash():
	# Anti-Bot: Apenas o jogador real acende a tela
	var ic = owner.get_node_or_null("%InputComponent")
	if ic and "is_bot" in ic and ic.is_bot:
		return
		
	# Busca a HUD correta em caso de Split-Screen
	var target_hud = null
	for hud in get_tree().get_nodes_in_group("HUD"):
		if is_instance_valid(owner) and hud.get_viewport() == owner.get_viewport():
			target_hud = hud
			break
			
	if target_hud and target_hud.has_method("play_heal_flash"):
		target_hud.play_heal_flash()

func _trigger_shield_flash():
	# Anti-Bot: Apenas o jogador real acende a tela
	var ic = owner.get_node_or_null("%InputComponent")
	if ic and "is_bot" in ic and ic.is_bot:
		return
		
	# Busca a HUD correta em caso de Split-Screen
	var target_hud = null
	for hud in get_tree().get_nodes_in_group("HUD"):
		if is_instance_valid(owner) and hud.get_viewport() == owner.get_viewport():
			target_hud = hud
			break
			
	if target_hud and target_hud.has_method("play_shield_flash"):
		target_hud.play_shield_flash()

func repair(amount: float):
	if amount <= 0: return
	
	var old_health = current_health
	current_health = clamp(current_health + amount, 0.0, max_health)
	
	# Só pisca a tela de cura se realmente curou algo (não estava com a vida cheia)
	if current_health > old_health:
		_check_damage_state()
		_trigger_heal_flash()
# =========================================================

func _get_health_color(health_percent: float) -> Color:
	if health_percent > 30.0:
		var t = (health_percent - 30.0) / 70.0
		return Color.YELLOW.lerp(Color.GREEN, t)
	elif health_percent > 5.0:
		var t = (health_percent - 5.0) / 25.0
		return Color.RED.lerp(Color.YELLOW, t)
	else:
		return Color.RED

func take_damage(amount: float, source: Node = null):
	if current_health <= 0 or is_invulnerable:
		return
		
	var attacker_node = source
	var final_knockback = amount * 30.0 
	
	if source:
		if "shooter" in source and is_instance_valid(source.shooter):
			attacker_node = source.shooter
		if "knockback_force" in source:
			final_knockback = source.knockback_force
			
	if is_instance_valid(attacker_node):
		var attacker_stats = attacker_node.find_child("StatsComponent*", true, false)
		if attacker_stats and "damage_dealt_multiplier" in attacker_stats:
			amount *= attacker_stats.damage_dealt_multiplier
			
	amount *= damage_received_multiplier
		
	var shield_damage_portion = amount * 0.8
	var health_damage_portion = amount * 0.2
	
	if current_shield > 0:
		if current_shield >= shield_damage_portion:
			current_shield -= shield_damage_portion
		else:
			var leftover = shield_damage_portion - current_shield
			current_shield = 0
			health_damage_portion += leftover
			shield_broken.emit()
	else:
		health_damage_portion = amount
	
	if health_damage_portion > 0:
		current_health -= health_damage_portion
		_check_damage_state()
		took_damage.emit(attacker_node)
		
		if owner is VehicleBody3D or owner is RigidBody3D:
			if is_instance_valid(attacker_node):
				var hit_dir = (owner.global_position - attacker_node.global_position).normalized()
				hit_dir.y = 0.2 
				owner.apply_central_impulse(hit_dir * final_knockback)
		
		if source:
			_process_scoring(source)
		
	if current_health <= 0:
		current_health = 0 
		_on_death() 
		health_depleted.emit(attacker_node)

func _process_scoring(source: Node):
	var attacker = source
	if "shooter" in source and source.shooter != null:
		attacker = source.shooter
	
	var g_manager = attacker.find_child("GroundTrickManager*", true, false)
	
	if g_manager and g_manager.has_method("add_ground_action"):
		g_manager.add_ground_action("HIT_OBJECT")
		if current_health <= 0:
			var is_bot = false
			if is_instance_valid(owner) and owner.has_node("%InputComponent"):
				var ic = owner.get_node("%InputComponent")
				if "is_bot" in ic and ic.is_bot: is_bot = true
				
			if not is_bot:
				g_manager.add_ground_action("DESTROY_OBJECT")

func _check_damage_state():
	var parent = get_parent()
	if not parent.has_method("update_visual_damage"): return
	
	var percent = (current_health / max_health) * 100.0
	parent.update_visual_damage(percent)

func restore_shield(amount: float):
	if amount <= 0: return
	
	var old_shield = current_shield
	current_shield = clamp(current_shield + amount, 0.0, max_shield)
	
	# Só pisca a tela se realmente recuperou escudo (não estava no máximo)
	if current_shield > old_shield:
		_trigger_shield_flash()

func _on_death():
	if mission_id != "" and is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
