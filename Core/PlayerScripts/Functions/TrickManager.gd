extends Node
class_name TrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO ---
@export_group("Timing & Balance")
@export var AIR_TIME_THRESHOLD : float = 1.3
@export var DISPLAY_STAY_TIME : float = 3.0
@export var AIR_TIME_POINTS_MULT : float = 10.0

# --- CORES DO SISTEMA ---
const COLOR_AIR = "#ffaa00"    # Laranja
const COLOR_GROUND = "#ff4444" # Vermelho
const COLOR_GAP = "#00aaff"    # Azul
const COLOR_TIME = "#ffffff"   # Branco

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

# Listas de Sincronia (Nomes, Pontos e Cores)
var tricks_done : Array = []
var points_per_trick : Array = []
var tricks_colors : Array = [] # <--- NOVA LISTA

var current_jump_uses = {}
var angle_accumulator_y := 0.0 
var last_basis : Basis

var jump_start_timestamp : int = 0
var display_version : int = 0
var is_showing_final_score := false

# --- FUNÇÕES DE REGISTRO ---

## Agora aceita uma cor opcional (Padrão Branco)
func add_external_action(action_name: String, points: int, color_hex: String = "#ffffff"):
	if not tracking_jump: _start_new_jump()
	tricks_done.append(action_name)
	points_per_trick.append(points)
	tricks_colors.append(color_hex) # Registra a cor (Azul para Gaps, etc)
	_update_live_display()

func add_trick_manually(id: String):
	if not tracking_jump: _start_new_jump()
	_register_trick_logic(id)

func _register_trick_logic(id: String):
	var base_pts = TRICK_DATA[id].points
	var g_count = global_stunt_uses.get(id, 0)
	var g_mult = max(0.1, 1.0 - (g_count * 0.05))
	var j_count = current_jump_uses.get(id, 0)
	var j_mult = max(0.1, pow(0.5, j_count))
	var final_pts = int(base_pts * g_mult * j_mult)
	
	tricks_done.append(TRICK_DATA[id].name)
	points_per_trick.append(final_pts)
	tricks_colors.append(COLOR_AIR) # Manobras de ar são LARANJA
	
	current_jump_uses[id] = j_count + 1
	_update_live_display()

func _start_new_jump():
	tracking_jump = true
	jump_start_timestamp = Time.get_ticks_msec()
	air_time = 0.0
	display_version += 1 
	
	tricks_done.clear()
	points_per_trick.clear()
	tricks_colors.clear() # Limpa as cores
	
	# Importação do GroundManager (Ações de chão entram em VERMELHO)
	var ground_manager = car.get_node_or_null("%GroundTrickManager")
	if ground_manager and ground_manager.tracking_combo:
		for i in range(ground_manager.actions_done.size()):
			tricks_done.append(ground_manager.actions_done[i])
			points_per_trick.append(ground_manager.points_per_action[i])
			tricks_colors.append(COLOR_GROUND) # Hits de chão são VERMELHOS
			
		ground_manager.tracking_combo = false
		ground_manager.actions_done.clear()
		ground_manager.points_per_action.clear()
	
	current_jump_uses.clear()
	angle_accumulator_y = 0.0
	last_basis = car.global_transform.basis

# --- LÓGICA DE EXIBIÇÃO BBCODE ---

func _update_live_display():
	if is_showing_final_score: return
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	var grouped_tricks = {} 
	var order = []
	
	for i in range(tricks_done.size()):
		var t_name = tricks_done[i]
		var t_pts = points_per_trick[i]
		var t_color = tricks_colors[i]
		
		if not grouped_tricks.has(t_name):
			grouped_tricks[t_name] = {"count": 0, "points": 0, "color": t_color}
			order.append(t_name)
		grouped_tricks[t_name].count += 1
		grouped_tricks[t_name].points += t_pts

	var names_bbcode = ""
	var pts_text = ""
	
	for t_name in order:
		var data = grouped_tricks[t_name]
		var color = data.color
		
		if data.count >= 3:
			names_bbcode += "[color=" + color + "](x" + str(data.count) + " " + t_name + ")[/color] + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_bbcode += "[color=" + color + "]" + t_name + "[/color] + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	var current_mult = _get_dynamic_multiplier()
	
	# Monta as duas linhas com BBCode
	var info = names_bbcode + "[color=" + COLOR_TIME + "]" + ("%.2fs" % air_time) + " airtime[/color]"
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
	
	# --- RECONSTRUÇÃO IDÊNTICA AO LIVE ---
	var grouped_tricks = {} 
	var order = []
	for i in range(tricks_done.size()):
		var t_name = tricks_done[i]
		if not grouped_tricks.has(t_name):
			grouped_tricks[t_name] = {"count": 0, "points": 0, "color": tricks_colors[i]}
			order.append(t_name)
		grouped_tricks[t_name].count += 1
		grouped_tricks[t_name].points += points_per_trick[i]

	var names_bbcode = ""
	var pts_text = ""
	for t_name in order:
		var data = grouped_tricks[t_name]
		if data.count >= 3:
			names_bbcode += "[color=" + data.color + "](x" + str(data.count) + " " + t_name + ")[/color] + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_bbcode += "[color=" + data.color + "]" + t_name + "[/color] + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	if names_bbcode.ends_with(" + "): names_bbcode = names_bbcode.left(-3)
	if pts_text.ends_with(" + "): pts_text = pts_text.left(-3)

	var info = names_bbcode + " [color=" + COLOR_TIME + "]" + ("%.2fs" % air_time) + " airtime[/color]"
	info += "\n" + str(mult) + "x " + pts_text + " + " + str(int(air_time * AIR_TIME_POINTS_MULT))
	
	var msg = "Awesome trick!" if tricks_done.size() > 0 else "Nice air!"
	var result = msg + "\n" + ScoreManager.format_score_with_dots(final_score) + " points"
	
	hud.show_combo_final(info, result)
	
	await get_tree().create_timer(DISPLAY_STAY_TIME).timeout
	is_showing_final_score = false

# --- RESTANTE DAS FUNÇÕES ORIGINAIS ---

func _get_dynamic_multiplier() -> float:
	var mult = 1.0
	var seen_in_this_jump = {}
	for t_name in tricks_done:
		if seen_in_this_jump.has(t_name): mult += 0.5
		else:
			mult += 1.0
			seen_in_this_jump[t_name] = true
	return mult

func process_air_time(_delta: float, _is_near_ground: bool):
	if not tracking_jump:
		if not _is_near_ground: _start_new_jump()
		else: return
	air_time = (Time.get_ticks_msec() - jump_start_timestamp) / 1000.0
	_track_rotation()
	if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0:
		_update_live_display()

func check_landing(_is_doing_stunt: bool):
	if tracking_jump:
		if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0: _finalize_score()
		else: reset_trick()
	tracking_jump = false

func _track_rotation():
	var current_basis = car.global_transform.basis
	var euler = (last_basis.inverse() * current_basis).get_rotation_quaternion().get_euler()
	last_basis = current_basis
	angle_accumulator_y += euler.y
	if abs(angle_accumulator_y) >= (PI * 1.85):
		_register_trick_logic("SPIN")
		angle_accumulator_y = 0.0

func reset_trick():
	tracking_jump = false
	if is_showing_final_score: return
	display_version += 1
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		hud.air_time_label.visible = false
		hud.air_message_label.visible = false
