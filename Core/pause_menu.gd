extends Control

var pode_pausar: bool = true # A trava que você precisava

@onready var resume_btn = $VBoxContainer/ResumeBtn

func _ready():
	hide() # Começa escondido
	# Garante que os botões aceitem foco para navegação por teclado/controle
	resume_btn.focus_neighbor_bottom = $VBoxContainer/MenuBtn.get_path()
	$VBoxContainer/MenuBtn.focus_neighbor_top = resume_btn.get_path()

func _input(event):
	# Só processa a pausa se a corrida ainda não acabou
	if pode_pausar and Input.is_action_just_pressed("Pause"):
		_toggle_pause()

func _toggle_pause():
	# Se por algum motivo o jogo tentar pausar após o fim, bloqueia aqui também
	if not pode_pausar: return
	
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	
	if new_pause_state:
		resume_btn.grab_focus()
	else:
		release_focus()

# Função que o seu RaceManager vai chamar quando alguém cruzar a linha de chegada
func desativar_pausa():
	pode_pausar = false
	# Se o jogo estiver pausado no exato momento que acabar (raro, mas possível), despausa
	if get_tree().paused:
		_toggle_pause()

func _on_resume_btn_pressed():
	_toggle_pause()

func _on_menu_btn_pressed():
	get_tree().paused = false # IMPORTANTE: Despausar antes de mudar de cena
	get_tree().change_scene_to_file("res://Scenes/UI/Menu.tscn")

# Lógica para aceitar o botão de Pulo (X) como "Confirmar" na UI de pausa
func _process(_delta):
	if visible:
		# Checa se algum dos 4 jogadores apertou o botão de pulo (X)
		# Usando os mesmos prefixos que você configurou no Lobby
		for esquema in ["K1", "K2", "J1", "J2", "J3", "J4"]:
			if Input.is_action_just_pressed("Action_" + esquema):
				var focused_node = get_viewport().gui_get_focus_owner()
				if focused_node is Button:
					focused_node.pressed.emit()
