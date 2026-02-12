extends Area3D

# Arraste o Marker3D de destino para este slot no Inspector
@export var destination_marker : Marker3D

func _ready():
	# Conecta o sinal de entrada de corpos
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# Verifica se quem entrou é o nosso carro
	if body is BaseVehicle and destination_marker:
		# Chama a função de teleportar no carro, passando a posição e rotação do marker
		body.teleport_to(destination_marker.global_transform)
