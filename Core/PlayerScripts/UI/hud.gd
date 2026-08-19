extends CanvasLayer

# ====================================================================
# OTIMIZAÇÃO: Preload de texturas pesadas para a memória RAM
# ====================================================================
const PIN_TEXTURE = preload("res://Assets/2D/location-pin.png")

@onready var ped_kill_label = find_child("PedKillLabel", true, false)
@onready var minimap_bg = get_node_or_null("UI_Base/MinimapBackground")
@onready var target_info_panel = get_node_or_null("UI_Base/TargetInfoPanel") 
@onready var target_name_label = get_node_or_null("UI_Base/TargetInfoPanel/NameLabel")
@onready var target_hp_bar = get_node_or_null("UI_Base/TargetInfoPanel/HPBar")
@onready var category_label = get_node_or_null("UI_Base/TargetInfoPanel/CategoryLabel")
# Puxando as referências baseadas na estrutura da sua imagem
@onready var slomo_container = get_node_or_null("SloMo")
@onready var slomo_bar = get_node_or_null("SloMo/SlowMoBar")
@onready var slomo_label = get_node_or_null("SloMo/SloMoLabel")

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

# ====================================================================
# UI DE QUADRADOS DAS ARMAS
# ====================================================================
@onready var weapon_squares = [
	$UI_Base/WeaponLabel/W1,
	$UI_Base/WeaponLabel/W2,
	$UI_Base/WeaponLabel/W3,
	$UI_Base/WeaponLabel/W4,
	$UI_Base/WeaponLabel/W5
]

var _base_square_y : Array[float] = []

var _nametags_dict : Dictionary = {}
var nametags_container = Control.new()

@export var toast_font_size: int = 38
@export var multiplayer_ui_scale: float = 0.7 
const REFERENCE_WIDTH : float = 1280.0 

@export_group("Missões de Entrega")
@export var delivery_icons: Array[Control] # No editor, arraste o Item 1, Item 2 e Item 3 para cá!

var _combo_display_version : int = 0
var player_suffix : String = ""
var my_player_id : int = -1
var my_car : BaseVehicle = null 

# --- GERENCIADOR DOS PAINÉIS DE HISTÓRIA ---
var mission_panels: HUDMissionPanels

# ====================================================================
# CACHES DE OTIMIZAÇÃO (Memória)
# ====================================================================
var _last_ped_kills : int = -1
var _shared_blood_style : StyleBoxFlat = null
var _target_stats_cache : Dictionary = {}

func _ready():
	air_time_label.visible = false
	air_message_label.visible = false
	
	add_child(nametags_container)
	
	mission_panels = HUDMissionPanels.new()
	add_child(mission_panels)
	mission_panels.setup(ui_base)
	
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	if Global.current_run_mode == Global.RunMode.STORY:
		call_deferred("esconder_timer")
	
	# Salva a posição Y original e cria o contorno de seleção automaticamente
	for sq in weapon_squares:
		_base_square_y.append(sq.position.y)
		sq.hide() # Começa invisível
		
		# Cria um ReferenceRect para servir de contorno brilhante
		var outline = ReferenceRect.new()
		outline.name = "Outline"
		outline.set_anchors_preset(Control.PRESET_FULL_RECT)
		outline.border_width = 3.0
		outline.editor_only = false
		outline.border_color = Color(1.0, 1.0, 1.0, 1.0) # Branco puro para destaque
		outline.hide()
		sq.add_child(outline)
		
	# ====================================================================
	# OTIMIZAÇÃO: Conecta a mudança de escala a um evento (Signal) em vez
	# de calcular tudo a cada frame no _process.
	# ====================================================================
	get_viewport().size_changed.connect(_update_ui_scaling)
	_update_ui_scaling() # Roda uma vez no início

# ====================================================================
# --- DELEGAÇÃO DE COMANDOS DA MISSÃO PARA O NOVO SCRIPT ---
# ====================================================================

func mostrar_item_secreto_coletado(nome_item: String, pontos: int):
	mission_panels.mostrar_item_secreto_coletado(nome_item, pontos)

func mostrar_missao_ativa_com_tiers(nome_missao: String, tiers: Array):
	mission_panels.mostrar_missao_ativa_com_tiers(nome_missao, tiers)

