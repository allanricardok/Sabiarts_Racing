# StartMenu.gd
extends CanvasLayer

@onready var mission_list = %MissionList 
@onready var desc_label = %MapDescription
@onready var start_button = %StartButton
# Adicione este botão no seu editor e renomeie o Unique Name para ClearDataButton
@onready var clear_button = get_node_or_null("%ClearDataButton")

func _ready():
	# IMPORTANTE: O Process Mode do StartMenu deve estar como "Always" no Inspetor
	get_tree().paused = true
	show()
	start_button.grab_focus()
	
	# Conecta o botão de limpar dados se ele existir na cena
	if clear_button:
		clear_button.pressed.connect(_on_clear_data_btn_pressed)
		print("[StartMenu] Botão de reset de dados conectado.")
	
	# Aguarda o MissionManager carregar os dados persistentes
	await get_tree().process_frame
	_preencher_missoes()

func _preencher_missoes():
	var data = MissionManager.current_map_data
	if not data: 
		print("[StartMenu] Erro: Dados do mapa não encontrados no MissionManager.")
		return
	
	# Usamos 'get()' para tentar pegar o valor. Se não existir, ele usa o map_name.
	var desc = data.get("map_description")
	if desc == null or desc == "":
		desc_label.text = data.map_name + "\nObjetivos da Fase:"
	else:
		desc_label.text = data.map_name + "\n" + desc
	
	# Limpa a lista atual
	for child in mission_list.get_children(): 
		child.queue_free()
	
	print("[StartMenu] Preenchendo resumo de ", data.missions.size(), " missões.")

	for i in range(data.missions.size()):
		var m = data.missions[i]
		var item = Label.new()
		
		# Lógica de exibição baseada no progresso salvo e no Batch 2
		var is_secret = i >= 6 and not MissionManager.batch_2_unlocked
		
		if is_secret and not m.is_completed:
			# Se for secreta e NÃO concluída, fica escondida
			item.text = "🔒 ??? (Bloqueada)"
			item.add_theme_color_override("font_color", Color.DIM_GRAY)
		else:
			# Se for Batch 1, ou Batch 2 desbloqueado, ou já concluída (mesmo secreta)
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
