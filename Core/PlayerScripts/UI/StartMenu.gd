# StartMenu.gd
extends CanvasLayer

@onready var mission_list = %MissionList 
@onready var desc_label = %MapDescription
@onready var start_button = %StartButton
@onready var mission_scroll = %ScrollContainer # Pegando o container inteiro para esconder

# --- NOVAS REFERÊNCIAS: Dicas de Controle ---
# Certifique-se de marcar "Use Unique Name" (%) no Editor para estes nós
@onready var control_img_key = get_node_or_null("%ControlHintKey")
@onready var control_img_joy = get_node_or_null("%ControlHintJoy")

# Botão de limpar dados (Unique Name no editor: ClearDataButton)
@onready var clear_button = get_node_or_null("%ClearDataButton")

func _ready():
	# IMPORTANTE: O Process Mode do StartMenu deve estar como "Always" no Inspetor
	get_tree().paused = true
	show()
	start_button.grab_focus()
	
	# Garante que as dicas de controle começam escondidas
	if control_img_key: control_img_key.hide()
	if control_img_joy: control_img_joy.hide()
	
	# --- LÓGICA ESPECÍFICA DO TUTORIAL ---
	if Global.current_run_mode == Global.RunMode.FREE_ROAM:
		print("[StartMenu] Modo Tutorial detectado. Configurando UI...")
		# Esconde a lista padrão de missões
		if mission_scroll:
			mission_scroll.visible = false
			
		# Tenta exibir a imagem de controle correta baseada no Jogador 1
		_exibir_controles_tutorial()
	
	# Conecta o botão de limpar dados se ele existir na cena
	if clear_button:
		clear_button.pressed.connect(_on_clear_data_btn_pressed)
		print("[StartMenu] Botão de reset de dados conectado.")
	
	# Aguarda o MissionManager carregar os dados persistentes
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
	var data = MissionManager.current_map_data
	if not data: 
		print("[StartMenu] Erro: Dados do mapa não encontrados no MissionManager.")
		return
	
	# 1. CARREGA A DESCRIÇÃO PRIMEIRO (Para todos os modos, incluindo Tutorial)
	var desc = data.get("map_description")
	if desc == null or desc == "":
		desc_label.text = data.map_name + "\nObjetivos da Fase:"
	else:
		desc_label.text = data.map_name + "\n" + desc
	
	# --- TRAVA DO TUTORIAL MUDOU PARA CÁ ---
	# Se for Tutorial, paramos a função aqui para não gerar a lista de checkboxes!
	if Global.current_run_mode == Global.RunMode.FREE_ROAM:
		return
	
	# 2. GERA A LISTA DE CAIXINHAS (Somente para Exploration)
	for child in mission_list.get_children(): 
		child.queue_free()
	
	print("[StartMenu] Preenchendo resumo de ", data.missions.size(), " missões.")

	for i in range(data.missions.size()):
		var m = data.missions[i]
		var item = Label.new()
		
		var is_secret = i >= 6 and not MissionManager.batch_2_unlocked
		
		if is_secret and not m.is_completed:
			item.text = "🔒 ??? (Bloqueada)"
			item.add_theme_color_override("font_color", Color.DIM_GRAY)
		else:
			var prefixo = "✔ " if m.is_completed else "□ "
			item.text = prefixo + m.description
			
			if m.is_completed:
				item.add_theme_color_override("font_color", Color.GREEN)
			else:
				item.add_theme_color_override("font_color", Color.WHITE)
		
		item.custom_minimum_size.y = 30 
		mission_list.add_child(item)

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

func _on_clear_data_btn_pressed():
	print("[StartMenu] Solicitando exclusão de dados do jogador.")
	# 1. Apaga o arquivo físico
	SaveManager.clear_data()
	
	# 2. Reseta o estado atual das missões em memória
	if MissionManager.current_map_data:
		for m in MissionManager.current_map_data.missions:
			m.is_completed = false
	
	MissionManager.completed_count = 0
	MissionManager.collection_progress.clear()
	MissionManager.batch_2_unlocked = false
	MissionManager.completed_mission_ids.clear()
	
	# 3. Atualiza a interface do menu imediatamente
	_preencher_missoes()
	print("[StartMenu] Interface resetada após limpeza de dados.")
