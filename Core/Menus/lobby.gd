extends Control

enum State { JOINING, SELECTING_MAP }
var current_state = State.JOINING

# --- CONFIGURAÇÃO ---
# No topo do lobby.gd, substitua a const MAPAS por isso:
@export var nomes_dos_mapas: Array[String] = ["Official_Test_Map"]
@export var cenas_dos_mapas: Array[PackedScene]

var selected_map_index = 0

# Referências de UI
@onready var join_panel = $JoinPanel
@onready var map_panel = $MapPanel
@onready var label_mapa_1 = $MapPanel/VBoxContainer/LabelMapa1
@onready var label_mapa_2 = $MapPanel/VBoxContainer/LabelMapa2
# NOVO: Referência para o botão de zerar dados
@onready var clear_data_button = get_node_or_null("ClearDataButton")

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
	_atualizar_visual_mapa()
	
	# NOVO: Conexão do sinal do botão de zerar dados
	if clear_data_button:
		if not clear_data_button.pressed.is_connected(_on_clear_data_pressed):
			clear_data_button.pressed.connect(_on_clear_data_pressed)
		print("[Lobby] Botão ClearDataButton conectado.")
	else:
		print("[Lobby] AVISO: Nó 'ClearDataButton' não encontrado na cena.")

func _process(_delta):
	if current_state == State.JOINING:
		# Se alguém apertar Start/Pause e houver jogadores, vai para o mapa
		if Input.is_action_just_pressed("Pause") and _get_contagem_jogadores() > 0:
			_mudar_para_selecao_mapa()
	
	elif current_state == State.SELECTING_MAP:
		_processar_navegacao_mapa()

func _input(_event):
	if current_state == State.JOINING:
		for esquema in esquemas_disponiveis:
			if esquema in jogadores_ativos: continue
			if Input.is_action_just_pressed("Fire_" + esquema) or Input.is_action_just_pressed("Action_" + esquema):
				_adicionar_jogador(esquema)

func _processar_navegacao_mapa():
	# 1. Confirmação Global (Botão START / PAUSE)
	# Qualquer um que apertar Start inicia a corrida
	if Input.is_action_just_pressed("Pause"):
		_iniciar_corrida()
		return

	# 2. Navegação GLOBAL (FORA DO LOOP)
	# Verificamos apenas UMA vez por frame. Isso evita o bug de alternar 2x.
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
		selected_map_index = 1 - selected_map_index
		_atualizar_visual_mapa()
		# Opcional: toque um som de 'tick' de menu aqui!
		return

	# 3. Confirmação Individual (Botão X / JUMP)
	# Aqui sim usamos o loop, pois cada jogador tem seu próprio botão de pulo mapeado
	for esquema in jogadores_ativos:
		if esquema == null: continue
		if Input.is_action_just_pressed("Action_" + esquema):
			_iniciar_corrida()
			break # Sai do loop assim que o primeiro confirmar
	
func _atualizar_visual_mapa():
	# Atualiza os textos se você quiser que eles mudem conforme a lista do Inspetor
	label_mapa_1.text = nomes_dos_mapas[0]
	
	# Efeito de cor (Sua lógica original)
	label_mapa_1.modulate = Color(1, 1, 1) if selected_map_index == 0 else Color(0.3, 0.3, 0.3)

func _mudar_para_selecao_mapa():
	current_state = State.SELECTING_MAP
	join_panel.hide()
	map_panel.show()
	print("Entrando na seleção de mapa...")

func _iniciar_corrida():
	# 1. Envia os dados para o Global (Sua lógica original)
	Global.dados_jogadores = jogadores_ativos
	
	# 2. Pega a cena que você arrastou no slot correspondente
	var mapa_para_carregar = cenas_dos_mapas[selected_map_index]
	
	if mapa_para_carregar:
		print("Iniciando mapa: ", nomes_dos_mapas[selected_map_index])
		# Como é uma PackedScene (arrastada), usamos change_scene_to_packed
		get_tree().change_scene_to_packed(mapa_para_carregar)
	else:
		print("ERRO: Você esqueceu de arrastar a cena para o slot no Inspetor!")

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

# NOVO: Função para limpar os dados via botão no Lobby
func _on_clear_data_pressed():
	print("[Lobby] Botão de zerar dados pressionado. Limpando persistência...")
	
	# 1. Apaga o arquivo físico do disco
	SaveManager.clear_data()
	
	# 2. Limpa o estado atual do MissionManager em memória
	if MissionManager:
		MissionManager.completed_mission_ids.clear()
		MissionManager.collection_progress.clear()
		MissionManager.completed_count = 0
		if MissionManager.current_map_data:
			for m in MissionManager.current_map_data.missions:
				m.is_completed = false
				
	print("[Lobby] Dados resetados com sucesso.")

func _on_botao_apagar_scores_pressed():
	SaveManager.clear_highscores()
	# Aqui pode adicionar lógica extra, como atualizar a interface ou mostrar um aviso de sucesso.
