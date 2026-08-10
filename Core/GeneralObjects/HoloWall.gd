extends StaticBody3D

@export_group("Regras de Missão")
## Se marcado, a colisão desta parede ligará e desligará automaticamente junto com a visibilidade.
@export var is_mission_wall: bool = false

@onready var mesh = $MeshInstance3D
# CORREÇÃO: Evita o crash caso o HoloWall não tenha a Area3D montada
@onready var sensor_area = get_node_or_null("Area3D") 

var flash_tween : Tween

func _ready():
	add_to_group("ignorar_gancho")
	add_to_group("ignorar_rage") 
	
	if mesh and mesh.material_override:
		mesh.material_override = mesh.material_override.duplicate()
		
	_set_intensity(0.0)
	
	if sensor_area:
		sensor_area.body_entered.connect(_on_sensor_ativado)
		
	# Se a parede começou invisível no mapa, já desliga a física dela de cara
	if is_mission_wall and not visible:
		_toggle_colisoes(false)

# ====================================================================
# A MÁGICA: O Godot avisa automaticamente quando o StoryController mudar a visibilidade!
# ====================================================================
func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_mission_wall:
			_toggle_colisoes(visible)

func _toggle_colisoes(ativo: bool):
	# Liga ou desliga fisicamente todos os CollisionShapes desta parede
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.set_deferred("disabled", not ativo)
			
	# Liga/Desliga também o sensor da área pra ele não piscar de forma fantasma
	if sensor_area:
		sensor_area.set_deferred("monitoring", ativo)
		sensor_area.set_deferred("monitorable", ativo)

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
	if mesh and mesh.material_override:
		mesh.material_override.set_shader_parameter("intensity", valor)
