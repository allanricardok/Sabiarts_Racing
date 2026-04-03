# HUD.gd
extends CanvasLayer

@onready var ped_kill_label = find_child("PedKillLabel", true, false)
@onready var minimap_bg = get_node_or_null("UI_Base/MinimapBackground")
# NOVO: Referências para a Info do Alvo (como antes)
@onready var target_info_panel = get_node_or_null("UI_Base/TargetInfoPanel") 
@onready var target_name_label = get_node_or_null("UI_Base/TargetInfoPanel/NameLabel")
@onready var target_hp_bar = get_node_or_null("UI_Base/TargetInfoPanel/HPBar")
@onready var category_label = get_node_or_null("UI_Base/TargetInfoPanel/CategoryLabel")

# Variáveis que armazenam a "foto" do radar atual (como antes)
var _radar_targets : Array = []
var _radar_current_target : Node3D = null
var _radar_player_pos : Vector3 = Vector3.ZERO
var _radar_player_fwd : Vector3 = Vector3.FORWARD
var _radar_range : float = 180.0

# --- REFERÊNCIAS DE UI ---
@onready var ui_base = $UI_Base
@onready var messages = $Messages
@onready var toast_container = $Toasts

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel
@onready var timer_label = $UI_Base/TimerLabel
@onready var player_id_label = get_node_or_null("UI_Base/PlayerIDLabel")

# --- NAMETAGS E GOTAS 2D (NOVO) ---
# Dicionário que guarda as UIs criadas para cada inimigo
var _nametags_dict : Dictionary = {}
# Container na UI onde as gotas/nomes vão ficar
var nametags_container = Control.new()

# --- CONFIGURAÇÕES ---
@export var toast_font_size: int = 38
@export var multiplayer_ui_scale: float = 0.7 
const REFERENCE_WIDTH : float = 1280.0 

# --- ESTADO INTERNO ---
var _combo_display_version : int = 0
var player_suffix : String = ""
var my_player_id : int = -1
var my_car : BaseVehicle = null 

# --- INICIALIZAÇÃO ---

func _ready():
	air_time_label.visible = false
	air_message_label.visible = false
	
	# Adiciona o container das Nametags direto na HUD (fora do UI_Base para não herdar escala errada)
	add_child(nametags_container)
	
	# Conecta a HUD ao cofre global
	if GameStats:
		GameStats.pedestrian_killed.connect(_update_ped_kill_ui)
		# Garante que ele já comece mostrando o número certo
		_update_ped_kill_ui(GameStats.pedestrians_killed_this_run)
	
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	if not MissionManager.mission_completed.is_connected(_on_mission_completed):
		MissionManager.mission_completed.connect(_on_mission_completed)
	
	if not MissionManager.mission_updated.is_connected(_on_mission_updated):
		MissionManager.mission_updated.connect(_on_mission_updated)

func setup_hud(suffix: String, real_id: int):
	player_suffix = suffix
	my_player_id = real_id
	
	if not is_in_group("HUD"): add_to_group("HUD")
	add_to_group("HUD" + player_suffix)
	
	# --- CORREÇÃO DE AUTO-VISÃO (BUSCA EXATA PELO ID) ---
	# Em vez de pegar um carro aleatório, buscamos o carro que tem o SEU ID
	for p in get_tree().get_nodes_in_group("jogadores"):
		if "id" in p and p.id == my_player_id:
			my_car = p
			break
			
	var nome_do_carro = my_car.name if my_car else "NENHUM"
	print("[HUD DEBUG] HUD do Player ", my_player_id + 1, " conectada ao carro: ", nome_do_carro)
	
	if player_id_label:
		player_id_label.text = "PLAYER " + str(my_player_id + 1)
		player_id_label.modulate = Color.CYAN if my_player_id == 0 else Color.ORANGE
		
	print("[HUD] Player ", my_player_id + 1, " pronto no Viewport: ", get_viewport().name)
	
# --- PROCESSAMENTO ---

func _process(delta):
	_update_ui_scaling()
	_update_2d_nametags() # Atualiza as gotas e nomes todos os frames

# --- LÓGICA DAS GOTAS TÁTICAS DINÂMICAS (POLIDO, SEM AUTO-VISÃO E AJUSTÁVEL) ---
func _update_2d_nametags():
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	# --- REDE DE SEGURANÇA ---
	# Se o carro ainda não foi linkado, tenta linkar de novo antes de desenhar as gotas
	if not is_instance_valid(my_car):
		for p in get_tree().get_nodes_in_group("jogadores"):
			if "id" in p and p.id == my_player_id:
				my_car = p
				break
		# Se MESMO ASSIM não achar o seu carro, não desenha nada para não dar erro
		if not is_instance_valid(my_car): return
	
	# --- CONFIGURAÇÕES FÁCEIS (Ajuste aqui o tamanho e as distâncias!) ---
	# Tamanho base da UI (O quadradinho onde a gota vai caber dentro)
	var ui_base_size := Vector2(64, 64) 
	
