extends Node
class_name TrickBuilder

@onready var car = owner as VehicleBody3D
@onready var manager = %TrickManager
@onready var input = %InputComponent 

# --- DICIONÁRIO DE MANOBRAS ---
const TRICK_DATA = {
	"ROLL_L": {"name": "Roll 360", "points": 50, "axis": Vector3(0, 0, 1)}, 
	"ROLL_R": {"name": "Roll 360", "points": 50, "axis": Vector3(0, 0, -1)},
	"BACKFLIP": {"name": "Backflip", "points": 80, "axis": Vector3(-1, 0, 0)}, 
	"FRONTFLIP": {"name": "Frontflip", "points": 80, "axis": Vector3(1, 0, 0)},
	"SPIN": {"name": "Spin 360", "points": 40, "axis": Vector3(0, 1, 0)},
	
	"SHIELD_SPIN": {"name": "Spin Shield", "points": 80, "axis": Vector3(0, 1, 0)},
	"EMOTE": {"name": "Style Emote", "points": 150, "axis": Vector3(0, 1, 0)},
	"FIREBALL": {"name": "Fireball!", "points": 100, "axis": Vector3.ZERO},
	"SHOCKWAVE": {"name": "Shockwave", "points": 100, "axis": Vector3.ZERO},
	
	"SPECIAL_TRICK": {"name": "SPECIAL TRICK", "points": 200, "axis": Vector3.ZERO}
}

@export var SEQUENCE_WINDOW : int = 450 
var tap_count : int = 0
var last_input_time : int = 0
var angle_accumulator_y := 0.0 
var last_basis : Basis

# ==============================================================================
# OTIMIZAÇÃO: MEMÓRIA CACHE E SEGURANÇA DE INPUT
# ==============================================================================
var _is_bot: bool = false
var _wall_rider: Node
var _air_move: Node

func _ready():
	if car: last_basis = car.global_transform.basis
	
	# Preenche o cache na inicialização
	_wall_rider = car.get_node_or_null("%WallRideComponent")
	if not _wall_rider:
		_wall_rider = car.find_child("WallRideComponent", true, false)
		
	_air_move = car.get_node_or_null("%AirMovementComponent")
	
	# Verifica se é bot um frame depois, para o BotBrain ter tempo de configurar
	call_deferred("_late_bot_check")

func _late_bot_check():
	if is_instance_valid(input) and "is_bot" in input:
		_is_bot = input.is_bot

func process_maneuvers(_delta: float):
	if not car or not manager: return
	if not manager.tracking_jump:
		reset_builder_logic()
		return
		
	_track_rotation()
	_handle_combo_logic()
	
	if tap_count > 0 and Time.get_ticks_msec() - last_input_time > SEQUENCE_WINDOW:
		_reset_sequence()

func _handle_combo_logic():
	# OTIMIZAÇÃO: Bots não usam combos de botões manuais! Aborta e economiza CPU.
	if _is_bot: return
	
	# OTIMIZAÇÃO: Leitura direto do cache na memória
	if is_instance_valid(_wall_rider) and _wall_rider.get("is_wallriding"):
		return

	var stunt_action = "Stunt" + input.suffix
	var now = Time.get_ticks_msec()
	
	# Trava de segurança anti-crash para o InputMap
	if InputMap.has_action(stunt_action) and Input.is_action_just_pressed(stunt_action):
		tap_count += 1
		last_input_time = now
		
		if tap_count == 3:
			_execute_trick("SPECIAL_TRICK")
			_reset_sequence()
			return

	var steer = input.steering
	var pitch = input.pitch
	
	if abs(steer) > 0.8 or abs(pitch) > 0.8:
		if tap_count > 0:
			_evaluate_combo_direction(steer, pitch)

func _evaluate_combo_direction(steer, pitch):
	var trick_id = ""
	
	if tap_count == 1:
		if steer < -0.8: trick_id = "ROLL_L"
		elif steer > 0.8: trick_id = "ROLL_R"
		elif pitch < -0.8: trick_id = "FRONTFLIP"
		elif pitch > 0.8: trick_id = "BACKFLIP"
		
	elif tap_count == 2:
		if steer < -0.8: trick_id = "SHIELD_SPIN"
		elif steer > 0.8: trick_id = "EMOTE"
		elif pitch < -0.8: trick_id = "FIREBALL"
		elif pitch > 0.8: trick_id = "SHOCKWAVE"

	if trick_id != "":
		_execute_trick(trick_id)
		_reset_sequence()

func _execute_trick(id: String):
	if not TRICK_DATA.has(id): return
	var data = TRICK_DATA[id]
	
	# OTIMIZAÇÃO: Uso de referência do cache
	if is_instance_valid(_air_move) and _air_move.has_method("execute_stunt_command"):
		_air_move.execute_stunt_command(data.axis, id)

func _track_rotation():
	var current_basis = car.global_transform.basis
	var euler = (last_basis.inverse() * current_basis).get_rotation_quaternion().get_euler()
	last_basis = current_basis
	angle_accumulator_y += euler.y
	
	if abs(angle_accumulator_y) >= (PI * 1.85):
		manager.add_trick_manually("SPIN")
		angle_accumulator_y = 0.0

func _reset_sequence():
	tap_count = 0

func reset_builder_logic():
	_reset_sequence()
	angle_accumulator_y = 0.0
	if car: last_basis = car.global_transform.basis
