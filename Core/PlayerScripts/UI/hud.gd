# HUD.gd
extends CanvasLayer

# --- REFERÊNCIAS DE UI ---
@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel
@onready var timer_label = $UI_Base/TimerLabel
@onready var toast_container = $Toasts
@onready var player_id_label = get_node_or_null("UI_Base/PlayerIDLabel")

# Retículo (Certifique-se que o nome do nó na cena seja 'Reticle' ou 'lockon_rect')
# Vou usar 'lockon_rect' para bater com o seu script anterior
@onready var lockon_rect = $UI_Base/Reticle 

# --- CONFIGURAÇÕES ---
@export var toast_font_size: int = 38

# --- ESTADO INTERNO ---
var _combo_display_version : int = 0
var player_suffix : String = ""
var my_player_id : int = -1
var my_car : BaseVehicle = null # Referência única do carro deste Viewport

# --- INICIALIZAÇÃO ---

func _ready():
	air_time_label.visible = false
	air_message_label.visible = false
	
	# Conexão com o ScoreManager (Filtro por ID)
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	# Conexões Globais de Missões
	if not MissionManager.mission_completed.is_connected(_on_mission_completed):
		MissionManager.mission_completed.connect(_on_mission_completed)
	
	if not MissionManager.mission_updated.is_connected(_on_mission_updated):
		MissionManager.mission_updated.connect(_on_mission_updated)

# Função chamada pelo BaseVehicle no nascimento
func setup_hud(suffix: String, real_id: int):
	player_suffix = suffix
	my_player_id = real_id
	
	# Entra no grupo global para o Timer e no específico para o Carro
	if not is_in_group("HUD"): add_to_group("HUD")
	add_to_group("HUD" + player_suffix)
	
	# --- BUSCA DO CARRO LOCAL ---
	# Procura o carro que compartilha o MESMO Viewport que este HUD
	# Isso garante que o retículo do P2 não olhe para o alvo do P1
	my_car = get_viewport().find_child("*", true, false) as BaseVehicle
	
	# Atualização visual do nome do jogador
	if player_id_label:
		player_id_label.text = "PLAYER " + str(my_player_id + 1)
		# Diferenciação por cor para facilitar o teste
		player_id_label.modulate = Color.CYAN if my_player_id == 0 else Color.ORANGE
		
	print("[HUD] Player ", my_player_id + 1, " pronto no Viewport: ", get_viewport().name)

# --- PROCESSAMENTO ---

func _process(_delta):
	_update_lockon_reticle()

# --- LÓGICA DO RETÍCULO (INDIVIDUAL POR TELA) ---

func _update_lockon_reticle():
	# Se não houver carro ou o nó do retículo não existir, aborta
	if not lockon_rect or not my_car: 
		if lockon_rect: lockon_rect.visible = false
		return
	
	var weapon_manager = my_car.weapons
	if not weapon_manager: return
	
	var target = weapon_manager.current_target
	var active = weapon_manager.get_active_special()
	
	# Só mostra retículo se a arma for de mira e houver um alvo válido
	var is_aiming_weapon = active and (active.nome == "HomingMissile" or active.nome == "GrapplingMissile")
	
	if is_aiming_weapon and target and is_instance_valid(target):
		# PEGA A CÂMERA DO VIEWPORT LOCAL (A câmera da metade da tela deste jogador)
		var cam = get_viewport().get_camera_3d()
		
		if cam and not cam.is_position_behind(target.global_position):
			# Projeta a posição 3D para a tela 2D relativa a este Viewport
			var screen_pos = cam.unproject_position(target.global_position)
			lockon_rect.visible = true
			# Centraliza o desenho (ex: se o retículo tem 64x64, ele centraliza no ponto)
			lockon_rect.position = screen_pos - (lockon_rect.size / 2)
		else:
			lockon_rect.visible = false
	else:
		lockon_rect.visible = false

# --- ATUALIZAÇÕES DE PONTUAÇÃO E INTERFACE ---

func _on_score_updated(player_id: int, new_score: int):
	# FILTRO CRUCIAL: Só atualiza se o ponto for deste jogador específico
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

# --- SISTEMA DE TOASTS (MISSÕES) ---

func _on_mission_completed(mission: MissionItem):
	criar_toast("⭐ CONCLUÍDO: " + mission.description, Color.YELLOW)

func _on_mission_updated(mission: MissionItem, current: float, target: float):
	if mission.type == MissionItem.Type.SPEED: return
	var status = str(int(current)) + "/" + str(int(target))
	criar_toast("📦 " + mission.description + ": " + status, Color.CYAN)

func criar_toast(texto: String, cor: Color):
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
