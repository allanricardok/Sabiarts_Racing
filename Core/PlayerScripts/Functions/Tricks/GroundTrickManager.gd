extends Node
class_name GroundTrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO ---
@export_group("Timing")
@export var COMBO_TIMEOUT : float = 3.0
@export var DISPLAY_STAY_TIME : float = 3.0

@export_group("Limites")
@export var MAX_COMBO_MULTIPLIER : float = 5.0

const COLOR_GROUND = "#ff4444" 

const GROUND_DATA = {
	"HIT_OBJECT": {"name": "Hit object", "points": 5},
	"DESTROY_OBJECT": {"name": "Destroyed object", "points": 50},
	"COMBAT_HIT": {"name": "Impact!", "points": 20}
}

var actions_done : Array = []
var points_per_action : Array = []
var tracking_combo := false
var display_version : int = 0

var _trick_manager: Node
var _stats_component: Node
var _is_bot: bool = false
var _cached_hud: Node
var _combo_timer: float = 0.0

func _ready():
	_trick_manager = car.get_node_or_null("%TrickManager")
	_stats_component = car.get_node_or_null("%StatsComponent")
	call_deferred("_setup_cache")

# CORREÇÃO: O Cache volta a ser feito preventivamente no _ready()
func _setup_cache():
	var input_comp = car.get_node_or_null("%InputComponent")
	if is_instance_valid(input_comp) and "is_bot" in input_comp:
		_is_bot = input_comp.is_bot
		
	if not _is_bot:
		for hud in get_tree().get_nodes_in_group("HUD"):
			if is_instance_valid(car) and hud.get_viewport() == car.get_viewport():
				_cached_hud = hud
				break

func _process(delta):
	if tracking_combo and _combo_timer > 0:
		_combo_timer -= delta
		if _combo_timer <= 0:
			_finalize_ground_score()

func add_ground_action(id: String):
	if not GROUND_DATA.has(id): return
	
	if is_instance_valid(_trick_manager) and _trick_manager.tracking_jump:
		_trick_manager.add_external_action(GROUND_DATA[id].name, GROUND_DATA[id].points, COLOR_GROUND)
		return
		
	if not tracking_combo: _start_combo()
	
	_register_action_logic(id)
	_restart_inactivity_timer()

func add_custom_action(custom_name: String, points: int):
	if is_instance_valid(_trick_manager) and _trick_manager.tracking_jump:
		_trick_manager.add_external_action(custom_name, points, COLOR_GROUND)
		return
		
	if not tracking_combo: _start_combo()
	
	actions_done.append(custom_name)
	points_per_action.append(points)
	
	_update_live_display()
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

func _get_dynamic_multiplier() -> float:
	if actions_done.size() == 0: return 1.0
	
	var mult = 1.0 
	var seen_in_this_combo = {}
	
	for i in range(actions_done.size()):
		var a_name = actions_done[i]
		if i == 0:
			seen_in_this_combo[a_name] = true
			continue
			
		if seen_in_this_combo.has(a_name):
			mult += 0.5 
		else:
			mult += 1.0 
			seen_in_this_combo[a_name] = true
			
	return min(mult, MAX_COMBO_MULTIPLIER)

func _get_local_hud() -> Node:
	# Retorna nulo imediatamente se for bot, poupando processamento
	if _is_bot: return null
	
	# Se já temos o cache válido, usa ele
	if is_instance_valid(_cached_hud): 
		return _cached_hud
		
	# Fallback: Se o cache falhou na inicialização, busca dinamicamente igual ao TrickManager
	if is_instance_valid(car) and "input" in car and is_instance_valid(car.input):
		_cached_hud = get_tree().get_first_node_in_group("HUD" + car.input.suffix)
		
	return _cached_hud

func _update_live_display():
	var hud = _get_local_hud()
	if not is_instance_valid(hud): return 
	
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
	var total_base = 0
	for p in points_per_action: total_base += p
	var mult = _get_dynamic_multiplier()
	var final_score = int(total_base * mult)

	ScoreManager.add_points(final_score, car.id)
	
	if is_instance_valid(_stats_component) and _stats_component.has_method("add_heal_score"):
		_stats_component.add_heal_score(final_score)
	
	var hud = _get_local_hud()
	if not is_instance_valid(hud): 
		tracking_combo = false
		return 
	
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
	if mult >= MAX_COMBO_MULTIPLIER: msg = "MAX COMBO!"
		
	var result = msg + "\n" + ScoreManager.format_score_with_dots(final_score) + " points"
	
	hud.show_combo_final(info, result)
	tracking_combo = false

func _restart_inactivity_timer():
	_combo_timer = COMBO_TIMEOUT
