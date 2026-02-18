extends Node
class_name TrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO (EXPOSTAS NO INSPETOR) ---
@export_group("Timing & Balance")
## Tempo mínimo no ar para o combo ser considerado "sério" e aparecer no HUD
@export var AIR_TIME_THRESHOLD : float = 1.3
## Tempo que o resultado final fica parado na tela (Obrigatório)
@export var DISPLAY_STAY_TIME : float = 3.0
## Multiplicador de pontos por tempo de ar (pts = segundos * mult)
@export var AIR_TIME_POINTS_MULT : float = 10.0

const TRICK_DATA = {
	"ROLL_L": {"name": "Roll 360", "points": 50}, 
	"ROLL_R": {"name": "Roll 360", "points": 50},
	"BACKFLIP": {"name": "Backflip", "points": 80}, 
	"FRONTFLIP": {"name": "Frontflip", "points": 80},
	"SPIN": {"name": "Spin 360", "points": 40}
}

var global_stunt_uses = {}
var air_time := 0.0
var tracking_jump := false
var tricks_done : Array = []
var points_per_trick : Array = []
var current_jump_uses = {}
var angle_accumulator_y := 0.0 
var last_basis : Basis

# Controle de Tempo Real e HUD
var jump_start_timestamp : int = 0
var display_version : int = 0
# NOVA VARIÁVEL: Bloqueia o HUD para garantir os 3 segundos
var is_showing_final_score := false

func add_external_action(action_name: String, points: int):
	if not tracking_jump: _start_new_jump()
	tricks_done.append(action_name)
	points_per_trick.append(points)
	_update_live_display()

func add_trick_manually(id: String):
	if not tracking_jump: _start_new_jump()
	_register_trick_logic(id)

func _track_rotation():
	var current_basis = car.global_transform.basis
	var euler = (last_basis.inverse() * current_basis).get_rotation_quaternion().get_euler()
	last_basis = current_basis
	angle_accumulator_y += euler.y
	if abs(angle_accumulator_y) >= (PI * 1.85):
		_register_trick_logic("SPIN")
		angle_accumulator_y = 0.0

func _register_trick_logic(id: String):
	var base_pts = TRICK_DATA[id].points
	var g_count = global_stunt_uses.get(id, 0)
	var g_mult = max(0.1, 1.0 - (g_count * 0.05))
	var j_count = current_jump_uses.get(id, 0)
	var j_mult = max(0.1, pow(0.5, j_count))
	var final_pts = int(base_pts * g_mult * j_mult)
	tricks_done.append(TRICK_DATA[id].name)
	points_per_trick.append(final_pts)
	current_jump_uses[id] = j_count + 1
	_update_live_display()

func process_air_time(_delta: float, _is_near_ground: bool):
	if not tracking_jump:
		if not _is_near_ground:
			_start_new_jump()
		else:
			return
	
	air_time = (Time.get_ticks_msec() - jump_start_timestamp) / 1000.0
	
	_track_rotation()
	
	if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0:
		is_showing_final_score = false 
		_update_live_display()

func _start_new_jump():
	tracking_jump = true
	jump_start_timestamp = Time.get_ticks_msec()
	air_time = 0.0
	display_version += 1 
	
	var ground_manager = car.get_node_or_null("%GroundTrickManager")
	if ground_manager and ground_manager.tracking_combo:
		tricks_done = ground_manager.actions_done.duplicate()
		points_per_trick = ground_manager.points_per_action.duplicate()
		ground_manager.tracking_combo = false
		ground_manager.actions_done.clear()
		ground_manager.points_per_action.clear()
	else:
		tricks_done.clear()
		points_per_trick.clear()
	
	current_jump_uses.clear()
	angle_accumulator_y = 0.0
	last_basis = car.global_transform.basis

# --- NOVA FUNÇÃO PARA CALCULAR O MULTIPLICADOR DINÂMICO ---
func _get_dynamic_multiplier() -> float:
	var mult = 1.0 # Base referente ao airtime
	var seen_in_this_jump = {}
	
	for t_name in tricks_done:
		if seen_in_this_jump.has(t_name):
			mult += 0.5 # Repetida: soma apenas 0.5
		else:
			mult += 1.0 # Nova: soma 1.0
			seen_in_this_jump[t_name] = true
	
	return mult

func _update_live_display():
	if is_showing_final_score: return
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	var grouped_tricks = {} 
	var order = []
	for i in range(tricks_done.size()):
		var t_name = tricks_done[i]
		var t_pts = points_per_trick[i]
		if not grouped_tricks.has(t_name):
			grouped_tricks[t_name] = {"count": 0, "points": 0}
			order.append(t_name)
		grouped_tricks[t_name].count += 1
		grouped_tricks[t_name].points += t_pts

	var names_text = ""
	var pts_text = ""
	for t_name in order:
		var data = grouped_tricks[t_name]
		if data.count >= 3:
			names_text += "(x" + str(data.count) + " " + t_name + ") + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_text += t_name + " + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	var current_mult = _get_dynamic_multiplier()
	
	# Monta o bloco de texto de duas linhas para a air_time_label
	var info = names_text + ("%.2fs" % air_time) + " airtime"
	info += "\n" + str(current_mult) + "x " + pts_text + str(int(air_time * AIR_TIME_POINTS_MULT))
	
	hud.update_combo_live(info)

func _finalize_score():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	is_showing_final_score = true 
	
	var total_base = int(air_time * AIR_TIME_POINTS_MULT)
	for p in points_per_trick: total_base += p
	var mult = _get_dynamic_multiplier()
	var final_score = int(total_base * mult)
	
	ScoreManager.add_points(final_score)
	
	# --- RECONSTRUÇÃO DA STRING DETALHADA (IGUAL AO LIVE) ---
	var grouped_tricks = {} 
	var order = []
	for i in range(tricks_done.size()):
		var t_name = tricks_done[i]
		var t_pts = points_per_trick[i]
		if not grouped_tricks.has(t_name):
			grouped_tricks[t_name] = {"count": 0, "points": 0}
			order.append(t_name)
		grouped_tricks[t_name].count += 1
		grouped_tricks[t_name].points += t_pts

	var names_text = ""
	var pts_text = ""
	for t_name in order:
		var data = grouped_tricks[t_name]
		if data.count >= 3:
			names_text += "(x" + str(data.count) + " " + t_name + ") + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_text += t_name + " + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	if names_text.ends_with(" + "): names_text = names_text.left(-3)
	if pts_text.ends_with(" + "): pts_text = pts_text.left(-3)

	# Info (Cima): Lista detalhada + Math
	var info = names_text + " " + ("%.2fs" % air_time) + " airtime"
	info += "\n" + str(mult) + "x " + pts_text + " + " + str(int(air_time * AIR_TIME_POINTS_MULT))
	
	# Result (Baixo): Mensagem + Score Final
	var msg = "Awesome trick!" if tricks_done.size() > 0 else "Nice air!"
	var result = msg + "\n" + ScoreManager.format_score_with_dots(final_score) + " points"
	
	hud.show_combo_final(info, result)
	
	# Mantém a flag por 3s para evitar que quiques limpem o HUD
	await get_tree().create_timer(3.0).timeout
	is_showing_final_score = false

func check_landing(_is_doing_stunt: bool):
	if tracking_jump:
		if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0:
			_finalize_score()
		else:
			reset_trick()
	tracking_jump = false

func reset_trick():
	tracking_jump = false
	if is_showing_final_score: return
	
	display_version += 1
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		hud.air_time_label.visible = false
		hud.air_message_label.visible = false
