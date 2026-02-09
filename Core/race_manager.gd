extends Node

# Referências para a UI
@onready var bolas = [
	$CanvasLayer/CenterContainer/HBoxContainer/Bola1,
	$CanvasLayer/CenterContainer/HBoxContainer/Bola2,
	$CanvasLayer/CenterContainer/HBoxContainer/Bola3
]

@export var voltas_para_vencer : int = 1
var tempo_decorrido : float = 0.0
var corrida_ativa : bool = false
var jogadores_que_finalizaram : int = 0

@export var tela_final_scene: PackedScene # Arraste a cena da TelaFinal para cá
var lista_resultados = [] # Guardará dicionários { "id": "K1", "tempo": 12.5 }

signal corrida_iniciada

func _ready():
	add_to_group("race_manager")
	corrida_iniciada.connect(_on_corrida_iniciada)
	
	# Inicia a sequência completa
	_sequencia_master_inicio()
	
	var jogadores_reais = 0
	for data in Global.dados_jogadores:
		if data != null:
			jogadores_reais += 1

func _sequencia_master_inicio():
	print("--- DEBUG MANAGER ---")
	
	# 1. Conta quantos jogadores não-nulos existem no Global
	var jogadores_reais = 0
	for data in Global.dados_jogadores:
		if data != null:
			jogadores_reais += 1
	
	print("Aguardando ", jogadores_reais, " carros na pista...")
	
	# 2. ESPERA ATIVA DINÂMICA
	while get_tree().get_nodes_in_group("jogadores").size() < jogadores_reais:
		await get_tree().process_frame
	
	# Pequena margem de segurança extra
	await get_tree().create_timer(0.03).timeout
	
	print("Todos os ", jogadores_reais, " detectados! Disparando call_group.")
	
	# 3. Dispara a intro
	get_tree().call_group("jogadores", "iniciar_intro_jogador")
	
	# 4. Tempo da intro (1.0s espera + 0.5s fade + margem)
	await get_tree().create_timer(1).timeout
	_iniciar_sequencia_largada()

func _iniciar_sequencia_largada():
	get_tree().call_group("jogadores", "set_pode_mover", false)
	
	# Loop corrigido para passar por todas as bolas
	for i in range(bolas.size()):
		await get_tree().create_timer(1.0).timeout
		bolas[i].modulate.a = 0.2
		print("Bola ", i+1, " apagada")

	await get_tree().create_timer(1.0).timeout
	$CanvasLayer/CenterContainer/HBoxContainer.hide()
	
	# ISSO dispara o sinal que liga o cronômetro
	emit_signal("corrida_iniciada") 
	get_tree().call_group("jogadores", "set_pode_mover", true)
	print("LARGADA!")

func _process(delta):
	# O tempo agora só para quando TODOS terminarem (ou você pode deixar rodando sempre)
	if corrida_ativa:
		tempo_decorrido += delta

func registrar_chegada_jogador(id_input, nome_exibicao, tempo):
	# Evita duplicatas se o colisor bater duas vezes
	for r in lista_resultados:
		if r.id_input == id_input: return
		
	lista_resultados.append({
		"id_input": id_input, 
		"nome": nome_exibicao, 
		"tempo": tempo
	})
	
	jogadores_que_finalizaram += 1
	var total_reais = 0
	for d in Global.dados_jogadores:
		if d != null: total_reais += 1
	
	if jogadores_que_finalizaram >= total_reais:
		_finalizar_corrida_total()

func _on_corrida_iniciada():
	corrida_ativa = true # ISSO faz o _process começar a contar o tempo
	tempo_decorrido = 0.0

func _finalizar_corrida_total():
	corrida_ativa = false
	lista_resultados.sort_custom(func(a, b): return a.tempo < b.tempo)
	
	# Adiciona ao root para cobrir toda a tela do Windows
	var tela = tela_final_scene.instantiate()
	get_tree().root.add_child(tela) 
	tela.configurar_resultados(lista_resultados)
	get_tree().call_group("menu_pausa", "desativar_pausa")

func _input(event):
	if OS.is_debug_build() and event.is_action_pressed("ui_accept"): # Tecla Enter/Espaço
		print("DEBUG: Pulando contagem de largada")
		_iniciar_sequencia_largada() # Pula direto para a liberação
