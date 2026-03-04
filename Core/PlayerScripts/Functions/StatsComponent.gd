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

@export_group("UI Integration")
@export var health_bar : ProgressBar
@export var shield_bar : ProgressBar

@export_group("Physics Multipliers")
@export var speed_multiplier: float = 1.0
@export var weight_multiplier: float = 1.0

@export_group("Mission Settings")
## ID da missão no Resource (ex: "enemy_car" ou "radar_tower")
@export var mission_id : String = ""

# Variável interna para o estilo da barra de vida
var _health_stylebox : StyleBoxFlat = null

func _ready():
	_initialize_ui()
	call_deferred("_auto_link_hud")

func _auto_link_hud():
	if health_bar and shield_bar:
		return
		
	var my_viewport = get_viewport()
	
	if not health_bar:
		health_bar = my_viewport.find_child("HealthBar", true, false) as ProgressBar
	if not shield_bar:
		shield_bar = my_viewport.find_child("ShieldBar", true, false) as ProgressBar
		
	if health_bar or shield_bar:
		print("[Stats] HUD detectada automaticamente para ", owner.name, " no Viewport: ", my_viewport.name)
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

func _process(_delta):
	_update_ui_bars()

func _update_ui_bars():
	if health_bar:
		health_bar.value = lerp(health_bar.value, current_health, 0.2)
		
		var pct = (health_bar.value / max_health) * 100.0
		var current_color = _get_health_color(pct)
		
		if _health_stylebox:
			_health_stylebox.bg_color = current_color
		else:
			health_bar.modulate = current_color
			
	if shield_bar:
		shield_bar.value = lerp(shield_bar.value, current_shield, 0.2)

func _get_health_color(health_percent: float) -> Color:
	if health_percent > 30.0:
		var t = (health_percent - 30.0) / 70.0
		return Color.YELLOW.lerp(Color.GREEN, t)
	elif health_percent > 5.0:
		var t = (health_percent - 5.0) / 25.0
		return Color.RED.lerp(Color.YELLOW, t)
	else:
		return Color.RED

## Recebe dano e o objeto que causou a batida (source)
func take_damage(amount: float, source: Node = null):
	if current_health <= 0: 
		return

	if is_invulnerable:
		return
		
	var nome_atacante = source.name if source else "Desconhecido/Impacto"
	var attacker_node = source
	var final_knockback = amount * 30.0 # Força padrão caso seja um impacto de cenário
	
	# Extrai os dados se a source for uma bala (BaseProjectile)
	if source:
		if "shooter" in source and is_instance_valid(source.shooter):
			nome_atacante = source.shooter.name + " (via arma)"
			attacker_node = source.shooter
		if "knockback_force" in source:
			final_knockback = source.knockback_force
		
	print("=========================================")
	print("[COMBATE - DANO] Vítima: ", owner.name, " | Agressor: ", nome_atacante)
	print(" -> Dano Bruto Recebido: ", amount)
		
	var shield_damage_portion = amount * 0.8
	var health_damage_portion = amount * 0.2
	
	if current_shield > 0:
		if current_shield >= shield_damage_portion:
			current_shield -= shield_damage_portion
			print(" -> Escudo absorveu: ", shield_damage_portion, " | Escudo Restante: ", current_shield)
		else:
			var leftover = shield_damage_portion - current_shield
			print(" -> Escudo absorveu: ", current_shield, " (QUEBROU!) | Vazou para a vida: ", leftover)
			current_shield = 0
			health_damage_portion += leftover
			shield_broken.emit()
	else:
		health_damage_portion = amount
		print(" -> Sem escudo! Dano 100% direto na vida.")
	
	if health_damage_portion > 0:
		current_health -= health_damage_portion
		print(" -> Dano final na vida: ", health_damage_portion, " | Vida Restante: ", current_health)
		print("=========================================")
		_check_damage_state()
		
		# --- EMPURRÃO FÍSICO CONTROLADO ---
		if owner is VehicleBody3D or owner is RigidBody3D:
			if is_instance_valid(attacker_node):
				var hit_dir = (owner.global_position - attacker_node.global_position).normalized()
				hit_dir.y = 0.2 
				
				# Aplica a força específica que extraímos da bala!
				owner.apply_central_impulse(hit_dir * final_knockback)
		
		# --- GERAÇÃO DE PONTUAÇÃO ---
		if source:
			_process_scoring(source)
		
	if current_health <= 0:
		current_health = 0 
		_on_death() 
		health_depleted.emit()

func _process_scoring(source: Node):
	var attacker = source
	if "shooter" in source and source.shooter != null:
		attacker = source.shooter
	
	var g_manager = attacker.find_child("GroundTrickManager*", true, false)
	
	if g_manager and g_manager.has_method("add_ground_action"):
		print("[Stats] Enviando bônus de HIT_OBJECT para o manager de: ", attacker.name)
		g_manager.add_ground_action("HIT_OBJECT")
		
		if current_health <= 0:
			g_manager.add_ground_action("DESTROY_OBJECT")

func _check_damage_state():
	var parent = get_parent()
	if not parent.has_method("update_visual_damage"): return
	
	var percent = (current_health / max_health) * 100.0
	parent.update_visual_damage(percent)

func repair(amount: float):
	current_health = clamp(current_health + amount, 0.0, max_health)
	_check_damage_state()

func restore_shield(amount: float):
	current_shield = clamp(current_shield + amount, 0.0, max_shield)
	print("[Stats] Escudo restaurado em ", amount, " | Escudo atual: ", current_shield)

func _on_death():
	if mission_id != "" and is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
	
	print("StatsComponent: Objeto '", mission_id, "' foi removido do mapa.")
