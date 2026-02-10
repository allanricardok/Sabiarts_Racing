extends Node3D

@export var carro_cena: PackedScene
@onready var grid = $GridContainer # Removi o "UI/" pois ele não existe na sua árvore
@onready var spawn_points =%SpawnPoints

func _ready():
	_configurar_tela_e_spawn()

func _configurar_tela_e_spawn():
	var jogadores_logados = []
	for esquema in Global.dados_jogadores:
		if esquema != null:
			jogadores_logados.append(esquema)
	print("Dados no Global: ", Global.dados_jogadores) # Verifique se não está [null, null, null, null]
	
	var total = jogadores_logados.size()
	
	# Só mexe no grid se ele foi encontrado corretamente
# No _configurar_tela_e_spawn():
	if total == 1:
		grid.columns = 1
	else:
		grid.columns = 2 # 2 colunas para 2, 3 ou 4 jogadores

	var containers = grid.get_children()
	
	# Pegamos o primeiro viewport (que agora deve conter o seu mundo 3D)
	var primeiro_viewport = containers[0].get_node("View_P1")

	for i in range(total):
		var viewport_atual = containers[i].get_node("View_P" + str(i+1))
		if i > 0:
			# Tentamos pegar o world_3d do P1. 
			# Se ele vier null por algum motivo, usamos o mundo padrão da cena.
			if primeiro_viewport.world_3d:
				viewport_atual.world_3d = primeiro_viewport.world_3d
			else:
				# Fallback caso o mundo do P1 ainda não tenha carregado
				viewport_atual.world_3d = get_viewport().find_world_3d()
# Garante que o container esteja visível
				containers[i].show()
		
		var novo_carro = carro_cena.instantiate()
		novo_carro.input_source = jogadores_logados[i]
		
		# Adiciona o carro ao seu respectivo Viewport
		viewport_atual.add_child(novo_carro)
		# Força a câmera do carro a ser a principal desse viewport
		novo_carro.get_node("Camera3D").make_current()
		
		# Print de Debug:
		print("Carro ", i+1, " criado no Viewport: ", viewport_atual.name)
		if spawn_points:
			var pontos = spawn_points.get_children()
			if i < pontos.size():
				novo_carro.global_transform = pontos[i].global_transform
				print("Posição do Carro: ", novo_carro.global_position)
