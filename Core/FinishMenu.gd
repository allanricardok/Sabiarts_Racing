# FinishMenu.gd
extends CanvasLayer

@onready var mission_list = %FinishMissionList
@onready var score_label = %FinalScoreLabel
@onready var menu_button = %MenuBtn

func _ready():
	add_to_group("FinishUI")
	hide()

func abrir_resultados():
	get_tree().paused = true
	show()
	menu_button.grab_focus()
	
	var total = ScoreManager.total_score
	score_label.text = "PONTUAÇÃO TOTAL: " + ScoreManager.format_score_with_dots(total)
	
	_preencher_resumo_missoes()

func _preencher_resumo_missoes():
	var data = MissionManager.current_map_data
	if not data: return
	
	for child in mission_list.get_children(): 
		child.queue_free()
	
	for i in range(data.missions.size()):
		var m = data.missions[i]
		var item = Label.new()
		item.custom_minimum_size.y = 30
		
		# LÓGICA DE VISIBILIDADE DO KARMA KILLER
		
		# 1. Missão concluída? Sempre revela (independente de batch)
		if m.is_completed:
			item.text = "✔ " + m.description
			item.add_theme_color_override("font_color", Color.GREEN)
		
		# 2. Não concluída, mas é do Batch 1 OU o Batch 2 já foi desbloqueado
		elif i < 6 or MissionManager.batch_2_unlocked:
			item.text = "✘ " + m.description
			item.add_theme_color_override("font_color", Color.GRAY)
			
		# 3. É missão secreta e o jogador nem sabe que ela existe
		else:
			item.text = "🔒 ??? [SECRETO]"
			item.add_theme_color_override("font_color", Color.DARK_SLATE_GRAY)
		
		mission_list.add_child(item)

func _on_menu_btn_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/UI/Menu.tscn")