# Distância (metros) que a gota mantém o tamanho máximo (100%)
	var dist_max_scale := 1.0 
	# Distância (metros) onde a gota atinge o tamanho mínimo (50%)
	var dist_min_scale := 10.0 
	# ---------------------------------------------------------------------

	var cat_index = 0
	if minimap_bg: cat_index = minimap_bg.active_category_index
	
	# 1. Limpeza de objetos deletados
	var keys_to_remove = []
	for p in _nametags_dict.keys():
		if not is_instance_valid(p):
			_nametags_dict[p]["container"].queue_free()
			keys_to_remove.append(p)
	for k in keys_to_remove: _nametags_dict.erase(k)
	
	# 2. Visibilidade (Mostra na Categoria 0 e 1)
	var show_tags = (cat_index == 0 or cat_index == 1)
	
	# Pega os Jogadores/Bots
	var players = get_tree().get_nodes_in_group("jogadores")
	
	# 3. FILTRO RÍGIDO ANTI-TORRETAS E ANTI-CENÁRIO
	var destructibles = get_tree().get_nodes_in_group("destructibles")
	var enemies = get_tree().get_nodes_in_group("inimigos")
	var invalid_tags = destructibles + enemies
	for inv in invalid_tags:
		if is_instance_valid(inv) and _nametags_dict.has(inv):
			_nametags_dict[inv]["container"].queue_free()
			_nametags_dict.erase(inv)

	for p in players:
		# --- CORREÇÃO: O JOGADOR NÃO VÊ A PRÓPRIA GOTA ---
		# Pula se for o próprio carro ou se não for válido
		if not is_instance_valid(p) or p == my_car: 
			# Se por algum erro a gota dele já existir, deleta ela
			if _nametags_dict.has(p):
				_nametags_dict[p]["container"].queue_free()
				_nametags_dict.erase(p)
			continue
		
		# Cria a UI se não existir
		if not _nametags_dict.has(p):
			var container = Control.new()
			nametags_container.add_child(container)
			
			var icon = TextureRect.new()
			# --- CAMINHO OFICIAL DO ÍCONE ---
			icon.texture = load("res://Assets/2D/location-pin.png") 
			
			# Configura o tamanho base e força a imagem a caber
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE 
			icon.custom_minimum_size = ui_base_size
			icon.size = ui_base_size
			icon.set_script(null) 
			container.add_child(icon)
			
			# --- PIVÔ CENTRAL (CORREÇÃO DE CENTRALIZAÇÃO) ---
# Centraliza o TextureRect e dá um empurrão extra de 15 pixels para cima
			icon.position = (-ui_base_size / 2.0) + Vector2(0, -15)
			# Centraliza o TextureRect dentro do container
			icon.position = -ui_base_size / 2.0
			
			# Transparência fixa de 50%
			icon.modulate.a = 0.5 
			
			_nametags_dict[p] = {"container": container, "icon": icon}
			
		var data = _nametags_dict[p]
		var container = data["container"]
		var icon = data["icon"]
		
		# Se a aba do minimapa não for de adversários, ou se estiver olhando pra trás, esconde
		if not show_tags or camera.is_position_behind(p.global_position):
			container.visible = false
			continue
			
		# --- REGRA DE DISTÂNCIA E ESCALA AJUSTÁVEL ---
		var dist = camera.global_position.distance_to(p.global_position)
		var scale_factor = 1.0
		
		# Se estiver longe do raio de tamanho máximo (dist_max_scale)
		if dist > dist_max_scale:
			# Distância total que a gota leva para encolher (Ex: 80m - 30m = 50m)
			var shrinking_distance = dist_min_scale - dist_max_scale
			# Calcula o progresso do encolhimento (Ex: se dist for 55m, progres é 0.5)
			var progress = clamp((dist - dist_max_scale) / shrinking_distance, 0.0, 1.0)
			# Interpola do tamanho 1.0 (100%) para 0.5 (50%)
			scale_factor = lerp(1.0, 0.5, progress)
		
		# Projeta a posição na tela (Sobe 2.3 metros para ficar no horizonte certo)
		var screen_pos = camera.unproject_position(p.global_position + Vector3(0, 2.3, 0))
		container.global_position = screen_pos
		container.visible = true
		
		# Aplica a escala dinâmica por distância
		container.scale = Vector2(scale_factor, scale_factor)
		
		# Cores de Lock-On
		if p == _radar_current_target:
			icon.modulate = Color.RED
			icon.modulate.a = 1.0 # Alvo travado fica 100% opaco
		else:
			icon.modulate = Color.WHITE
			icon.modulate.a = 0.5 # Gota tática normal volta a 50%

