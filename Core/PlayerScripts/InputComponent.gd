# InputComponent.gd
extends Node
class_name InputComponent

var suffix : String = ""

# Eixos de direção e motor
var throttle : float = 0.0
var steering : float = 0.0
var pitch : float = 0.0 
var is_look_behind_pressed : bool = false
var look_vector : Vector2 = Vector2.ZERO

# Variável exclusiva para acumular o movimento do mouse
var mouse_look : Vector2 = Vector2.ZERO
@export var mouse_sensitivity : float = 0.002 
@export var mouse_return_speed : float = 4.0 

# Botões de Disparo
var is_action_pressed : bool = false
var is_fire_pressed : bool = false
var is_attribute_pressed : bool = false
var is_stunt_pressed: bool = false

# Intenções de Habilidade
var ability_up : bool = false
var ability_down : bool = false
var ability_left : bool = false
var ability_right : bool = false

# Referência para detecção de chão
var air_move : Node = null

# --- CONTROLE DE LOGS ---
var debug_timer : float = 0.0

func setup(input_source: String):
	suffix = "_" + input_source
	print("[DEBUG-INPUT] Iniciando ", suffix)
	
	air_move = owner.find_child("AirMovementComponent")
	
	# Fazemos o componente ignorar o pause para poder capturar o mouse no menu
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event):
	if suffix == "" or not suffix.begins_with("_K"): return
	
	# 1. Captura o movimento bruto (Mudado de _unhandled_input para _input)
	if event is InputEventMouseMotion:
		# Só processamos se o jogo NÃO estiver pausado
		if not get_tree().paused:
			# Se o mouse fugiu, o movimento ainda conta, mas forçamos a volta
			if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			
			mouse_look.x += event.relative.x * mouse_sensitivity
			mouse_look.y -= event.relative.y * mouse_sensitivity
			
			mouse_look.x = clamp(mouse_look.x, -1.0, 1.0)
			mouse_look.y = clamp(mouse_look.y, -1.0, 1.0)
			
			# Log de movimento a cada 0.5 segundos para não inundar o console
			if Time.get_ticks_msec() > debug_timer:
				print("[DEBUG-K1] Mouse detectado! LookVector: ", mouse_look)
				debug_timer = Time.get_ticks_msec() + 500

func _process(delta):
	if suffix == "": return
	
	# 1. Gestão Automática do Mouse (Menu vs Gameplay)
	if suffix.begins_with("_K"):
		if get_tree().paused:
			if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Se estiver pausado, paramos o resto do processamento
	if get_tree().paused: return
	
	# 2. Verificação de estado
	var is_grounded = true
	if air_move and air_move.has_method("check_grounded"):
		is_grounded = air_move.check_grounded()
	
	throttle = Input.get_axis("Backward" + suffix, "Forward" + suffix)
	
	# 3. Lógica de Direção/Pitch
	if suffix.begins_with("_K"):
		if is_grounded:
			steering = Input.get_axis("Right" + suffix, "Left" + suffix)
			pitch = 0.0
		else:
			steering = -mouse_look.x
			pitch = -mouse_look.y
	else:
		steering = Input.get_axis("Right" + suffix, "Left" + suffix)
		pitch = Input.get_axis("Pitch_Down" + suffix, "Pitch_Up" + suffix)

	# 4. Botões e Camera
	is_action_pressed = Input.is_action_pressed("Action" + suffix)
	is_fire_pressed = Input.is_action_pressed("Fire" + suffix)
	is_stunt_pressed = Input.is_action_pressed("Stunt" + suffix)
	is_look_behind_pressed = Input.is_action_pressed("LookBehind" + suffix)
	
	# 5. Look Vector (Mouse no K, Analógico no J)
	if suffix.begins_with("_J"):
		is_attribute_pressed = Input.is_action_pressed("Attribute" + suffix)
		var joy_x = Input.get_axis("LookLeft" + suffix, "LookRight" + suffix)
		var joy_y = Input.get_axis("LookUp" + suffix, "LookDown" + suffix)
		look_vector = Vector2(joy_x, joy_y)
	else:
		# Teclado: Atributo é simulado se Q, E, R ou D forem pressionados
		is_attribute_pressed = Input.is_action_pressed("AbilityUp" + suffix) or \
							   Input.is_action_pressed("AbilityDown" + suffix) or \
							   Input.is_action_pressed("AbilityLeft" + suffix) or \
							   Input.is_action_pressed("AbilityRight" + suffix)
		look_vector = mouse_look
	
	# 6. Retorno Suave (Mola)
	mouse_look = mouse_look.move_toward(Vector2.ZERO, delta * mouse_return_speed)
	
	# 7. Habilidades
	if is_attribute_pressed:
		ability_up = Input.is_action_pressed("AbilityUp" + suffix)
		ability_down = Input.is_action_pressed("AbilityDown" + suffix)
		ability_left = Input.is_action_pressed("AbilityLeft" + suffix)
		ability_right = Input.is_action_pressed("AbilityRight" + suffix)
	else:
		ability_up = false
		ability_down = false
		ability_left = false
		ability_right = false
