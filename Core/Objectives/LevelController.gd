# LevelController.gd
extends Node

## O Resource contendo as 13 missões e o tempo limite deste mapa
@export var map_missions : MapMissionData

# Variáveis de controle de estado
var time_left : float = 0.0
var timer_active : bool = false
var level_ended : bool = false

func _ready():
	# Adiciona ao grupo para que a UI de Start possa chamar o 'start_timer'
	add_to_group("LevelLogic")
	
	if map_missions:
		# 1. Entrega o "caderno de missões" para o Singleton MissionManager
		MissionManager.setup_map(map_missions)
		
		# 2. Configura o cronômetro baseado no que você definiu no Resource
		time_left = map_missions.time_limit
		
		# 3. Atualiza o HUD inicialmente para mostrar o tempo parado (ex: 02:00)
		_update_hud_timer()
		
		print("LevelController: Mapa '", map_missions.map_name, "' carregado e aguardando Start.")
	else:
		push_error("LevelController: Nenhuma missão (MapMissionData) configurada no Inspetor!")

func _process(delta: float):
	# O cronômetro só roda se a partida tiver começado e não tiver acabado
	if timer_active and not level_ended:
		_process_timer(delta)

## Chamada pelo botão 'START' do seu menu de missões inicial
func start_timer():
	if not level_ended:
		timer_active = true
		print("LevelController: Partida Iniciada! Cronômetro rodando.")

func _process_timer(delta: float):
	time_left -= delta
	
	_update_hud_timer()
	
	# Condição de fim de tempo
	if time_left <= 0:
		time_left = 0
		_update_hud_timer()
		_on_time_up()

func _update_hud_timer():
	# MUDANÇA SENIOR: Em split-screen, precisamos atualizar TODOS os HUDs.
	# get_first_node_in_group pegaria apenas o Player 1.
	get_tree().call_group("HUD", "atualizar_timer", time_left)

## Executado quando o relógio zera
func _on_time_up():
	timer_active = false
	level_ended = true
	
	print("LevelController: Tempo esgotado! Chamando tela de resultados...")
	
	# Isso aqui vai procurar qualquer nó no grupo "FinishUI" e rodar a função
	get_tree().call_group("FinishUI", "abrir_resultados")
	
	# MUDANÇA SENIOR: Limpa o HUD de todos os jogadores para não ficar texto sobrando
	get_tree().call_group("HUD", "clear_combo_display")
	print("[LevelController] Solicitando limpeza de combo display para todos os jogadores.")

func _show_results_summary():
	# Aqui você pode instanciar sua cena de "Resultados" 
	# ou ativar o mesmo menu de missões, mas agora mostrando o que foi concluído.
	# MUDANÇA SENIOR: Notifica todas as instâncias de HUD
	get_tree().call_group("HUD", "abrir_menu_resultados")
	print("LevelController: Solicitando tela de resultados ao grupo HUD.")

# --- FUNÇÕES DE UTILIDADE ---

## Caso você precise adicionar tempo extra (ex: pegar um item de bônus)
func add_bonus_time(amount: float):
	time_left += amount
	_update_hud_timer() # Força atualização imediata em todos os HUDs
	print("LevelController: +", amount, " segundos de bônus! Novo tempo: ", time_left)
