extends Node
class_name ManualTrickComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var trick_manager = car.get_node_or_null("%TrickManager")

@export_group("Configurações do Manual")
@export var min_angle: float = 5.0
@export var max_angle: float = 60.0
@export var pop_force: float = 8.0 # Força do empurrão na frente do carro
@export var bail_spin_force: float = 12.0

# --- ESTADOS DO SISTEMA ---
enum State { IDLE, ARMED, WARMUP, ACTIVE }
var current_state: State = State.IDLE

var is_manual_armed: bool = false # Use essa variável no seu AirMovement para blindar o combo!

# --- TIMERS E CONTADORES ---
var _double_tap_timer: float = 0.0
var _stunt_pressed_last_frame: bool = false

var _warmup_timer: float = 0.0
var _score_timer: float = 0.0

# --- UI ---
var ui_canvas: CanvasLayer
var ui_bg: ColorRect
var ui_cursor: ColorRect

var _wheels_front: Array[VehicleWheel3D] = []
var _wheels_rear: Array[VehicleWheel3D] = []

func _ready():
	for child in car.get_children():
		if child is VehicleWheel3D:
			if child.position.z < 0: # Frente
				_wheels_front.append(child)
			else: # Traseira
				_wheels_rear.append(child)
	_setup_ui()

func _setup_ui():
	ui_canvas = CanvasLayer.new()
	add_child(ui_canvas)
	
	ui_bg = ColorRect.new()
	ui_bg.color = Color(0, 0, 0, 0.6) 
	ui_bg.size = Vector2(16, 150)
	ui_canvas.add_child(ui_bg)
	
	ui_cursor = ColorRect.new()
	ui_cursor.size = Vector2(16, 10)
	ui_bg.add_child(ui_cursor)
	
	ui_canvas.visible = false

func _log(msg: String):
	print("[Manual ZERO] " + msg)

# ==============================================================================
# DETECÇÃO DE INPUT (DOUBLE TAP)
# ==============================================================================
func _process_input_layer(delta):
	if _double_tap_timer > 0:
		_double_tap_timer -= delta
		
	var stunt_now = input.is_stunt_pressed
	
	if stunt_now and not _stunt_pressed_last_frame:
		# Acabou de apertar!
		if _double_tap_timer > 0.0:
			_on_double_tap()
			_double_tap_timer = 0.0
		else:
			_double_tap_timer = 0.3 # Tem 300ms para apertar a segunda vez
			
	_stunt_pressed_last_frame = stunt_now

func _on_double_tap():
	var pitch_deg = _get_car_pitch()
	
	# REGRA 4: Início instantâneo se já estiver no ângulo (5 a 60 graus)
	if pitch_deg >= min_angle and pitch_deg <= max_angle:
		_start_active_manual()
	else:
		# REGRA 1: Arma a Flag para quando tocar no chão
		current_state = State.ARMED
		is_manual_armed = true
		_log("Armado! Aguardando toque no chão...")

# ==============================================================================
# FÍSICA E MÁQUINA DE ESTADOS
# ==============================================================================
func _physics_process(delta):
	if not car.pode_mover: return
	
	_process_input_layer(delta)
	
	var pitch_deg = _get_car_pitch()
	var rear_grounded = _count_grounded(_wheels_rear)
	var front_grounded = _count_grounded(_wheels_front)
	var total_grounded = rear_grounded + front_grounded
	
	# Lógica da UI
	_update_ui(pitch_deg)
	
	match current_state:
		State.ARMED:
			# REGRA 1: Tocou no chão armado (Ignoramos se está só com a frente, assumimos pouso normal)
			if total_grounded > 0:
				_log("Tocou no chão! Aplicando pop e iniciando WARMUP...")
				is_manual_armed = false
				current_state = State.WARMUP
				_warmup_timer = 0.0
				
				# Impulso na parte da frente (Z negativo) para empinar
				var force = Vector3.UP * car.mass * pop_force
				var offset = car.global_transform.basis.z * 1.5
				car.apply_impulse(force, offset)
				
		State.WARMUP:
			# REGRA 2: Conta 0.2s se mantendo entre 5 e 60 graus
			if pitch_deg >= min_angle and pitch_deg <= max_angle:
				_warmup_timer += delta
				if _warmup_timer >= 0.2:
					_start_active_manual()
					
			# REGRA 3: Se estourar os 60 graus durante o warmup, dá Bail!
			elif pitch_deg > max_angle:
				_bail("Passou de 60 graus no Warmup!")
				
