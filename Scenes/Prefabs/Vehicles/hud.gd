# HUD.gd
extends CanvasLayer

@onready var weapon_label = $UI_Base/WeaponLabel
@onready var air_time_label = $Messages/AirTimeLabel
@onready var air_message_label = $Messages/AirMessageLabel
@onready var score_label = $UI_Base/ScoreLabel # Certifique-se que o nome do nó está correto

func _ready():
		# Adicionamos o HUD a um grupo para o WeaponManager achá-lo fácil
	add_to_group("HUD")
	air_time_label.visible = false
	air_message_label.visible = false
	# Conecta o sinal do Global Score ao HUD
	ScoreManager.score_changed.connect(_on_score_updated)
	# Atualiza o valor inicial (caso já tenha pontos)
	_on_score_updated(ScoreManager.total_score)

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

func _on_score_updated(new_score):
	# 1. Chamamos a função através do Singleton ScoreManager
	# 2. Somamos o prefixo desejado ao resultado da função
	var pontos_formatados = ScoreManager.format_score_with_dots(new_score)
	
	score_label.text = "Match Points: " + pontos_formatados
	
func ocultar_cronometro_ar():
	# Se você usa um Label, pode apenas limpar o texto ou esconder o nó
	$Messages/AirTimeLabel.text = "" 
	# Ou se tiver um container: $AirTimeContainer.hide()

func atualizar_combo_live(tricks: Array, air_time: float):
	var texto_manobras = ""
	var texto_pontos = ""
	
	# Monta a string de nomes: "Roll + Backflip"
	for i in range(tricks.size()):
		texto_manobras += tricks[i].name
		texto_pontos += str(tricks[i].points)
		if i < tricks.size() - 1:
			texto_manobras += " + "
			texto_pontos += " + "
			
	# Adiciona o tempo de ar no final
	var ms_time = int(air_time * 1000)
	texto_manobras += " + %d ms air" % ms_time
	texto_pontos += " + %d" % int(air_time * 10)
	
	# Multiplicador
	var mult = max(1, tricks.size())
	
	# Exemplo de saída no Label: "Roll + Backflip + 1200 ms air"
	$LabelComboNomes.text = texto_manobras
	# Exemplo: "2x 50 + 80 + 12"
	$LabelComboValores.text = "%dx %s" % [mult, texto_pontos]
	$AirTimeContainer.show()

func mostrar_finalizacao_combo(total_final: int, mult: int):
	$LabelComboNomes.text = "" # Limpa o live
	$LabelComboValores.text = ""
	
	# Mostra o resultado final bonitão
	$LabelFinalScore.text = str(total_final) + " points"
	
	var msg = "Nice Score!"
	if mult >= 3: msg = "INSANE COMBO!"
	elif mult >= 2: msg = "Great Combo!"
	
	$LabelMensagem.text = msg
	
	# Timer para sumir
	await get_tree().create_timer(2.0).timeout
	$LabelFinalScore.text = ""
	$LabelMensagem.text = ""
