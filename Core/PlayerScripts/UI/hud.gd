# HUD.gd
extends CanvasLayer

@onready var ped_kill_label = find_child("PedKillLabel", true, false)
@onready var minimap_bg = get_node_or_null("UI_Base/MinimapBackground")
@onready var target_info_panel = get_node_or_null("UI_Base/TargetInfoPanel") 
@onready var target_name_label = get_node_or_null("UI_Base/TargetInfoPanel/NameLabel")
@onready var target_hp_bar = get_node_or_null("UI_Base/TargetInfoPanel/HPBar")
@onready var category_label = get_node_or_null("UI_Base/TargetInfoPanel/CategoryLabel")

var _radar_targets : Array = []
var _radar_current_target : Node3D = null
var _radar_player_pos : Vector3 = Vector3.ZERO
var _radar_player_fwd : Vector3 = Vector3.FORWARD
var _radar_range : float = 180.0

@onready var ui_base = $UI_Base
@onready var messages = $Messages
@onready var toast_container = $Toasts

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel
@onready var timer_label = $UI_Base/TimerLabel
@onready var player_id_label = get_node_or_null("UI_Base/PlayerIDLabel")

var _nametags_dict : Dictionary = {}
var nametags_container = Control.new()

@export var toast_font_size: int = 38
@export var multiplayer_ui_scale: float = 0.7 
const REFERENCE_WIDTH : float = 1280.0 

var _combo_display_version : int = 0
var player_suffix : String = ""
var my_player_id : int = -1
var my_car : BaseVehicle = null 

var story_mission_panel: PanelContainer
var story_mission_label: Label
var story_mission_line: ColorRect

func _ready():
	air_time_label.visible = false
	air_message_label.visible = false
	
	add_child(nametags_container)
	_setup_story_mission_ui()
	
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	if not MissionManager.mission_completed.is_connected(_on_mission_completed):
		MissionManager.mission_completed.connect(_on_mission_completed)
	
	if not MissionManager.mission_updated.is_connected(_on_mission_updated):
		MissionManager.mission_updated.connect(_on_mission_updated)

func _setup_story_mission_ui():
	story_mission_panel = PanelContainer.new()
	ui_base.add_child(story_mission_panel)
	
	story_mission_panel.anchor_left = 1.0
	story_mission_panel.anchor_top = 1.0
	story_mission_panel.anchor_right = 1.0
	story_mission_panel.anchor_bottom = 1.0
	
	story_mission_panel.offset_left = -380
	story_mission_panel.offset_top = -400
	story_mission_panel.offset_right = -30
	story_mission_panel.offset_bottom = -180
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.96, 0.85)
	style.border_color = Color(0.9, 0.4, 0.4)
	style.border_width_left = 4
	style.content_margin_left = 15
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	style.content_margin_right = 15
	style.shadow_color = Color(0, 0, 0, 0.15)
	style.shadow_size = 4
	story_mission_panel.add_theme_stylebox_override("panel", style)
	
	story_mission_label = Label.new()
	story_mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_mission_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2))
	story_mission_label.add_theme_font_size_override("font_size", 22)
	story_mission_panel.add_child(story_mission_label)
	
	story_mission_line = ColorRect.new()
	story_mission_line.color = Color(0.8, 0.1, 0.1, 0.8)
	story_mission_line.custom_minimum_size.y = 4
	story_mission_line.size.y = 4
	story_mission_line.size.x = 0
	story_mission_line.anchor_top = 0.5
	story_mission_line.anchor_bottom = 0.5
	story_mission_label.add_child(story_mission_line)
	
	story_mission_panel.visible = false

func mostrar_missao_ativa(nome_missao: String):
	if story_mission_panel:
		story_mission_label.text = "- " + nome_missao
		story_mission_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2))
		story_mission_line.size.x = 0
		story_mission_panel.visible = true

