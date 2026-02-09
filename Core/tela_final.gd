extends CanvasLayer

@onready var labels_podio = [
	$VBoxContainer/Control/HBoxContainer/p1,
	$VBoxContainer/Control/HBoxContainer/p2,
	$VBoxContainer/Control/HBoxContainer/p3,
	$VBoxContainer/Control/HBoxContainer/p4
]

@onready var labels_tempos = [
	$VBoxContainer2/Tempo,
	$VBoxContainer2/Tempo2,
	$VBoxContainer2/Tempo3,
	$VBoxContainer2/Tempo4
]

func _process(_delta):
	if Input.is_action_just_pressed("Pause"):
		# LIMPEZA CRÍTICA: Remove a si mesma do root antes de trocar de cena
		get_tree().change_scene_to_file("res://new folder/Menu.tscn")
		queue_free() 
		
func configurar_resultados(resultados):
	for i in range(resultados.size()):
		if i >= labels_podio.size(): break
		
		var dados = resultados[i]
		
		var lbl_p = labels_podio[i]
		lbl_p.show()
		if i == 0:
			lbl_p.text = "👑 VENCEDOR\n" + str(dados.nome)
			lbl_p.modulate = Color.YELLOW
		else:
			lbl_p.text = str(dados.nome)
			lbl_p.modulate = Color.WHITE

		var lbl_t = labels_tempos[i]
		lbl_t.show()
		lbl_t.text = "%dº Lugar: %s - %s" % [i+1, dados.nome, _formatar_tempo(dados.tempo)]

func _formatar_tempo(tempo: float) -> String:
	var minutos = int(tempo / 60)
	var segundos = int(tempo) % 60
	var milissegundos = int((tempo - int(tempo)) * 100)
	return "%02d:%02d.%02d" % [minutos, segundos, milissegundos]
