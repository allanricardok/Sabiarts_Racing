extends Camera3D

@export_group("Velocidades de Seguimento")
@export var follow_speed_lateral := 4.0
@export var follow_speed_depth := 15.0
@export var follow_speed_vertical := 20.0

@export_group("Configurações do Analógico")
@export var stick_sensitivity_x := 5.0 
@export var stick_sensitivity_y := 2.5 
@export var stick_lean_forward := 1.5 

@export_group("Configurações Look Back")
## O quanto a câmera se afasta a mais quando olha para trás (1.5 = 50% mais longe)
@export var look_back_distance_multiplier := 1.2 
## Altura extra opcional ao olhar para trás para ver por cima do capô
@export var look_back_height_offset := 0.5

@export_group("Limites de Segurança")
@export var min_local_y := -0.8 
@export var max_local_y := 8.0 

@export var look_offset := 1.0

@onready var target_node = $"../CameraTarget"
@onready var car = $".."

func _ready():
	set_as_top_level(true)
	global_position = target_node.global_position

func _physics_process(delta):
	if not car or not target_node: return

	# 1. ENTRADAS
	var r_stick = Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	var is_looking_back = Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_STICK)
	
	if r_stick.length() < 0.15:
		r_stick = Vector2.ZERO

	# 2. CONVERSÃO PARA ESPAÇO LOCAL
	var current_local_pos = car.global_transform.basis.inverse() * (global_position - car.global_position)
	var target_local_pos = car.global_transform.basis.inverse() * (target_node.global_position - car.global_position)

	# 3. LÓGICA DE POSICIONAMENTO
	var final_local_pos : Vector3

	if is_looking_back:
		# INVERSÃO E DISTÂNCIA (Instantâneo)
		# Multiplicamos o Z e o X para ela ficar mais longe na frente do carro
		target_local_pos.z = -target_local_pos.z * look_back_distance_multiplier
		target_local_pos.x = -target_local_pos.x * look_back_distance_multiplier
		target_local_pos.y += look_back_height_offset
		
		# PULO DO GATO: Atribuímos direto sem LERP para ser instantâneo
		final_local_pos = target_local_pos
	else:
		# MOVIMENTO NORMAL (Com LERP)
		var offset_x = r_stick.x * stick_sensitivity_x
		var offset_y = -r_stick.y * stick_sensitivity_y
		offset_y = clamp(offset_y, min_local_y, max_local_y)
		
		target_local_pos.x += offset_x
		target_local_pos.y += offset_y
		target_local_pos.z -= offset_y * 0.5 
		target_local_pos.z -= abs(offset_x) * 0.3
		
		# Interpolação suave para a câmera de perseguição
		final_local_pos.x = lerp(current_local_pos.x, target_local_pos.x, delta * follow_speed_lateral)
		final_local_pos.z = lerp(current_local_pos.z, target_local_pos.z, delta * follow_speed_depth)
		final_local_pos.y = lerp(current_local_pos.y, target_local_pos.y, delta * follow_speed_vertical)

	# 4. APLICAÇÃO GLOBAL
	global_position = car.global_transform.basis * final_local_pos + car.global_position

	# 5. ROTAÇÃO
	var look_target = car.global_position + Vector3.UP * look_offset
	look_at(look_target, Vector3.UP)

	# 6. FOV FIXO 100
	var speed = car.linear_velocity.length()
	fov = lerpf(fov, remap(clamp(speed, 0, 60), 0, 100, 100, 100), 0.1)
