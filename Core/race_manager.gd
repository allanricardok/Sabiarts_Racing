extends Node

# Removidas as referências das bolas de UI que não usaremos mais
@export var voltas_para_vencer : int = 1
var tempo_decorrido : float = 0.0
var corrida_ativa : bool = false
var jogadores_que_finalizaram : int = 0

@export var tela_final_scene: PackedScene
var lista_resultados = [] 

signal corrida_iniciada

func _ready():
	add_to_group("race_manager")
	corrida_iniciada.connect(_on_corrida_iniciada)
	
	# Inicia a detecção imediata
	_sequencia_master_inicio()

func _sequencia_master_inicio():
	# 1. Conta quantos jogadores reais devem entrar
	var jogadores_reais = 0
	for data in Global.dados_jogadores:
		if data != null:
			jogadores_reais += 1
	
	# 2. ESPERA ATIVA (Apenas para garantir que os nós foram criados)
	while get_tree().get_nodes_in_group("jogadores").size() < jogadores_reais:
		await get_tree().process_frame
	
	# Margem técnica mínima para o motor de física estabilizar (0.03s é imperceptível)
	await get_tree().create_timer(0.03).timeout
	
	# 3. LARGADA IMEDIATA
	# Escondemos o container de UI caso ele ainda exista na cena
	if has_node("CanvasLayer/CenterContainer/HBoxContainer"):
		$CanvasLayer/CenterContainer/HBoxContainer.hide()
	
	# Disparamos tudo de uma vez
	emit_signal("corrida_iniciada") 
	get_tree().call_group("jogadores", "set_pode_mover", true)
	
	print("FOI! Corrida iniciada sem espera.")

func _process(delta):
	if corrida_ativa:
		tempo_decorrido += delta

func registrar_chegada_jogador(id_input, nome_exibicao, tempo):
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
	corrida_ativa = true
	tempo_decorrido = 0.0

func _finalizar_corrida_total():
	corrida_ativa = false
	lista_resultados.sort_custom(func(a, b): return a.tempo < b.tempo)
	
	var tela = tela_final_scene.instantiate()
	get_tree().root.add_child(tela) 
	tela.configurar_resultados(lista_resultados)
	get_tree().call_group("menu_pausa", "desativar_pausa")