func riscar_objetivo_tier(index: int, tier_name: String):
	mission_panels.riscar_objetivo_tier(index, tier_name)

func atualizar_status_missao(sucesso: bool):
	mission_panels.atualizar_status_missao(sucesso)

func esconder_missao_ativa():
	mission_panels.esconder_missao_ativa()

# ====================================================================
# --- CÓDIGO ORIGINAL DO HUD ---
# ====================================================================

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

func _process(_delta):
	# OTIMIZAÇÃO: _update_ui_scaling() foi removido daqui e passado para o sinal de size_changed.
	
	# OTIMIZAÇÃO: Só reconstrói a string do Label de abates se o número mudar.
	if ped_kill_label and is_instance_valid(my_car):
		var current_kills = my_car.pedestrians_killed
		if current_kills != _last_ped_kills:
			_last_ped_kills = current_kills
			ped_kill_label.text = "x" + str(_last_ped_kills)

func sync_nametags(active_tags_data: Array):
	var valid_nodes = []

	for data in active_tags_data:
		var p = data["node"]
		valid_nodes.append(p)

		if not _nametags_dict.has(p):
			var container = Control.new()
			nametags_container.add_child(container)
			
			var icon = TextureRect.new()
			# OTIMIZAÇÃO: Lê direto da memória RAM (Preload)
			icon.texture = PIN_TEXTURE 
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

	var keys_to_remove = []
	for p in _nametags_dict.keys():
		if not p in valid_nodes:
			_nametags_dict[p]["container"].queue_free()
			keys_to_remove.append(p)
			
	for k in keys_to_remove: 
		_nametags_dict.erase(k)

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
			
			# OTIMIZAÇÃO: find_child com wildcard '*' é lentíssimo para o _process.
			# Criamos um cache para guardar a referência do StatsComponent.
			var stats = null
			if _target_stats_cache.has(display_target):
				stats = _target_stats_cache[display_target]
			else:
				stats = display_target.find_child("StatsComponent*", true, false)
				# Se encontrar, guarda no cache para a próxima volta do frame.
				if stats: _target_stats_cache[display_target] = stats
			
			if is_instance_valid(stats):
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
		# Limpeza do cache para não segurar referências a objetos deletados
		if _target_stats_cache.size() > 20: 
			_target_stats_cache.clear()

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
	
func esconder_timer():
	var timer_label = get_node_or_null("%TimerLabel")
	var timer_bg = get_node_or_null("%ColorRect4")

	if timer_label: 
		timer_label.hide()
		timer_bg.hide()

func mostrar_timer():
	var timer_label = get_node_or_null("%TimerLabel")
	var timer_bg = get_node_or_null("%ColorRect4")

	if timer_label: 
		timer_label.show()
		timer_bg.show()

func splatter_blood_on_lens():
	var splash_node = Control.new()
	var vp_size = get_viewport().get_visible_rect().size
	
	splash_node.position = Vector2.ZERO
	add_child(splash_node)
	
	# ====================================================================
	# OTIMIZAÇÃO: Cria o StyleBox do sangue uma única vez e compartilha
	# entre todas as gotas, economizando alocação de objetos!
	# ====================================================================
	if _shared_blood_style == null:
		_shared_blood_style = StyleBoxFlat.new()
		_shared_blood_style.bg_color = Color(0.6, 0.0, 0.0, 0.85)
		_shared_blood_style.corner_radius_top_left = 1024
		_shared_blood_style.corner_radius_top_right = 1024
		_shared_blood_style.corner_radius_bottom_right = 1024
		_shared_blood_style.corner_radius_bottom_left = 1024

	var drops = randi_range(6, 12) 
	
	for i in range(drops):
		var drop = Panel.new()
		drop.add_theme_stylebox_override("panel", _shared_blood_style)
		
		var size_val = randf_range(5.0, 25.0)
		if randf() > 0.8:
			size_val = randf_range(60.0, 180.0)
			
		var w = size_val * randf_range(0.7, 1.3)
		var h = size_val * randf_range(0.7, 1.3)
		drop.size = Vector2(w, h)
		
		var cx = randf_range(vp_size.x * 0.05, vp_size.x * 0.95)
		var cy = randf_range(vp_size.y * 0.05, vp_size.y * 0.95)
		drop.position = Vector2(cx - w * 0.5, cy - h * 0.5)
		
		splash_node.add_child(drop)
		
		var tween_drop = create_tween()
		tween_drop.tween_property(drop, "position:y", drop.position.y + randf_range(20.0, 100.0), randf_range(1.5, 4.0)).set_ease(Tween.EASE_OUT)
		
	var tween = create_tween()
	var delay = randf_range(0.5, 1.0)
	tween.tween_property(splash_node, "modulate:a", 0.0, randf_range(1.5, 2.5)).set_delay(delay)
	tween.chain().tween_callback(splash_node.queue_free)
	
