extends Control

# --- MÁQUINA DE ESTADOS ---
enum State { ROOT, QUICK_PLAY, SINGLE_PLAYER, MULTIPLAYER, SETTINGS, VEHICLE_SELECT, MAP_SELECT }
var current_state = State.ROOT
var menu_index = 0

# --- REFERÊNCIAS DE TELAS (Esconde/Mostra os painéis inteiros) ---
@onready var screens = {
	State.ROOT: $Screen_Root,
	State.QUICK_PLAY: $Screen_QuickPlay,
	State.SINGLE_PLAYER: $Screen_SinglePlayer,
	State.MULTIPLAYER: $Screen_Multiplayer,
	State.SETTINGS: $Screen_Settings,
	State.VEHICLE_SELECT: $Screen_JoinAndVehicle,
	State.MAP_SELECT: $Screen_MapSelect
}

# --- SISTEMA DE UI ORGANIZADO (Foco Visual) ---
@onready var menu_options = {
	State.ROOT: [find_child("QuickPlay", true, false), find_child("Settings", true, false)],
	State.QUICK_PLAY: [find_child("SinglePlayer", true, false), find_child("Multiplayer", true, false)],
	State.SINGLE_PLAYER: [find_child("FreeRoam", true, false), find_child("Combat", true, false)],
	State.MULTIPLAYER: [find_child("Coop", true, false), find_child("PvP", true, false)],
	State.SETTINGS: [find_child("ClearDataButton", true, false), find_child("ClearScoresButton", true, false)],
	State.MAP_SELECT: [$Screen_MapSelect/VBoxContainer/LabelMapa1, $Screen_MapSelect/VBoxContainer/LabelMapa2]
}

# --- CONFIGURAÇÃO DE JOGO ---
@export var nomes_dos_mapas: Array[String] = ["Official_Test_Map"]
@export var cenas_dos_mapas: Array[PackedScene]
@export var carros_disponiveis: Array[PackedScene]

# --- REFERÊNCIAS ESPECÍFICAS DE UI ---
@onready var slots_ui = $Screen_JoinAndVehicle/HBoxContainer.get_children() if has_node("Screen_JoinAndVehicle/HBoxContainer") else []

# --- LÓGICA DE JOGADORES ---
var esquemas_disponiveis = ["K1", "J1", "J2", "J3", "J4"]
var nomes_controles = {"K1": "Keyboard 1", "J1": "Joystick 1", "J2": "Joystick 2", "J3": "Joystick 3", "J4": "Joystick 4"}
var jogadores_ativos = [null, null, null, null]
var max_players = 4 

const ICON_KEYBOARD = preload("res://Assets/2D/images.jpg")
const ICON_JOYSTICK = preload("res://Assets/2D/explosion.png")

func _ready():
	var btn_data = find_child("ClearDataButton", true, false)
	var btn_scores = find_child("ClearScoresButton", true, false)
	if btn_data: btn_data.focus_mode = Control.FOCUS_NONE
	if btn_scores: btn_scores.focus_mode = Control.FOCUS_NONE
	
	_mudar_estado(State.ROOT)

func _mudar_estado(novo_estado: int):
	current_state = novo_estado
	menu_index = 0
	
	if current_state == State.VEHICLE_SELECT:
		max_players = 1 if Global.game_mode in ["Free Roam", "Combat"] else 4
		for i in range(slots_ui.size()):
			slots_ui[i].visible = (i < max_players)
	
	for state_key in screens:
		if screens[state_key]:
			screens[state_key].visible = (state_key == current_state)
			
	_atualizar_visual_menus()

