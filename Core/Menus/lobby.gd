extends Control

# --- MÁQUINA DE ESTADOS ---
enum State { ROOT, QUICK_PLAY, SINGLE_PLAYER, MULTIPLAYER, SETTINGS, VEHICLE_SELECT, MAP_SELECT }
var current_state = State.ROOT
var is_multiplayer_session : bool = false
var menu_index = 0

# --- REFERÊNCIAS DE TELAS ---
@onready var screens = {
	State.ROOT: $Screen_Root,
	State.QUICK_PLAY: $Screen_QuickPlay,
	State.SINGLE_PLAYER: $Screen_SinglePlayer,
	State.MULTIPLAYER: $Screen_Multiplayer,
	State.SETTINGS: $Screen_Settings,
	State.VEHICLE_SELECT: $Screen_JoinAndVehicle,
	State.MAP_SELECT: $Screen_MapSelect
}

# --- SISTEMA DE UI ORGANIZADO ---
@onready var menu_options = {
	State.ROOT: [find_child("QuickPlay", true, false), find_child("Settings", true, false)],
	State.QUICK_PLAY: [find_child("SinglePlayer", true, false), find_child("Multiplayer", true, false)],
	State.SINGLE_PLAYER: [
		find_child("Tutorial", true, false),   # Index 0
		find_child("Story", true, false),      # Index 1
		find_child("FreeRoam", true, false),   # Index 2
		find_child("Combat", true, false)      # Index 3
	], 
	State.MULTIPLAYER: [find_child("Coop", true, false), find_child("PvP", true, false)],
	State.SETTINGS: [find_child("ClearDataButton", true, false), find_child("ClearScoresButton", true, false)],
	State.MAP_SELECT: $Screen_MapSelect/VBoxContainer.get_children() if has_node("Screen_MapSelect/VBoxContainer") else []
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
		max_players = 4 if is_multiplayer_session else 1
		for i in range(slots_ui.size()):
			slots_ui[i].visible = (i < max_players)
	
	for state_key in screens:
		if screens[state_key]:
			screens[state_key].visible = (state_key == current_state)
			
	_atualizar_visual_menus()

func _process(_delta):
	# 1. LÓGICA DE ESCOLHA DE CARRO (Lobby)
	if current_state == State.VEHICLE_SELECT:
		for esquema in esquemas_disponiveis:
			
			var accept_pressed = false
			var cancel_pressed = false
			
			# ISOLAMENTO DE TECLADO: Mouse devolvido para testes
			if esquema == "K1":
				if InputMap.has_action("Menu_Accept_K1") and Input.is_action_just_pressed("Menu_Accept_K1"): accept_pressed = true
				if InputMap.has_action("Action_K1") and Input.is_action_just_pressed("Action_K1"): accept_pressed = true
				if InputMap.has_action("Fire_K1") and Input.is_action_just_pressed("Fire_K1"): accept_pressed = true
				if InputMap.has_action("Menu_Cancel_K1") and Input.is_action_just_pressed("Menu_Cancel_K1"): cancel_pressed = true
			else:
				if InputMap.has_action("Action_" + esquema) and Input.is_action_just_pressed("Action_" + esquema): accept_pressed = true
				if InputMap.has_action("Fire_" + esquema) and Input.is_action_just_pressed("Fire_" + esquema): accept_pressed = true
				if InputMap.has_action("Stunt_" + esquema) and Input.is_action_just_pressed("Stunt_" + esquema): cancel_pressed = true
			
			# Start Partida
			if InputMap.has_action("Pause_" + esquema) and Input.is_action_just_pressed("Pause_" + esquema): 
				if _todos_estao_prontos():
					if Global.current_run_mode == Global.RunMode.FREE_ROAM:
						_iniciar_corrida(0) 
					else:
						_mudar_estado(State.MAP_SELECT)
				return 
				
			var idx_jogador = _get_indice_jogador(esquema)
			
			# Entrar no Lobby
			if idx_jogador == -1:
				if accept_pressed:
					_adicionar_jogador(esquema)
				continue
				
			var p_data = jogadores_ativos[idx_jogador]
			
			# Sair ou Desmarcar Pronto
			if cancel_pressed:
				if p_data.pronto:
					p_data.pronto = false 
					_atualizar_ui_slot(idx_jogador)
				else:
					_remover_jogador(esquema) 
					if _get_contagem_jogadores() == 0: 
						_voltar_menu_anterior()
			
			# Trocar de Carro e Confirmar
			if not p_data.pronto:
				var btn_left = false
				var btn_right = false
				
				if InputMap.has_action("Left_" + esquema) and Input.is_action_just_pressed("Left_" + esquema): btn_left = true
				if InputMap.has_action("cat_left_" + esquema) and Input.is_action_just_pressed("cat_left_" + esquema): btn_left = true
				
				if InputMap.has_action("Right_" + esquema) and Input.is_action_just_pressed("Right_" + esquema): btn_right = true
				if InputMap.has_action("cat_right_" + esquema) and Input.is_action_just_pressed("cat_right_" + esquema): btn_right = true
				
				if btn_left:
					p_data.carro_idx -= 1
					if p_data.carro_idx < 0: p_data.carro_idx = carros_disponiveis.size() - 1
					_atualizar_ui_slot(idx_jogador)
					
				elif btn_right:
					p_data.carro_idx += 1
					if p_data.carro_idx >= carros_disponiveis.size(): p_data.carro_idx = 0
					_atualizar_ui_slot(idx_jogador)
					
				elif accept_pressed:
					p_data.pronto = true
					_atualizar_ui_slot(idx_jogador)

	# 2. LÓGICA DE NAVEGAÇÃO DOS MENUS SIMPLES
	else:
		var moved_this_frame = false
		
		for esquema in esquemas_disponiveis:
			var accept_pressed = false
			var cancel_pressed = false
			var btn_up = false
			var btn_down = false
			
			# ISOLAMENTO DE TECLADO: Mouse devolvido para testes
			if esquema == "K1":
				if InputMap.has_action("Menu_Accept_K1") and Input.is_action_just_pressed("Menu_Accept_K1"): accept_pressed = true
				if InputMap.has_action("Action_K1") and Input.is_action_just_pressed("Action_K1"): accept_pressed = true
				if InputMap.has_action("Fire_K1") and Input.is_action_just_pressed("Fire_K1"): accept_pressed = true
				if InputMap.has_action("Menu_Cancel_K1") and Input.is_action_just_pressed("Menu_Cancel_K1"): cancel_pressed = true
				if InputMap.has_action("Menu_Up_K1") and Input.is_action_just_pressed("Menu_Up_K1"): btn_up = true
				if InputMap.has_action("Menu_Down_K1") and Input.is_action_just_pressed("Menu_Down_K1"): btn_down = true
			else:
				if InputMap.has_action("Action_" + esquema) and Input.is_action_just_pressed("Action_" + esquema): accept_pressed = true
				if InputMap.has_action("Fire_" + esquema) and Input.is_action_just_pressed("Fire_" + esquema): accept_pressed = true
				if InputMap.has_action("Stunt_" + esquema) and Input.is_action_just_pressed("Stunt_" + esquema): cancel_pressed = true
				
				# CORREÇÃO DA INVERSÃO (CIMA NO MENU) -> Pitch_Down = Analógico para Cima!
				if InputMap.has_action("target_up_" + esquema) and Input.is_action_just_pressed("target_up_" + esquema): btn_up = true
				
				# CORREÇÃO DA INVERSÃO (BAIXO NO MENU) -> Pitch_Up = Analógico para Baixo!
				if InputMap.has_action("target_down_" + esquema) and Input.is_action_just_pressed("target_down_" + esquema): btn_down = true
			
			# Confirmar
			if accept_pressed:
				if current_state == State.MAP_SELECT: 
					_iniciar_corrida(menu_index + 1)
				else: 
					_confirmar_menu_simples()
				break
				
			# Voltar
			elif cancel_pressed:
				_voltar_menu_anterior()
				break
				
			# Executa Navegação
			if not moved_this_frame:
				if btn_up:
					menu_index -= 1
					_atualizar_visual_menus()
					moved_this_frame = true
					
				elif btn_down:
					menu_index += 1
					_atualizar_visual_menus()
					moved_this_frame = true
# ==============================================================================
# RESTANTE DO CÓDIGO (Visual, Fluxo e Lobby) MANTIDO INTACTO
# ==============================================================================

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

func _confirmar_menu_simples():
	match current_state:
		State.ROOT:
			if menu_index == 0: _mudar_estado(State.QUICK_PLAY)
			elif menu_index == 1: _mudar_estado(State.SETTINGS)
		State.QUICK_PLAY:
			if menu_index == 0: 
				is_multiplayer_session = false
				_mudar_estado(State.SINGLE_PLAYER)
			elif menu_index == 1: 
				is_multiplayer_session = true
				_mudar_estado(State.MULTIPLAYER)
		State.SINGLE_PLAYER:
			if menu_index == 0: 
				Global.current_run_mode = Global.RunMode.FREE_ROAM
				Global.spawn_bots = false
			elif menu_index == 1: 
				Global.current_run_mode = Global.RunMode.STORY
				Global.spawn_bots = false 
			elif menu_index == 2: 
				Global.current_run_mode = Global.RunMode.EXPLORATION
				Global.spawn_bots = false
			elif menu_index == 3: 
				Global.current_run_mode = Global.RunMode.BATTLE
				Global.spawn_bots = true
			_mudar_estado(State.VEHICLE_SELECT)
		State.MULTIPLAYER:
			Global.current_run_mode = Global.RunMode.BATTLE
			if menu_index == 0: 
				Global.spawn_bots = true # COOP
			elif menu_index == 1: 
				Global.spawn_bots = false # PVP Puro
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
			_mudar_estado(State.MULTIPLAYER if is_multiplayer_session else State.SINGLE_PLAYER)
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
	
	if label_controle:
		var nome_carro = "Carro Desconhecido"
		
		if carros_disponiveis.size() > p_data.carro_idx and carros_disponiveis[p_data.carro_idx] != null:
			var cena = carros_disponiveis[p_data.carro_idx]
			nome_carro = cena.resource_path.get_file().get_basename().capitalize()
			
		label_controle.text = nome_carro + (" (PRONTO!)" if p_data.pronto else "")
		label_controle.show()
		
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

		if filho is Camera3D or filho is Control or filho is CollisionShape3D or filho is AudioStreamPlayer3D or filho is Light3D or filho is Label3D:
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
		Global.current_map = nomes_dos_mapas[mapa_id]
		print("Iniciando mapa: ", nomes_dos_mapas[mapa_id], " | Modo: ", Global.RunMode.keys()[Global.current_run_mode])
		get_tree().change_scene_to_packed(cenas_dos_mapas[mapa_id])

func _on_clear_data_pressed():
	SaveManager.clear_data()
	
	if SaveManager.has_method("clear_story_data"):
		SaveManager.clear_story_data()
	
	if is_instance_valid(Global):
		if "completed_story_missions" in Global:
			Global.completed_story_missions.clear()
		if "story_total_points" in Global:
			Global.story_total_points = 0
		if "collected_items_ids" in Global:
			Global.collected_items_ids.clear()
			
		if "completed_mission_tiers" in Global:
			Global.completed_mission_tiers.clear()
		if "missions_repeated_this_run" in Global:
			Global.missions_repeated_this_run.clear()
			
		if Global.has_method("save_story_progress"):
			Global.save_story_progress()
		
	var btn = find_child("ClearDataButton", true, false)
	if btn: btn.modulate = Color(1, 0, 0)
	
	get_tree().create_timer(0.2).timeout.connect(_atualizar_visual_menus)
	
func _on_botao_apagar_scores_pressed():
	SaveManager.clear_highscores()
	var btn = find_child("ClearScoresButton", true, false)
	if btn: btn.modulate = Color(1, 0, 0)
	get_tree().create_timer(0.2).timeout.connect(_atualizar_visual_menus)
