# ScoreManager.gd
extends Node

# Dicionário para guardar a pontuação da PARTIDA ATUAL (Zera a cada corrida)
var player_scores : Dictionary = {0: 0, 1: 0, 2: 0, 3: 0}

# --- NOVO: Dicionário para guardar o RECORDE MÁXIMO de cada mapa ---
# Exemplo de como vai ficar: {"CityMap": 15000, "DesertMap": 8000}
var map_highscores : Dictionary = {}

signal score_changed(player_id, new_score)
signal new_highscore_achieved(map_name, new_highscore) # Avisa a UI para soltar fogos!

func add_points(amount: int, player_id: int = 0):
	if not player_scores.has(player_id):
		player_scores[player_id] = 0
		print("[ScoreManager] Novo player_id detectado e inicializado: ", player_id)
		
	player_scores[player_id] += amount
	var current_score = player_scores[player_id]
	
	score_changed.emit(player_id, current_score)
	
	if is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.SCORE, current_score)
		
	# --- LÓGICA DE HIGHSCORE POR MAPA ---
	# Descobre em qual mapa estamos agora
	var current_map = get_tree().current_scene.name
	var current_high = get_map_highscore(current_map)
	
	# Se a pontuação atual passou o recorde do mapa, atualizamos na hora!
	if current_score > current_high:
		map_highscores[current_map] = current_score
		new_highscore_achieved.emit(current_map, current_score)
		# Pode colocar um som maneiro na UI ouvindo esse sinal!

func get_total_score(player_id: int = 0) -> int:
	return player_scores.get(player_id, 0)

func get_map_highscore(map_name: String) -> int:
	# Se já carregamos o recorde nesta sessão, retorna ele
	if map_highscores.has(map_name):
		return map_highscores[map_name]
		
	# Se ainda não carregou, vai no SaveManager ler o arquivo do HD!
	if is_instance_valid(SaveManager):
		var top_scores = SaveManager.get_highscores(map_name)
		if top_scores.size() > 0:
			# O seu SaveManager já ordena do maior pro menor. 
			# Então o índice [0] é sempre o Campeão isolado!
			var recorde = top_scores[0]["score"]
			map_highscores[map_name] = recorde
			return recorde
			
	return 0

func reset_score():
	# Zera apenas as pontuações da partida. Os RECORDES continuam salvos!
	for id in player_scores.keys():
		player_scores[id] = 0
		score_changed.emit(id, 0)
	print("[ScoreManager] As pontuações da partida foram resetadas.")
	
func format_score_with_dots(value: int) -> String:
	var string_value = str(value)
	var formatted_string = ""
	var count = 0
	
	for i in range(string_value.length() - 1, -1, -1):
		formatted_string = string_value[i] + formatted_string
		count += 1
		
		if count == 3 and i > 0:
			formatted_string = "." + formatted_string
			count = 0
			
	return formatted_string
