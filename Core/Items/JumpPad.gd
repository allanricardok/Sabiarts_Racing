extends Area3D

@export var jump_force: float = 35.0  # Força do pulo (vertical)
@export var forward_kick: float = 10.0 # Empurrãozinho pra frente pra não subir reto

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	if body is VehicleBody3D:
		apply_jump(body)

func apply_jump(vehicle: VehicleBody3D):
	# 1. Definimos a direção: Cima (global) + um pouco da frente do tapete
	var up_direction = global_transform.basis.y.normalized() 
	var forward_direction = -global_transform.basis.z.normalized()
	
	# 2. Combinamos as forças
	var final_impulse = (up_direction * jump_force * 100) + (forward_direction * forward_kick * 100)
	
	# 3. Zera a velocidade vertical atual para o pulo ser sempre consistente
	# (Evita que o carro 'esmague' o pulo se estiver descendo rápido)
	vehicle.linear_velocity.y = 0
	
	# 4. Aplica o impulso
	vehicle.apply_central_impulse(final_impulse)
	
	print("SALTO INICIADO!")
