extends Node
class_name GroundTrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO ---
@export_group("Timing")
@export var COMBO_TIMEOUT : float = 3.0
@export var DISPLAY_STAY_TIME : float = 3.0

const GROUND_DATA = {
	"HIT_OBJECT": {"name": "Hit object", "points": 5},
	"DESTROY_OBJECT": {"name": "Destroyed object", "points": 500},
	"COMBAT_HIT": {"name": "Impact!", "points": 150}
}

var actions_done : Array = []
var points_per_action : Array = []
var tracking_combo := false
var last_action_time := 0
var display_version : int = 0

func add_ground_action(id: String):
	if not GROUND_DATA.has(id): return
	var air_tricks = car.get_node_or_null("%TrickManager") as TrickManager
	if air_tricks and air_tricks.tracking_jump:
		air_tricks.add_external_action(GROUND_DATA[id].name, GROUND_DATA[id].points)
		return
	if not tracking_combo: _start_combo()
	_register_action_logic(id)
	_restart_inactivity_timer()

func _start_combo():
	tracking_combo = true
	actions_done.clear()
	points_per_action.clear()
	display_version += 1

func _register_action_logic(id: String):
	var data = GROUND_DATA[id]
	actions_done.append(data.name)
	points_per_action.append(data.points)
	_update_live_display()

func _update_live_display():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	display_version += 1
	
	var grouped = {}
	var order = []
	for i in range(actions_done.size()):
		var a_name = actions_done[i]
		var a_pts = points_per_action[i]
		if not grouped.has(a_name):
			grouped[a_name] = {"count": 0, "points": 0}
			order.append(a_name)
		grouped[a_name].count += 1
		grouped[a_name].points += a_pts

	var names_text = ""
	var pts_text = ""
	for a_name in order:
		var data = grouped[a_name]
		if data.count >= 3:
			names_text += "(x" + str(data.count) + " " + a_name + ") + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_text += a_name + " + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	if names_text.ends_with(" + "): names_text = names_text.left(-3)
	if pts_text.ends_with(" + "): pts_text = pts_text.left(-3)

	var mult = actions_done.size()
	hud.air_time_label.text = names_text
	hud.air_time_label.text += "\n" + str(mult) + "x " + pts_text
	hud.air_time_label.visible = true
	hud.air_message_label.visible = false

func _restart_inactivity_timer():
	var current_timer_id = Time.get_ticks_msec()
	last_action_time = current_timer_id
	await get_tree().create_timer(COMBO_TIMEOUT).timeout
	if last_action_time == current_timer_id:
		if tracking_combo: _finalize_ground_score()

func _finalize_ground_score():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	var current_version = display_version
	
	var total_base = 0
	for p in points_per_action: total_base += p
	var mult = actions_done.size()
	var final_score = total_base * mult
	ScoreManager.add_points(final_score)
	
	var msg = "Cool trick!" if mult > 1 else "Nice hit!"
	hud.air_message_label.text = msg + "\n" + str(final_score) + " points"
	hud.air_message_label.visible = true
	hud.air_time_label.visible = true
	tracking_combo = false
	
	await get_tree().create_timer(DISPLAY_STAY_TIME).timeout
	
	if display_version == current_version:
		hud.air_time_label.visible = false
		hud.air_message_label.visible = false
