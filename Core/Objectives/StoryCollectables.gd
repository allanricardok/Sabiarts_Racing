extends Area3D
class_name StoryCollectible

@export_group("Configuração do Coletável")
## O NOME ÚNICO deste item. NUNCA repita o ID em dois itens diferentes!
@export var collectible_id: String = "item_001"
## O nome que vai aparecer no Menu de Pausa.
@export var collectible_name: String = "Troféu Oculto"
## Quantidade de pontos que este item dá para a progressão.
@export var points_value: int = 500

func _ready():
	# 1. TRAVA DE MODO DE JOGO: Só existe no Modo História!
	if is_instance_valid(Global) and "current_run_mode" in Global:
		if Global.current_run_mode != Global.RunMode.STORY:
			queue_free() # Destrói de verdade se for modo Batalha/Corrida
			return
			
	# Adiciona ao grupo para o Menu de Pausa o encontrar
	add_to_group("story_collectibles")

	# 2. VERIFICAÇÃO DE SAVE: O jogador já pegou isto antes?
	if is_instance_valid(Global) and "collected_items_ids" in Global:
		if Global.collected_items_ids.has(collectible_id):
			_desativar_coletavel()
			return
			
	body_entered.connect(_on_body_entered)
	_iniciar_animacao_flutuante()

# --- A TÁTICA DO SONO PROFUNDO ---
func _desativar_coletavel():
	hide()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# Destrói apenas os gráficos e as animações para limpar a memória RAM
	var visual = find_child("Visual", true, false)
	if is_instance_valid(visual):
		visual.queue_free()

func _on_body_entered(body):
	if not body.is_in_group("jogadores"): return
		
	var is_bot = false
	var ic = body.get_node_or_null("%InputComponent")
	if not ic: ic = body.find_child("InputComponent*", true, false)
	if ic and "is_bot" in ic and ic.is_bot: is_bot = true
	
	if not is_bot:
		_coletar_item()

func _coletar_item():
	# Coloca o item para dormir imediatamente
	_desativar_coletavel()
	
	if is_instance_valid(Global) and "story_total_points" in Global:
		Global.story_total_points += points_value
		
	if is_instance_valid(Global) and "collected_items_ids" in Global:
		Global.collected_items_ids.append(collectible_id)
		if Global.has_method("save_story_progress"):
			Global.save_story_progress()
			
	var mensagem = "Encontrado: " + collectible_name + " (+" + str(points_value) + " pts)"
	get_tree().call_group("HUD", "mostrar_missao_ativa", mensagem)
	
	await get_tree().create_timer(3.0).timeout
	get_tree().call_group("HUD", "esconder_missao_ativa")
	
	var controller = get_tree().get_first_node_in_group("StoryController")
	if controller and controller.has_method("_check_next_map_unlock"):
		controller._check_next_map_unlock()

func _iniciar_animacao_flutuante():
	var visual = find_child("Visual", true, false)
	if not visual: return
	
	var tween_move = create_tween().set_loops()
	tween_move.tween_property(visual, "position:y", 0.3, 1.5).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween_move.tween_property(visual, "position:y", -0.3, 1.5).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	var tween_spin = create_tween().set_loops()
	tween_spin.tween_property(visual, "rotation:y", TAU, 3.0).as_relative()
