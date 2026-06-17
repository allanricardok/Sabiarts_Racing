# pause_menu.gd
extends CanvasLayer

var pode_pausar: bool = true

@export var start_menu: CanvasLayer
@onready var mission_container = %MissionList
@onready var resume_btn = %ResumeBtn 
@onready var menu_btn = %MenuBtn
@onready var end_match_btn = get_node_or_null("%EndMatchBtn")

var camera_select_btn: OptionButton
var abort_mission_btn: Button 
var reset_mission_btn: Button # --- NOVO: Referência do botão de reiniciar ---

func _ready():
	_setup_dynamic_buttons()

func _setup_dynamic_buttons():
	var vbox = $Control/VBoxContainer
	if not vbox: return
	
	# --- INSTANCIAÇÃO DO ABORTAR MISSÃO ---
	abort_mission_btn = Button.new()
	abort_mission_btn.name = "AbortMissionBtn"
	abort_mission_btn.text = "Abortar Missão"
	abort_mission_btn.focus_mode = Control.FOCUS_ALL
	
	if resume_btn:
		var font = resume_btn.get_theme_font("font")
		if font: abort_mission_btn.add_theme_font_override("font", font)
		abort_mission_btn.add_theme_font_size_override("font_size", 32)
		var style = resume_btn.get_theme_stylebox("focus")
		if style: abort_mission_btn.add_theme_stylebox_override("focus", style)
	
	abort_mission_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	abort_mission_btn.pressed.connect(_on_abort_mission_btn_pressed)
	vbox.add_child(abort_mission_btn)
	
	# --- NOVO: INSTANCIAÇÃO DO REINICIAR MISSÃO ---
	reset_mission_btn = Button.new()
	reset_mission_btn.name = "ResetMissionBtn"
	reset_mission_btn.text = "Reiniciar Missão"
	reset_mission_btn.focus_mode = Control.FOCUS_ALL
	
	if resume_btn:
		var font = resume_btn.get_theme_font("font")
		if font: reset_mission_btn.add_theme_font_override("font", font)
		reset_mission_btn.add_theme_font_size_override("font_size", 32)
		var style = resume_btn.get_theme_stylebox("focus")
		if style: reset_mission_btn.add_theme_stylebox_override("focus", style)
		
	reset_mission_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reset_mission_btn.pressed.connect(_on_reset_mission_btn_pressed)
	vbox.add_child(reset_mission_btn)
	
	# --- CONFIGURAÇÃO DA CÂMERA ---
	camera_select_btn = OptionButton.new()
	camera_select_btn.name = "CameraSelectBtn"
	camera_select_btn.add_item("Opções de Câmera", 999) 
	camera_select_btn.add_item("Câmera: Normal", 0)
	camera_select_btn.add_item("Câmera: Capô", 1)
	camera_select_btn.add_item("Câmera: Longe", 2)
	
	camera_select_btn.focus_mode = Control.FOCUS_ALL
	
	if resume_btn:
		var font = resume_btn.get_theme_font("font")
		if font: camera_select_btn.add_theme_font_override("font", font)
		camera_select_btn.add_theme_font_size_override("font_size", 32)
		var style = resume_btn.get_theme_stylebox("focus")
		if style: camera_select_btn.add_theme_stylebox_override("focus", style)
		
	camera_select_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	camera_select_btn.item_selected.connect(_on_camera_selected)
	vbox.add_child(camera_select_btn)
	
	# Ordenação visual dos nós dentro da VBox
	vbox.move_child(abort_mission_btn, 0)
	vbox.move_child(reset_mission_btn, 1)
	vbox.move_child(camera_select_btn, 2)

func _on_camera_selected(index: int):
	if index == 0 and camera_select_btn.get_item_id(0) == 999: return
	
	var mode = camera_select_btn.get_item_id(index)
	get_tree().call_group("jogadores", "set_camera_mode", mode)

func _input(event):
	if start_menu and start_menu.visible:
		return

	if pode_pausar and Input.is_action_just_pressed("Pause"):
		_toggle_pause()

func _toggle_pause():
	if not pode_pausar: return
	
	if Global.current_run_mode == Global.RunMode.FREE_ROAM:
		%ScrollContainer.visible = false
	
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	
	if new_pause_state:
		_atualizar_lista_missoes()
		
		var story_controller = get_tree().get_first_node_in_group("StoryController")
		var has_mission = story_controller and story_controller.has_method("has_active_mission") and story_controller.has_active_mission()
		
		if abort_mission_btn:
			abort_mission_btn.visible = has_mission
			abort_mission_btn.disabled = not has_mission
			
		# --- NOVO: Controla exibição do botão de reset ---
		if reset_mission_btn:
			reset_mission_btn.visible = has_mission
			reset_mission_btn.disabled = not has_mission
		
		# Define onde o foco inicial do controle/teclado vai pousar ao abrir o menu
		if has_mission and reset_mission_btn:
			reset_mission_btn.grab_focus()
		elif camera_select_btn:
			camera_select_btn.grab_focus()
	else:
		get_viewport().gui_release_focus()

func _atualizar_lista_missoes():
	if not mission_container: return
	for child in mission_container.get_children(): child.queue_free()
	
	if Global.current_run_mode == Global.RunMode.STORY:
		_atualizar_lista_historia()
	else:
		_atualizar_lista_classica()

