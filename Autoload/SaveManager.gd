# SaveManager.gd
extends Node

const SAVE_PATH = "user://kkflp_save.cfg"
const HIGHSCORE_PATH = "user://highscores.cfg" # Arquivo separado e persistente

func save_game(completed_missions: Array, collection_data: Dictionary):
	var config = ConfigFile.new()
	config.set_value("Progress", "completed_ids", completed_missions)
	config.set_value("Progress", "collection_progress", collection_data)
	
	var err = config.save(SAVE_PATH)
	if err == OK:
		print("[SaveManager] Missões salvas em: ", SAVE_PATH)
	else:
		print("[SaveManager] ERRO ao salvar missões: ", err)

func load_game() -> Dictionary:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	var data = {"completed_ids": [], "collection_progress": {}}
	if err == OK:
		data["completed_ids"] = config.get_value("Progress", "completed_ids", [])
		data["collection_progress"] = config.get_value("Progress", "collection_progress", {})
	return data

func clear_data():
	var dir = DirAccess.open("user://")
	if dir.file_exists("kkflp_save.cfg"):
		dir.remove("kkflp_save.cfg")
		print("[SaveManager] Progresso de missões apagado. Highscores preservados.")

# --- SISTEMA DE HIGHSCORE ---

func save_highscore(map_name: String, score: int, player_name: String = "Player"):
	var config = ConfigFile.new()
	config.load(HIGHSCORE_PATH)
	
	# Recupera a lista atual do mapa ou cria uma nova
	var scores = config.get_value("Scores", map_name, [])
	
	# Adiciona o novo score
	var new_entry = {"name": player_name, "score": score}
	scores.append(new_entry)
	
	# Ordena do maior para o menor
	scores.sort_custom(func(a, b): return a["score"] > b["score"])
	
	# MUDANÇA: Mantém apenas o Top 8 (antes era 5)
	if scores.size() > 8:
		scores.resize(8)
		print("[SaveManager] Limite atingido. Lista redimensionada para o Top 8.")
	
	config.set_value("Scores", map_name, scores)
	config.save(HIGHSCORE_PATH)
	print("[SaveManager] Highscore salvo para ", map_name, ": ", score)

func get_highscores(map_name: String) -> Array:
	var config = ConfigFile.new()
	config.load(HIGHSCORE_PATH)
	var list = config.get_value("Scores", map_name, [])
	return list

func clear_highscores():
	var dir = DirAccess.open("user://")
	if dir.file_exists("highscores.cfg"):
		dir.remove("highscores.cfg")
		print("[SaveManager] Ficheiro de highscores apagado com sucesso.")
	else:
		print("[SaveManager] Nenhum ficheiro de highscores encontrado para apagar.")

func clear_story_data():
	var path = "user://kkflp_save.cfg"
	if FileAccess.file_exists(path):
		var err = DirAccess.remove_absolute(path)
		if err == OK:
			print("[SaveManager] Ficheiro de história (kkflp_save.cfg) apagado permanentemente.")
		else:
			print("[SaveManager] Erro ao tentar apagar ficheiro de história: ", err)
	else:
		print("[SaveManager] Ficheiro de história não encontrado. Nada a apagar.")