func _input(_event):
	# 1. LÓGICA DE NAVEGAÇÃO DOS MENUS SIMPLES
	if current_state in [State.ROOT, State.QUICK_PLAY, State.SINGLE_PLAYER, State.MULTIPLAYER, State.SETTINGS, State.MAP_SELECT]:
		if Input.is_action_just_pressed("ui_up"):
			menu_index -= 1
			_atualizar_visual_menus()
		elif Input.is_action_just_pressed("ui_down"):
			menu_index += 1
			_atualizar_visual_menus()
			
		for esquema in esquemas_disponiveis:
			if Input.is_action_just_pressed("Action_" + esquema):
				if current_state == State.MAP_SELECT: _iniciar_corrida(menu_index)
				else: _confirmar_menu_simples()
				break
			if Input.is_action_just_pressed("Stunt_" + esquema):
				_voltar_menu_anterior()
				break

	# 2. LÓGICA DE ESCOLHA DE CARRO
	elif current_state == State.VEHICLE_SELECT:
		if Input.is_action_just_pressed("Pause"): 
			if _todos_estao_prontos():
				_mudar_estado(State.MAP_SELECT)
			return 
			
		for esquema in esquemas_disponiveis:
			var idx_jogador = _get_indice_jogador(esquema)
			
			if idx_jogador == -1:
				if Input.is_action_just_pressed("Action_" + esquema) or Input.is_action_just_pressed("Fire_" + esquema):
					_adicionar_jogador(esquema)
				continue
				
			var p_data = jogadores_ativos[idx_jogador]
			
			if Input.is_action_just_pressed("Stunt_" + esquema):
				if p_data.pronto:
					p_data.pronto = false 
					_atualizar_ui_slot(idx_jogador)
				else:
					_remover_jogador(esquema) 
					if _get_contagem_jogadores() == 0: 
						_voltar_menu_anterior()
			
# Movimentação Horizontal e Confirmação (Apenas se não estiver Pronto)
			if not p_data.pronto:
				# USANDO AS SUAS AÇÕES JÁ EXISTENTES: "Left_" e "Right_" + esquema
				if Input.is_action_just_pressed("Left_" + esquema):
					p_data.carro_idx -= 1
					if p_data.carro_idx < 0: p_data.carro_idx = carros_disponiveis.size() - 1
					_atualizar_ui_slot(idx_jogador)
					
				elif Input.is_action_just_pressed("Right_" + esquema):
					p_data.carro_idx += 1
					if p_data.carro_idx >= carros_disponiveis.size(): p_data.carro_idx = 0
					_atualizar_ui_slot(idx_jogador)
					
				elif Input.is_action_just_pressed("Action_" + esquema) or Input.is_action_just_pressed("Fire_" + esquema):
					p_data.pronto = true
					_atualizar_ui_slot(idx_jogador)

# --- A MÁGICA VISUAL DOS MENUS ---
func _atualizar_visual_menus():
	if not menu_options.has(current_state): return
	
	var opcoes_atuais = menu_options[current_state]
	var max_opcoes = opcoes_atuais.size()
	
	if max_opcoes == 0: return
	
	if menu_index < 0: menu_index = max_opcoes - 1
	elif menu_index >= max_opcoes: menu_index = 0
	
	for i in range(max_opcoes):
		var node = opcoes_atuais[i]
		if not is_instance_valid(node): continue
			
		if i == menu_index:
			node.modulate = Color(1.0, 0.8, 0.0) 
			node.scale = Vector2(1.1, 1.1) 
		else:
			node.modulate = Color(0.4, 0.4, 0.4) 
			node.scale = Vector2(1.0, 1.0)

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
		State.VEHICLE_SELECT: 
			for i in range(4): _remover_jogador(esquemas_disponiveis[i])
			_mudar_estado(State.SINGLE_PLAYER if Global.game_mode in ["Free Roam", "Combat"] else State.MULTIPLAYER)
		State.MAP_SELECT: _mudar_estado(State.VEHICLE_SELECT)

# --- SISTEMA DE VEÍCULOS E LOBBY ---
var _carros_preview_instanciados = [null, null, null, null]

func _get_indice_jogador(esquema: String) -> int:
	for i in range(4):
		if jogadores_ativos[i] != null and jogadores_ativos[i].esquema == esquema: return i
	return -1

func _get_contagem_jogadores() -> int:
	var c = 0
	for p in jogadores_ativos: if p != null: c += 1
	return c

