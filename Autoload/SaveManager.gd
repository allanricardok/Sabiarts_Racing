# SaveManager.gd
extends Node

const SAVE_PATH = "user://kkflp_save.cfg"

func save_game(completed_missions: Array, collection_data: Dictionary):
	var config = ConfigFile.new()
	
	# Guardamos os IDs das missões completadas e o progresso das coleções
	config.set_value("Progress", "completed_ids", completed_missions)
	config.set_value("Progress", "collection_progress", collection_data)
	
	var err = config.save(SAVE_PATH)
	if err == OK:
		print("[SaveManager] Jogo guardado com sucesso em: ", SAVE_PATH)
	else:
		print("[SaveManager] ERRO ao guardar jogo: ", err)

func load_game() -> Dictionary:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	
	var data = {
		"completed_ids": [],
		"collection_progress": {}
	}
	
	if err == OK:
		data["completed_ids"] = config.get_value("Progress", "completed_ids", [])
		data["collection_progress"] = config.get_value("Progress", "collection_progress", {})
		print("[SaveManager] Dados carregados do disco.")
	else:
		print("[SaveManager] Nenhum ficheiro de save encontrado, a começar do zero.")
		
	return data

func clear_data():
	var dir = DirAccess.open("user://")
	if dir.file_exists("kkflp_save.cfg"):
		var err = dir.remove("kkflp_save.cfg")
		if err == OK:
			print("[SaveManager] Dados do jogador apagados com sucesso.")
		else:
			print("[SaveManager] ERRO ao apagar dados: ", err)
	else:
		print("[SaveManager] Nada para apagar.")
