# BloodPuddleTrigger.gd
extends Area3D

func _ready():
	# Garante que o sinal de colisão está conectado
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	
	# Se a própria poça do pedestre sumir depois de um tempo, o Area3D some junto!

func _on_body_entered(body):
	# Verifica se o objeto que pisou na poça é um veículo válido
	if body is VehicleBody3D:
		# Procura o nosso componente recém-criado dentro do carro
		var blood_manager = body.find_child("TireBloodManager", true, false)
		
		if is_instance_valid(blood_manager) and blood_manager.has_method("infect_tires"):
			blood_manager.infect_tires()
			
			# Opcional: Se quiser que a poça perca a capacidade de sujar 
			# depois que um carro passa, você pode desativar o monitoramento aqui:
			# set_deferred("monitoring", false)
