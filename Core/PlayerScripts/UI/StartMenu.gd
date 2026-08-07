# StartMenu.gd
extends CanvasLayer

@onready var mission_list = %MissionList 
@onready var desc_label = %MapDescription
@onready var start_button = %StartButton
@onready var mission_scroll = %ScrollContainer # Pegando o container inteiro para esconder

# --- NOVAS REFERÊNCIAS: Dicas de Controle ---
@onready var control_img_key = get_node_or_null("%ControlHintKey")
@onready var control_img_joy = get_node_or_null("%ControlHintJoy")

# Botão de limpar dados (Unique Name no editor: ClearDataButton)
@onready var clear_button = get_node_or_null("%ClearDataButton")

func _ready():
	get_tree().paused = true
	show()
	start_button.grab_focus()
	
	# Zera as flags de repetição de missão da run anterior ao entrar no menu
	if is_instance_valid(Global) and "missions_repeated_this_run" in Global:
		Global.missions_repeated_this_run.clear()
	
	# --- CORREÇÃO: Removida a linha _mudar_estado(State.ROOT) que gerava o erro de escopo ---
	
	# Garante que as dicas de controle começam escondidas
	if control_img_key: control_img_key.hide()
	if control_img_joy: control_img_joy.hide()
	
	# --- LÓGICA ESPECÍFICA DO TUTORIAL ---
	if Global.current_run_mode == Global.RunMode.FREE_ROAM:
		print("[StartMenu] Modo Tutorial detectado. Configurando UI...")
		if mission_scroll:
			mission_scroll.visible = false
		_exibir_controles_tutorial()
	
	if clear_button:
		# Evita conexões duplicadas limpando conexões antigas se houverem
		if clear_button.pressed.is_connected(_on_clear_data_btn_pressed):
			clear_button.pressed.disconnect(_on_clear_data_btn_pressed)
		clear_button.pressed.connect(_on_clear_data_btn_pressed)
		print("[StartMenu] Botão de reset de dados conectado.")
	
	await get_tree().process_frame
	_preencher_missoes()

# --- NOVA FUNÇÃO: DETECÇÃO DE CONTROLE (SÓ TUTORIAL) ---
func _exibir_controles_tutorial():
	# Proteção caso os nós não tenham sido criados no editor
	if not control_img_key or not control_img_joy:
		print("[StartMenu] Erro: Nós de dica de controle (Key/Joy) não encontrados na cena.")
		return

	# No tutorial (Single Player), só precisamos olhar os dados do Jogador 1 (Índice 0)
	if Global.dados_jogadores.size() > 0 and Global.dados_jogadores[0] != null:
		var p1_data = Global.dados_jogadores[0]
		
		# O Global armazena uma Dictionary: {"esquema": "K1", "carro_cena": PackedScene}
		var esquema_input = "K1" # Fallback padrão
		
		if p1_data is Dictionary and p1_data.has("esquema"):
			esquema_input = p1_data["esquema"]
		elif p1_data is String: # Suporte caso a estrutura antiga ainda exista
			esquema_input = p1_data
			
		# Checa se o esquema começa com 'K' (Keyboard) ou 'J' (Joystick)
		if esquema_input.begins_with("K"):
			print("[StartMenu] Tutorial: Detectado Teclado (", esquema_input, "). Mostrando KEY.")
			control_img_key.show()
			control_img_joy.hide()
		elif esquema_input.begins_with("J"):
			print("[StartMenu] Tutorial: Detectado Joystick (", esquema_input, "). Mostrando JOY.")
			control_img_key.hide()
			control_img_joy.show()
		else:
			print("[StartMenu] Tutorial: Esquema desconhecido (", esquema_input, "). Padrão para KEY.")
			control_img_key.show()
	else:
		# Se por algum motivo não houver dados de jogador (bug no lobby), mostra teclado por padrão
		print("[StartMenu] Tutorial Aviso: Sem dados do P1 no Global. Padrão para KEY.")
		control_img_key.show()

# --- LÓGICA EXISTENTE MANTIDA ---

func _preencher_missoes():
	# A lista de caixinhas não existe mais, pois as missões ficam nos portais 3D!
	# Vamos apenas esconder o painel para manter a UI limpa.
	if mission_scroll:
		mission_scroll.visible = false
		
	# Deixamos a descrição genérica do mapa
	if desc_label:
		desc_label.text = "Objetivos da Fase:\nExplore o mapa e encontre os portais de missão!"

func _on_clear_data_btn_pressed():
	print("[StartMenu] Solicitando exclusão de dados do jogador.")
	# 1. Apaga o arquivo físico
	SaveManager.clear_data()
	
	# 2. Atualiza a interface
	_preencher_missoes()
	print("[StartMenu] Interface resetada após limpeza de dados.")
	
	# 3. Zera os dados Globais
	if is_instance_valid(Global):
		Global.total_tokens = 0
		Global.missions_repeated_this_run.clear()
		if "completed_story_missions" in Global:
			Global.completed_story_missions.clear()
		if "completed_mission_tiers" in Global:
			Global.completed_mission_tiers.clear()
		Global.save_player_profile()

func _on_start_btn_pressed():
	print("[StartMenu] Botão Start pressionado! Despausando jogo.")
	get_tree().paused = false
	hide()
	
	# Avisa o LevelController para iniciar a lógica de jogo
	var logic = get_tree().get_first_node_in_group("LevelLogic")
	if logic and logic.has_method("start_timer"): 
		logic.start_timer()
		print("[StartMenu] Cronômetro iniciado via LevelLogic.")
	else:
		print("[StartMenu] AVISO: LevelLogic não encontrado ou função start_timer ausente.")