func _atualizar_lista_historia():
	# ---------------------------------------------------------
	# PARTE 1: MISSÕES
	# ---------------------------------------------------------
	var portals = get_tree().get_nodes_in_group("mission_portals")
	
	var titulo = Label.new()
	titulo.text = "--- MISSÕES DO MAPA ---"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_container.add_child(titulo)
	
	for portal in portals:
		if "mission_data" in portal and portal.mission_data:
			var m_data = portal.mission_data
			var is_completed = Global.completed_story_missions.has(m_data.mission_id)
			
			var h_box = HBoxContainer.new()
			var lbl = Label.new()
			
			var prefixo = "[✔] " if is_completed else "[ ] "
			lbl.text = prefixo + m_data.mission_name + " (" + str(m_data.mission_reward_points) + " pts)"
			lbl.add_theme_color_override("font_color", Color.GREEN if is_completed else Color.WHITE)
			
			h_box.add_child(lbl)
			mission_container.add_child(h_box)
			
	# ---------------------------------------------------------
	# PARTE 2: COLETÁVEIS SECRETOS
	# ---------------------------------------------------------
	var coletaveis = get_tree().get_nodes_in_group("story_collectibles")
	if coletaveis.size() > 0:
		var sep_col = HSeparator.new()
		mission_container.add_child(sep_col)
		
		var titulo_col = Label.new()
		titulo_col.text = "--- ITENS SECRETOS ---"
		titulo_col.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mission_container.add_child(titulo_col)
		
		for col in coletaveis:
			var h_box = HBoxContainer.new()
			var lbl = Label.new()
			
			var is_completed = false
			if "collectible_id" in col:
				is_completed = Global.collected_items_ids.has(col.collectible_id)
				
			var prefixo = "[✔] " if is_completed else "[ ] "
			var c_name = col.collectible_name if "collectible_name" in col else "Coletável Misterioso"
			var c_pts = col.points_value if "points_value" in col else 0
			
			lbl.text = prefixo + c_name + " (" + str(c_pts) + " pts)"
			lbl.add_theme_color_override("font_color", Color.AQUAMARINE if is_completed else Color.GRAY)
			
			h_box.add_child(lbl)
			mission_container.add_child(h_box)
	
	# ---------------------------------------------------------
	# PARTE 3: META DE PONTUAÇÃO
	# ---------------------------------------------------------
	var sep_meta = HSeparator.new()
	mission_container.add_child(sep_meta)
	
	var meta_lbl = Label.new()
	var pontos_atuais = Global.story_total_points
	var pontos_necessarios = Global.pontos_para_proximo_mapa if "pontos_para_proximo_mapa" in Global else 5000
	
	meta_lbl.text = "Progresso Total: " + str(pontos_atuais) + " / " + str(pontos_necessarios) + " pts"
	meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_lbl.add_theme_color_override("font_color", Color.YELLOW)
	meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_container.add_child(meta_lbl)

func _atualizar_lista_classica():
	var data = MissionManager.current_map_data
	if not data: return
	
	for i in range(data.missions.size()):
		var m = data.missions[i]
		var h_box = HBoxContainer.new()
		var lbl = Label.new()
		
		var is_locked = i >= 6 and not MissionManager.batch_2_unlocked
		
		if is_locked and not m.is_completed:
			lbl.text = "🔒 ??? (Secreta)"
			lbl.add_theme_color_override("font_color", Color.DIM_GRAY)
		else:
			var prefixo = "[✔] " if m.is_completed else "[ ] "
			lbl.text = prefixo + m.description
			lbl.add_theme_color_override("font_color", Color.GREEN if m.is_completed else Color.WHITE)
			
		h_box.add_child(lbl)
		mission_container.add_child(h_box)

func desativar_pausa():
	pode_pausar = false
	if get_tree().paused:
		_toggle_pause()

func _on_abort_mission_btn_pressed():
	_toggle_pause()
	var story_controller = get_tree().get_first_node_in_group("StoryController")
	if story_controller and story_controller.has_method("abort_current_mission"):
		story_controller.abort_current_mission()

func _on_reset_mission_btn_pressed():
	print("=========================================")
	print("[PauseMenu-DEBUG] Botão de Reiniciar Missão CLICADO!")
	_toggle_pause()
	
	var story_controller = get_tree().get_first_node_in_group("StoryController")
	if story_controller:
		print("[PauseMenu-DEBUG] StoryController ENCONTRADO no grupo!")
		if story_controller.has_method("restart_current_mission"):
			print("[PauseMenu-DEBUG] Método 'restart_current_mission' EXISTE! Enviando ordem...")
			story_controller.restart_current_mission()
		else:
			push_error("[PauseMenu-DEBUG] ERRO: O StoryController não tem a função 'restart_current_mission'!")
	else:
		push_error("[PauseMenu-DEBUG] ERRO: StoryController NÃO FOI ENCONTRADO na cena!")
	print("=========================================")

func _on_resume_btn_pressed():
	_toggle_pause()

func _on_menu_btn_pressed():
	get_tree().paused = false 
	get_tree().change_scene_to_file("res://Scenes/UI/Menu.tscn")

func _on_end_match_btn_pressed():
	_toggle_pause() 
	var controller = get_tree().get_first_node_in_group("LevelController")
	if controller and controller.has_method("encerrar_partida"):
		controller.encerrar_partida()

func _process(_delta):
	if visible:
		for esquema in ["K1", "J1", "J2", "J3", "J4"]:
			if Input.is_action_just_pressed("Action_" + esquema):
				var focused_node = get_viewport().gui_get_focus_owner()
				if focused_node is OptionButton:
					focused_node.show_popup()
				elif focused_node is Button:
					focused_node.pressed.emit()
