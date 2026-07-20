# HUDMissionPanels.gd
extends Node
class_name HUDMissionPanels

var ui_base: Control

# --- VARIÁVEIS DA UI DE MISSÃO ---
var story_mission_panel: PanelContainer
var story_mission_title_label: Label
var story_mission_tiers_container: VBoxContainer
var _labels_de_tier : Dictionary = {}

# --- VARIÁVEIS DA UI DO ITEM SECRETO (INDEPENDENTE) ---
var secret_item_panel: PanelContainer
var secret_item_label: Label
var secret_item_tween: Tween

func setup(base_node: Control):
	ui_base = base_node
	_setup_story_mission_ui()

func _setup_story_mission_ui():
	# 1. PAINEL DA MISSÃO PRINCIPAL
	story_mission_panel = PanelContainer.new()
	ui_base.add_child(story_mission_panel)
	
	story_mission_panel.anchor_left = 1.0
	story_mission_panel.anchor_top = 1.0
	story_mission_panel.anchor_right = 1.0
	story_mission_panel.anchor_bottom = 1.0
	
	story_mission_panel.offset_left = -380
	story_mission_panel.offset_top = -400
	story_mission_panel.offset_right = -30
	story_mission_panel.offset_bottom = -180
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.96, 0.85, 0.9)
	style.border_color = Color(0.9, 0.4, 0.4)
	style.border_width_left = 4
	style.content_margin_left = 15
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	style.content_margin_right = 15
	style.shadow_color = Color(0, 0, 0, 0.15)
	style.shadow_size = 4
	story_mission_panel.add_theme_stylebox_override("panel", style)
	
	var main_vbox = VBoxContainer.new()
	story_mission_panel.add_child(main_vbox)
	
	story_mission_title_label = Label.new()
	story_mission_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_mission_title_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2))
	story_mission_title_label.add_theme_font_size_override("font_size", 22)
	main_vbox.add_child(story_mission_title_label)
	
	var separator = HSeparator.new()
	main_vbox.add_child(separator)
	
	story_mission_tiers_container = VBoxContainer.new()
	main_vbox.add_child(story_mission_tiers_container)
	
	story_mission_panel.visible = false

	# 2. NOVO PAINEL ISOLADO PARA OS ITENS SECRETOS
	secret_item_panel = PanelContainer.new()
	ui_base.add_child(secret_item_panel)

	secret_item_panel.anchor_left = 1.0
	secret_item_panel.anchor_top = 1.0
	secret_item_panel.anchor_right = 1.0
	secret_item_panel.anchor_bottom = 1.0
	
	# Ele fica posicionado fisicamente logo acima do painel de missão
	secret_item_panel.offset_left = -380
	secret_item_panel.offset_top = -510
	secret_item_panel.offset_right = -30
	secret_item_panel.offset_bottom = -410
	
	var secret_style = StyleBoxFlat.new()
	secret_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	secret_style.border_color = Color(0.2, 0.8, 0.6)
	secret_style.border_width_left = 4
	secret_style.content_margin_left = 15
	secret_style.content_margin_top = 15
	secret_style.content_margin_bottom = 15
	secret_style.content_margin_right = 15
	secret_style.shadow_color = Color(0, 0, 0, 0.2)
	secret_style.shadow_size = 4
	secret_item_panel.add_theme_stylebox_override("panel", secret_style)
	
	secret_item_label = Label.new()
	secret_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	secret_item_label.add_theme_font_size_override("font_size", 18)
	secret_item_panel.add_child(secret_item_label)
	
	secret_item_panel.visible = false

func mostrar_item_secreto_coletado(nome_item: String, pontos: int):
	if not secret_item_panel: return
	
	secret_item_panel.visible = true
	secret_item_label.text = "★ ITEM SECRETO ENCONTRADO!\n" + nome_item + " (+" + str(pontos) + " pts)"
	secret_item_label.add_theme_color_override("font_color", Color.AQUAMARINE)
	
	if secret_item_tween and secret_item_tween.is_running():
		secret_item_tween.kill()
		
	secret_item_tween = create_tween()
	secret_item_panel.modulate.a = 0
	
	secret_item_tween.tween_property(secret_item_panel, "modulate:a", 1.0, 0.3)
	secret_item_tween.tween_interval(4.0)
	secret_item_tween.tween_property(secret_item_panel, "modulate:a", 0.0, 0.5)
	secret_item_tween.tween_callback(func(): secret_item_panel.visible = false)

func mostrar_missao_ativa_com_tiers(nome_missao: String, tiers: Array):
	if not story_mission_panel: return
	
	story_mission_panel.visible = true
	if story_mission_title_label: 
		story_mission_title_label.text = nome_missao
		story_mission_title_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2))
	
	if story_mission_tiers_container:
		for child in story_mission_tiers_container.get_children():
			child.queue_free()
		_labels_de_tier.clear()
		
		if tiers.is_empty():
			var lbl = Label.new()
			lbl.text = "- Completar Objetivo Clássico"
			lbl.add_theme_color_override("font_color", Color(0.2, 0.2, 0.3))
			story_mission_tiers_container.add_child(lbl)
			_labels_de_tier[0] = lbl
		else:
			for i in range(tiers.size()):
				var tier = tiers[i]
				var lbl = Label.new()
				lbl.text = "- Tier %d (%s): Meta %.0f" % [i + 1, tier.tier_name, tier.target_value]
				lbl.add_theme_color_override("font_color", Color(0.2, 0.2, 0.3))
				story_mission_tiers_container.add_child(lbl)
				_labels_de_tier[i] = lbl

func riscar_objetivo_tier(index: int, tier_name: String):
	if _labels_de_tier.has(index):
		var lbl = _labels_de_tier[index]
		if is_instance_valid(lbl):
			lbl.text = "[✔] Tier " + str(index + 1) + " (" + tier_name + ") Completado!"
			lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

func atualizar_status_missao(sucesso: bool):
	if story_mission_panel and story_mission_panel.visible:
		if sucesso:
			story_mission_title_label.add_theme_color_override("font_color", Color(0.2, 0.6, 0.2))
			story_mission_title_label.text = story_mission_title_label.text + " (CONCLUÍDA)"
		else:
			story_mission_title_label.add_theme_color_override("font_color", Color.RED)
			story_mission_title_label.text = story_mission_title_label.text + " (TEMPO ESGOTADO)"

func esconder_missao_ativa():
	if story_mission_panel:
		story_mission_panel.visible = false
