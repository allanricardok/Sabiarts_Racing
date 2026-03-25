extends Area3D

@export var jump_force: float = 50  # Força do pulo (vertical)
@export var forward_kick: float = 5.0 # Empurrãozinho pra frente pra não subir reto

# NOVO: Peso base do seu "carro médio" (ajuste para bater com a massa média dos seus carros)
@export var massa_de_referencia: float = 400.0 

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	if body is VehicleBody3D:
		apply_jump(body)

func apply_jump(vehicle: VehicleBody3D):
	# 1. Definimos a direção: Cima (global) + um pouco da frente do tapete
	var up_direction = global_transform.basis.y.normalized() 
	var forward_direction = -global_transform.basis.z.normalized()
	
	# 2. Força base total (como era antes)
	var impulso_base = (up_direction * jump_force * 100) + (forward_direction * forward_kick * 100)
	
	# 3. A MÁGICA DA PROPORÇÃO (50/50):
	# Metade da força é "burra" e aplicada a qualquer um igual
	var forca_fixa = impulso_base * 0.5
	
	# Metade da força é inteligente e multiplica pela diferença de peso do carro
	# Ex: Se o caminhão tiver 2000 de massa, ele ganha o dobro nessa metade!
	var multiplicador_de_peso = vehicle.mass / massa_de_referencia
	var forca_proporcional = impulso_base * 0.5 * multiplicador_de_peso
	
	var final_impulse = forca_fixa + forca_proporcional
	
	# 4. Zera a velocidade vertical atual para o pulo ser sempre consistente
	vehicle.linear_velocity.y = 0
	
	# 5. Aplica o impulso
	vehicle.apply_central_impulse(final_impulse)
	
	# Um print legal para você testar e ver a diferença de força aplicada em cada carro!
	print("SALTO! Carro: ", vehicle.name, " | Massa: ", vehicle.mass, " | Impulso Final: ", final_impulse.length())
