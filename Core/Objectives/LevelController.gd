# LevelController.gd
extends Node

@export var map_missions : MapMissionData

var time_left : float = 0.0
var timer_active : bool = false
var level_ended : bool = false

func _ready():
	add_to_group("LevelLogic")
	add_to_group("LevelController")
	
	print("[LevelController] Mapa carregado no modo: ", Global.RunMode.keys()[Global.current_run_mode])
	
	match Global.current_run_mode:
		Global.RunMode.FREE_ROAM:
			_setup_free_roam()
		Global.RunMode.EXPLORATION:
			_setup_exploration()
		Global.RunMode.BATTLE:
			_setup_battle()

# ==========================================
# CONFIGURAÇÕES DE MODOS
# ==========================================

func _setup_free_roam():
	# MODO LIVRE: Apaga os Bots e os itens de missão. Deixa APENAS os itens de tutorial.
	timer_active = false
	time_left = 0.0 
	_remover_bots()
	_remover_itens_exploracao()

func _setup_exploration():
	# EXPLORAÇÃO: Apaga os Bots e os itens de tutorial. Deixa APENAS os itens de missão.
	_remover_bots()
	_remover_itens_tutorial()
	
	if map_missions:
		MissionManager.setup_map(map_missions)
		time_left = map_missions.time_limit
		_update_hud_timer()

func _setup_battle():
	# BATALHA: Apaga TUDO (itens de missão e de tutorial). Deixa APENAS os Bots.
	_remover_itens_exploracao()
	_remover_itens_tutorial()
	
	if map_missions:
		time_left = map_missions.time_limit
		_update_hud_timer()

# ==========================================
# FUNÇÕES DE FAXINA (FILTROS DE MAPA)
# ==========================================

func _remover_bots():
	var bots = get_tree().get_nodes_in_group("inimigos") # Verifique o grupo exato dos seus bots
	for b in bots:
		if is_instance_valid(b) and not b.is_in_group("jogadores"):
			b.queue_free()
	print("[LevelController] Bots removidos para este modo.")

func _remover_itens_exploracao():
	# Apaga todos os coletáveis e objetivos do modo Buenos Aires padrão
	var itens = get_tree().get_nodes_in_group("itens_exploracao")
	for item in itens:
		if is_instance_valid(item): item.queue_free()
	print("[LevelController] Itens de exploração removidos.")

func _remover_itens_tutorial():
	# Apaga alvos e coletáveis específicos do mapa de treino
	var itens = get_tree().get_nodes_in_group("itens_tutorial")
	for item in itens:
		if is_instance_valid(item): item.queue_free()
	print("[LevelController] Itens de tutorial removidos.")

# ==========================================
# FLUXO DA PARTIDA
# ==========================================

func start_timer():
	if level_ended: return
	
	if Global.current_run_mode != Global.RunMode.FREE_ROAM:
		timer_active = true
		print("[LevelController] Partida Iniciada! Cronômetro rodando.")
	else:
		print("[LevelController] Partida Iniciada (Modo Livre - Sem Tempo).")

func _process(delta: float):
	if timer_active and not level_ended:
		_process_timer(delta)

func _process_timer(delta: float):
	time_left -= delta
	_update_hud_timer()
	
	if time_left <= 0:
		time_left = 0
		_update_hud_timer()
		_on_time_up()

func _update_hud_timer():
	get_tree().call_group("HUD", "atualizar_timer", time_left)

func _on_time_up():
	print("[LevelController] Tempo esgotado!")
	encerrar_partida()

func encerrar_partida():
	if level_ended: return 
	
	timer_active = false
	level_ended = true
	
	print("[LevelController] Encerrando partida! Chamando tela de resultados...")
	
	var mapa_atual = "MapaDesconhecido"
	if map_missions and map_missions.map_name != "":
		mapa_atual = map_missions.map_name
	
	for p_id in range(4): 
		var pts = ScoreManager.get_total_score(p_id)
		if pts > 0:
			SaveManager.save_highscore(mapa_atual, pts, "Player " + str(p_id + 1))
	
	get_tree().call_group("FinishUI", "abrir_resultados")
	get_tree().call_group("HUD", "clear_combo_display")
	
# ==========================================
# MULTIPLAYER (LAST MAN STANDING)
# ==========================================

func registrar_morte_jogador():
	if level_ended: return
	
	var qtd_jogadores_totais = Global.dados_jogadores.size()
	if qtd_jogadores_totais <= 1:
		return 
		
	call_deferred("_checar_jogadores_vivos")

func _checar_jogadores_vivos():
	if level_ended: return
	
	var carros_vivos = get_tree().get_nodes_in_group("jogadores")
	if carros_vivos.size() <= 1:
		print("[LevelController] LAST MAN STANDING! Encerrando a partida multiplayer.")
		encerrar_partida()

func _show_results_summary():
	get_tree().call_group("HUD", "abrir_menu_resultados")

func add_bonus_time(amount: float):
	if Global.current_run_mode == Global.RunMode.FREE_ROAM: return
	
	time_left += amount
	_update_hud_timer() 
	print("[LevelController] +", amount, " segundos!")
