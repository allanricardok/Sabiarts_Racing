# pause_menu.gd
extends CanvasLayer

var pode_pausar: bool = true

@export var start_menu: CanvasLayer
@onready var mission_container = %MissionList
@onready var resume_btn = %ResumeBtn 
@onready var end_match_btn = get_node_or_null("%EndMatchBtn")
@onready var main_button_container = $Control/VBoxContainer

# --- BOTÕES QUE AGORA VÊM DIRETAMENTE DO EDITOR ---
@onready var abort_mission_btn = get_node_or_null("%AbortMissionBtn")
@onready var reset_mission_btn = get_node_or_null("%ResetMissionBtn")
@onready var retry_last_btn = get_node_or_null("%RetryLastBtn")
@onready var camera_select_btn = get_node_or_null("%CameraSelectBtn")
@onready var toggle_ps1_btn = get_node_or_null("%TogglePS1Btn")

func _ready():
	# Conecta os outros botões (caso não estejam conectados no editor)
	if abort_mission_btn and not abort_mission_btn.pressed.is_connected(_on_abort_mission_btn_pressed):
		abort_mission_btn.pressed.connect(_on_abort_mission_btn_pressed)
	if reset_mission_btn and not reset_mission_btn.pressed.is_connected(_on_reset_mission_btn_pressed):
		reset_mission_btn.pressed.connect(_on_reset_mission_btn_pressed)
	if retry_last_btn and not retry_last_btn.pressed.is_connected(_on_retry_last_btn_pressed):
		retry_last_btn.pressed.connect(_on_retry_last_btn_pressed)

# --- CONEXÃO DO BOTÃO PS1 ---
	if toggle_ps1_btn:
		# CheckButtons usam o sinal 'toggled', que já entrega um bool (true/false)
		if not toggle_ps1_btn.toggled.is_connected(_on_toggle_ps1_toggled):
			toggle_ps1_btn.toggled.connect(_on_toggle_ps1_toggled)
			
		# Opcional, mas muito bom: Sincroniza o botão com o estado inicial do shader
		var shader = get_tree().get_first_node_in_group("ps1_shaders")
		if shader:
			toggle_ps1_btn.button_pressed = shader.visible

	# --- CONFIGURAÇÃO BLINDADA DO SUBMENU DE CÂMERA ---
	if camera_select_btn:
		# 1. Garante que o sinal "selecionou item" dispare a função
		if not camera_select_btn.item_selected.is_connected(_on_camera_selected):
			camera_select_btn.item_selected.connect(_on_camera_selected)
			
		# 2. Limpa qualquer lixo que tenha ficado no Editor e cria o submenu limpo!
		camera_select_btn.clear()
		camera_select_btn.add_item("Opções de Câmera", 999) 
		camera_select_btn.add_item("Câmera: Normal", 0)
		camera_select_btn.add_item("Câmera: Capô", 1)
		camera_select_btn.add_item("Câmera: Longe", 2)

func _on_camera_selected(index: int):
	# Se for o título (ID 999), ignora
	if camera_select_btn.get_item_id(index) == 999: return
	
	# Pega o ID (0, 1 ou 2) e manda o carro executar
	var mode = camera_select_btn.get_item_id(index)
	get_tree().call_group("jogadores", "set_camera_mode", mode)

func _input(event):
	if start_menu and start_menu.visible:
		return

	if pode_pausar and Input.is_action_just_pressed("Pause"):
		_toggle_pause()

