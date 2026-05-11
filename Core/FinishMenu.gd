# FinishMenu.gd
extends CanvasLayer

@onready var mission_list = %FinishMissionList
@onready var score_label = %FinalScoreLabel
@onready var menu_button = %MenuBtn
@onready var highscore_list = %HighscoreList
@onready var current_score_label = %CurrentScoreLabel
@onready var map_name_label = %MapNameLabel

# --- REFERÊNCIAS DOS NOVOS LABELS DE ATROPELAMENTO ---
# (Lembre-se de criar esses Labels na cena do FinishMenu e marcar o Access as Unique Name '%')
@onready var run_kills_label = get_node_or_null("%RunKillsLabel")
@onready var total_kills_label = get_node_or_null("%TotalKillsLabel")

func _ready():
	add_to_group("FinishUI")
	hide()
	

func abrir_resultados():
	get_tree().paused = true
	show()
		# Se for o Tutorial, esconde o painel inteiro de missões!
	if Global.current_run_mode == Global.RunMode.FREE_ROAM:
		# Substitua "$PainelDeMissoes" pelo nome do nó que segura o texto das missões no seu Menu
		%ScrollContainer.visible = false
	if menu_button:
		menu_button.grab_focus()
	
	# --- FIX MULTIPLAYER: Encontra a maior pontuação entre os jogadores ---
	var highest_score : int = 0
	var winner_id : int = 0
	
	for p_id in ScoreManager.player_scores.keys():
		var p_score = ScoreManager.get_total_score(p_id)
		if p_score > highest_score:
			highest_score = p_score
			winner_id = p_id
			
	print("[FinishMenu] Maior pontuação alcançada pelo Player ", winner_id + 1, ": ", highest_score)
	
	var formatted_score = ScoreManager.format_score_with_dots(highest_score)
	var winner_name = "Player " + str(winner_id + 1)
	
	if score_label:
		score_label.text = "PONTUAÇÃO MÁXIMA: " + formatted_score
	
	if current_score_label:
		current_score_label.text = winner_name.to_upper() + " - " + formatted_score
		print("[FinishMenu] CurrentScoreLabel atualizado: ", current_score_label.text)
	
	# --- CORREÇÃO: PUXANDO O NOME DA FONTE SEGURA (GLOBAL) ---
	var map_name = "MAPA DESCONHECIDO"
	if Global.current_map != "":
		map_name = Global.current_map
	elif MissionManager.current_map_data:
		map_name = MissionManager.current_map_data.map_name
	
	if map_name_label:
		map_name_label.text = map_name
		
	# --- ATUALIZA OS TEXTOS DE ATROPELAMENTO ---
	if GameStats:
		if run_kills_label:
			run_kills_label.text = "x" + str(GameStats.pedestrians_killed_this_run)
		if total_kills_label:
			total_kills_label.text = "x" + str(GameStats.total_pedestrians_killed) + " total since started"
	
	# 2. Preenche as listas
	_preencher_resumo_missoes()
	_preencher_highscores(map_name, highest_score)

func _preencher_resumo_missoes():
	if not mission_list: return
	var data = MissionManager.current_map_data
	if not data: return
	
	for child in mission_list.get_children(): 
		child.queue_free()
	
	for i in range(data.missions.size()):
		var m = data.missions[i]
		var item = Label.new()
		item.custom_minimum_size.y = 30
		
		if m.is_completed:
			item.text = "✔ " + m.description
			item.add_theme_color_override("font_color", Color.GREEN)
		elif i < 6 or MissionManager.batch_2_unlocked:
			item.text = "✘ " + m.description
			item.add_theme_color_override("font_color", Color.GRAY)
		else:
			item.text = "🔒 ??? [SECRETO]"
			item.add_theme_color_override("font_color", Color.DARK_SLATE_GRAY)
		
		mission_list.add_child(item)

func _preencher_highscores(map_name: String, current_session_score: int):
	if not highscore_list: return
	
	for child in highscore_list.get_children():
		child.queue_free()
	
	var scores = SaveManager.get_highscores(map_name)
	var ja_destacou_atual = false
	var max_display_count = min(scores.size(), 8)
	
	for i in range(max_display_count):
		var entry = scores[i]
		var lbl = Label.new()
		
		var pos = str(i + 1) + ". "
		var player = entry["name"].to_upper()
		var points_val = entry["score"]
		var points_text = ScoreManager.format_score_with_dots(points_val)
		
		var line_text = pos + player
		var dots = ""
		for j in range(max(2, 25 - line_text.length())):
			dots += "."
			
		lbl.text = line_text + dots + points_text
		
		if points_val == current_session_score and not ja_destacou_atual:
			lbl.add_theme_color_override("font_color", Color.YELLOW)
			lbl.text += " [NEW]"
			ja_destacou_atual = true
		else:
			lbl.add_theme_color_override("font_color", Color.WHITE)
		
		highscore_list.add_child(lbl)

func _on_menu_btn_pressed():
	print("[FinishMenu] Saindo para o menu.")
	
	# --- ZERA A CONTAGEM DA RUN ANTES DE SAIR ---
	if GameStats:
		GameStats.reset_run_stats()
		
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/UI/Menu.tscn")
