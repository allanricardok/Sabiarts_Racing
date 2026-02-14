# TrickManager.gd
extends Node
class_name TrickManager

@onready var car = owner as VehicleBody3D
@onready var ability_comp = %AbilityComponent

# --- ESTRUTURA DE PONTOS ---
const TRICK_DATA = {
	"ROLL_L": {"name": "Roll Esq", "points": 50},
	"ROLL_R": {"name": "Roll Dir", "points": 50},
	"BACKFLIP": {"name": "Backflip", "points": 80},
	"FRONTFLIP": {"name": "Frontflip", "points": 80},
	"YAW_SPIN": {"name": "Spin", "points": 40}
}

# --- ESTADO ATUAL DO COMBO ---
var air_time : float = 0.0
var tracking_jump : bool = false
var tricks_in_current_jump : Array = [] # Armazena os nomes das manobras feitas

# Rastreamento de ângulos independentes
var angle_x : float = 0.0
var angle_y : float = 0.0
var angle_z : float = 0.0
var last_basis : Basis

func process_air_time(delta: float, is_near_ground: bool):
	if not tracking_jump:
		tracking_jump = true
		tricks_in_current_jump.clear()
		angle_x = 0; angle_y = 0; angle_z = 0
		last_basis = car.global_transform.basis
	
	air_time += delta
	_track_rotations()
	
	# Atualiza o HUD em tempo real com a lista de manobras
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud: 
		hud.atualizar_combo_live(tricks_in_current_jump, air_time)

func _track_rotations():
	var current_basis = car.global_transform.basis
	var relative_rot = (last_basis.inverse() * current_basis).get_rotation_quaternion()
	last_basis = current_basis
	
	# Decompõe a rotação em eixos locais
	var Euler = relative_rot.get_euler()
	angle_x += Euler.x
	angle_y += Euler.y
	angle_z += Euler.z
	
	# Verifica se algum eixo completou 360 graus (aprox 6.28 radianos)
	_check_trick_completion()

func _check_trick_completion():
	var threshold = PI * 1.9 # Quase 360 para ser mais responsivo
	
	if abs(angle_z) >= threshold:
		_register_trick("ROLL_L" if angle_z > 0 else "ROLL_R")
		angle_z = 0
	if abs(angle_x) >= threshold:
		_register_trick("FRONTFLIP" if angle_x > 0 else "BACKFLIP")
		angle_x = 0
	if abs(angle_y) >= threshold:
		_register_trick("YAW_SPIN")
		angle_y = 0

func _register_trick(trick_id: String):
	tricks_in_current_jump.append(TRICK_DATA[trick_id])
	print("Manobra detectada: ", TRICK_DATA[trick_id].name)

func check_landing(is_doing_stunt: bool):
	if tracking_jump:
		if air_time > 0.5: # Só pontua se o pulo foi relevante
			_finalize_combo()
		tracking_jump = false
	air_time = 0.0
	tricks_in_current_jump.clear()

func _finalize_combo():
	var base_points = 0
	var trick_names = []
	
	# Soma pontos das manobras
	for trick in tricks_in_current_jump:
		base_points += trick.points
		trick_names.append(trick.name)
	
	# Soma pontos de tempo de ar (10 pontos por segundo)
	var air_points = int(air_time * 10)
	base_points += air_points
	
	# Multiplicador baseado na quantidade de manobras (Combo)
	var multiplier = max(1, tricks_in_current_jump.size())
	var final_score = base_points * multiplier
	
	# Envia para o placar geral
	ScoreManager.add_points(final_score)
	
	# Avisa o HUD para mostrar o banner de vitória
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		hud.mostrar_finalizacao_combo(final_score, multiplier)

func reset_trick():
	air_time = 0.0
	tracking_jump = false
	tricks_in_current_jump.clear()
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud: hud.ocultar_cronometro_ar()