func _toggle_pause():
	if not pode_pausar: return
	
	if Global.current_run_mode == Global.RunMode.FREE_ROAM:
		%ScrollContainer.visible = false
	
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	
	if new_pause_state:
		_atualizar_lista_missoes()
		
		var story_controller = get_tree().get_first_node_in_group("StoryController")
		var has_mission = false
		var can_retry = false
		
		if story_controller:
			# Lemos a variável booleana diretamente do controlador
			has_mission = story_controller.get("is_mission_running") == true
			
			# Pode tentar de novo se NÃO estiver em missão E tiver uma missão salva no histórico
			can_retry = (not has_mission) and (story_controller.get("last_played_mission") != null)
		
		# =================================================================
		# LÓGICA DE TOGGLE (Visibilidade e Bloqueio)
		# =================================================================
		if abort_mission_btn:
			abort_mission_btn.visible = has_mission
			abort_mission_btn.disabled = not has_mission
			
		if reset_mission_btn:
			reset_mission_btn.visible = has_mission
			reset_mission_btn.disabled = not has_mission
			
		if retry_last_btn:
			retry_last_btn.visible = can_retry
			retry_last_btn.disabled = not can_retry
		
		# Gerenciamento de Foco Automático
		if has_mission and reset_mission_btn:
			reset_mission_btn.grab_focus()
		elif can_retry and retry_last_btn:
			retry_last_btn.grab_focus()
		elif camera_select_btn and camera_select_btn.visible:
			camera_select_btn.grab_focus()
		elif resume_btn:
			resume_btn.grab_focus()
	else:
		get_viewport().gui_release_focus()

func _on_toggle_ps1_toggled(toggled_on: bool):
	# Pega todos os shaders (caso você adicione suporte a split-screen no futuro) e altera a visibilidade
	var shaders = get_tree().get_nodes_in_group("ps1_shaders")
	for shader in shaders:
		shader.visible = toggled_on

func _atualizar_lista_missoes():
	if not mission_container: return
	for child in mission_container.get_children(): child.queue_free()
	
	if Global.current_run_mode == Global.RunMode.STORY:
		_atualizar_lista_historia()
	else:
		_atualizar_lista_classica()

func _atualizar_lista_historia():
	var portals = get_tree().get_nodes_in_group("mission_portals")
	
	var titulo = Label.new()
	titulo.text = "--- MISSÕES DO MAPA ---"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_container.add_child(titulo)
	
	for portal in portals:
		if "mission_data" in portal and portal.mission_data:
			var m_data = portal.mission_data
			
			var required_pts = m_data.get("required_unlock_points")
			if required_pts == null: required_pts = 0
			
			var current_pts = Global.story_total_points if is_instance_valid(Global) else 0
			if current_pts < required_pts:
				continue
				
			var is_completed = false
			var total_pts = 0
			
			if "mission_tiers" in m_data and not m_data.mission_tiers.is_empty():
				is_completed = true
				for i in range(m_data.mission_tiers.size()):
					if m_data.mission_tiers[i]:
						total_pts += m_data.mission_tiers[i].reward_points
					
					var tier_key = m_data.mission_id + "_tier_" + str(i)
					if not Global.completed_mission_tiers.has(tier_key):
						is_completed = false
			else:
				is_completed = Global.completed_story_missions.has(m_data.mission_id)
				var rew = m_data.get("mission_reward_points")
				total_pts = rew if rew != null else 0
			
			var h_box = HBoxContainer.new()
			var lbl = Label.new()
			
			var prefixo = "[✔] " if is_completed else "[ ] "
			lbl.text = prefixo + m_data.mission_name + " (Máx: " + str(total_pts) + " pts)"
			lbl.add_theme_color_override("font_color", Color.GREEN if is_completed else Color.WHITE)
			
			h_box.add_child(lbl)
			mission_container.add_child(h_box)

	var coletaveis = get_tree().get_nodes_in_group("story_collectibles")
	if coletaveis.size() > 0:
		var sep_col = HSeparator.new()
		mission_container.add_child(sep_col)
		
		var titulo_col = Label.new()
		titulo_col.text = "--- ITENS SECRETOS ---"
		titulo_col.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mission_container.add_child(titulo_col)
		
		for col in coletaveis:
			var h_box = HBoxContainer.new()
			var lbl = Label.new()
			
			var is_completed = false
			if "collectible_id" in col:
				is_completed = Global.collected_items_ids.has(col.collectible_id)
				
			var prefixo = "[✔] " if is_completed else "[ ] "
			var c_name = col.collectible_name if "collectible_name" in col else "Coletável Misterioso"
			var c_pts = col.points_value if "points_value" in col else 0
			
			lbl.text = prefixo + c_name + " (" + str(c_pts) + " pts)"
			lbl.add_theme_color_override("font_color", Color.AQUAMARINE if is_completed else Color.GRAY)
			
			h_box.add_child(lbl)
			mission_container.add_child(h_box)
	
	var sep_meta = HSeparator.new()
	mission_container.add_child(sep_meta)
	
	var meta_lbl = Label.new()
	var pontos_atuais = Global.story_total_points
	var pontos_necessarios = Global.pontos_para_proximo_mapa if "pontos_para_proximo_mapa" in Global else 5000
	
	meta_lbl.text = "Progresso Total: " + str(pontos_atuais) + " / " + str(pontos_necessarios) + " pts"
	meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_lbl.add_theme_color_override("font_color", Color.YELLOW)
	meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_container.add_child(meta_lbl)

