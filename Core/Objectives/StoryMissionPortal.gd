# StoryMissionPortal.gd
extends Area3D
class_name StoryMissionPortal

@export var mission_data: StoryMissionData
var is_active: bool = true

func _ready():
	add_to_group("mission_portals")
	body_entered.connect(_on_body_entered)
	
	if is_instance_valid(Global) and "completed_story_missions" in Global:
		if mission_data and Global.completed_story_missions.has(mission_data.mission_id):
			make_semitransparent()

func _on_body_entered(body):
	if not is_active: return
	
	if body.is_in_group("jogadores"):
		if not mission_data:
			push_error("[StoryPortal] Portal sem Mission Data configurado!")
			return
		
		set_deferred("monitoring", false)
		_trigger_mission.call_deferred()

func _trigger_mission():
	print("[StoryPortal] Jogador entrou no portal da missão: ", mission_data.mission_name)
	
	var story_controller = get_tree().get_first_node_in_group("StoryController")
	if story_controller:
		get_tree().paused = true
		story_controller.request_mission_start(self, mission_data)
	else:
		push_error("[StoryPortal] StoryModeController não foi encontrado na raiz da cena!")
		set_deferred("monitoring", true)

func make_semitransparent():
	# Mudado para MeshInstance3D para garantir compatibilidade direta com a malha visual
	for child in find_children("*", "MeshInstance3D", true, false):
		if "transparency" in child:
			child.transparency = 0.65
	print("[StoryPortal] Portal da missão '", mission_data.mission_name, "' agora está semitransparente.")