func _update_ui_scaling():
	var current_size = get_viewport().size
	if current_size.x == 0 or current_size.y == 0: return

	# Determina o fator de escala: Usa 1.0 se for Singleplayer, e a variável escolhida (ex: 0.7) no Multiplayer
	var scale_factor = 1.0
	if current_size.x < REFERENCE_WIDTH * 0.8: # Consideramos que se a tela é 20% menor que o padrão, dividiu
		scale_factor = multiplayer_ui_scale
	
	# 1. TRATAMENTO PARA FULL RECT (UI_Base)
	# Congelamos no canto (0,0) e aumentamos o tamanho virtual para compensar o encolhimento
	if ui_base:
		ui_base.anchor_left = 0.0
		ui_base.anchor_top = 0.0
		ui_base.anchor_right = 0.0
		ui_base.anchor_bottom = 0.0
		ui_base.offset_left = 0.0
		ui_base.offset_top = 0.0
		
		ui_base.scale = Vector2(scale_factor, scale_factor)
		ui_base.size = current_size / scale_factor

	# 2. TRATAMENTO PARA ELEMENTOS FLUTUANTES (Messages e Toasts)
	# Aplicamos escala sem mexer nas âncoras para não perder a posição original
	_scale_floating_control(messages, scale_factor)
	_scale_floating_control(toast_container, scale_factor)

# Calcula o pivô automático baseado nas âncoras para encolher no lugar certo
func _scale_floating_control(control: Control, scale_factor: float):
	if not control: return
	
	var anchor_center_x = (control.anchor_left + control.anchor_right) / 2.0
	var anchor_center_y = (control.anchor_top + control.anchor_bottom) / 2.0
	
	control.pivot_offset = Vector2(
		control.size.x * anchor_center_x,
		control.size.y * anchor_center_y
	)
	control.scale = Vector2(scale_factor, scale_factor)

# --- ATUALIZAÇÕES DE PONTUAÇÃO E INTERFACE (como antes) ---

func _on_score_updated(player_id: int, new_score: int):
	if player_id == my_player_id:
		if score_label:
			score_label.text = ScoreManager.format_score_with_dots(new_score)

func atualizar_arma(nome: String, muniçao: int):
	if weapon_label:
		weapon_label.text = nome + ": " + str(muniçao)

func update_combo_live(full_bbcode_text: String):
	_combo_display_version += 1
	air_time_label.visible = true
	air_time_label.text = full_bbcode_text
	air_message_label.visible = false 

func show_combo_final(full_bbcode_text: String, result_text: String):
	var version_at_start = _combo_display_version
	air_time_label.visible = true
	air_time_label.text = full_bbcode_text
	air_message_label.visible = true
	air_message_label.text = result_text
	
	await get_tree().create_timer(3.0).timeout
	
	if _combo_display_version == version_at_start:
		air_time_label.visible = false
		air_message_label.visible = false

func clear_combo_display():
	_combo_display_version += 1
	air_time_label.visible = false
	air_message_label.visible = false

func atualizar_timer(segundos: float):
	if not timer_label: return
	var minutos = int(segundos) / 60
	var resto_segundos = int(segundos) % 60
	timer_label.text = "%02d:%02d" % [minutos, resto_segundos]
	
	if segundos <= 10:
		timer_label.add_theme_color_override("font_color", Color.RED)
	else:
		timer_label.add_theme_color_override("font_color", Color.WHITE)

# --- SISTEMA DE TOASTS (MISSÕES) (como antes) ---

func _on_mission_completed(mission: MissionItem):
	criar_toast("⭐ CONCLUÍDO: " + mission.description, Color.YELLOW)

func _on_mission_updated(mission: MissionItem, current: float, target: float):
	if mission.type == MissionItem.Type.SPEED: return
	var status = str(int(current)) + "/" + str(int(target))
	criar_toast("📦 " + mission.description + ": " + status, Color.CYAN)

