extends StaticBody3D

@onready var mesh = $MeshInstance3D
@onready var sensor_area = $Area3D 

var flash_tween : Tween

func _ready():
	add_to_group("ignorar_gancho")
	add_to_group("ignorar_rage") # <--- NOVA TAG AQUI!
	
	if mesh.material_override:
		mesh.material_override = mesh.material_override.duplicate()
		
	_set_intensity(0.0)
	
	if sensor_area:
		sensor_area.body_entered.connect(_on_sensor_ativado)

func _on_sensor_ativado(body: Node3D):
	if body.is_in_group("jogadores") or body is VehicleBody3D:
		_piscar_parede()

func take_damage(amount: float, attacker: Node = null):
	_piscar_parede()

func _piscar_parede():
	if flash_tween:
		flash_tween.kill()
		
	flash_tween = create_tween()
	_set_intensity(1.0)
	flash_tween.tween_method(_set_intensity, 1.0, 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_intensity(valor: float):
	if mesh.material_override:
		mesh.material_override.set_shader_parameter("intensity", valor)
