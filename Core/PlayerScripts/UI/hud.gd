# HUD.gd
extends CanvasLayer

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel

func _ready():
	add_to_group("HUD")
	air_time_label.visible = false
	air_message_label.visible = false
	
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	_on_score_updated(ScoreManager.total_score)
	print("HUD: Inicializado e conectado ao ScoreManager")

func _on_score_updated(new_score: int):
	if score_label:
		score_label.text = ScoreManager.format_score_with_dots(new_score)

func atualizar_arma(nome: String, muniçao: int):
	if weapon_label:
		weapon_label.text = nome + ": " + str(muniçao)

# --- SISTEMA DE COMBO UNIFICADO ---

## Chamado pelos Managers para atualizar o texto enquanto o combo acontece
func update_combo_live(actions_list: Array, points_list: Array, multiplier: int, extra_info: String = ""):
	air_message_label.visible = true
	
	var names_text = " + ".join(actions_list)
	if extra_info != "":
		names_text += " + " + extra_info
		
	var math_text = str(multiplier) + "x " + " + ".join(points_list.map(func(p): return str(p)))
	
	air_message_label.text = names_text + "\n" + math_text
	print("HUD: Atualizando display de combo: ", multiplier, "x")

## Chamado quando o combo fecha (pouso ou timer de inatividade)
func show_combo_final(total_points: int, message: String):
	air_message_label.visible = true
	air_message_label.text = message + "\n" + str(total_points) + " points"
	
	# Timer para limpar o HUD após a exibição final
	var timer_id = Time.get_ticks_msec()
	air_message_label.set_meta("last_timer_id", timer_id)
	
	await get_tree().create_timer(2.5).timeout
	
	# Só esconde se não houver um novo combo sobrepondo
	if air_message_label.get_meta("last_timer_id") == timer_id:
		air_message_label.visible = false
		air_time_label.visible = false
		print("HUD: Combo display limpo.")

func atualizar_cronometro_ar(tempo: float):
	air_time_label.visible = true
	air_time_label.text = "Airtime: " + "%.2f" % tempo
