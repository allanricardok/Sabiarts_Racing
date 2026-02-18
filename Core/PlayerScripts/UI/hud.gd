# HUD.gd
extends CanvasLayer

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel

var _combo_display_version : int = 0

func _ready():
	add_to_group("HUD")
	air_time_label.visible = false
	air_message_label.visible = false
	
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	_on_score_updated(ScoreManager.total_score)

func _on_score_updated(new_score: int):
	if score_label:
		score_label.text = ScoreManager.format_score_with_dots(new_score)

# RESTAURADA: Função que as armas chamam
func atualizar_arma(nome: String, muniçao: int):
	if weapon_label:
		weapon_label.text = nome + ": " + str(muniçao)

# RESTAURADA: Função de airtime simples
func atualizar_cronometro_ar(tempo: float):
	air_time_label.visible = true
	air_time_label.text = "Airtime: " + "%.2f" % tempo

# --- SISTEMA DE COMBO (FIXED) ---

## Live: Atualiza apenas a AirTimeLabel com as manobras e a conta
func update_combo_live(full_info_text: String):
	_combo_display_version += 1
	air_time_label.visible = true
	air_time_label.text = full_info_text
	air_message_label.visible = false 

## Final: Mantém a AirTimeLabel e mostra a AirMessageLabel com o prêmio
func show_combo_final(full_info_text: String, result_text: String):
	var version_at_start = _combo_display_version
	
	air_time_label.visible = true
	air_time_label.text = full_info_text
	
	air_message_label.visible = true
	air_message_label.text = result_text
	
	await get_tree().create_timer(3.0).timeout
	
	if _combo_display_version == version_at_start:
		air_time_label.visible = false
		air_message_label.visible = false
