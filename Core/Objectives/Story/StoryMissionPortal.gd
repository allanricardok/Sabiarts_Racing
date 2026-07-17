# StoryMissionPortal.gd
extends Area3D
class_name StoryMissionPortal

@export var mission_data: StoryMissionData
var is_active: bool = true

func _ready():
	add_to_group("mission_portals")
	body_entered.connect(_on_body_entered)
	
	if is_instance_valid(Global) and "completed_mission_tiers" in Global:
		if mission_data and is_fully_completed():
			make_semitransparent()

	if not is_unlocked():
		_hide_and_disable()

func is_unlocked() -> bool:
	if not mission_data: return true
	var required = mission_data.required_unlock_points if "required_unlock_points" in mission_data else 0
	var current = Global.story_total_points if is_instance_valid(Global) and "story_total_points" in Global else 0
	return current >= required

# =====================================================================
# CORREÇÃO 3: Avaliação Inteligente de Missões (Com e Sem Tiers)
# =====================================================================
func is_fully_completed() -> bool:
	if not mission_data:
		return false
		
	# Fallback: Se for uma missão clássica que não usa a lista de Tiers, checa direto a chave antiga.
	if mission_data.mission_tiers.is_empty():
		return Global.completed_story_missions.has(mission_data.mission_id)
		
	for i in range(mission_data.mission_tiers.size()):
		var tier_key = mission_data.mission_id + "_tier_" + str(i)
		if not Global.completed_mission_tiers.has(tier_key):
			return false
	return true

func _hide_and_disable():
	visible = false
	is_active = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

func activate_portal_safely():
	if not is_unlocked(): return 
	
	visible = true
	is_active = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

func _on_body_entered(body):
	if not is_active: return
	
	if body.is_in_group("jogadores"):
		if not mission_data:
			return
		
		set_deferred("monitoring", false)
		_trigger_mission.call_deferred()

func _trigger_mission():
	var story_controller = get_tree().get_first_node_in_group("StoryController")
	if story_controller:
		get_tree().paused = true
		story_controller.request_mission_start(self, mission_data)
	else:
		set_deferred("monitoring", true)

func make_semitransparent():
	var meshes = find_children("*", "MeshInstance3D", true, false)
	
	for child in meshes:
		if "transparency" in child:
			child.transparency = 0.65
			
		var mat = child.get_active_material(0)
		if mat and mat is BaseMaterial3D:
			var novo_material = mat.duplicate()
			novo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			novo_material.albedo_color.a = 0.35 
			child.set_surface_override_material(0, novo_material)