func criar_toast(texto: String, cor: Color):
	print("[HUD DEBUG] Gerando Toast na tela: ", texto)
	var label = Label.new()
	label.text = texto
	label.add_theme_font_size_override("font_size", toast_font_size)
	label.add_theme_color_override("font_color", cor)
	
	if toast_container:
		toast_container.add_child(label)
		var tween = create_tween().set_parallel(true)
		label.modulate.a = 0
		tween.tween_property(label, "modulate:a", 1.0, 0.2)
		
		await get_tree().create_timer(2.8).timeout
		
		var fade = create_tween()
		fade.tween_property(label, "modulate:a", 0.0, 0.4)
		fade.finished.connect(label.queue_free)

func update_radar_data(targets: Array, lockon_target: Node3D, player_pos: Vector3, player_fwd: Vector3, cat_index: int, cat_name: String):
	_radar_current_target = lockon_target
	
	if minimap_bg:
		minimap_bg.radar_targets = targets
		minimap_bg.current_target = lockon_target
		minimap_bg.player_pos = player_pos
		minimap_bg.player_fwd = player_fwd
		minimap_bg.active_category_index = cat_index 
		minimap_bg.queue_redraw()
		
	# Atualiza o texto visual da HUD com a Categoria
	if category_label:
		category_label.text = cat_name
		
	_update_target_info_ui()

func _update_target_info_ui():
	# CADEADO: Garante que o painel existe
	if not target_info_panel: return
	
	# --- REGRA 1: O PAINEL NUNCA MAIS SUMIR ---
	# A categoria sempre fica visível!
	target_info_panel.visible = true
	
	var display_target = _radar_current_target
	
	# --- NOVO FLUXO: FALLBACK DE DISTÂNCIA INFINITA ---
	# Se não temos alvo travado (ou se ele é um pedestre)...
	if not is_instance_valid(display_target) or display_target.is_in_group("pedestrians"):
		display_target = null
		var closest_dist = INF
		
		# Pega a categoria selecionada do minimapa para saber qual grupo procurar
		var cat_index = 0
		if minimap_bg: cat_index = minimap_bg.active_category_index
		
		# Define os grupos de busca globais (mundo inteiro) baseados na aba ativa
		var search_groups = []
		if cat_index == 0: search_groups = ["jogadores", "inimigos", "destructibles"]
		elif cat_index == 1: search_groups = ["jogadores"] # Adversaries
		elif cat_index == 2: search_groups = ["inimigos"] # Fuckers
		elif cat_index == 3: search_groups = ["destructibles"] # Environment

		for group_name in search_groups:
			for t in get_tree().get_nodes_in_group(group_name):
				if is_instance_valid(t) and t != my_car:
					# Cálculo de distância em 3D real
					var dist = my_car.global_position.distance_to(t.global_position)
					if dist < closest_dist:
						closest_dist = dist
						display_target = t # Elege o alvo mais próximo da categoria certa no MUNDO

	# --- ATUALIZAÇÃO DA UI COM O ALVO ESCOLHIDO ---
	if is_instance_valid(display_target):
		# Mostra as labels internas do painel
		if target_name_label: target_name_label.show(); target_name_label.text = display_target.name
		if target_hp_bar: target_hp_bar.show()
		
		# Busca dados de vida (HealthComponent)
		if target_hp_bar:
			var current_hp = 0.0
			var max_hp = 100.0
			var found_health_data = false
			var stats = display_target.find_child("StatsComponent*", true, false)
			
			if stats:
				current_hp = stats.current_health
				max_hp = stats.max_health
				found_health_data = true
			elif "health" in display_target and "max_health" in display_target:
				current_hp = display_target.health
				max_hp = display_target.max_health
				found_health_data = true
				
			if found_health_data:
				target_hp_bar.max_value = max_hp
				target_hp_bar.value = current_hp
				# Lógica de cor (Verde -> Amarelo -> Vermelho)
				var pct = (current_hp / max_hp) * 100.0
				var current_color = Color.RED
				if pct > 30.0: current_color = Color.YELLOW.lerp(Color.GREEN, (pct - 30.0) / 70.0)
				elif pct > 5.0: current_color = Color.RED.lerp(Color.YELLOW, (pct - 5.0) / 25.0)
				target_hp_bar.modulate = current_color
	else:
		# Se realmente não houver nada no mundo dessa categoria, esconde as labels internas
		if target_name_label: target_name_label.hide()
		if target_hp_bar: target_hp_bar.hide()

# Função que atualiza o texto quando alguém morre
func _update_ped_kill_ui(amount: int):
	if ped_kill_label:
		ped_kill_label.text = "x" + str(amount)
