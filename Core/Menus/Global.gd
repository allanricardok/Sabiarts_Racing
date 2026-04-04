# Global.gd
extends Node

# --- DEFINIÇÃO DOS MODOS DE JOGO ---
enum RunMode { FREE_ROAM, EXPLORATION, BATTLE }

# --- ESTADO ATUAL ---
var current_run_mode : RunMode = RunMode.FREE_ROAM
var current_map : String = "TestMap" # "TestMap" ou "BuenosAires"

# --- PROGRESSÃO DO JOGADOR (Save Data) ---
var unlocked_test_battle : bool = false
var unlocked_ba_exploration : bool = false
var unlocked_ba_battle : bool = false

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
