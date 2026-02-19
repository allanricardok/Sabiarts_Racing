# HUD.gd
extends CanvasLayer

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel # Agora é um RichTextLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel
@onready var timer_label = $UI_Base/TimerLabel

var _combo_display_version : int = 0

func _ready():
	add_to_group("HUD")
	air_time_label.visible = false
	air_message_label.visible = false
	
	# Garante que o RichTextLabel esteja configurado para centralizar se necessário
	# air_time_label.bbcode_enabled = true # Pode ser feito via código também
	
	if ScoreManager.is_connected("score_changed", _on_score_updated):
		ScoreManager.score_changed.disconnect(_on_score_updated)
	ScoreManager.score_changed.connect(_on_score_updated)
	
	_on_score_updated(ScoreManager.total_score)

func _on_score_updated(new_score: int):
	if score_label:
		score_label.text = ScoreManager.format_score_with_dots(new_score)

func atualizar_arma(nome: String, muniçao: int):
	if weapon_label:
		weapon_label.text = nome + ": " + str(muniçao)

func atualizar_cronometro_ar(tempo: float):
	# Se estiver apenas voando sem manobras, ainda usamos o air_time_label
	air_time_label.visible = true
	air_time_label.text = "Airtime: " + "%.2f" % tempo

# --- SISTEMA DE COMBO COLORIDO (BBCODE) ---

## Live: Recebe o texto já formatado com tags [color] dos Managers
func update_combo_live(full_bbcode_text: String):
	_combo_display_version += 1
	air_time_label.visible = true
	
	# O RichTextLabel interpreta as tags [color=#hex] automaticamente
	air_time_label.text = full_bbcode_text
	
	# Escondemos a mensagem final enquanto o combo está ativo
	air_message_label.visible = false 

## Final: Mostra o resumo detalhado e a mensagem de "Cool Trick"
func show_combo_final(full_bbcode_text: String, result_text: String):
	var version_at_start = _combo_display_version
	
	# Mantém a lista colorida no topo
	air_time_label.visible = true
	air_time_label.text = full_bbcode_text
	
	# Mostra a mensagem de pontos e o elogio (ex: Awesome Trick) embaixo
	air_message_label.visible = true
	air_message_label.text = result_text
	
	# Aguarda o tempo de exibição antes de limpar
	await get_tree().create_timer(3.0).timeout
	
	# Só limpa se um novo combo não tiver começado (controle de versão)
	if _combo_display_version == version_at_start:
		air_time_label.visible = false
		air_message_label.visible = false
		print("HUD: Combo display limpo.")

## Função utilitária para limpar tudo se o jogador bater ou resetar
func clear_combo_display():
	_combo_display_version += 1
	air_time_label.visible = false
	air_message_label.visible = false
	air_time_label.text = ""

# Função para atualizar o relógio
func atualizar_timer(segundos: float):
	if not timer_label: return
	
	# Formata segundos em MM:SS
	var minutos = int(segundos) / 60
	var resto_segundos = int(segundos) % 60
	timer_label.text = "%02d:%02d" % [minutos, resto_segundos]
	
	# Feedback visual: fica vermelho nos últimos 10 segundos
	if segundos <= 10:
		timer_label.add_theme_color_override("font_color", Color.RED)
	else:
		timer_label.add_theme_color_override("font_color", Color.WHITE)
