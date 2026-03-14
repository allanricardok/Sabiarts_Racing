# LevelController.gd
extends Node

## O Resource contendo as 13 missões e o tempo limite deste mapa
@export var map_missions : MapMissionData

# Variáveis de controle de estado
var time_left : float = 0.0
var timer_active : bool = false
var level_ended : bool = false

func _ready():
	# Adiciona aos grupos para que as UIs de Start e Pause consigam achá-lo
	add_to_group("LevelLogic")
	add_to_group("LevelController") # <--- ADICIONADO PARA O PAUSE MENU
	
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
	print("LevelController: Tempo esgotado!")
	encerrar_partida()

# --- NOVA FUNÇÃO CENTRAL DE ENCERRAMENTO ---
# --- NOVA FUNÇÃO CENTRAL DE ENCERRAMENTO ---
func encerrar_partida():
	if level_ended: return 
	
	timer_active = false
	level_ended = true
	
	print("LevelController: Encerrando partida! Chamando tela de resultados...")
	
	# --- A MÁGICA DO HIGHSCORE (CORRIGIDA) ---
	# Em vez de pegar o nome do Nó Raiz, pegamos o nome oficial dentro do Resource de Missões!
	# Assim, é impossível os mapas se confundirem, mesmo se os nós tiverem o mesmo nome.
	var mapa_atual = "MapaDesconhecido"
	if map_missions and map_missions.map_name != "":
		mapa_atual = map_missions.map_name
	
	# Salva a pontuação do Player 1 (ID 0)
	var pontuacao_p1 = ScoreManager.get_total_score(0)
	if pontuacao_p1 > 0:
		SaveManager.save_highscore(mapa_atual, pontuacao_p1, "Player 1")
		
	# BÔNUS: Split-Screen
	for p_id in range(1, 4):
		var pts = ScoreManager.get_total_score(p_id)
		if pts > 0:
			SaveManager.save_highscore(mapa_atual, pts, "Player " + str(p_id + 1))
	
	get_tree().call_group("FinishUI", "abrir_resultados")
	get_tree().call_group("HUD", "clear_combo_display")
	
# --- LÓGICA DE MULTIPLAYER (LAST MAN STANDING) ---
func registrar_morte_jogador():
	if level_ended: return
	
	# Se for Singleplayer, a gente não encerra, o jogador apenas fica morto até o tempo acabar 
	# (ou você pode mudar para encerrar direto, mas mantive a regra de ignorar no SP)
	var qtd_jogadores_totais = Global.dados_jogadores.size()
	if qtd_jogadores_totais <= 1:
		return 
		
	# Aguardamos o fim do frame para garantir que o queue_free() apagou o carro do grupo "jogadores"
	call_deferred("_checar_jogadores_vivos")

func _checar_jogadores_vivos():
	if level_ended: return
	
	var carros_vivos = get_tree().get_nodes_in_group("jogadores")
	print("[LevelController] Checando sobreviventes... Vivos restantes: ", carros_vivos.size())
	
	if carros_vivos.size() <= 1:
		print("[LevelController] LAST MAN STANDING! Encerrando a partida multiplayer antecipadamente.")
		encerrar_partida()

func _show_results_summary():
	# Aqui você pode instanciar sua cena de "Resultados" 
	# ou ativar o mesmo menu de missões, mas agora mostrando o que foi concluído.
	get_tree().call_group("HUD", "abrir_menu_resultados")
	print("LevelController: Solicitando tela de resultados ao grupo HUD.")

# --- FUNÇÕES DE UTILIDADE ---

## Caso você precise adicionar tempo extra (ex: pegar um item de bônus)
func add_bonus_time(amount: float):
	time_left += amount
	_update_hud_timer() # Força atualização imediata em todos os HUDs
	print("LevelController: +", amount, " segundos de bônus! Novo tempo: ", time_left)