func play_pickup_flash(success: bool):
	if not has_node("PickupFlash"): return
	var flash = $PickupFlash
	
	var tween = get_tree().create_tween()
	
	if success:
		flash.color = Color(1.0, 0.817, 0.0, 0.302) 
		flash.visible = true
		tween.tween_property(flash, "color:a", 0.6, 0.01)
		tween.tween_property(flash, "color:a", 0.0, 0.2)
	else:
		flash.color = Color(1.0, 0.2, 0.2, 0.25) 
		flash.visible = true
		tween.tween_property(flash, "color:a", 0.4, 0.01)
		tween.tween_property(flash, "color:a", 0.0, 0.2)
		
	tween.tween_callback(func(): flash.visible = false)
	
func play_heal_flash():
	if not has_node("PickupFlash"): return
	var flash = $PickupFlash
	var tween = get_tree().create_tween()
	flash.color = Color(0.355, 1.0, 0.1, 0.4) 
	flash.visible = true
	tween.tween_property(flash, "color:a", 0.7, 0.03)
	tween.tween_property(flash, "color:a", 0.0, 0.3)
	tween.tween_callback(func(): flash.visible = false)
	
func play_shield_flash():
	if not has_node("PickupFlash"): return
	var flash = $PickupFlash
	var tween = get_tree().create_tween()
	flash.color = Color(0.1, 0.6, 1.0, 0.4) 
	flash.visible = true
	tween.tween_property(flash, "color:a", 0.6, 0.01)
	tween.tween_property(flash, "color:a", 0.0, 0.2)
	tween.tween_callback(func(): flash.visible = false)

# Adicione esta função em qualquer lugar do script da HUD:
func update_delivery_ui(held_count: int):
	# Varre os ícones da HUD
	for i in range(delivery_icons.size()):
		if is_instance_valid(delivery_icons[i]):
			# A mágica: Se o índice do ícone for menor que o número de itens na mão, ele fica visível!
			# Ex: Pegou 1 item. held_count = 1. O Item 1 (índice 0) fica true. O resto fica false.
			delivery_icons[i].visible = i < held_count

# ====================================================================
# PROGRESS BAR DO SLOW-MO E TIMER
# ====================================================================


func atualizar_barra_slomo(pct: float, tempo_restante: float):
	# Mostra o grupo inteiro (pai)
	if slomo_container:
		slomo_container.show()
		
	if slomo_bar:
		slomo_bar.value = pct * 100.0
		
	if slomo_label:
		# Formata para mostrar 1 casa decimal e a letra 's'. Ex: "2.8s"
		# Se quiser apenas números inteiros (3, 2, 1), troque "%.1fs" por "%ds" e passe int(ceil(tempo_restante))
		slomo_label.text = "%.1fs" % tempo_restante

func esconder_barra_slomo():
	# Esconde o grupo inteiro (pai e filhos)
	if slomo_container:
		slomo_container.hide()

func atualizar_lista_armas(weapon_pool: Array, current_index: int):
	for i in range(weapon_squares.size()):
		var sq = weapon_squares[i]
		var outline = sq.get_node_or_null("Outline")
		
		if i < weapon_pool.size():
			sq.show()
			var weapon = weapon_pool[i]
			
			# REAPROVEITANDO A VARIÁVEL EXISTENTE: item_color
			if "item_color" in weapon:
				sq.color = weapon.item_color
				
			# Animação de Seleção
			if i == current_index:
				# Sobe 20 pixels com um efeito elástico (TRANS_BACK)
				create_tween().tween_property(sq, "position:y", _base_square_y[i] - 20.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				if outline: 
					outline.show()
			else:
				# Volta para a posição original
				create_tween().tween_property(sq, "position:y", _base_square_y[i], 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				if outline: 
					outline.hide()
		else:
			sq.hide()
