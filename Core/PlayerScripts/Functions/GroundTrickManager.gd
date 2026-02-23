# GroundTrickManager.gd
extends Node
class_name GroundTrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO ---
@export_group("Timing")
@export var COMBO_TIMEOUT : float = 3.0
@export var DISPLAY_STAY_TIME : float = 3.0

const COLOR_GROUND = "#ff4444" 

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

## Agora aceita um valor de pontos customizado
func add_ground_action(id: String, custom_points: int = -1):
	if not GROUND_DATA.has(id): return
	
	# Define se usamos o ponto do dicionário ou o ponto vindo do objeto
	var final_points = custom_points if custom_points != -1 else GROUND_DATA[id].points
	
	# Se o carro estiver no ar, envia para o TrickManager (Combo Aéreo)
	var air_tricks = car.get_node_or_null("%TrickManager") as TrickManager
	if air_tricks and air_tricks.tracking_jump:
		# Passamos o nome da ação e os pontos (dinâmicos ou fixos)
		air_tricks.add_external_action(GROUND_DATA[id].name, final_points, COLOR_GROUND)
		return
		
	if not tracking_combo: _start_combo()
	
	_register_action_logic(id, final_points)
	_restart_inactivity_timer()

func _start_combo():
	tracking_combo = true
	actions_done.clear()
	points_per_action.clear()
	display_version += 1

func _register_action_logic(id: String, points: int):
	var data = GROUND_DATA[id]
	actions_done.append(data.name)
	points_per_action.append(points) # Usa os pontos passados pela função
	_update_live_display()

# --- (O RESTANTE DAS FUNÇÕES: MULTIPLICADOR, DISPLAY E FINALIZE PERMANECEM IGUAIS) ---

func _get_dynamic_multiplier() -> float:
	if actions_done.size() == 0: return 1.0
	var mult = 1.0 
	var seen_in_this_combo = {}
	for i in range(actions_done.size()):
		var a_name = actions_done[i]
		if i == 0:
			seen_in_this_combo[a_name] = true
			continue
		if seen_in_this_combo.has(a_name): mult += 0.5 
		else:
			mult += 1.0 
			seen_in_this_combo[a_name] = true
	return mult

func _update_live_display():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
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
	var names_bbcode = ""
	var pts_text = ""
	for a_name in order:
		var data = grouped[a_name]
		if data.count >= 3:
			names_bbcode += "[color=" + COLOR_GROUND + "](x" + str(data.count) + " " + a_name + ")[/color] + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_bbcode += "[color=" + COLOR_GROUND + "]" + a_name + "[/color] + "
				pts_text += str(int(data.points / data.count)) + " + "
	if names_bbcode.ends_with(" + "): names_bbcode = names_bbcode.left(-3)
	if pts_text.ends_with(" + "): pts_text = pts_text.left(-3)
	var current_mult = _get_dynamic_multiplier()
	var info = names_bbcode + "\n" + str(current_mult) + "x " + pts_text
	hud.update_combo_live(info)

func _finalize_ground_score():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	var total_base = 0
	for p in points_per_action: total_base += p
	var mult = _get_dynamic_multiplier()
	var final_score = int(total_base * mult)
	ScoreManager.add_points(final_score)
	var grouped = {}
	var order = []
	for i in range(actions_done.size()):
		var a_name = actions_done[i]
		if not grouped.has(a_name):
			grouped[a_name] = {"count": 0, "points": 0}
			order.append(a_name)
		grouped[a_name].count += 1
		grouped[a_name].points += points_per_action[i]
	var names_bbcode = ""
	var pts_text = ""
	for a_name in order:
		var data = grouped[a_name]
		if data.count >= 3:
			names_bbcode += "[color=" + COLOR_GROUND + "](x" + str(data.count) + " " + a_name + ")[/color] + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_bbcode += "[color=" + COLOR_GROUND + "]" + a_name + "[/color] + "
				pts_text += str(int(data.points / data.count)) + " + "
	if names_bbcode.ends_with(" + "): names_bbcode = names_bbcode.left(-3)
	if pts_text.ends_with(" + "): pts_text = pts_text.left(-3)
	var info = names_bbcode + "\n" + str(mult) + "x " + pts_text
	var msg = "Cool combo!" if mult > 1.5 else "Nice hit!"
	var result = msg + "\n" + ScoreManager.format_score_with_dots(final_score) + " points"
	hud.show_combo_final(info, result)
	tracking_combo = false

func _restart_inactivity_timer():
	var current_timer_id = Time.get_ticks_msec()
	last_action_time = current_timer_id
	await get_tree().create_timer(COMBO_TIMEOUT).timeout
	if last_action_time == current_timer_id:
		if tracking_combo: _finalize_ground_score()
