# Mapa_Teste_Inicio.gd
extends Node3D

@export var carro_cena: PackedScene
@onready var grid = $GridContainer 
@onready var spawn_points = %SpawnPoints

func _ready():
	_configurar_tela_e_spawn()

func _configurar_tela_e_spawn():
	var jogadores_logados = []
	
	# Filtra os dados globais para pegar apenas quem realmente entrou no jogo
	for esquema in Global.dados_jogadores:
		if esquema != null:
			jogadores_logados.append(esquema)
	
	print("Dados no Global: ", Global.dados_jogadores)
	
	var total = jogadores_logados.size()
	
	# Configura as colunas do GridContainer conforme a quantidade de jogadores
	if total == 1:
		grid.columns = 1
	else:
		grid.columns = 2 # 2 colunas para 2, 3 ou 4 jogadores

	var containers = grid.get_children()
	
	# Referência ao primeiro viewport para sincronizar o mundo 3D
	var primeiro_viewport = containers[0].get_node("View_P1")

	for i in range(total):
		# Pega o Viewport correspondente (View_P1, View_P2, etc)
		var viewport_atual = containers[i].get_node("View_P" + str(i+1))
		
		# Sincronização do Mundo 3D (necessário para que todos vejam os mesmos objetos)
		if i > 0:
			if primeiro_viewport.world_3d:
				viewport_atual.world_3d = primeiro_viewport.world_3d
			else:
				viewport_atual.world_3d = get_viewport().find_world_3d()
		
		# Garante que o container do jogador esteja visível
		containers[i].show()
		
		# Instancia o carro
		var novo_carro = carro_cena.instantiate()
		
		# --- CORREÇÃO DE IDENTIDADE ---
		# Definimos o ID antes de adicionar à árvore para o _ready do carro ler correto
		novo_carro.id = i 
		novo_carro.input_source = jogadores_logados[i]
		
		# Adiciona o carro ao seu respectivo Viewport
		viewport_atual.add_child(novo_carro)
		
		# Força a câmera do carro a ser a principal desse viewport específico
		var camera_carro = novo_carro.get_node_or_null("Camera3D")
		if camera_carro:
			camera_carro.make_current()
		
		# --- NOVO SISTEMA DE POSICIONAMENTO COM FALLBACK DE SEGURANÇA ---
		print("Carro ", i+1, " (ID: ", i, ") criado no Viewport: ", viewport_atual.name)
		if spawn_points and spawn_points.get_child_count() > 0:
			var pontos = spawn_points.get_children()
			
			# O módulo (%) garante que se o i for maior que a quantidade de pontos, ele volta pro zero.
			var index_ponto = i % pontos.size() 
			novo_carro.global_transform = pontos[index_ponto].global_transform
			
			# Se teve que repetir o spawn (ex: 4 players mas só tem 1 spawn no mapa)
			# Adiciona um deslocamento lateral (eixo X) para não explodirem juntos
			if i >= pontos.size():
				var offset_multiplicador = (i / pontos.size()) * 4.0 # 4 metros pro lado
				novo_carro.global_position += novo_carro.global_transform.basis.x * offset_multiplicador
				
			print("Posição do Carro ", i+1, ": ", novo_carro.global_position)
