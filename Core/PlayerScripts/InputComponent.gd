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

# Botões de Disparo
var is_action_pressed : bool = false       # X (Metralhadora)
var is_fire_pressed : bool = false         # Quadrado (Especial)
var is_attribute_pressed : bool = false    # Círculo (Modificador de Habilidades)

# Intenções de Habilidade (Referenciando o Project Settings)
var ability_up : bool = false
var ability_down : bool = false
var ability_left : bool = false
var ability_right : bool = false

func setup(input_source: String):
	suffix = "_" + input_source
	print("InputComponent pronto para: ", suffix)

func _process(_delta):
	if suffix == "": return
	
	# 1. Movimentação e Pitch (Analógicos)
	throttle = Input.get_axis("Backward" + suffix, "Forward" + suffix)
	steering = Input.get_axis("Right" + suffix, "Left" + suffix)
	pitch = Input.get_axis("Pitch_Down" + suffix, "Pitch_Up" + suffix)
	
	# 2. Botões Principais
	is_action_pressed = Input.is_action_pressed("Action" + suffix)
	is_fire_pressed = Input.is_action_pressed("Fire" + suffix)
	is_attribute_pressed = Input.is_action_pressed("Attribute" + suffix)
	is_look_behind_pressed = Input.is_action_pressed("LookBehind" + suffix)
	# Captura o analógico direito (ajuste os nomes conforme seu Input Map)
	look_vector.x = Input.get_axis("LookLeft" + suffix, "LookRight" + suffix)
	look_vector.y = Input.get_axis("LookUp" + suffix, "LookDown" + suffix)
	
	# 3. Lógica de Habilidades (Referenciando as ações do Project Settings)
	# IMPORTANTE: No seu Input Map, as ações "AbilityUp_K1", etc, 
	# devem estar mapeadas para o analógico desejado.
	# Só validamos a direção da habilidade se o botão modificador (Círculo) estiver ativo
	if is_attribute_pressed:
		ability_up = Input.is_action_pressed("AbilityUp" + suffix)
		ability_down = Input.is_action_pressed("AbilityDown" + suffix)
		ability_left = Input.is_action_pressed("AbilityLeft" + suffix)
		ability_right = Input.is_action_pressed("AbilityRight" + suffix)
	else:
		# Se não está segurando o Círculo, as habilidades são resetadas para falso
		ability_up = false
		ability_down = false
		ability_left = false
		ability_right = false
