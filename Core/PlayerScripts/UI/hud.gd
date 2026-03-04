# HUD.gd
extends CanvasLayer

@onready var ped_kill_label = find_child("PedKillLabel", true, false)
@onready var minimap_bg = get_node_or_null("UI_Base/MinimapBackground")
# NOVO: Referências para a Info do Alvo
@onready var target_info_panel = get_node_or_null("UI_Base/TargetInfoPanel") # Crie um Panel na UI para isso depois
@onready var target_name_label = get_node_or_null("UI_Base/TargetInfoPanel/NameLabel")
@onready var target_hp_bar = get_node_or_null("UI_Base/TargetInfoPanel/HPBar")
@onready var category_label = get_node_or_null("UI_Base/TargetInfoPanel/CategoryLabel")

# Variáveis que armazenam a "foto" do radar atual
var _radar_targets : Array = []
var _radar_current_target : Node3D = null
var _radar_player_pos : Vector3 = Vector3.ZERO
var _radar_player_fwd : Vector3 = Vector3.FORWARD
var _radar_range : float = 150.0

# --- REFERÊNCIAS DE UI ---
@onready var ui_base = $UI_Base
@onready var messages = $Messages
@onready var toast_container = $Toasts

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel
@onready var timer_label = $UI_Base/TimerLabel
@onready var player_id_label = get_node_or_null("UI_Base/PlayerIDLabel")

# --- CONFIGURAÇÕES ---
@export var toast_font_size: int = 38
@export var multiplayer_ui_scale: float = 0.7 # Novo parâmetro para você testar 70% ou qualquer outro valor
const REFERENCE_WIDTH : float = 1280.0 # A largura padrão do seu jogo em Singleplayer

# --- ESTADO INTERNO ---
var _combo_display_version : int = 0
var player_suffix : String = ""
var my_player_id : int = -1
var my_car : BaseVehicle = null # Referência única do carro deste Viewport

# --- INICIALIZAÇÃO ---

func _ready():
	air_time_label.visible = false
	air_message_label.visible = false
	
	# Conecta a HUD ao cofre global
	if GameStats:
		GameStats.pedestrian_killed.connect(_update_ped_kill_ui)
		# Garante que ele já comece mostrando o número certo (zero ou o que estiver salvo na run)
		_update_ped_kill_ui(GameStats.pedestrians_killed_this_run)
	
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	if not MissionManager.mission_completed.is_connected(_on_mission_completed):
		MissionManager.mission_completed.connect(_on_mission_completed)
	
	if not MissionManager.mission_updated.is_connected(_on_mission_updated):
		MissionManager.mission_updated.connect(_on_mission_updated)

func setup_hud(suffix: String, real_id: int):
	player_suffix = suffix
	my_player_id = real_id
	
	if not is_in_group("HUD"): add_to_group("HUD")
	add_to_group("HUD" + player_suffix)
	
	my_car = get_viewport().find_child("*", true, false) as BaseVehicle
	
	if player_id_label:
		player_id_label.text = "PLAYER " + str(my_player_id + 1)
		player_id_label.modulate = Color.CYAN if my_player_id == 0 else Color.ORANGE
		
	print("[HUD] Player ", my_player_id + 1, " pronto no Viewport: ", get_viewport().name)

# --- PROCESSAMENTO (ESCALA RESPONSIVA) ---

func _process(_delta):
	_update_ui_scaling()

func _update_ui_scaling():
	var current_size = get_viewport().size
	if current_size.x == 0 or current_size.y == 0: return

	# Determina o fator de escala: Usa 1.0 se for Singleplayer, e a variável escolhida (ex: 0.7) no Multiplayer
	var scale_factor = 1.0
	if current_size.x < REFERENCE_WIDTH * 0.8: # Consideramos que se a tela é 20% menor que o padrão, dividiu
		scale_factor = multiplayer_ui_scale
	
	# 1. TRATAMENTO PARA FULL RECT (UI_Base)
	# Congelamos no canto (0,0) e aumentamos o tamanho virtual para compensar o encolhimento
	if ui_base:
		ui_base.anchor_left = 0.0
		ui_base.anchor_top = 0.0
		ui_base.anchor_right = 0.0
		ui_base.anchor_bottom = 0.0
		ui_base.offset_left = 0.0
		ui_base.offset_top = 0.0
		
		ui_base.scale = Vector2(scale_factor, scale_factor)
		ui_base.size = current_size / scale_factor

	# 2. TRATAMENTO PARA ELEMENTOS FLUTUANTES (Messages e Toasts)
	# Aplicamos escala sem mexer nas âncoras para não perder a posição original
	_scale_floating_control(messages, scale_factor)
	_scale_floating_control(toast_container, scale_factor)

# Calcula o pivô automático baseado nas âncoras para encolher no lugar certo
func _scale_floating_control(control: Control, scale_factor: float):
	if not control: return
	
	var anchor_center_x = (control.anchor_left + control.anchor_right) / 2.0
	var anchor_center_y = (control.anchor_top + control.anchor_bottom) / 2.0
	
	control.pivot_offset = Vector2(
		control.size.x * anchor_center_x,
		control.size.y * anchor_center_y
	)
	control.scale = Vector2(scale_factor, scale_factor)

