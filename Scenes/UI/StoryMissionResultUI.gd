# StoryMissionResultUI.gd
extends CanvasLayer

@onready var title_label = %Title # Ajuste o caminho para a sua árvore
@onready var desc_label = %Description   # Ajuste o caminho
@onready var continue_btn = %ContinueBtn # Ajuste o caminho

var current_controller: Node = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Funciona durante a pausa
	visible = false

# Chamado pelo Controller quando a missão acaba
func show_result(success: bool, mission_name: String, controller: Node):
	current_controller = controller
	
	if success:
		title_label.text = "MISSÃO CONCLUÍDA!"
		title_label.add_theme_color_override("font_color", Color.GREEN)
		desc_label.text = "Completaste: " + mission_name
	else:
		title_label.text = "MISSÃO FALHADA!"
		title_label.add_theme_color_override("font_color", Color.RED)
		desc_label.text = "O tempo esgotou-se para: " + mission_name
		
	visible = true
	continue_btn.grab_focus()

# Conecte o sinal "pressed" do botão Continuar a esta função
func _on_continue_btn_pressed():
	visible = false
	if current_controller:
		current_controller.resume_open_world()
