# StoryMissionUI.gd
extends CanvasLayer

@onready var title_label = %Title 
@onready var desc_label = %Description   
@onready var accept_btn = %Accept   
@onready var reject_btn = %Reject

var current_controller: Node = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS 
	visible = false

func show_mission_prompt(data: StoryMissionData, controller: Node):
	current_controller = controller
	title_label.text = data.mission_name
	
	# Constrói o texto do prompt listando todas as metas dinamicamente
	var full_desc = data.mission_description + "\n\nOBJETIVOS DE TIERS:"
	
	if not data.mission_tiers.is_empty():
		for i in range(data.mission_tiers.size()):
			var tier = data.mission_tiers[i]
			full_desc += "\n- Tier %d (%s): Meta %.0f | Recompensa: %d pts" % [i + 1, tier.tier_name, tier.target_value, tier.reward_points]
	else:
		full_desc += "\n- Meta Padrão: Completar o objetivo clássico"
		
	desc_label.text = full_desc
	visible = true
	accept_btn.grab_focus()

func _on_accept_btn_pressed():
	visible = false
	if current_controller:
		current_controller.accept_mission()

func _on_reject_btn_pressed():
	visible = false
	if current_controller:
		current_controller.decline_mission()
