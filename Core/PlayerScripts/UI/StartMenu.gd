# StartMenu.gd
extends CanvasLayer # Ajustado para o seu tipo de nó

@onready var mission_list = %MissionList 
@onready var desc_label = %MapDescription
@onready var start_button = %StartButton

func _ready():
	# IMPORTANTE: O Process Mode do StartMenu deve estar como "Always" no Inspetor
	get_tree().paused = true
	show()
	start_button.grab_focus()
	
	# Aguarda o MissionManager carregar os dados
	await get_tree().process_frame
	_preencher_missoes()

func _preencher_missoes():
	var data = MissionManager.current_map_data
	if not data: return
	
	# Usamos 'get()' para tentar pegar o valor. Se não existir, ele usa o map_name.
	var desc = data.get("map_description")
	if desc == null or desc == "":
		desc_label.text = data.map_name + "\nObjetivos da Fase:"
	else:
		desc_label.text = data.map_name + "\n" + desc
	
	# Limpa e popula a lista (mantenha o resto como estava)
	for child in mission_list.get_children(): child.queue_free()
	
	print("Carregando ", data.missions.size(), " missões...")

	for i in range(data.missions.size()):
		var m = data.missions[i]
		# Usando Label simples para teste inicial (mais seguro que RichText)
		var item = Label.new()
		
		# Lógica de cores/texto
		if i < 6:
			item.text = "□ " + m.description
			item.add_theme_color_override("font_color", Color.WHITE)
		else:
			item.text = "🔒 ??? (Bloqueada)"
			item.add_theme_color_override("font_color", Color.DIM_GRAY)
		
		# Garante que a Label apareça no VBoxContainer
		item.custom_minimum_size.y = 30 
		mission_list.add_child(item)

func _on_start_btn_pressed():
	print("Botão Start pressionado!")
	get_tree().paused = false
	hide()
	
	# Avisa o LevelController
	var logic = get_tree().get_first_node_in_group("LevelLogic")
	if logic and logic.has_method("start_timer"): 
		logic.start_timer()
	else:
		print("AVISO: LevelLogic não encontrado ou função start_timer ausente.")
