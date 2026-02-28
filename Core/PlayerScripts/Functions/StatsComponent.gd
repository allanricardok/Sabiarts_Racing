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
		
		# Clona o StyleBox para podermos mudar a cor dinamicamente sem afetar outros UI
		var current_style = health_bar.get_theme_stylebox("fill")
		if current_style is StyleBoxFlat:
			_health_stylebox = current_style.duplicate()
		else:
			# Se não tiver um estilo configurado, cria um base
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
		
		# --- LÓGICA DE DEGRADÊ DE COR ---
		var pct = (health_bar.value / max_health) * 100.0
		var current_color = _get_health_color(pct)
		
		if _health_stylebox:
			_health_stylebox.bg_color = current_color
		else:
			# Fallback caso dê algum erro na extração do StyleBox
			health_bar.modulate = current_color
			
	if shield_bar:
		shield_bar.value = lerp(shield_bar.value, current_shield, 0.2)

# --- FUNÇÃO MATEMÁTICA DE CORES ---
func _get_health_color(health_percent: float) -> Color:
	if health_percent > 30.0:
		# De 30% a 100%: Transição do Amarelo para o Verde
		var t = (health_percent - 30.0) / 70.0
		return Color.YELLOW.lerp(Color.GREEN, t)
	elif health_percent > 5.0:
		# De 5% a 30%: Transição do Vermelho para o Amarelo
		var t = (health_percent - 5.0) / 25.0
		return Color.RED.lerp(Color.YELLOW, t)
	else:
		# De 5% para baixo: Vermelho cravado
		return Color.RED

## Recebe dano e o objeto que causou a batida (source)
func take_damage(amount: float, source: Node = null):
	if current_health <= 0: 
		return

	if is_invulnerable:
		return
		
	# --- NOVA DISTRIBUIÇÃO DE DANO (80% / 20%) ---
	var shield_damage_portion = amount * 0.8
	var health_damage_portion = amount * 0.2
	
	if current_shield > 0:
		if current_shield >= shield_damage_portion:
			current_shield -= shield_damage_portion
		else:
			# Se o escudo for quebrar antes de absorver os 80%, o restante vaza para a vida
			var leftover = shield_damage_portion - current_shield
			current_shield = 0
			health_damage_portion += leftover
			shield_broken.emit()
	else:
		# Se não tem escudo, 100% do dano vai direto na vida
		health_damage_portion = amount
	
	# Aplica o dano resultante na vida
	if health_damage_portion > 0:
		current_health -= health_damage_portion
		_check_damage_state()
		
		# --- GERAÇÃO DE PONTUAÇÃO ---
		if source:
			_process_scoring(source)
		
	if current_health <= 0:
		current_health = 0 # Trava em zero para a UI não bugar
		_on_death() # Avisa que morreu para as missões
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
	
	# Cálculo de porcentagem de dano para o visual do carro:
	var percent = (current_health / max_health) * 100.0
	parent.update_visual_damage(percent)

func repair(amount: float):
	current_health = clamp(current_health + amount, 0.0, max_health)
	_check_damage_state()

func _on_death():
	# Independente de quem matou, se tem ID de missão, avisa o Manager
	if mission_id != "" and is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
	
	print("StatsComponent: Objeto '", mission_id, "' foi removido do mapa.")
