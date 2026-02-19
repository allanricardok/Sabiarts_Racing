# pause_menu.gd
extends CanvasLayer

var pode_pausar: bool = true

## Arraste o nó StartMenu para este campo no Inspetor
@export var start_menu: CanvasLayer

# Use Unique Names (%) nos seus botões no editor!
@onready var resume_btn = %ResumeBtn 
@onready var menu_btn = %MenuBtn

func _input(event):
	if start_menu and start_menu.visible:
		return

	if pode_pausar and Input.is_action_just_pressed("Pause"):
		_toggle_pause()

func _toggle_pause():
	if not pode_pausar: return
	
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	
	if new_pause_state:
		# Se usar Unique Name (%), não precisa se preocupar com o caminho VBoxContainer/...
		if resume_btn:
			resume_btn.grab_focus()
	else:
		get_viewport().gui_release_focus()

func desativar_pausa():
	pode_pausar = false
	if get_tree().paused:
		_toggle_pause()

func _on_resume_btn_pressed():
	print("Botão Continuar pressionado!")
	_toggle_pause()

func _on_menu_btn_pressed():
	print("Botão Menu pressionado!")
	get_tree().paused = false 
	get_tree().change_scene_to_file("res://Scenes/UI/Menu.tscn")

func _process(_delta):
	if visible:
		for esquema in ["K1", "K2", "J1", "J2", "J3", "J4"]:
			if Input.is_action_just_pressed("Action_" + esquema):
				var focused_node = get_viewport().gui_get_focus_owner()
				if focused_node is Button:
					# Isso força o clique do botão focado
					focused_node.pressed.emit()