# Se o carro abaixar antes dos 0.2s, apenas aborta sem dar Bail
			elif pitch_deg < min_angle and total_grounded >= 3:
				_log("Carro desceu antes de 0.2s. Abortado.")
				current_state = State.IDLE
				if trick_manager and trick_manager.has_method("cash_out_combo"):
					trick_manager.cash_out_combo()
				
		State.ACTIVE:
			# REGRA 3: Finalização ou Bail
			if pitch_deg > max_angle:
				_bail("Passou de 60 graus!")
			elif pitch_deg < min_angle:
				_end_safely()
			else:
				# REGRA 6: Conta 20 pontos a cada 1 segundo
				_score_timer += delta
				if _score_timer >= 1.0:
					_score_timer -= 1.0
					if trick_manager:
						trick_manager.add_external_action("Manual", 20, TrickManager.COLOR_AIR)
						_log("+20 Pontos!")

# ==============================================================================
# FUNÇÕES AUXILIARES
# ==============================================================================
func _start_active_manual():
	_log("Manual ACTIVE! UI ligada.")
	current_state = State.ACTIVE
	_score_timer = 0.0
	
	# Só para garantir que o combo registre a entrada inicial
	if trick_manager:
		trick_manager.add_external_action("Manual", 10, TrickManager.COLOR_AIR)

func _end_safely():
	_log("Abaixou de 5 graus. Encerrado com sucesso.")
	current_state = State.IDLE
	is_manual_armed = false
	if trick_manager and trick_manager.has_method("cash_out_combo"):
		trick_manager.cash_out_combo()

func _bail(motivo: String):
	_log("BAIL: " + motivo)
	current_state = State.IDLE
	is_manual_armed = false
	
	if trick_manager and trick_manager.has_method("reset_trick"):
		trick_manager.reset_trick()
		
	# REGRA 3: Impulso de rotação lateral e para baixo simultâneo
	# 1. Rotação lateral (Torque)
	var direcao = 1.0 if randf() > 0.5 else -1.0
	car.apply_torque_impulse(car.global_transform.basis.y * car.mass * bail_spin_force * direcao)
	
	# 2. Impulso para baixo na parte de trás (para capotar mais rápido)
	var slam_force = Vector3.DOWN * car.mass * 8.0
	var offset = car.global_transform.basis.z * 1.5
	car.apply_impulse(slam_force, offset)

# ==============================================================================
# UTILIDADES FÍSICAS E UI
# ==============================================================================
func _get_car_pitch() -> float:
	# Retorna o ângulo de inclinação do nariz para o teto (Positivo = Empinando)
	var pitch_rad = asin(clamp(-car.global_transform.basis.z.dot(Vector3.UP), -1.0, 1.0))
	return rad_to_deg(pitch_rad)

func _count_grounded(wheels: Array) -> int:
	var count = 0
	for w in wheels:
		if is_instance_valid(w) and w.is_in_contact():
			count += 1
	return count

func _update_ui(pitch_deg: float):
	# REGRA 5: UI só aparece no ACTIVE
	if current_state != State.ACTIVE or not is_instance_valid(ui_canvas):
		if is_instance_valid(ui_canvas): ui_canvas.visible = false
		return
		
	var cam = get_viewport().get_camera_3d()
	if cam and not cam.is_position_behind(car.global_position):
		ui_canvas.visible = true
		var screen_pos = cam.unproject_position(car.global_position + Vector3(0, 1.5, 0))
		ui_bg.position = screen_pos + Vector2(60, -75)
		
		# Mapeia de 0 até o max_angle (60) nos 150 pixels da UI
		var percent = clamp(pitch_deg / max_angle, 0.0, 1.0)
		ui_cursor.position.y = lerp(140.0, 0.0, percent)
		
		# Cores simplificadas para o novo range (5 a 60)
		if pitch_deg < 15.0 or pitch_deg > 55.0:
			ui_cursor.color = Color.RED
		elif pitch_deg >= 15.0 and pitch_deg < 25.0 or pitch_deg > 45.0 and pitch_deg <= 55.0:
			ui_cursor.color = Color.YELLOW
		else:
			ui_cursor.color = Color.GREEN
	else:
		ui_canvas.visible = false
