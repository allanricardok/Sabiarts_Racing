# Mapa_Teste_Inicio.gd
extends Node3D

@onready var grid = $GridContainer 
@onready var spawn_points = %SpawnPoints

func _ready():
	_configurar_tela_e_spawn()
	_auto_categorizar_objetos()
# Zera a contagem toda vez que o mapa é carregado!
	if GameStats:
		GameStats.reset_run_stats()

# --- NOVA FUNÇÃO AUTOMÁTICA ---
func _auto_categorizar_objetos():
	print("[Mapa] Iniciando Auto-Categorização para os Bots...")
	var count_armas = 0
	var count_vida = 0
	var count_rampas = 0
	
	# 1. Tagueando Armas (Pega todos os filhos de "Pickups")
	var node_pickups = find_child("Pickups", true, false)
	if node_pickups:
		for arma in node_pickups.get_children():
			arma.add_to_group("weapon_pickups")
			count_armas += 1
			
	# 2. Tagueando Vida/Status (Pega todos os filhos de "StatusItems")
	var node_status = find_child("StatusItems", true, false)
	if node_status:
		for item in node_status.get_children():
			item.add_to_group("health_pickups")
			count_vida += 1

	# 3. Tagueando Rampas 
	# (Procura na árvore inteira por qualquer nó que tenha "Ramp" no nome)
	var todos_os_nos = find_children("*Ramp*", "Node3D", true)
	for rampa in todos_os_nos:
		rampa.add_to_group("rampas")
		count_rampas += 1

	print("[Mapa] Categorização concluída! Armas: ", count_armas, " | Vida: ", count_vida, " | Rampas: ", count_rampas)

func _configurar_tela_e_spawn():
	var jogadores_logados = []
	
	for dados in Global.dados_jogadores:
		if dados != null:
			jogadores_logados.append(dados)
	
	var total = jogadores_logados.size()
	
	# Se estiver testando a cena direto (apertou F6 no mapa)
	if total == 0:
		print("Nenhum jogador no Global. Criando jogador de teste...")
		# ATENÇÃO: Se quiser testar direto, passe o seu BaseVehicle aqui
		Global.clonar_jogador_teste(0, preload("res://Scenes/Prefabs/Vehicles/BrasiliaTest.tscn"))
		jogadores_logados.append(Global.dados_jogadores[0])
		total = 1

	if total == 1: grid.columns = 1
	else: grid.columns = 2

	var containers = grid.get_children()
	var primeiro_viewport = containers[0].get_node("View_P1")

	for i in range(total):
		var viewport_atual = containers[i].get_node("View_P" + str(i+1))
		var config = jogadores_logados[i] # Aqui temos o Dicionário!
		
		if i > 0:
			if primeiro_viewport.world_3d: viewport_atual.world_3d = primeiro_viewport.world_3d
			else: viewport_atual.world_3d = get_viewport().find_world_3d()
		
		containers[i].show()
		
		# --- A MÁGICA DOS CARROS DIFERENTES ---
		var cena_do_carro = config["carro_cena"]
		var novo_carro = cena_do_carro.instantiate()
		
		novo_carro.id = i 
		novo_carro.input_source = config["esquema"]
		
		viewport_atual.add_child(novo_carro)
		
		var camera_carro = novo_carro.get_node_or_null("Camera3D")
		if camera_carro: camera_carro.make_current()
		
		# Setup do SpawnPoint
		if spawn_points and spawn_points.get_child_count() > 0:
			var pontos = spawn_points.get_children()
			var index_ponto = i % pontos.size() 
			novo_carro.global_transform = pontos[index_ponto].global_transform
			
			if i >= pontos.size():
				var offset_multiplicador = (i / pontos.size()) * 4.0 
				novo_carro.global_position += novo_carro.global_transform.basis.x * offset_multiplicador
