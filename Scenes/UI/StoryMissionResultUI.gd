# StoryMissionResultUI.gd
extends CanvasLayer

@onready var title_label = %Title # Ajuste o caminho para a sua árvore
@onready var desc_label = %Description   # Ajuste o caminho
@onready var continue_btn = %ContinueBtn # Ajuste o caminho  
@onready var points_label = %PointsLabel # <-- NOVO LABEL (Crie na cena se não tiver)


var current_controller: Node = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

# Atualizado para receber os pontos
func show_result(success: bool, mission_name: String, points_earned: int, controller: Node):
	current_controller = controller
	
	if success:
		title_label.text = "MISSÃO CONCLUÍDA!"
		title_label.add_theme_color_override("font_color", Color.GREEN)
		desc_label.text = "Completaste: " + mission_name
		if points_label:
			points_label.text = "+ " + str(points_earned) + " Pontos!\nProgresso da Cidade: " + str(Global.story_total_points) + " / " + str(Global.points_to_next_city)
			points_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		title_label.text = "MISSÃO FALHADA!"
		title_label.add_theme_color_override("font_color", Color.RED)
		desc_label.text = "Não conseguiste completar: " + mission_name
		if points_label:
			points_label.text = "0 Pontos recebidos."
			points_label.add_theme_color_override("font_color", Color.GRAY)
		
	visible = true
	continue_btn.grab_focus()

# Conecte o sinal "pressed" do botão Continuar a esta função
func _on_continue_btn_pressed():
	visible = false
	if current_controller:
		current_controller.resume_open_world()
