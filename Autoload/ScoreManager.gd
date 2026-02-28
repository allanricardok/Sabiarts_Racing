# ScoreManager.gd
extends Node

# Dicionário para guardar a pontuação individual de cada slot de jogador
var player_scores : Dictionary = {0: 0, 1: 0, 2: 0, 3: 0}

# O sinal agora avisa QUEM mudou e QUAL o novo valor
signal score_changed(player_id, new_score)

func add_points(amount: int, player_id: int = 0):
	if not player_scores.has(player_id):
		player_scores[player_id] = 0
		print("[ScoreManager] Novo player_id detectado e inicializado: ", player_id)
		
	player_scores[player_id] += amount
	score_changed.emit(player_id, player_scores[player_id])
	
	# Integração com missões (Geralmente baseada no Player Principal/Soma)
	if is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.SCORE, player_scores[player_id])
	
	print("[ScoreManager] Player ", player_id, " ganhou: ", amount, " | Total: ", player_scores[player_id])

func get_total_score(player_id: int = 0) -> int:
	return player_scores.get(player_id, 0)

func reset_score():
	for id in player_scores.keys():
		player_scores[id] = 0
		score_changed.emit(id, 0)
	print("[ScoreManager] Todas as pontuações foram resetadas.")
	
func format_score_with_dots(value: int) -> String:
	var string_value = str(value)
	var formatted_string = ""
	var count = 0
	
	# Percorremos a string de trás para frente
	for i in range(string_value.length() - 1, -1, -1):
		formatted_string = string_value[i] + formatted_string
		count += 1
		
		# Se contamos 3 números e ainda não chegamos no início da string, pomos um ponto
		if count == 3 and i > 0:
			formatted_string = "." + formatted_string
			count = 0
			
	return formatted_string
