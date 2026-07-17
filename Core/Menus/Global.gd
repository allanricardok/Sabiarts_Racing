# Global.gd
extends Node

# --- DEFINIÇÃO DOS MODOS DE JOGO ---
enum RunMode { FREE_ROAM, EXPLORATION, BATTLE, STORY }
var spawn_bots : bool = true 

# --- ESTADO ATUAL ---
var current_run_mode : RunMode = RunMode.FREE_ROAM
var current_map : String = "TestMap" 

# --- PROGRESSÃO DO JOGADOR (Save Data) ---
var unlocked_test_battle : bool = false
var unlocked_ba_exploration : bool = false
var unlocked_ba_battle : bool = false
var collected_items_ids: Array[String] = []
var story_total_points: int = 0
var points_to_next_city: int = 7000 
var completed_story_missions : Array[String] = []

# =====================================================================
# --- NOVO: CARTEIRA GLOBAL, REPETIDAS E CONTROLE INDIVIDUAL DE TIERS ---
var total_tokens: int = 0
## Guarda as missões repetidas NA RUN ATUAL. Limpa ao voltar para o Menu.
var missions_repeated_this_run: Array[String] = []
## Salva as chaves individuais de cada tier completado na vida (ex: "m_01_tier_0", "m_01_tier_1")
var completed_mission_tiers: Array[String] = []
# =====================================================================

var dados_jogadores = [null, null, null, null]

func clonar_jogador_teste(slot_index: int = 0, carro_fallback: PackedScene = null):
	if dados_jogadores[slot_index] == null:
		dados_jogadores[slot_index] = {
			"esquema": "K1", 
			"carro_cena": carro_fallback, 
			"stats": { "health": 100, "speed": 8, "weight": 5 },
			"equipe": "Chosen Ones",
			"is_debug": true
		}
		print("DEBUG: Jogador de teste injetado no slot ", slot_index)

func _ready():
	load_story_progress()
	load_player_profile()

# --- SALVAMENTO INDEPENDENTE DE PROFILE (TOKENS) ---
func save_player_profile():
	var file = ConfigFile.new()
	file.set_value("Profile", "total_tokens", total_tokens)
	file.save("user://player_profile.cfg")

func load_player_profile():
	var file = ConfigFile.new()
	if file.load("user://player_profile.cfg") == OK:
		total_tokens = file.get_value("Profile", "total_tokens", 0)

func save_story_progress():
	var file = ConfigFile.new()
	file.set_value("Story", "completed_missions", completed_story_missions)
	file.set_value("Story", "completed_mission_tiers", completed_mission_tiers) # Gravando novos tiers
	file.set_value("Story", "total_points", story_total_points)
	file.set_value("Story", "collected_items", collected_items_ids)
	file.save("user://story_progress.cfg")

func load_story_progress():
	var file = ConfigFile.new()
	if file.load("user://story_progress.cfg") == OK:
		completed_story_missions.assign(file.get_value("Story", "completed_missions", []))
		completed_mission_tiers.assign(file.get_value("Story", "completed_mission_tiers", [])) # Lendo novos tiers
		story_total_points = file.get_value("Story", "total_points", 0)
		collected_items_ids.assign(file.get_value("Story", "collected_items", []))
