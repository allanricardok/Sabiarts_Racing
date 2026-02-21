# HUD.gd
extends CanvasLayer

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel
@onready var timer_label = $UI_Base/TimerLabel
@onready var toast_container = $Toasts

# Configurações de estilo para os Toasts (ajuste no Inspector)
@export var toast_font_size: int = 38

var _combo_display_version : int = 0

func _ready():
	add_to_group("HUD")
	air_time_label.visible = false
	air_message_label.visible = false
	
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	# Conexões com o MissionManager
	if not MissionManager.mission_completed.is_connected(_on_mission_completed):
		MissionManager.mission_completed.connect(_on_mission_completed)
	
	if not MissionManager.mission_updated.is_connected(_on_mission_updated):
		MissionManager.mission_updated.connect(_on_mission_updated)
	
	_on_score_updated(ScoreManager.total_score)
	print("[HUD] Sistema de HUD e Toasts inicializado.")

func _on_score_updated(new_score: int):
	if score_label:
		score_label.text = ScoreManager.format_score_with_dots(new_score)

func atualizar_arma(nome: String, muniçao: int):
	if weapon_label:
		weapon_label.text = nome + ": " + str(muniçao)

func atualizar_cronometro_ar(tempo: float):
	air_time_label.visible = true
	air_time_label.text = "Airtime: " + "%.2f" % tempo

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
		print("[HUD] Combo display limpo automaticamente.")

func clear_combo_display():
	_combo_display_version += 1
	air_time_label.visible = false
	air_message_label.visible = false
	air_time_label.text = ""

func atualizar_timer(segundos: float):
	if not timer_label: return
	var minutos = int(segundos) / 60
	var resto_segundos = int(segundos) % 60
	timer_label.text = "%02d:%02d" % [minutos, resto_segundos]
	
	if segundos <= 10:
		timer_label.add_theme_color_override("font_color", Color.RED)
	else:
		timer_label.add_theme_color_override("font_color", Color.WHITE)

func _on_mission_completed(mission: MissionItem):
	criar_toast("⭐ CONCLUÍDO: " + mission.description, Color.YELLOW)

func _on_mission_updated(mission: MissionItem, current: float, target: float):
	# TRAVA: Se for missão de velocidade, ignoramos o toast automático do Manager
	# pois o SpeedRadar já chama o toast manualmente com a velocidade exata.
	if mission.type == MissionItem.Type.SPEED:
		return
		
	var status = str(int(current)) + "/" + str(int(target))
	criar_toast("📦 " + mission.description + ": " + status, Color.CYAN)

func criar_toast(texto: String, cor: Color):
	var label = Label.new()
	label.text = texto
	
	# Aplicação dinâmica de estilo e tamanho
	label.add_theme_font_size_override("font_size", toast_font_size)
	label.add_theme_color_override("font_color", cor)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	
	if toast_container:
		toast_container.add_child(label)
		print("[HUD] Toast criado: ", texto)
		
		# Animação via Tween
		label.modulate.a = 0
		label.position.x += 60 
		var tween = create_tween().set_parallel(true)
		tween.tween_property(label, "modulate:a", 1.0, 0.2)
		tween.tween_property(label, "position:x", label.position.x - 60, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
		# Timer de vida do Toast
		await get_tree().create_timer(2.8).timeout
		
		var fade = create_tween()
		fade.tween_property(label, "modulate:a", 0.0, 0.4)
		fade.finished.connect(label.queue_free)