func _atualizar_lista_classica():
	# O sistema clássico foi removido. Apenas exibimos um aviso no menu.
	var lbl = Label.new()
	lbl.text = "Modo Livre / Combate\n(Nenhuma missão ativa)"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color.GRAY)
	
	mission_container.add_child(lbl)

func desativar_pausa():
	pode_pausar = false
	if get_tree().paused:
		_toggle_pause()

# =================================================================
# --- FUNÇÕES DOS BOTÕES ---
# =================================================================

func _on_retry_last_btn_pressed():
	_toggle_pause()
	var story_controller = get_tree().get_first_node_in_group("StoryController")
	if story_controller and story_controller.has_method("start_last_played_mission"):
		story_controller.start_last_played_mission()

func _on_abort_mission_btn_pressed():
	_toggle_pause()
	var story_controller = get_tree().get_first_node_in_group("StoryController")
	if story_controller:
		# Verifica se o jogador já alcançou algum tier parcial
		var has_achieved_tiers = false
		if "completed_tiers_this_run" in story_controller:
			has_achieved_tiers = story_controller.completed_tiers_this_run.size() > 0
			
		# Se ele alcançou um Tier, encerramos a missão com "true" para forçar o recebimento dos bônus!
		if story_controller.has_method("end_mission"):
			story_controller.end_mission(has_achieved_tiers)
		elif story_controller.has_method("abort_current_mission"):
			story_controller.abort_current_mission()

func _on_reset_mission_btn_pressed():
	_toggle_pause()
	var story_controller = get_tree().get_first_node_in_group("StoryController")
	if story_controller and story_controller.has_method("restart_current_mission"):
		story_controller.restart_current_mission()

func _on_resume_btn_pressed():
	_toggle_pause()

func _on_menu_btn_pressed():
	get_tree().paused = false 
	get_tree().change_scene_to_file("res://Scenes/UI/Menu.tscn")

func _on_end_match_btn_pressed():
	_toggle_pause() 
	var controller = get_tree().get_first_node_in_group("LevelController")
	if controller and controller.has_method("encerrar_partida"):
		controller.encerrar_partida()

func _process(delta):
	if visible:
		for esquema in ["K1", "J1", "J2", "J3", "J4"]:
			if Input.is_action_just_pressed("Action_" + esquema):
				var focused_node = get_viewport().gui_get_focus_owner()
				if focused_node is OptionButton:
					focused_node.show_popup()
				elif focused_node is Button:
					focused_node.pressed.emit() # Voltou a ser exatamente o que você tinha!

# Conectado ao TogglePS1Btn (Apenas Mapa)
func _on_toggle_ps1_btn_toggled(toggled_on: bool):
	get_tree().call_group("mapa", "aplicar_shader_ps1", false, toggled_on)

# Conectado ao TogglePS1BtnUI (Tela Cheia)
func _on_toggle_ps1_btn_ui_toggled(toggled_on: bool):
	get_tree().call_group("mapa", "aplicar_shader_ps1", true, toggled_on)
