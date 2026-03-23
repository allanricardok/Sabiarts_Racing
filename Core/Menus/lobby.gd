extends Control

# --- MÁQUINA DE ESTADOS ---
enum State { ROOT, QUICK_PLAY, SINGLE_PLAYER, MULTIPLAYER, SETTINGS, VEHICLE_SELECT, MAP_SELECT }
var current_state = State.ROOT
var menu_index = 0

# --- REFERÊNCIAS DE TELAS (Arraste no Inspetor ou garanta que os nomes batem com sua árvore) ---
@onready var screens = {
	State.ROOT: $Screen_Root,
	State.QUICK_PLAY: $Screen_QuickPlay,
	State.SINGLE_PLAYER: $Screen_SinglePlayer,
	State.MULTIPLAYER: $Screen_Multiplayer,
	State.SETTINGS: $Screen_Settings,
	State.VEHICLE_SELECT: $Screen_JoinAndVehicle,
	State.MAP_SELECT: $Screen_MapSelect
}

# --- CONFIGURAÇÃO DE JOGO ---
@export var nomes_dos_mapas: Array[String] = ["Official_Test_Map"]
@export var cenas_dos_mapas: Array[PackedScene]
@export var carros_disponiveis: Array[PackedScene] # ARRASTE SEUS CARROS AQUI NO INSPETOR!

# --- REFERÊNCIAS ESPECÍFICAS DE UI ---
@onready var label_mapa_1 = $Screen_MapSelect/VBoxContainer/LabelMapa1 if has_node("Screen_MapSelect/VBoxContainer/LabelMapa1") else null
@onready var clear_data_button = find_child("ClearDataButton", true, false)
@onready var clear_scores_button = find_child("ClearScoresButton", true, false)
@onready var slots_ui = $Screen_JoinAndVehicle/HBoxContainer.get_children() if has_node("Screen_JoinAndVehicle/HBoxContainer") else []

# --- LÓGICA DE JOGADORES ---
var esquemas_disponiveis = ["K1", "J1", "J2", "J3", "J4"]
var nomes_controles = {"K1": "Keyboard 1", "J1": "Joystick 1", "J2": "Joystick 2", "J3": "Joystick 3", "J4": "Joystick 4"}
var jogadores_ativos = [null, null, null, null]
const ICON_KEYBOARD = preload("res://Assets/2D/images.jpg")
const ICON_JOYSTICK = preload("res://Assets/2D/explosion.png")

func _ready():
	if clear_data_button: clear_data_button.focus_mode = Control.FOCUS_NONE
	if clear_scores_button: clear_scores_button.focus_mode = Control.FOCUS_NONE
	_mudar_estado(State.ROOT)

func _mudar_estado(novo_estado: int):
	current_state = novo_estado
	menu_index = 0 # Reseta o cursor ao mudar de tela
	
	# Liga apenas a tela do estado atual
	for state_key in screens:
		if screens[state_key]:
			screens[state_key].visible = (state_key == current_state)
			
	_atualizar_visual_menus()

