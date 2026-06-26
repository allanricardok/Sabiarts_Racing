# Global.gd
extends Node

# --- DEFINIÇÃO DOS MODOS DE JOGO ---
enum RunMode { FREE_ROAM, EXPLORATION, BATTLE, STORY }
var spawn_bots : bool = true # Controla se o Spawner deve agir

# --- ESTADO ATUAL ---
var current_run_mode : RunMode = RunMode.FREE_ROAM
var current_map : String = "TestMap" # "TestMap" ou "BuenosAires"

# --- PROGRESSÃO DO JOGADOR (Save Data) ---
var unlocked_test_battle : bool = false
var unlocked_ba_exploration : bool = false
var unlocked_ba_battle : bool = false
var collected_items_ids: Array[String] = []
var story_total_points: int = 0
var points_to_next_city: int = 5000 # O alvo para abrir a próxima cidade
var completed_story_missions : Array[String] = []
var total_tokens: int = 0

# Agora cada jogador é um Dicionário: {"esquema": "J1", "carro_cena": PackedScene}
var dados_jogadores = [null, null, null, null]

# Função para criar um jogador fantasma para testes direto do mapa
func clonar_jogador_teste(slot_index: int = 0, carro_fallback: PackedScene = null):
	if dados_jogadores[slot_index] == null:
		dados_jogadores[slot_index] = {
			"esquema": "K1", # Controle padrão do teste
			"carro_cena": carro_fallback, 
			"stats": { "health": 100, "speed": 8, "weight": 5 },
			"equipe": "Chosen Ones",
			"is_debug": true
		}
		print("DEBUG: Jogador de teste injetado no slot ", slot_index)

func _ready():
	# Carrega o progresso automaticamente assim que o jogo abre
	load_story_progress()

func save_story_progress():
	var file = ConfigFile.new()
	file.set_value("Story", "completed_missions", completed_story_missions)
	file.set_value("Story", "total_points", story_total_points)
	# --- NOVO: Salvando os coletáveis ---
	file.set_value("Story", "collected_items", collected_items_ids)
	
	file.save("user://story_progress.cfg")
	print("[Global] Progresso da História Salvo no HD!")

func load_story_progress():
	var file = ConfigFile.new()
	if file.load("user://story_progress.cfg") == OK:
		# No Godot 4, usamos .assign() para jogar Arrays genéricos do HD em Arrays Tipados
		completed_story_missions.assign(file.get_value("Story", "completed_missions", []))
		story_total_points = file.get_value("Story", "total_points", 0)
		collected_items_ids.assign(file.get_value("Story", "collected_items", []))
		
		print("[Global] Progresso da História Carregado do HD!")
