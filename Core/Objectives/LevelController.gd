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
		Global.RunMode.STORY:
			_setup_story()

# ==========================================
# CONFIGURAÇÕES DE MODOS
# ==========================================

func _setup_free_roam():
	timer_active = false
	time_left = 0.0 
	# CORREÇÃO: Não remove mais os itens aqui para não quebrar outros testes
	if map_missions:
		MissionManager.setup_map(map_missions)

func _setup_exploration():
	# CORREÇÃO: Mantém os itens presentes por padrão
	if map_missions:
		MissionManager.setup_map(map_missions)
		time_left = map_missions.time_limit
		_update_hud_timer()

func _setup_battle():
	# LÓGICA INVERTIDA: Apenas o modo Batalha faz a faxina pesada no mapa!
	_remover_itens_exploracao()
	_remover_itens_tutorial()
	
	# Garante que o MissionManager não mostre UI de maletas	
	# Desliga as missões na memória para a HUD sumir com o painel!
	if is_instance_valid(MissionManager):
		MissionManager.current_map_data = null 
	
	if map_missions:
		time_left = map_missions.time_limit
		_update_hud_timer()

func _setup_story():
	timer_active = false
	time_left = 0.0 
	# CORREÇÃO: No Modo História os objetos NÃO são deletados, permitindo que os
	# portais controlem a visibilidade deles dinamicamente sem conflito!
	print("[LevelController] Modo História configurado. Objetos preservados na cena.")

# ==========================================
# FUNÇÕES DE FAXINA (FILTROS DE MAPA)
# ==========================================

func _remover_bots():
	# 1. VARREDURA DE CARROS (Acha os bots disfarçados de jogadores)
	var todos_carros = get_tree().get_nodes_in_group("jogadores")
	for carro in todos_carros:
		if is_instance_valid(carro):
			var input = carro.get_node_or_null("%InputComponent")
			# Se o controle pertencer à IA, apaga o carro!
			if input and "is_bot" in input and input.is_bot:
				carro.queue_free()
				
	# 2. VARREDURA DE OUTROS INIMIGOS (Torretas, etc)
	var outros_inimigos = get_tree().get_nodes_in_group("inimigos")
	for inimigo in outros_inimigos:
		if is_instance_valid(inimigo):
			# Se for Tutorial (Free Roam) OU História, poupa a vida das torretas!
			if Global.current_run_mode in [Global.RunMode.FREE_ROAM, Global.RunMode.STORY] and inimigo is EnemyTurret:
				continue 
			inimigo.queue_free()
			
	print("[LevelController] Limpeza de Bots e Inimigos concluída para este modo.")

func _remover_itens_exploracao():
	var itens = get_tree().get_nodes_in_group("itens_exploracao")
	for item in itens:
		if is_instance_valid(item): item.queue_free()
	print("[LevelController] Itens de exploração removidos de forma forçada.")

func _remover_itens_tutorial():
	var itens = get_tree().get_nodes_in_group("itens_tutorial")
	for item in itens:
		if is_instance_valid(item): item.queue_free()
	print("[LevelController] Itens de tutorial removidos de forma forçada.")

# ==========================================
# FLUXO DA PARTIDA
# ==========================================

func start_timer():
	if level_ended: return
	
	if Global.current_run_mode in [Global.RunMode.FREE_ROAM, Global.RunMode.STORY]:
		timer_active = false
		print("[LevelController] Partida Iniciada (Modo Infinito - Sem Tempo).")
	else:
		timer_active = true
		print("[LevelController] Partida Iniciada! Cronômetro rodando.")

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
	if Global.current_map != "":
		mapa_atual = Global.current_map
	elif map_missions and map_missions.map_name != "":
		mapa_atual = map_missions.map_name
	
	for p_id in range(4): 
		var pts = ScoreManager.get_total_score(p_id)
		if pts > 0:
			SaveManager.save_highscore(mapa_atual, pts, "Player " + str(p_id + 1))
	
	get_tree().call_group("FinishUI", "abrir_resultados")
	get_tree().call_group("HUD", "clear_combo_display")
	
# ==========================================
# CONDIÇÕES DE VITÓRIA / ELIMINAÇÃO (BATALHA)
# ==========================================

func registrar_morte_jogador():
	if level_ended: return
	call_deferred("_checar_condicoes_batalha")

func _checar_condicoes_batalha():
	if level_ended: return
	
	if Global.current_run_mode != Global.RunMode.BATTLE:
		return

	var carros_vivos = get_tree().get_nodes_in_group("jogadores")
	var humanos_vivos = 0
	var bots_vivos = 0
	
	for carro in carros_vivos:
		if not is_instance_valid(carro) or carro.is_queued_for_deletion():
			continue
			
		if "_is_dead" in carro and carro._is_dead:
			continue
			
		var is_bot = false
		var input = carro.get_node_or_null("%InputComponent")
		if input and "is_bot" in input and input.is_bot:
			is_bot = true
		elif carro.has_node("BotBrain"):
			is_bot = true
			
		if is_bot:
			bots_vivos += 1
		else:
			humanos_vivos += 1
			
	print("[LevelController] Checando Batalha... Humans vivos: ", humanos_vivos, " | Bots vivos: ", bots_vivos)
	
	if Global.spawn_bots:
		if bots_vivos == 0:
			print("[LevelController] VITÓRIA! Todos os bots foram destruídos.")
			encerrar_partida()
		elif humanos_vivos == 0:
			print("[LevelController] DERROTA! Todos os jogadores morreram.")
			encerrar_partida()
	else:
		if humanos_vivos <= 1:
			print("[LevelController] LAST MAN STANDING! Fim do PVP.")
			encerrar_partida()

func _show_results_summary():
	get_tree().call_group("HUD", "abrir_menu_resultados")

func add_bonus_time(amount: float):
	if Global.current_run_mode == Global.RunMode.FREE_ROAM: return
	
	time_left += amount
	_update_hud_timer() 
	print("[LevelController] +", amount, " segundos!")

func _enter_tree():
	if Global.current_run_mode == Global.RunMode.FREE_ROAM:
		if map_missions:
			for m in map_missions.missions:
				m.is_completed = false
				if m.id in MissionManager.completed_mission_ids:
					MissionManager.completed_mission_ids.erase(m.id)
			
			MissionManager.completed_count = 0
			
			if is_instance_valid(SaveManager):
				var scores_atuais = {}
				if "highscores" in SaveManager:
					scores_atuais = SaveManager.highscores
				elif "high_scores" in SaveManager:
					scores_atuais = SaveManager.high_scores
					
				SaveManager.save_game(MissionManager.completed_mission_ids, scores_atuais)