func _input(_event):
	# 1. LÓGICA DE NAVEGAÇÃO DOS MENUS SIMPLES
	if current_state in [State.ROOT, State.QUICK_PLAY, State.SINGLE_PLAYER, State.MULTIPLAYER, State.SETTINGS]:
		if Input.is_action_just_pressed("ui_up"):
			menu_index -= 1
			_atualizar_visual_menus()
		elif Input.is_action_just_pressed("ui_down"):
			menu_index += 1
			_atualizar_visual_menus()
			
		# Qualquer jogador pode navegar e confirmar menus genéricos
		for esquema in esquemas_disponiveis:
			if Input.is_action_just_pressed("Action_" + esquema):
				_confirmar_menu_simples()
				break
			if Input.is_action_just_pressed("Stunt_" + esquema):
				_voltar_menu_anterior()
				break

	# 2. LÓGICA DE ESCOLHA DE CARRO (Multijogador simultâneo)
	elif current_state == State.VEHICLE_SELECT:
		for i in range(4):
			var esquema = esquemas_disponiveis[i] # Simplificando para teste, ideal buscar do InputMap
			
			# SE NÃO ESTÁ NA SALA: Aperta Action para entrar
			var idx_jogador = _get_indice_jogador(esquema)
			if idx_jogador == -1:
				if Input.is_action_just_pressed("Action_" + esquema) or Input.is_action_just_pressed("Fire_" + esquema):
					_adicionar_jogador(esquema)
				continue
				
			# SE ESTÁ NA SALA:
			var p_data = jogadores_ativos[idx_jogador]
			if Input.is_action_just_pressed("Stunt_" + esquema):
				if p_data.pronto:
					p_data.pronto = false # Cancela o "Ready"
					_atualizar_ui_slot(idx_jogador)
				else:
					_remover_jogador(esquema) # Sai da sala se não estava ready
					if _get_contagem_jogadores() == 0: _voltar_menu_anterior()
					
			if not p_data.pronto:
				if Input.is_action_just_pressed("ui_left_" + esquema) or Input.is_action_just_pressed("ui_left"):
					p_data.carro_idx -= 1
					if p_data.carro_idx < 0: p_data.carro_idx = carros_disponiveis.size() - 1
					_atualizar_ui_slot(idx_jogador)
				elif Input.is_action_just_pressed("ui_right_" + esquema) or Input.is_action_just_pressed("ui_right"):
					p_data.carro_idx += 1
					if p_data.carro_idx >= carros_disponiveis.size(): p_data.carro_idx = 0
					_atualizar_ui_slot(idx_jogador)
				elif Input.is_action_just_pressed("Action_" + esquema):
					p_data.pronto = true
					_atualizar_ui_slot(idx_jogador)
					_checar_todos_prontos()

	# 3. LÓGICA DE SELEÇÃO DE MAPA
	elif current_state == State.MAP_SELECT:
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
			menu_index = 1 - menu_index # Alterna entre 0 e 1
			_atualizar_visual_menus()
		for esquema in esquemas_disponiveis:
			if Input.is_action_just_pressed("Action_" + esquema):
				_iniciar_corrida(menu_index)
				break
			if Input.is_action_just_pressed("Stunt_" + esquema):
				_mudar_estado(State.VEHICLE_SELECT)
				break

# --- FLUXO DE NAVEGAÇÃO ---
func _confirmar_menu_simples():
	match current_state:
		State.ROOT:
			if menu_index == 0: _mudar_estado(State.QUICK_PLAY)
			elif menu_index == 1: _mudar_estado(State.SETTINGS)
		State.QUICK_PLAY:
			if menu_index == 0: _mudar_estado(State.SINGLE_PLAYER)
			elif menu_index == 1: _mudar_estado(State.MULTIPLAYER)
		State.SINGLE_PLAYER:
			if menu_index == 0: Global.game_mode = "Free Roam"
			elif menu_index == 1: Global.game_mode = "Combat"
			_mudar_estado(State.VEHICLE_SELECT)
		State.MULTIPLAYER:
			if menu_index == 0: Global.game_mode = "Co-op"
			elif menu_index == 1: Global.game_mode = "PvP"
			_mudar_estado(State.VEHICLE_SELECT)
		State.SETTINGS:
			if menu_index == 0: _on_clear_data_pressed()
			elif menu_index == 1: _on_botao_apagar_scores_pressed()

func _voltar_menu_anterior():
	match current_state:
		State.QUICK_PLAY, State.SETTINGS: _mudar_estado(State.ROOT)
		State.SINGLE_PLAYER, State.MULTIPLAYER: _mudar_estado(State.QUICK_PLAY)
		State.VEHICLE_SELECT: _mudar_estado(State.SINGLE_PLAYER if Global.game_mode in ["Free Roam", "Combat"] else State.MULTIPLAYER)

