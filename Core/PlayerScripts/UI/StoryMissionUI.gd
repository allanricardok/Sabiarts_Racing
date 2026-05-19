# StoryMissionUI.gd
extends CanvasLayer

@onready var title_label = %Title # Ajuste o caminho conforme sua árvore
@onready var desc_label = %Description   # Ajuste o caminho
@onready var accept_btn = %Accept   # Ajuste o caminho
@onready var reject_btn = %Reject

var current_controller: Node = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Precisa funcionar enquanto o jogo está pausado!
	visible = false

# Essa função é chamada pelo Controller
func show_mission_prompt(data: StoryMissionData, controller: Node):
	current_controller = controller
	title_label.text = data.mission_name
	desc_label.text = data.mission_description
	visible = true
	accept_btn.grab_focus() # Para funcionar no controle/teclado

# Conecte o sinal "pressed" do botão Aceitar nesta função
func _on_accept_btn_pressed():
	visible = false
	if current_controller:
		current_controller.accept_mission()

# Conecte o sinal "pressed" do botão Recusar nesta função
func _on_reject_btn_pressed():
	visible = false
	if current_controller:
		current_controller.decline_mission()
