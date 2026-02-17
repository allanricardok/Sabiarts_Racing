# ScoreManager.gd
extends Node

# Esta variável guarda a pontuação total da partida
var total_score : int = 0

# Sinal que avisa ao HUD para se atualizar quando os pontos mudarem
signal score_changed(new_score)

func add_points(amount: int):
	total_score += amount
	score_changed.emit(total_score)
	
	# --- INTEGRAÇÃO COM MISSÕES ---
	# Avisa o MissionManager para checar se batemos as metas de score (20k, 35k, 50k)
	if is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.SCORE, total_score)
	
	print("Pontos Adicionados: ", amount, " | Total: ", total_score)

func reset_score():
	total_score = 0
	score_changed.emit(total_score)
	
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