func _atualizar_visual_menus():
	# Limita o índice para não bugar
	var max_opcoes = 2
	if current_state == State.SETTINGS: max_opcoes = 3
	if menu_index < 0: menu_index = max_opcoes - 1
	elif menu_index >= max_opcoes: menu_index = 0
	
	# Como você não me enviou o código de cor dos botões novos, você pode adicionar a lógica visual de "piscar" os botões selecionados aqui!
	if current_state == State.MAP_SELECT and label_mapa_1:
		label_mapa_1.modulate = Color(1, 1, 1) if menu_index == 0 else Color(0.3, 0.3, 0.3)

# --- SISTEMA DE VEÍCULOS ---
func _get_indice_jogador(esquema: String) -> int:
	for i in range(4):
		if jogadores_ativos[i] != null and jogadores_ativos[i].esquema == esquema: return i
	return -1

func _get_contagem_jogadores() -> int:
	var c = 0
	for p in jogadores_ativos: if p != null: c += 1
	return c

func _adicionar_jogador(esquema):
	for i in range(4):
		if jogadores_ativos[i] == null:
			jogadores_ativos[i] = {"esquema": esquema, "carro_idx": 0, "pronto": false}
			_atualizar_ui_slot(i)
			break

func _remover_jogador(esquema):
	var idx = _get_indice_jogador(esquema)
	if idx != -1:
		jogadores_ativos[idx] = null
		_resetar_ui_slot(idx)

func _atualizar_ui_slot(index):
	if slots_ui.size() <= index: return
	var slot = slots_ui[index]
	var p_data = jogadores_ativos[index]
	
	var label_press = slot.find_child("Label")
	var label_controle = slot.find_child("Controller")
	
	if label_press: label_press.hide()
	if label_controle:
		label_controle.text = "Carro " + str(p_data.carro_idx + 1) + (" (PRONTO!)" if p_data.pronto else "")
		label_controle.show()
		
	# Muda a cor se o cara estiver pronto
	slot.modulate = Color(0.5, 1.0, 0.5) if p_data.pronto else Color(1, 1, 1)

func _resetar_ui_slot(index):
	if slots_ui.size() <= index: return
	var slot = slots_ui[index]
	var label_press = slot.find_child("Label")
	var label_controle = slot.find_child("Controller")
	if label_press: label_press.show()
	if label_controle: label_controle.hide()
	slot.modulate = Color(1, 1, 1)

func _checar_todos_prontos():
	var ativos = 0
	var prontos = 0
	for p in jogadores_ativos:
		if p != null:
			ativos += 1
			if p.pronto: prontos += 1
	
	if ativos > 0 and ativos == prontos:
		_mudar_estado(State.MAP_SELECT)

func _iniciar_corrida(mapa_id: int = 0):
	# Salva no Global apenas os dados formatados
	for i in range(4):
		if jogadores_ativos[i] != null:
			Global.dados_jogadores[i] = {
				"esquema": jogadores_ativos[i].esquema,
				"carro_cena": carros_disponiveis[jogadores_ativos[i].carro_idx] # Salva A CENA que ele escolheu!
			}
		else:
			Global.dados_jogadores[i] = null
			
	if mapa_id < cenas_dos_mapas.size() and cenas_dos_mapas[mapa_id]:
		print("Iniciando mapa: ", nomes_dos_mapas[mapa_id], " | Modo: ", Global.game_mode)
		get_tree().change_scene_to_packed(cenas_dos_mapas[mapa_id])

# --- FUNÇÕES DE SETTINGS ---
func _on_clear_data_pressed():
	SaveManager.clear_data()
	if clear_data_button: clear_data_button.modulate = Color(1, 0, 0)
	get_tree().create_timer(0.2).timeout.connect(_atualizar_visual_menus)

func _on_botao_apagar_scores_pressed():
	SaveManager.clear_highscores()
	if clear_scores_button: clear_scores_button.modulate = Color(1, 0, 0)
	get_tree().create_timer(0.2).timeout.connect(_atualizar_visual_menus)
