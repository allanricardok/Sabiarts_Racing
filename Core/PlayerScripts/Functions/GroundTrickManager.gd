# GroundTrickManager.gd
extends Node
class_name GroundTrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO ---
@export_group("Timing")
## Tempo de inatividade (segundos) para fechar o combo no chão
@export var COMBO_TIMEOUT : float = 3.0
## Tempo que o resultado final do combo de solo fica na tela
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
	
	# Se o carro estiver no ar, envia a ação para o TrickManager (Combo Aéreo)
	var air_tricks = car.get_node_or_null("%TrickManager") as TrickManager
	if air_tricks and air_tricks.tracking_jump:
		air_tricks.add_external_action(GROUND_DATA[id].name, GROUND_DATA[id].points)
		return
		
	# Inicia combo de solo se não estiver ativo
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

# --- NOVA LÓGICA DE MULTIPLICADOR DINÂMICO PARA O SOLO ---
func _get_dynamic_multiplier() -> float:
	if actions_done.size() == 0: return 1.0
	
	var mult = 1.0 # Base do combo
	var seen_in_this_combo = {}
	
	for i in range(actions_done.size()):
		var a_name = actions_done[i]
		# A primeira ação do combo não soma, ela é a base (1.0)
		if i == 0:
			seen_in_this_combo[a_name] = true
			continue
			
		if seen_in_this_combo.has(a_name):
			mult += 0.5 # Repetida: soma apenas 0.5
		else:
			mult += 1.0 # Nova: soma 1.0
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

	var current_mult = _get_dynamic_multiplier()
	var info = names_text + "\n" + str(current_mult) + "x " + pts_text
	
	hud.update_combo_live(info)

func _finalize_ground_score():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	var total_base = 0
	for p in points_per_action: total_base += p
	var mult = _get_dynamic_multiplier()
	var final_score = int(total_base * mult)
	
	ScoreManager.add_points(final_score)
	
	# --- RECONSTRUÇÃO DA STRING DETALHADA (IGUAL AO LIVE) ---
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

	# Info (Cima): Replicamos o texto do combo na air_time_label
	var info = names_text + "\n" + str(mult) + "x " + pts_text
	
	# Result (Baixo): Mensagem de combo final na air_message_label
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
