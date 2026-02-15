extends Node
class_name TrickManager

@onready var car = owner as VehicleBody3D

const TRICK_DATA = {
	"ROLL_L": {"name": "Roll 360", "points": 50}, "ROLL_R": {"name": "Roll 360", "points": 50},
	"BACKFLIP": {"name": "Backflip", "points": 80}, "FRONTFLIP": {"name": "Frontflip", "points": 80},
	"SPIN": {"name": "Spin 360", "points": 40}
}

var global_stunt_uses = {}
var air_time := 0.0
var tracking_jump := false
var tricks_done : Array = []
var points_per_trick : Array = []
var current_jump_uses = {}
var angle_accumulator_y := 0.0 # Agora só rastreamos o Y (Spin)
var last_basis : Basis

# --- FUNÇÃO PARA MANOBRAS DE BOTÃO ---
func add_trick_manually(id: String):
	if not tracking_jump: _start_new_jump()
	_register_trick_logic(id)

# --- LOGICA DE ROTAÇÃO APENAS PARA SPIN ---
func _track_rotation():
	var current_basis = car.global_transform.basis
	var euler = (last_basis.inverse() * current_basis).get_rotation_quaternion().get_euler()
	last_basis = current_basis
	
	angle_accumulator_y += euler.y
	
	if abs(angle_accumulator_y) >= (PI * 1.85):
		_register_trick_logic("SPIN")
		angle_accumulator_y = 0.0

# --- NÚCLEO DE CÁLCULO DE PONTOS (UNIFICADO) ---
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
	_update_live_display() # Força atualização do HUD na hora

func process_air_time(delta: float, _is_near_ground: bool):
	if not tracking_jump: _start_new_jump()
	air_time += delta
	_track_rotation()
	if air_time >= 1.1 or tricks_done.size() > 0:
		_update_live_display()

func _start_new_jump():
	tracking_jump = true
	air_time = 0.0
	tricks_done.clear()
	points_per_trick.clear()
	current_jump_uses.clear()
	angle_accumulator_y = 0.0
	last_basis = car.global_transform.basis

func _update_live_display():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	var names_text = ""
	var pts_text = ""
	for i in range(tricks_done.size()):
		names_text += tricks_done[i] + " + "
		pts_text += str(points_per_trick[i]) + " + "
	
	hud.air_time_label.text = names_text + str(int(air_time * 1000)) + " airtime"
	hud.air_time_label.text += "\n" + str(tricks_done.size() + 1) + "x " + pts_text + str(int(air_time * 10))
	hud.air_time_label.visible = true
	hud.air_message_label.visible = false

func _add_trick(id: String):
	var base_pts = TRICK_DATA[id].points
	
	# 1. CÁLCULO DO DECAIMENTO GLOBAL (5% por uso anterior)
	var g_count = global_stunt_uses.get(id, 0)
	var g_mult = max(0.1, 1.0 - (g_count * 0.05))
	
	# 2. CÁLCULO DO DECAIMENTO INTERNO (50% por repetição no mesmo pulo)
	var j_count = current_jump_uses.get(id, 0)
	var j_mult = max(0.1, pow(0.5, j_count))
	
	# Pontuação final da manobra
	var final_pts = int(base_pts * g_mult * j_mult)
	
	tricks_done.append(TRICK_DATA[id].name)
	points_per_trick.append(final_pts)
	
	# Incrementa contador de repetição interna
	current_jump_uses[id] = j_count + 1

func check_landing(_is_doing_stunt: bool):
	if tracking_jump and (air_time >= 1.1 or tricks_done.size() > 0):
		_finalize_score()
	tracking_jump = false

func _finalize_score():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	# 1. CÁLCULO DE PONTOS
	var total_base = int(air_time * 10)
	for p in points_per_trick: total_base += p
	
	var mult = tricks_done.size() + 1
	var final_score = total_base * mult
	ScoreManager.add_points(final_score)
	
	# 2. SALVA O USO GLOBAL (Decaimento para o próximo pulo)
	for id in current_jump_uses.keys():
		global_stunt_uses[id] = global_stunt_uses.get(id, 0) + 1
	
	# 3. EXIBIÇÃO FINAL
	var msg = "Awesome trick!" if mult > 1 else "Nice air!"
	hud.air_message_label.text = msg + "\n" + str(final_score) + " points"
	hud.air_message_label.visible = true
	hud.air_time_label.visible = true
	
	# --- O TIMER DE 3 SEGUNDOS ---
	# Esperamos 3 segundos após o pouso
	await get_tree().create_timer(3.0).timeout
	
	# 4. CHECAGEM DE SEGURANÇA
	# Só escondemos se o jogador NÃO começou um novo pulo "sério" nesse intervalo
	if not tracking_jump or (air_time < 1.1 and tricks_done.size() == 0):
		hud.air_time_label.visible = false
		hud.air_message_label.visible = false

func reset_trick():
	tracking_jump = false
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		hud.air_time_label.visible = false
		hud.air_message_label.visible = false
