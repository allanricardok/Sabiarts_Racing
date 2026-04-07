# pause_menu.gd
extends CanvasLayer

var pode_pausar: bool = true

@export var start_menu: CanvasLayer
@onready var mission_container = %MissionList
@onready var resume_btn = %ResumeBtn 
@onready var menu_btn = %MenuBtn

# --- NOVO BOTÃO ---
@onready var end_match_btn = get_node_or_null("%EndMatchBtn")

func _input(event):
	if start_menu and start_menu.visible:
		return

	if pode_pausar and Input.is_action_just_pressed("Pause"):
		_toggle_pause()

func _toggle_pause():
	if not pode_pausar: return
	# Se for o Tutorial, esconde o painel inteiro de missões!
	if Global.current_run_mode == Global.RunMode.FREE_ROAM:
		# Substitua "$PainelDeMissoes" pelo nome do nó que segura o texto das missões no seu Menu
		%ScrollContainer.visible = false
	
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	
	if new_pause_state:
		print("[PauseMenu] Jogo pausado. Atualizando lista de missões.")
		if resume_btn:
			resume_btn.grab_focus()
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
	print("[PauseMenu] Lista sincronizada com segredos.")

func desativar_pausa():
	pode_pausar = false
	if get_tree().paused:
		_toggle_pause()

func _on_resume_btn_pressed():
	print("[PauseMenu] Botão Continuar pressionado.")
	_toggle_pause()

func _on_menu_btn_pressed():
	print("[PauseMenu] Saindo para o menu principal.")
	get_tree().paused = false 
	get_tree().change_scene_to_file("res://Scenes/UI/Menu.tscn")

# --- NOVA FUNÇÃO: FINALIZAR PARTIDA ---
func _on_end_match_btn_pressed():
	print("[PauseMenu] Finalizar Partida pressionado.")
	_toggle_pause() # Despausa o jogo e esconde o menu
	
	var controller = get_tree().get_first_node_in_group("LevelController")
	if controller and controller.has_method("encerrar_partida"):
		controller.encerrar_partida()
	else:
		push_error("[PauseMenu] LevelController não encontrado ou sem o método encerrar_partida()!")

func _process(_delta):
	if visible:
		for esquema in ["K1", "J1", "J2", "J3", "J4"]:
			if Input.is_action_just_pressed("Action_" + esquema):
				var focused_node = get_viewport().gui_get_focus_owner()
				if focused_node is Button:
					print("[PauseMenu] Botão ativado via ação de pulo: ", focused_node.name)
					focused_node.pressed.emit()