func atualizar_status_missao(sucesso: bool):
	if story_mission_panel and story_mission_panel.visible:
		if sucesso:
			story_mission_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.7))
			var font = story_mission_label.get_theme_font("font")
			var font_size = story_mission_label.get_theme_font_size("font_size")
			var text_width = font.get_string_size(story_mission_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			
			var tween = create_tween()
			tween.tween_property(story_mission_line, "size:x", text_width + 10.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			story_mission_label.add_theme_color_override("font_color", Color.RED)
			story_mission_label.text = story_mission_label.text + " (FALHOU)"

func esconder_missao_ativa():
	if story_mission_panel:
		story_mission_panel.visible = false

func setup_hud(suffix: String, real_id: int):
	player_suffix = suffix
	my_player_id = real_id
	
	if not is_in_group("HUD"): add_to_group("HUD")
	add_to_group("HUD" + player_suffix)
	
	for p in get_tree().get_nodes_in_group("jogadores"):
		if "id" in p and p.id == my_player_id:
			my_car = p
			break
			
	if player_id_label:
		player_id_label.text = "PLAYER " + str(my_player_id + 1)
		player_id_label.modulate = Color.CYAN if my_player_id == 0 else Color.ORANGE

# --- O NOVO _PROCESS SUPER LEVE ---
func _process(_delta):
	_update_ui_scaling()
	
	if ped_kill_label and is_instance_valid(my_car):
		ped_kill_label.text = "x" + str(my_car.pedestrians_killed)

# --- RECEPTOR DE DADOS DAS GOTAS ---
func sync_nametags(active_tags_data: Array):
	var valid_nodes = []

	# Desenha e atualiza as posições passadas pelo componente
	for data in active_tags_data:
		var p = data["node"]
		valid_nodes.append(p)

		if not _nametags_dict.has(p):
			var container = Control.new()
			nametags_container.add_child(container)
			
			var icon = TextureRect.new()
			icon.texture = load("res://Assets/2D/location-pin.png") 
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE 
			icon.custom_minimum_size = Vector2(64, 64)
			icon.size = Vector2(64, 64)
			container.add_child(icon)
			
			icon.position = -Vector2(32, 32)
			_nametags_dict[p] = {"container": container, "icon": icon}
			
		var dict_data = _nametags_dict[p]
		var container = dict_data["container"]
		var icon = dict_data["icon"]
		
		container.visible = true
		container.global_position = data["screen_pos"]
		container.scale = Vector2(data["scale"], data["scale"])
		
		if data["is_locked"]:
			icon.modulate = Color.RED
			icon.modulate.a = 1.0
		else:
			icon.modulate = Color.WHITE
			icon.modulate.a = 0.5

	# Limpa os elementos que saíram da tela ou foram destruídos
	var keys_to_remove = []
	for p in _nametags_dict.keys():
		if not p in valid_nodes:
			_nametags_dict[p]["container"].queue_free()
			keys_to_remove.append(p)
			
	for k in keys_to_remove: 
		_nametags_dict.erase(k)

# --- RECEPTOR DO PAINEL DE ALVO ---
func sync_target_info(display_target: Node3D):
	if not target_info_panel: return
	target_info_panel.visible = true

	if is_instance_valid(display_target):
		if target_name_label: target_name_label.show(); target_name_label.text = display_target.name
		if target_hp_bar: target_hp_bar.show()
		
		if target_hp_bar:
			var current_hp = 0.0
			var max_hp = 100.0
			var found_health_data = false
			var stats = display_target.find_child("StatsComponent*", true, false)
			
			if stats:
				current_hp = stats.current_health
				max_hp = stats.max_health
				found_health_data = true
			elif "health" in display_target and "max_health" in display_target:
				current_hp = display_target.health
				max_hp = display_target.max_health
				found_health_data = true
				
			if found_health_data:
				target_hp_bar.max_value = max_hp
				target_hp_bar.value = current_hp
				var pct = (current_hp / max_hp) * 100.0
				var current_color = Color.RED
				if pct > 30.0: current_color = Color.YELLOW.lerp(Color.GREEN, (pct - 30.0) / 70.0)
				elif pct > 5.0: current_color = Color.RED.lerp(Color.YELLOW, (pct - 5.0) / 25.0)
				target_hp_bar.modulate = current_color
	else:
		if target_name_label: target_name_label.hide()
		if target_hp_bar: target_hp_bar.hide()

func get_active_minimap_category() -> int:
	if minimap_bg: return minimap_bg.active_category_index
	return 0

func update_radar_data(targets: Array, lockon_target: Node3D, player_pos: Vector3, player_fwd: Vector3, cat_index: int, cat_name: String):
	_radar_current_target = lockon_target
	if minimap_bg:
		minimap_bg.radar_targets = targets
		minimap_bg.current_target = lockon_target
		minimap_bg.player_pos = player_pos
		minimap_bg.player_fwd = player_fwd
		minimap_bg.active_category_index = cat_index 
		minimap_bg.queue_redraw()
	if category_label:
		category_label.text = cat_name

func _update_ui_scaling():
	var current_size = get_viewport().size
	if current_size.x == 0 or current_size.y == 0: return

	var scale_factor = 1.0
	if current_size.x < REFERENCE_WIDTH * 0.8:
		scale_factor = multiplayer_ui_scale
	
	if ui_base:
		ui_base.anchor_left = 0.0
		ui_base.anchor_top = 0.0
		ui_base.anchor_right = 0.0
		ui_base.anchor_bottom = 0.0
		ui_base.offset_left = 0.0
		ui_base.offset_top = 0.0
		
		ui_base.scale = Vector2(scale_factor, scale_factor)
		ui_base.size = current_size / scale_factor

	_scale_floating_control(messages, scale_factor)
	_scale_floating_control(toast_container, scale_factor)

func _scale_floating_control(control: Control, scale_factor: float):
	if not control: return
	var anchor_center_x = (control.anchor_left + control.anchor_right) / 2.0
	var anchor_center_y = (control.anchor_top + control.anchor_bottom) / 2.0
	control.pivot_offset = Vector2(control.size.x * anchor_center_x, control.size.y * anchor_center_y)
	control.scale = Vector2(scale_factor, scale_factor)

func _on_score_updated(player_id: int, new_score: int):
	if player_id == my_player_id and score_label:
		score_label.text = ScoreManager.format_score_with_dots(new_score)

func atualizar_arma(nome: String, muniçao: int):
	if weapon_label: weapon_label.text = nome + ": " + str(muniçao)

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

func _update_ped_kill_ui(amount: int):
	if ped_kill_label: ped_kill_label.text = "x" + str(amount)