func _adicionar_jogador(esquema):
	for i in range(max_players):
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
	
	# --- INÍCIO DA MÁGICA DO NOME DO CARRO ---
	if label_controle:
		var nome_carro = "Carro Desconhecido"
		
		# Verifica se a cena do carro existe no Array
		if carros_disponiveis.size() > p_data.carro_idx and carros_disponiveis[p_data.carro_idx] != null:
			var cena = carros_disponiveis[p_data.carro_idx]
			
			# 1. .resource_path pega o caminho todo ("res://Carros/Fusca_Azul.tscn")
			# 2. .get_file() arranca as pastas ("Fusca_Azul.tscn")
			# 3. .get_basename() arranca o .tscn ("Fusca_Azul")
			# 4. .capitalize() tira o underline e deixa maiúsculo ("Fusca Azul")
			nome_carro = cena.resource_path.get_file().get_basename().capitalize()
			
		label_controle.text = nome_carro + (" (PRONTO!)" if p_data.pronto else "")
		label_controle.show()
	# --- FIM DA MÁGICA ---
		
	slot.modulate = Color(0.5, 1.0, 0.5) if p_data.pronto else Color(1, 1, 1)
	
	_atualizar_preview_3d(index, p_data.carro_idx)

func _atualizar_preview_3d(slot_index: int, carro_idx: int):
	var slot = slots_ui[slot_index]
	var spawn_point = slot.find_child("CarSpawnPoint", true, false)
	
	if not spawn_point: return 
		
	if _carros_preview_instanciados[slot_index] != null:
		_carros_preview_instanciados[slot_index].queue_free()
		_carros_preview_instanciados[slot_index] = null
		
	if carros_disponiveis.size() > 0 and carros_disponiveis[carro_idx]:
		var preview = _gerar_modelo_de_exibicao(carros_disponiveis[carro_idx])
		spawn_point.add_child(preview)
		preview.position = Vector3.ZERO
		_carros_preview_instanciados[slot_index] = preview

func _gerar_modelo_de_exibicao(cena_original: PackedScene) -> Node3D:
	var clone = cena_original.instantiate()
	clone.process_mode = Node.PROCESS_MODE_DISABLED
	clone.set_script(null)

	var lixo = []
	for filho in clone.find_children("*", "", true, false):
		if filho.get_script() != null:
			filho.set_script(null)

		if filho is Camera3D or filho is Control or filho is CollisionShape3D or filho is AudioStreamPlayer3D or filho is Light3D:
			lixo.append(filho)
		elif "Component" in filho.name or "Manager" in filho.name or filho is RayCast3D:
			lixo.append(filho)

	for node in lixo:
		node.queue_free()

	return clone

func _resetar_ui_slot(index):
	if slots_ui.size() <= index: return
	var slot = slots_ui[index]
	var label_press = slot.find_child("Label")
	var label_controle = slot.find_child("Controller")
	if label_press: label_press.show()
	if label_controle: label_controle.hide()
	slot.modulate = Color(1, 1, 1)
	
	if _carros_preview_instanciados[index] != null:
		_carros_preview_instanciados[index].queue_free()
		_carros_preview_instanciados[index] = null

func _todos_estao_prontos() -> bool:
	var ativos = 0
	var prontos = 0
	for p in jogadores_ativos:
		if p != null:
			ativos += 1
			if p.pronto: prontos += 1
	
	return (ativos > 0 and ativos == prontos)

func _iniciar_corrida(mapa_id: int = 0):
	for i in range(4):
		if jogadores_ativos[i] != null:
			var idx_carro_escolhido = jogadores_ativos[i].carro_idx
			Global.dados_jogadores[i] = {
				"esquema": jogadores_ativos[i].esquema,
				"carro_cena": carros_disponiveis[idx_carro_escolhido] 
			}
		else:
			Global.dados_jogadores[i] = null
			
	if mapa_id < cenas_dos_mapas.size() and cenas_dos_mapas[mapa_id]:
		print("Iniciando mapa: ", nomes_dos_mapas[mapa_id], " | Modo: ", Global.game_mode)
		get_tree().change_scene_to_packed(cenas_dos_mapas[mapa_id])

func _on_clear_data_pressed():
	SaveManager.clear_data()
	var btn = find_child("ClearDataButton", true, false)
	if btn: btn.modulate = Color(1, 0, 0)
	get_tree().create_timer(0.2).timeout.connect(_atualizar_visual_menus)

func _on_botao_apagar_scores_pressed():
	SaveManager.clear_highscores()
	var btn = find_child("ClearScoresButton", true, false)
	if btn: btn.modulate = Color(1, 0, 0)
	get_tree().create_timer(0.2).timeout.connect(_atualizar_visual_menus)
