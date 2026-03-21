extends Control

enum State { JOINING, SELECTING_MAP }
var current_state = State.JOINING

# --- CONFIGURAÇÃO ---
@export var nomes_dos_mapas: Array[String] = ["Official_Test_Map"]
@export var cenas_dos_mapas: Array[PackedScene]

# NOVO: Indíce unificado do menu (0 = Mapa 1, 1 = Mapa 2, 2 = Clear Data, 3 = Clear Scores)
var menu_index = 0

# Referências de UI
@onready var join_panel = $JoinPanel
@onready var map_panel = $MapPanel
@onready var label_mapa_1 = $MapPanel/VBoxContainer/LabelMapa1
@onready var label_mapa_2 = $MapPanel/VBoxContainer/LabelMapa2

# Usando find_child para achar os botões em qualquer lugar da árvore de forma segura
@onready var clear_data_button = find_child("ClearDataButton", true, false)
@onready var clear_scores_button = find_child("ClearScoresButton", true, false) # Confirme se o nome é esse!

# --- LÓGICA DE JOGADORES ---
var esquemas_disponiveis = ["K1", "J1", "J2", "J3", "J4"]
var nomes_controles = {"K1": "Keyboard 1", "J1": "Joystick 1", "J2": "Joystick 2", "J3": "Joystick 3", "J4": "Joystick 4"}
var jogadores_ativos = [null, null, null, null]

const ICON_KEYBOARD = preload("res://Assets/2D/images.jpg")
const ICON_JOYSTICK = preload("res://Assets/2D/explosion.png")
@onready var slots_ui = $JoinPanel/HBoxContainer.get_children()

func _ready():
	join_panel.show()
	map_panel.hide()
	
	# MATANDO O FOCO NATIVO PARA O MOUSE NÃO INTERFERIR COM O JOYSTICK
	if clear_data_button: clear_data_button.focus_mode = Control.FOCUS_NONE
	if clear_scores_button: clear_scores_button.focus_mode = Control.FOCUS_NONE
	
	_atualizar_visual_mapa()

func _process(_delta):
	if current_state == State.JOINING:
		if Input.is_action_just_pressed("Pause") and _get_contagem_jogadores() > 0:
			_mudar_para_selecao_mapa()
	elif current_state == State.SELECTING_MAP:
		_processar_navegacao_mapa()

func _input(_event):
	if current_state == State.JOINING:
		for esquema in esquemas_disponiveis:
			if esquema in jogadores_ativos: 
				if Input.is_action_just_pressed("Stunt_" + esquema):
					_remover_jogador(esquema)
				continue
				
			if Input.is_action_just_pressed("Fire_" + esquema) or Input.is_action_just_pressed("Action_" + esquema):
				_adicionar_jogador(esquema)

func _processar_navegacao_mapa():
	# 1. Start global
	if Input.is_action_just_pressed("Pause"):
		_iniciar_corrida()
		return

	# 2. Navegação GLOBAL (UP / DOWN) por 4 opções agora!
	if Input.is_action_just_pressed("ui_up"):
		menu_index -= 1
		if menu_index < 0: menu_index = 3 # Volta pro último
		_atualizar_visual_mapa()
		return
		
	if Input.is_action_just_pressed("ui_down"):
		menu_index += 1
		if menu_index > 3: menu_index = 0 # Volta pro primeiro
		_atualizar_visual_mapa()
		return

	# 3. Confirmação (Action) e Voltar (Trick)
	for esquema in jogadores_ativos:
		if esquema == null: continue
		
		if Input.is_action_just_pressed("Action_" + esquema):
			_confirmar_selecao()
			return 
			
		if Input.is_action_just_pressed("Stunt_" + esquema):
			_voltar_para_lobby()
			return 
	
func _atualizar_visual_mapa():
	label_mapa_1.text = nomes_dos_mapas[0] if nomes_dos_mapas.size() > 0 else "Map 1"
	
	# Desmarca todo mundo
	label_mapa_1.modulate = Color(0.3, 0.3, 0.3)
	if label_mapa_2: label_mapa_2.modulate = Color(0.3, 0.3, 0.3)
	if clear_data_button: clear_data_button.modulate = Color(0.3, 0.3, 0.3)
	if clear_scores_button: clear_scores_button.modulate = Color(0.3, 0.3, 0.3)
	
	# Acende só o que está selecionado
	match menu_index:
		0: label_mapa_1.modulate = Color(1, 1, 1)
		1: if label_mapa_2: label_mapa_2.modulate = Color(1, 1, 1)
		2: if clear_data_button: clear_data_button.modulate = Color(1, 1, 1)
		3: if clear_scores_button: clear_scores_button.modulate = Color(1, 1, 1)

