# InputComponent.gd
extends Node
class_name InputComponent

var suffix : String = ""

# --- EIXOS DE MOVIMENTO ---
var throttle : float = 0.0
var steering : float = 0.0
var pitch : float = 0.0 
var is_look_behind_pressed : bool = false
var is_grounded : bool = true 

# --- VETORES DE OLHAR E MANOBRA (SEPARADOS) ---
var look_vector : Vector2 = Vector2.ZERO 
var mouse_look : Vector2 = Vector2.ZERO  

@export var camera_sensitivity : float = 0.000005 
@export var air_camera_multiplier : float = 0.2   
@export var mouse_return_speed : float = 5.0    
# NOVO: Define a força mínima do empurrão do mouse para gerar a manobra
@export var mouse_maneuver_threshold : float = 1000.0 

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
var debug_timer : float = 0.0

func setup(input_source: String):
	suffix = "_" + input_source
	print("[SYSTEM] InputComponent pronto para: ", suffix)
	air_move = owner.find_child("AirMovementComponent")
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta):
	if suffix == "": return
	
	is_grounded = true
	if air_move and air_move.has_method("check_grounded"):
		is_grounded = air_move.check_grounded()
	
	if suffix.begins_with("_K"):
		_handle_global_mouse(delta)
	
	if get_tree().paused: return
	
	throttle = Input.get_axis("Backward" + suffix, "Forward" + suffix)
	
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

	is_action_pressed = Input.is_action_pressed("Action" + suffix)
	is_fire_pressed = Input.is_action_pressed("Fire" + suffix)
	is_stunt_pressed = Input.is_action_pressed("Stunt" + suffix)
	is_look_behind_pressed = Input.is_action_pressed("LookBehind" + suffix)
	
	if suffix.begins_with("_J"):
		is_attribute_pressed = Input.is_action_pressed("Attribute" + suffix)
		var joy_x = Input.get_axis("LookLeft" + suffix, "LookRight" + suffix)
		var joy_y = Input.get_axis("LookUp" + suffix, "LookDown" + suffix)
		look_vector = Vector2(joy_x, joy_y)
	else:
		is_attribute_pressed = Input.is_action_pressed("AbilityUp" + suffix) or \
							   Input.is_action_pressed("AbilityDown" + suffix) or \
							   Input.is_action_pressed("AbilityLeft" + suffix) or \
							   Input.is_action_pressed("AbilityRight" + suffix)

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
	
	var current_cam_sens = camera_sensitivity
	if not is_grounded:
		current_cam_sens *= air_camera_multiplier
	
	# Usamos uma fração do threshold para a câmera continuar registrando movimentos leves
	if mouse_vel.length() > (mouse_maneuver_threshold * 0.2): 
		
		look_vector.x += mouse_vel.x * current_cam_sens
		look_vector.y -= mouse_vel.y * current_cam_sens
		look_vector.x = clamp(look_vector.x, -1.0, 1.0)
		look_vector.y = clamp(look_vector.y, -1.0, 1.0)

		# MUDANÇA: Agora usa a variável exposta no Inspetor
		if abs(mouse_vel.x) > mouse_maneuver_threshold:
			mouse_look.x = sign(mouse_vel.x)
		else:
			mouse_look.x = move_toward(mouse_look.x, 0.0, delta * mouse_return_speed)
			
		if abs(mouse_vel.y) > mouse_maneuver_threshold:
			mouse_look.y = -sign(mouse_vel.y)
		else:
			mouse_look.y = move_toward(mouse_look.y, 0.0, delta * mouse_return_speed)
		
		if Time.get_ticks_msec() > debug_timer:
			var estado_log = "No Ar" if not is_grounded else "No Chão"
			print("[DEBUG-K1] Mouse movendo (", estado_log, "). LookVector: ", look_vector)
			debug_timer = Time.get_ticks_msec() + 500
	else:
		look_vector = look_vector.move_toward(Vector2.ZERO, delta)
		mouse_look = mouse_look.move_toward(Vector2.ZERO, delta * mouse_return_speed)
