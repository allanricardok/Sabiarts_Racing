# Global.gd
extends Node

var dados_jogadores = [null, null, null, null]

# Função para criar um jogador fantasma para testes
func clonar_jogador_teste(slot_index: int = 0):
	if dados_jogadores[slot_index] == null:
		dados_jogadores[slot_index] = {
			"id_input": slot_index,
			"nome_carro": "Brasília de Teste",
			"stats": { "health": 100, "speed": 8, "weight": 5 },
			"equipe": "Chosen Ones",
			"is_debug": true
		}
		print("DEBUG: Jogador de teste injetado no slot ", slot_index)
