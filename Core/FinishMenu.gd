# FinishMenu.gd
extends CanvasLayer

@onready var mission_list = %FinishMissionList
@onready var score_label = %FinalScoreLabel
@onready var menu_button = %MenuBtn

func _ready():
	# Adiciona ao grupo para o LevelController te achar fácil
	add_to_group("FinishUI")
	hide() # Começa escondido, diferente do StartMenu

## Esta função é o que o LevelController vai chamar
func abrir_resultados():
	# 1. Trava o jogo e mostra a tela
	get_tree().paused = true
	show()
	
	# 2. Dá o foco no botão para o controle/teclado funcionar
	menu_button.grab_focus()
	
	# 3. Pega o score final do ScoreManager
	var total = ScoreManager.total_score
	score_label.text = "PONTUAÇÃO TOTAL: " + ScoreManager.format_score_with_dots(total)
	
	# 4. Preenche a lista de missões
	_preencher_resumo_missoes()

func _preencher_resumo_missoes():
	var data = MissionManager.current_map_data
	if not data: return
	
	# Limpa a lista anterior
	for child in mission_list.get_children(): 
		child.queue_free()
	
	for m in data.missions:
		var item = Label.new()
		
		# Se a missão foi completada, mostra verde com check, se não, cinza com X
		if m.is_completed:
			item.text = "✔ " + m.description
			item.add_theme_color_override("font_color", Color.GREEN)
		else:
			item.text = "✘ " + m.description
			item.add_theme_color_override("font_color", Color.GRAY)
		
		item.custom_minimum_size.y = 30 
		mission_list.add_child(item)

func _on_menu_btn_pressed():
	# Despausa antes de sair para não travar o Menu Principal
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/UI/Menu.tscn")