# --- ATUALIZAÇÕES DE PONTUAÇÃO E INTERFACE ---

func _on_score_updated(player_id: int, new_score: int):
	if player_id == my_player_id:
		if score_label:
			score_label.text = ScoreManager.format_score_with_dots(new_score)

func atualizar_arma(nome: String, muniçao: int):
	if weapon_label:
		weapon_label.text = nome + ": " + str(muniçao)

func update_combo_live(full_bbcode_text: String):
	_combo_display_version += 1
	air_time_label.visible = true
	air_time_label.text = full_bbcode_text
	air_message_label.visible = false 

func show_combo_final(full_bbcode_text: String, result_text: String):
	var version_at_start = _combo_display_version
	air_time_label.visible = true
	air_time_label.text = full_bbcode_text
	air_message_label.visible = true
	air_message_label.text = result_text
	
	await get_tree().create_timer(3.0).timeout
	
	if _combo_display_version == version_at_start:
		air_time_label.visible = false
		air_message_label.visible = false

func clear_combo_display():
	_combo_display_version += 1
	air_time_label.visible = false
	air_message_label.visible = false

func atualizar_timer(segundos: float):
	if not timer_label: return
	var minutos = int(segundos) / 60
	var resto_segundos = int(segundos) % 60
	timer_label.text = "%02d:%02d" % [minutos, resto_segundos]
	
	if segundos <= 10:
		timer_label.add_theme_color_override("font_color", Color.RED)
	else:
		timer_label.add_theme_color_override("font_color", Color.WHITE)

# --- SISTEMA DE TOASTS (MISSÕES) ---

func _on_mission_completed(mission: MissionItem):
	criar_toast("⭐ CONCLUÍDO: " + mission.description, Color.YELLOW)

func _on_mission_updated(mission: MissionItem, current: float, target: float):
	if mission.type == MissionItem.Type.SPEED: return
	var status = str(int(current)) + "/" + str(int(target))
	criar_toast("📦 " + mission.description + ": " + status, Color.CYAN)

func criar_toast(texto: String, cor: Color):
	var label = Label.new()
	label.text = texto
	label.add_theme_font_size_override("font_size", toast_font_size)
	label.add_theme_color_override("font_color", cor)
	
	if toast_container:
		toast_container.add_child(label)
		var tween = create_tween().set_parallel(true)
		label.modulate.a = 0
		tween.tween_property(label, "modulate:a", 1.0, 0.2)
		
		await get_tree().create_timer(2.8).timeout
		
		var fade = create_tween()
		fade.tween_property(label, "modulate:a", 0.0, 0.4)
		fade.finished.connect(label.queue_free)

# Adicionamos cat_index e cat_name na assinatura!
func update_radar_data(targets: Array, lockon_target: Node3D, player_pos: Vector3, player_fwd: Vector3, cat_index: int, cat_name: String):
	_radar_current_target = lockon_target
	
	if minimap_bg:
		minimap_bg.radar_targets = targets
		minimap_bg.current_target = lockon_target
		minimap_bg.player_pos = player_pos
		minimap_bg.player_fwd = player_fwd
		minimap_bg.active_category_index = cat_index # Injeta no radar
		minimap_bg.queue_redraw()
		
	# Atualiza o texto visual da HUD com a Categoria
	if category_label:
		category_label.text = cat_name
		
	_update_target_info_ui()

func _update_target_info_ui():
	# Se não temos painel configurado, ignora
	if not target_info_panel: return
	
	if is_instance_valid(_radar_current_target):
		target_info_panel.visible = true
		if target_name_label:
			target_name_label.text = _radar_current_target.name
		
		if target_hp_bar:
			var current_hp = 0.0
			var max_hp = 100.0
			var found_health_data = false
			
			# 1. Tenta achar via StatsComponent (Para Carros e Turrets)
			var stats = _radar_current_target.find_child("StatsComponent*", true, false)
			if stats:
				current_hp = stats.current_health
				max_hp = stats.max_health
				found_health_data = true
				
			# 2. Se não achou, tenta achar via Duck Typing (Para DestructibleProps)
			elif "health" in _radar_current_target and "max_health" in _radar_current_target:
				current_hp = _radar_current_target.health
				max_hp = _radar_current_target.max_health
				found_health_data = true
				
			# 3. Se achou os dados de qualquer uma das formas, atualiza a UI
			if found_health_data:
				target_hp_bar.max_value = max_hp
				target_hp_bar.value = current_hp
				
				# --- LÓGICA DE COR (DEGRADÊ) ---
				var pct = (current_hp / max_hp) * 100.0
				var current_color = Color.RED
				
				if pct > 30.0:
					current_color = Color.YELLOW.lerp(Color.GREEN, (pct - 30.0) / 70.0)
				elif pct > 5.0:
					current_color = Color.RED.lerp(Color.YELLOW, (pct - 5.0) / 25.0)
					
				target_hp_bar.modulate = current_color
	else:
		target_info_panel.visible = false

# Função que atualiza o texto quando alguém morre
func _update_ped_kill_ui(amount: int):
	if ped_kill_label:
		ped_kill_label.text = "x" + str(amount)
