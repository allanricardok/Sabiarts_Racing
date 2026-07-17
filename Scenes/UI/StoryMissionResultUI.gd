# StoryMissionResultUI.gd
extends CanvasLayer

@onready var title_label = %Title 
@onready var desc_label = %Description   
@onready var continue_btn = %ContinueBtn  
@onready var points_label = %PointsLabel 

var current_controller: Node = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

# Nova assinatura de função que lida perfeitamente com vitórias parciais ou absolutas
func show_result_with_tiers(success: bool, is_all_completed: bool, mission_name: String, points_earned: int, controller: Node):
	current_controller = controller
	
	if success:
		if is_all_completed:
			title_label.text = "MISSÃO COMPLETADA!"
			title_label.add_theme_color_override("font_color", Color.GREEN)
			desc_label.text = "Você platinou com sucesso todos os tiers de:\n" + mission_name
		else:
			title_label.text = "VITÓRIA PARCIAL!"
			title_label.add_theme_color_override("font_color", Color.YELLOW)
			desc_label.text = "O tempo acabou, mas você completou tiers em:\n" + mission_name
			
		if points_label:
			points_label.text = "+ " + str(points_earned) + " Pontos!\nProgresso da Cidade: " + str(Global.story_total_points) + " / " + str(Global.points_to_next_city)
			points_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		title_label.text = "MISSÃO FALHADA!"
		title_label.add_theme_color_override("font_color", Color.RED)
		desc_label.text = "Nenhum tier foi completado a tempo em:\n" + mission_name
		if points_label:
			points_label.text = "0 Pontos recebidos."
			points_label.add_theme_color_override("font_color", Color.GRAY)
		
	visible = true
	continue_btn.grab_focus()

func _on_continue_btn_pressed():
	visible = false
	if current_controller:
		current_controller.resume_open_world()
