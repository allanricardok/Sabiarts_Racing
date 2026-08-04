# Mapa_Teste_Inicio.gd
extends Node3D

@onready var grid = $GridContainer 
@onready var spawn_points = %SpawnPoints

# Referenciamos os Viewports DIRETAMENTE
@onready var sub_viewports = [
	$GridContainer/Cont_P1/View_P1,
	$GridContainer/Cont_P2/View_P2,
	$GridContainer/Cont_P3/View_P3,
	$GridContainer/Cont_P4/View_P4
]

var ps1_material = preload("res://Core/Shaders/2DPixelShader.tres")

# Variáveis para a memória dos botões
var ps1_map_active: bool = false
var ps1_ui_active: bool = false
var canvas_layer_ui: CanvasLayer = null 

func aplicar_shader_ps1(afetar_ui: bool, ativar: bool):
	# Atualiza a memória de qual botão está ligado/desligado
	if afetar_ui:
		ps1_ui_active = ativar
	else:
		ps1_map_active = ativar

	# ====================================================================
	# 1. FAXINA GERAL (Apaga todos os shaders para evitar sobreposição)
	# ====================================================================
	if is_instance_valid(canvas_layer_ui):
		canvas_layer_ui.queue_free()
		canvas_layer_ui = null
		
	for vp in sub_viewports:
		if vp == null: continue
		var old_shader = vp.get_node_or_null("PS1_Map_Layer")
		if is_instance_valid(old_shader):
			old_shader.queue_free()

	# ====================================================================
	# 2. APLICA O SHADER CORRETO (O botão "Tudo" tem prioridade máxima)
	# ====================================================================
	if ps1_ui_active:
		# Pega TUDO de uma vez (Mapa, UI do carro e Menus). Layer 100
		canvas_layer_ui = CanvasLayer.new()
		canvas_layer_ui.layer = 100 
		
		var cr = ColorRect.new()
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.material = ps1_material
		
		canvas_layer_ui.add_child(cr)
		add_child(canvas_layer_ui)
		
	elif ps1_map_active:
		# Pega APENAS o mapa (Fica atrás da UI do carro). Layer -1
		for vp in sub_viewports:
			if vp == null: continue
			
			var cl = CanvasLayer.new()
			cl.name = "PS1_Map_Layer"
			cl.layer = -1 
			
			var cr = ColorRect.new()
			cr.set_anchors_preset(Control.PRESET_FULL_RECT)
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cr.material = ps1_material
			
			cl.add_child(cr)
			vp.add_child(cl)

func _ready():
	_configurar_tela_e_spawn()
	_auto_categorizar_objetos()
	
	# Zera a contagem toda vez que o mapa é carregado!
	if GameStats:
		GameStats.reset_run_stats()

	# --- CHAMA A FAXINA DOS MODOS AQUI ---
	_limpar_elementos_por_modo()

# --- NOVA FUNÇÃO DE LIMPEZA ---
func _limpar_elementos_por_modo():
	# 1. Limpeza de História: Se NÃO for o modo História, apaga tudo que é de história
	if Global.current_run_mode != Global.RunMode.STORY:
		print("[Mapa] Modo não-história detectado. Apagando elementos de história...")
		# Procura todo mundo que você colocou no grupo "elementos_historia"
		var story_elements = get_tree().get_nodes_in_group("elementos_historia")
		for element in story_elements:
			element.queue_free()

	# 2. (BÔNUS) Limpeza de Armas: Se for modo História ou Exploração, talvez você não queira armas/vidas no chão
	if Global.current_run_mode == Global.RunMode.STORY or Global.current_run_mode == Global.RunMode.EXPLORATION:
		print("[Mapa] Limpando Pickups de Combate...")
		var weapons = get_tree().get_nodes_in_group("weapon_pickups")
		for w in weapons:
			w.queue_free()

# --- NOVA FUNÇÃO AUTOMÁTICA ---
func _auto_categorizar_objetos():
	print("[Mapa] Iniciando Auto-Categorização para os Bots...")
	var count_rampas = 0

	# 3. Tagueando Rampas 
	# (Procura na árvore inteira por qualquer nó que tenha "Ramp" no nome)
	var todos_os_nos = find_children("*Ramp*", "Node3D", true)
	for rampa in todos_os_nos:
		rampa.add_to_group("rampas")
		count_rampas += 1

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
