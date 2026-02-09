extends Camera3D

@export_group("Velocidades de Seguimento")
@export var follow_speed_lateral := 4.0   # Lento: Cria o "balanço" nas curvas (Eixo X local)
@export var follow_speed_depth := 15.0   # Rápido: Mantém a distância do para-choque (Eixo Z local)
@export var follow_speed_vertical := 20.0 # Rápido: Mantém a altura fixa (Eixo Y local)

@export var look_offset := 1.0

@onready var target_node = $"../CameraTarget"
@onready var car = $".."

func _ready():
	set_as_top_level(true)
	global_position = target_node.global_position

func _physics_process(delta):
	if not car or not target_node: return

	# 1. CONVERSÃO PARA ESPAÇO LOCAL
	# Pegamos onde a câmera está AGORA em relação ao carro
	var current_local_pos = car.global_transform.basis.inverse() * (global_position - car.global_position)
	
	# Pegamos onde a câmera DEVERIA estar (o CameraTarget) em relação ao carro
	var target_local_pos = car.global_transform.basis.inverse() * (target_node.global_position - car.global_position)

	# 2. INTERPOLAÇÃO INDEPENDENTE
	var next_local_pos = Vector3.ZERO
	
	# Lateral (X): O "strafe" lento que você pediu
	next_local_pos.x = lerp(current_local_pos.x, target_local_pos.x, delta * follow_speed_lateral)
	
	# Profundidade (Z): Rápido para não distanciar demais ao acelerar
	next_local_pos.z = lerp(current_local_pos.z, target_local_pos.z, delta * follow_speed_depth)
	
	# Vertical (Y): Firme para acompanhar pulos e rampas
	next_local_pos.y = lerp(current_local_pos.y, target_local_pos.y, delta * follow_speed_vertical)

	# 3. VOLTA PARA O ESPAÇO GLOBAL E APLICA
	global_position = car.global_transform.basis * next_local_pos + car.global_position

	# 4. ROTAÇÃO E FOV (Mantidos do sistema que funcionou)
	var look_target = car.global_position + Vector3.UP * look_offset
	look_at(look_target, Vector3.UP)

	var speed = car.linear_velocity.length() * 2
	fov = lerpf(fov, remap(clamp(speed, 0, 60), 0, 100, 100, 100), 0.1)
