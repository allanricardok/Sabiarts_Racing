# GameStats.gd
extends Node

# Sinal para avisar a HUD na mesma hora que alguém for atropelado
signal pedestrian_killed(run_total)

var pedestrians_killed_this_run: int = 0
var total_pedestrians_killed: int = 0

# Caminho do arquivo onde o Godot vai salvar o progresso no computador do jogador
const SAVE_PATH = "user://global_stats.save"

func _ready():
	load_stats()

# Chamamos isso toda vez que o mapa reiniciar para zerar a contagem da partida
func reset_run_stats():
	pedestrians_killed_this_run = 0

func add_pedestrian_kill():
	pedestrians_killed_this_run += 1
	total_pedestrians_killed += 1
	
	# Grita para o jogo inteiro: "O número atualizou!"
	pedestrian_killed.emit(pedestrians_killed_this_run)
	
	# Salva no HD (se quiser otimizar, pode salvar apenas no final da partida)
	save_stats()

func save_stats():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_32(total_pedestrians_killed)

func load_stats():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			total_pedestrians_killed = file.get_32()
