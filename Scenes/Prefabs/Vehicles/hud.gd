# HUD.gd
extends CanvasLayer

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel

func _ready():
		# Adicionamos o HUD a um grupo para o WeaponManager achá-lo fácil
	add_to_group("HUD")
	air_time_label.visible = false
	air_message_label.visible = false

# Atualiza o cronômetro enquanto o jogador está no ar
func atualizar_cronometro_ar(tempo: float):
	air_time_label.visible = true
	air_time_label.text = "%.3f" % tempo # Formata para 3 casas decimais (milésimos)

# Mostra o resultado final e a mensagem
func mostrar_resultado_ar(tempo: float, pontos: int, mensagem: String):
	air_time_label.visible = true # Mantém o tempo final parado
	air_message_label.visible = true
	air_message_label.text = str(pontos) + " Ability Points\n" + mensagem
	
	# Timer para sumir tudo após 2 segundos
	await get_tree().create_timer(2.0).timeout
	air_time_label.visible = false
	air_message_label.visible = false

func atualizar_arma(nome: String, munição: int):
	var texto_mun = str(munição)
	
	weapon_label.text = nome.to_upper() + "\n" + texto_mun