func _confirmar_selecao():
	match menu_index:
		0:
			# Inicia Mapa 1
			_iniciar_corrida(0)
		1:
			# Inicia Mapa 2 (Se existir)
			if cenas_dos_mapas.size() > 1:
				_iniciar_corrida(1)
		2:
			# Aciona Reset de Dados
			_on_clear_data_pressed()
		3:
			# Aciona Reset de Scores
			_on_botao_apagar_scores_pressed()

func _mudar_para_selecao_mapa():
	current_state = State.SELECTING_MAP
	menu_index = 0 # Reseta o cursor pro primeiro mapa sempre que abrir
	_atualizar_visual_mapa()
	join_panel.hide()
	map_panel.show()

func _voltar_para_lobby():
	current_state = State.JOINING
	map_panel.hide()
	join_panel.show()

func _iniciar_corrida(mapa_id: int = 0):
	Global.dados_jogadores = jogadores_ativos
	if mapa_id < cenas_dos_mapas.size() and cenas_dos_mapas[mapa_id]:
		print("Iniciando mapa: ", nomes_dos_mapas[mapa_id])
		get_tree().change_scene_to_packed(cenas_dos_mapas[mapa_id])
	else:
		print("ERRO: Cena não encontrada ou não assinada no Inspetor!")

# --- AUXILIARES ---
func _get_contagem_jogadores():
	var c = 0
	for p in jogadores_ativos: if p != null: c += 1
	return c

func _adicionar_jogador(esquema):
	for i in range(4):
		if jogadores_ativos[i] == null:
			jogadores_ativos[i] = esquema
			_atualizar_ui_slot(i, esquema)
			break

func _remover_jogador(esquema):
	for i in range(4):
		if jogadores_ativos[i] == esquema:
			jogadores_ativos[i] = null
			_resetar_ui_slot(i)
			break

func _atualizar_ui_slot(index, esquema):
	var slot = slots_ui[index]
	var label_press = slot.find_child("Label")
	if label_press: label_press.hide()
	var label_controle = slot.find_child("Controller")
	if label_controle:
		label_controle.text = nomes_controles.get(esquema, esquema)
		label_controle.show()
	var icon_rect = slot.find_child("ControllerIcon")
	if icon_rect:
		icon_rect.texture = ICON_KEYBOARD if esquema.begins_with("K") else ICON_JOYSTICK
	slot.modulate = Color(1, 1, 1, 1)

func _resetar_ui_slot(index):
	var slot = slots_ui[index]
	var label_press = slot.find_child("Label")
	if label_press: label_press.show()
	var label_controle = slot.find_child("Controller")
	if label_controle: label_controle.hide()
	var icon_rect = slot.find_child("ControllerIcon")
	if icon_rect: icon_rect.texture = null

func _on_clear_data_pressed():
	print("[Lobby] Limpando persistência...")
	SaveManager.clear_data()
	if is_instance_valid(MissionManager):
		MissionManager.completed_mission_ids.clear()
		MissionManager.collection_progress.clear()
		MissionManager.completed_count = 0
		if MissionManager.current_map_data:
			for m in MissionManager.current_map_data.missions:
				m.is_completed = false
	
	# Efeito visual para mostrar que apertou o botão!
	if clear_data_button: clear_data_button.modulate = Color(1, 0, 0) # Pisca vermelho
	get_tree().create_timer(0.2).timeout.connect(_atualizar_visual_mapa)

func _on_botao_apagar_scores_pressed():
	print("[Lobby] Limpando Highscores...")
	SaveManager.clear_highscores()
	
	# Efeito visual para mostrar que apertou o botão!
	if clear_scores_button: clear_scores_button.modulate = Color(1, 0, 0)
	get_tree().create_timer(0.2).timeout.connect(_atualizar_visual_mapa)
