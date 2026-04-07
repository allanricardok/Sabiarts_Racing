# TutorialChecklist.gd
extends PanelContainer

# A lista de missões (ID : Texto visível)
var tasks = {
	"barrels": "Shoot barrels using the machine gun",
	"grab_weapon": "Grab the Common Weapon",
	"shoot_enemy": "Shoot the enemy using the Common Weapon",
	"speedtrap": "Speedtrap at 80 km/h",
	"ramp_jump": "Jump over the ramp",
	"pedestrian": "Run over or shoot a pedestrian",
	"turbo": "Use the Turbo Boost",
	"jump": "Use the Jump Boost",
	"trick": "Execute a trick",
	"letters": "Get the 5 floating letters",
	"teleport": "Use a teleport",
	"cross_map": "Cross the map"	
}

# Guarda as referências visuais de cada missão
var task_nodes = {}

func _ready():
	# Se não estivermos no modo Free Roam, a checklist se auto-destrói para não atrapalhar
	if Global.current_run_mode != Global.RunMode.FREE_ROAM:
		queue_free()
		return
		
	_gerar_visual_caderno()
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)
	
	# Cria uma linha de texto para cada missão
	for key in tasks.keys():
		var label = Label.new()
		label.text = "- " + tasks[key]
		# Fonte parecida com caneta (azul escura/preta)
		label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2)) 
		label.add_theme_font_size_override("font_size", 18)
		
		# Cria o risco vermelho (começa com largura 0)
		var line = ColorRect.new()
		line.color = Color(0.8, 0.1, 0.1, 0.8) # Vermelho translúcido (canetão)
		line.custom_minimum_size.y = 3
		line.size.y = 3
		line.size.x = 0
		
		# Centraliza a linha no meio do texto
		line.anchor_top = 0.5
		line.anchor_bottom = 0.5
		label.add_child(line)
		
		task_nodes[key] = {"label": label, "line": line, "completed": false}
		vbox.add_child(label)

# Função de estilo 100% via código! Cria uma folha de caderno amarela com a margem vermelha.
func _gerar_visual_caderno():
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.96, 0.85) # Amarelo papel
	style.border_color = Color(0.9, 0.4, 0.4) # Linha vermelha da margem esquerda
	style.border_width_left = 4
	style.content_margin_left = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.content_margin_right = 10
	style.shadow_color = Color(0, 0, 0, 0.15)
	style.shadow_size = 4
	add_theme_stylebox_override("panel", style)

# Função Mágica que os outros scripts vão chamar para riscar o papel
func complete_task(task_id: String):
	if not task_nodes.has(task_id): return
	
	var data = task_nodes[task_id]
	if data["completed"]: return # Se já riscou, ignora
	
	data["completed"] = true
	var line = data["line"]
	var label = data["label"]
	
	# Muda a cor da fonte para cinza para dar efeito de "já feito"
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.7))
	
	# Calcula o tamanho real do texto gerado
	var font = label.get_theme_font("font")
	var font_size = label.get_theme_font_size("font_size")
	var text_width = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	
	# Anima o risco vermelho da esquerda para a direita
	var tween = create_tween()
	tween.tween_property(line, "size:x", text_width + 5.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Checa se terminou tudo
	_check_all_completed()

func _check_all_completed():
	for key in task_nodes.keys():
		if not task_nodes[key]["completed"]:
			return
	
	print("[TutorialChecklist] ALL COMPLETED! Triggering level finish.")
	
	# --- NOVO: A MÁGICA DE ENCERRAR O TUTORIAL ---
	# Busca o cérebro da fase (LevelController)
	var lc = get_tree().get_first_node_in_group("LevelLogic")
	if is_instance_valid(lc) and lc.has_method("encerrar_partida"):
		# Chama a função que já criamos: desliga tempo, desliga input do carro, etc.
		lc.encerrar_partida()
