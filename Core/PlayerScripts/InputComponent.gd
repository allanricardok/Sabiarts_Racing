# InputComponent.gd
extends Node
class_name InputComponent

var suffix : String = ""

# --- EIXOS DE MOVIMENTO ---
var throttle : float = 0.0
var steering : float = 0.0
var pitch : float = 0.0 
var is_look_behind_pressed : bool = false
var is_grounded : bool = true # Promovido para o escopo da classe para compartilhamento

# --- VETORES DE OLHAR E MANOBRA (SEPARADOS) ---
var look_vector : Vector2 = Vector2.ZERO # Exclusivo para a Camera (Suave)
var mouse_look : Vector2 = Vector2.ZERO  # Exclusivo para Manobras/Ar (Digital)

@export var camera_sensitivity : float = 0.000005 # Sensibilidade suave solicitada
@export var air_camera_multiplier : float = 0.2   # Multiplicador para reduzir a sensibilidade no ar
@export var mouse_return_speed : float = 0.1    # Retorno rápido para o centro

# --- BOTÕES E ESTADOS ---
var is_action_pressed : bool = false
var is_fire_pressed : bool = false
var is_attribute_pressed : bool = false
var is_stunt_pressed: bool = false

var ability_up : bool = false
var ability_down : bool = false
var ability_left : bool = false
var ability_right : bool = false

var air_move : Node = null

# --- CONTROLE DE LOGS ---
var debug_timer : float = 0.0

func setup(input_source: String):
	suffix = "_" + input_source
	print("[SYSTEM] InputComponent pronto para: ", suffix)

	air_move = owner.find_child("AirMovementComponent")

	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta):
	if suffix == "": return
	
	# 0. Verificação de Estado (Movido para antes do mouse para ele saber se está no ar)
	is_grounded = true
	if air_move and air_move.has_method("check_grounded"):
		is_grounded = air_move.check_grounded()
	
	# 1. GESTÃO DO MOUSE (Exclusivo K1)
	if suffix.begins_with("_K"):
		_handle_global_mouse(delta)
	
	if get_tree().paused: return
	
	throttle = Input.get_axis("Backward" + suffix, "Forward" + suffix)
	
	# 3. Lógica de Direção e Pitch (K1 Direto)
	if suffix.begins_with("_K"):
		if is_grounded:
			steering = Input.get_axis("Right" + suffix, "Left" + suffix)
			pitch = 0.0
		else:
			# Para o ar e manobras, usamos o mouse_look que "estala" em 1.0/-1.0
			steering = -mouse_look.x
			pitch = -mouse_look.y
	else:
		steering = Input.get_axis("Right" + suffix, "Left" + suffix)
		pitch = Input.get_axis("Pitch_Down" + suffix, "Pitch_Up" + suffix)

	# 4. Botões
	is_action_pressed = Input.is_action_pressed("Action" + suffix)
	is_fire_pressed = Input.is_action_pressed("Fire" + suffix)
	is_stunt_pressed = Input.is_action_pressed("Stunt" + suffix)
	is_look_behind_pressed = Input.is_action_pressed("LookBehind" + suffix)
	
	# 5. Look Vector e Atributo
	if suffix.begins_with("_J"):
		is_attribute_pressed = Input.is_action_pressed("Attribute" + suffix)
		var joy_x = Input.get_axis("LookLeft" + suffix, "LookRight" + suffix)
		var joy_y = Input.get_axis("LookUp" + suffix, "LookDown" + suffix)
		look_vector = Vector2(joy_x, joy_y)
	else:
		# Teclado: Atributo simulado por habilidades
		is_attribute_pressed = Input.is_action_pressed("AbilityUp" + suffix) or \
							   Input.is_action_pressed("AbilityDown" + suffix) or \
							   Input.is_action_pressed("AbilityLeft" + suffix) or \
							   Input.is_action_pressed("AbilityRight" + suffix)
		# Nota: look_vector (Câmera) já foi atualizado suavemente no _handle_global_mouse

	# 6. Habilidades
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

func _handle_global_mouse(delta):
	if get_tree().paused:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var mouse_vel = Input.get_last_mouse_velocity()
	
	# Define a sensibilidade baseada no estado do carro
	var current_cam_sens = camera_sensitivity
	if not is_grounded:
		current_cam_sens *= air_camera_multiplier
	
	# --- LÓGICA DUPLA ---
	if mouse_vel.length() > 5.0: # Se houver qualquer movimento
		
		# A: CAMERA (look_vector) - Suave e acumulativo
		look_vector.x += mouse_vel.x * current_cam_sens
		look_vector.y -= mouse_vel.y * current_cam_sens
		look_vector.x = clamp(look_vector.x, -1.0, 1.0)
		look_vector.y = clamp(look_vector.y, -1.0, 1.0)

		# B: MANOBRA/AR (mouse_look) - Digital e instantâneo
		# Ele assume 1.0 ou -1.0 baseada apenas no sinal (direção) da velocidade, sem usar a sensibilidade
		mouse_look.x = sign(mouse_vel.x)
		mouse_look.y = -sign(mouse_vel.y)
		
		# Log de debug para acompanhar o multiplicador em ação (dispara a cada 500ms)
		if Time.get_ticks_msec() > debug_timer:
			var estado_log = "No Ar" if not is_grounded else "No Chão"
			print("[DEBUG-K1] Mouse movendo (", estado_log, "). LookVector: ", look_vector)
			debug_timer = Time.get_ticks_msec() + 500
	else:
		# Quando o mouse para, ambos voltam ao centro
		# O look_vector volta mais devagar para manter a câmera estável
		look_vector = look_vector.move_toward(Vector2.ZERO, delta)
		# O mouse_look volta rápido para resetar a intenção de manobra
		mouse_look = mouse_look.move_toward(Vector2.ZERO, delta * mouse_return_speed)
