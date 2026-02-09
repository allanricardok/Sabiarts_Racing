extends Area3D

signal collected 

@export var rotation_speed = 2.0
@export var float_amplitude = 0.2
@export var float_speed = 3.0

# Referência para o nó visual (o filho)
@onready var mesh_visual = $MeshInstance3D 

func _ready():
	# Conecta o sinal de entrada
	body_entered.connect(_on_body_entered)
	# Não precisamos mais de start_y do pai, 
	# pois a mesh flutua em relação à posição (0,0,0) local da Area3D.

func _process(delta):
	if mesh_visual:
		# Gira apenas o filho
		mesh_visual.rotate_y(rotation_speed * delta)
		
		# Faz o filho flutuar localmente
		var time = Time.get_ticks_msec() / 1000.0
		mesh_visual.position.y = sin(time * float_speed) * float_amplitude

func _on_body_entered(body):
	# Dica: Em vez de body.has_method, você pode verificar se é um VehicleBody3D
	if body is VehicleBody3D:
		if body.has_method("add_boost"):
			body.add_boost(1)
		
		collected.emit() 
		queue_free()
