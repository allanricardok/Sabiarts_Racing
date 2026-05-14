# pause_menu.gd
extends CanvasLayer

var pode_pausar: bool = true

@export var start_menu: CanvasLayer
@onready var mission_container = %MissionList
@onready var resume_btn = %ResumeBtn 
@onready var menu_btn = %MenuBtn
@onready var end_match_btn = get_node_or_null("%EndMatchBtn")

var camera_select_btn: OptionButton

func _ready():
	_setup_camera_button()

func _setup_camera_button():
	camera_select_btn = OptionButton.new()
	camera_select_btn.name = "CameraSelectBtn"
	camera_select_btn.add_item("Opções de Câmera", 999) # Placeholder inicial
	camera_select_btn.add_item("Câmera: Normal", 0)
	camera_select_btn.add_item("Câmera: Capô", 1)
	camera_select_btn.add_item("Câmera: Longe", 2)
	
	# Habilita o foco para o controle
	camera_select_btn.focus_mode = Control.FOCUS_ALL
	
	if resume_btn:
		var font = resume_btn.get_theme_font("font")
		if font: camera_select_btn.add_theme_font_override("font", font)
		camera_select_btn.add_theme_font_size_override("font_size", 32)
		var style = resume_btn.get_theme_stylebox("focus")
		if style: camera_select_btn.add_theme_stylebox_override("focus", style)
		
	camera_select_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	camera_select_btn.item_selected.connect(_on_camera_selected)
	
	var vbox = $Control/VBoxContainer
	if vbox:
		vbox.add_child(camera_select_btn)
		vbox.move_child(camera_select_btn, 0) # COLOCA COMO PRIMEIRO BOTÃO

func _on_camera_selected(index: int):
	# Ignora o clique no placeholder se necessário
	if index == 0 and camera_select_btn.get_item_id(0) == 999: return
	
	var mode = camera_select_btn.get_item_id(index)
	print("[PauseMenu] Alterando câmera para o modo: ", mode)
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
		# Ao pausar, o foco vai para o seletor de câmera que é o primeiro
		if camera_select_btn:
			camera_select_btn.grab_focus()
		_atualizar_lista_missoes()
	else:
		get_viewport().gui_release_focus()

func _atualizar_lista_missoes():
	if not mission_container: return
	for child in mission_container.get_children(): child.queue_free()
	
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
					# No caso do OptionButton, simula o clique para abrir o popup
					focused_node.show_popup()
				elif focused_node is Button:
					focused_node.pressed.emit()
