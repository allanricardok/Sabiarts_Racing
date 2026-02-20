extends Area3D

@export var boost_force: float = 50.0  # Força do empurrão
@export var extra_top_speed_time: float = 0.5 # Tempo que o carro ignora o limite de velocidade (opcional)

func _ready():
	# Conecta o sinal de entrada automaticamente
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	# Verifica se o que entrou é o nosso veículo (pelo nome da classe ou grupo)
	if body is VehicleBody3D:
		apply_boost(body)

func apply_boost(vehicle: VehicleBody3D):
	# Pegamos a direção "Frente" do tapete (Basis.z ou -Basis.z dependendo de como você modelou)
	# No Godot, -basis.z costuma ser o 'frente' local
	var boost_direction = -global_transform.basis.z.normalized()
	
	# Aplicamos o impulso
	# Usamos central_impulse para não fazer o carro capotar, apenas ganhar velocidade linear
	vehicle.apply_central_impulse(boost_direction * boost_force * 100)
	
	# Dica Visual/Sonora:
	# Se você tiver um som de "Tshhh" ou partículas, dê o play aqui
	print("BOOST APLICADO!")
