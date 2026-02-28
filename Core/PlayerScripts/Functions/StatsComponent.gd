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

@export_group("UI Integration (Optional if Auto-Link works)")
@export var health_bar : ProgressBar
@export var shield_bar : ProgressBar

@export_group("Physics Multipliers")
@export var speed_multiplier: float = 1.0
@export var weight_multiplier: float = 1.0

@export_group("Mission Settings")
## ID da missão no Resource (ex: "enemy_car" ou "radar_tower")
@export var mission_id : String = ""

# --- TRAVA DE SEGURANÇA POR COLISOR ---
var _hit_history: Dictionary = {}

func _ready():
	# Inicializa as barras com os valores máximos configurados
	_initialize_ui()
	
	# NOVO: Tenta linkar as barras automaticamente para o multiplayer
	# Esperamos um frame (deferred) para garantir que a HUD já foi instanciada no Viewport
	call_deferred("_auto_link_hud")

func _auto_link_hud():
	# Se as barras já foram colocadas manualmente, não faz nada
	if health_bar and shield_bar:
		return
		
	# Procura as barras dentro do Viewport atual do jogador
	# No multiplayer, find_child vai olhar apenas dentro da "sua" fatia da tela
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
	if shield_bar:
		shield_bar.max_value = max_shield
		shield_bar.value = current_shield

func _process(_delta):
	# Atualização contínua garante que mesmo curas ou efeitos graduais apareçam
	_update_ui_bars()

func _update_ui_bars():
	# Interpolação suave para um visual de alta qualidade
	if health_bar:
		health_bar.value = lerp(health_bar.value, current_health, 0.2)
	if shield_bar:
		shield_bar.value = lerp(shield_bar.value, current_shield, 0.2)

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
		current_health = 0 # Trava em zero para a UI não bugar
		_on_death() # <--- ADICIONADO: Avisa que morreu para as missões
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
	
	# Cálculo de porcentagem de dano para o shader/visual do carro:
	# $$\text{percent} = \frac{\text{current\_health}}{\text{max\_health}} \times 100$$
	var percent = (current_health / max_health) * 100
	parent.update_visual_damage(percent)

func repair(amount: float):
	current_health = clamp(current_health + amount, 0, max_health)
	_check_damage_state()

func _on_death():
	# REGRA: Independente de quem matou, se tem ID de missão, avisa o Manager
	if mission_id != "" and is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
	
	print("StatsComponent: Objeto '", mission_id, "' foi removido do mapa.")
