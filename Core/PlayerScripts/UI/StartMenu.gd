extends CanvasLayer

@onready var mission_list = %MissionList 
@onready var desc_label = %MapDescription
@onready var start_button = %StartButton
@onready var mission_scroll = %ScrollContainer 

# --- A CORTINA DE LOADING ---
@onready var loading_label = get_node_or_null("%LoadingLabel")

# --- O BURACO NEGRO DE CACHE (Arraste os TSCNs pesados aqui no Inspector!) ---
@export_group("Otimização de Shaders (Warm-up)")
@export var vfx_to_cache: Array[PackedScene] = []

# --- NOVAS REFERÊNCIAS: Dicas de Controle ---
@onready var control_img_key = get_node_or_null("%ControlHintKey")
@onready var control_img_joy = get_node_or_null("%ControlHintJoy")

# Botão de limpar dados
@onready var clear_button = get_node_or_null("%ClearDataButton")

func _ready():
	get_tree().paused = true
	show()
	
	# 1. PREPARA A UI DE LOADING
	start_button.hide()
	if loading_label: loading_label.show()
	
	# Zera as flags de repetição de missão da run anterior ao entrar no menu
	if is_instance_valid(Global) and "missions_repeated_this_run" in Global:
		Global.missions_repeated_this_run.clear()
	
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
		if clear_button.pressed.is_connected(_on_clear_data_btn_pressed):
			clear_button.pressed.disconnect(_on_clear_data_btn_pressed)
		clear_button.pressed.connect(_on_clear_data_btn_pressed)
	
	# 2. INICIA O PROCESSO DE COMPILAÇÃO DA GPU
	_aquecer_shaders_e_liberar_start()

# ==============================================================================
# NOVO: SISTEMA DE SHADER CACHING (WARM-UP)
# ==============================================================================
func _aquecer_shaders_e_liberar_start():
	var dummy_nodes = []
	print("[StartMenu] Iniciando compilação de shaders pesados...")

	# 1. Spawna todos os efeitos da lista num buraco negro cego
	for prefab in vfx_to_cache:
		if prefab:
			var inst = prefab.instantiate()
			# Se for um objeto 3D, manda pra debaixo da terra
			if inst is Node3D: inst.position = Vector3(0, -5000, 0)
			
			add_child(inst)
			dummy_nodes.append(inst)

			# 2. Força as partículas a emitirem um frame para a GPU processar o material
			if inst is CPUParticles3D or inst is GPUParticles3D:
				inst.emitting = true
			for child in inst.find_children("*", "CPUParticles3D", true):
				child.emitting = true
			for child in inst.find_children("*", "GPUParticles3D", true):
				child.emitting = true

	# 3. Dá 3 frames físicos para a Placa de Vídeo "engolir e mastigar" tudo
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# 4. Limpa a sujeira gerada
	for node in dummy_nodes:
		if is_instance_valid(node):
			node.queue_free()

	print("[StartMenu] Shaders cacheados com sucesso!")

	# 5. Esconde o Loading e libera o Botão de Start
	if loading_label: loading_label.hide()
	start_button.show()
	start_button.grab_focus()
	
	_preencher_missoes()

# --- NOVA FUNÇÃO: DETECÇÃO DE CONTROLE (SÓ TUTORIAL) ---
func _exibir_controles_tutorial():
	if not control_img_key or not control_img_joy:
		return

	if Global.dados_jogadores.size() > 0 and Global.dados_jogadores[0] != null:
		var p1_data = Global.dados_jogadores[0]
		var esquema_input = "K1" 
		
		if p1_data is Dictionary and p1_data.has("esquema"):
			esquema_input = p1_data["esquema"]
		elif p1_data is String: 
			esquema_input = p1_data
			
		if esquema_input.begins_with("K"):
			control_img_key.show()
			control_img_joy.hide()
		elif esquema_input.begins_with("J"):
			control_img_key.hide()
			control_img_joy.show()
		else:
			control_img_key.show()
	else:
		control_img_key.show()

# --- LÓGICA EXISTENTE MANTIDA ---
func _preencher_missoes():
	if mission_scroll:
		mission_scroll.visible = false
		
	if desc_label:
		desc_label.text = "Objetivos da Fase:\nExplore o mapa e encontre os portais de missão!"

func _on_clear_data_btn_pressed():
	SaveManager.clear_data()
	_preencher_missoes()
	
	if is_instance_valid(Global):
		Global.total_tokens = 0
		Global.missions_repeated_this_run.clear()
		if "completed_story_missions" in Global:
			Global.completed_story_missions.clear()
		if "completed_mission_tiers" in Global:
			Global.completed_mission_tiers.clear()
		Global.save_player_profile()

func _on_start_btn_pressed():
	get_tree().paused = false
	hide()
	
	var logic = get_tree().get_first_node_in_group("LevelLogic")
	if logic and logic.has_method("start_timer"): 
		logic.start_timer()
