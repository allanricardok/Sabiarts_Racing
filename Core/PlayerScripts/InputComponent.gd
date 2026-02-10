# InputComponent.gd
extends Node
class_name InputComponent

var suffix : String = ""

# Eixos de direção e motor
var throttle : float = 0.0
var steering : float = 0.0

# O novo botão unificado (Antigo Jump)
var is_action_pressed : bool = false
var is_action_just_pressed : bool = false

# Botões digitais do D-pad para combos
var ability_up : bool = false
var ability_down : bool = false
var ability_left : bool = false
var ability_right : bool = false

var pitch : float = 0.0 


func setup(input_source: String):
	suffix = "_" + input_source

func _process(_delta):
	if suffix == "": return
	
	throttle = Input.get_axis("Backward" + suffix, "Forward" + suffix)
	steering = Input.get_axis("Right" + suffix, "Left" + suffix)
	
	# RE ADICIONE ESTA LINHA:
	pitch = Input.get_axis("Pitch_Down" + suffix, "Pitch_Up" + suffix)
	
	is_action_pressed = Input.is_action_pressed("Action" + suffix)
	# Adicione esta para o MovementComponent não dar erro no pulo:
	is_action_just_pressed = Input.is_action_just_pressed("Action" + suffix)
	
	# Captura os botões direcionais (D-pad)
	ability_up = Input.is_action_pressed("AbilityUp")
	ability_down = Input.is_action_pressed("AbilityDown")
	ability_left = Input.is_action_pressed("AbilityLeft")
	ability_right = Input.is_action_pressed("AbilityRight")
