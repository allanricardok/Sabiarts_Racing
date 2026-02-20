extends Area3D

@export var destination_marker : Marker3D

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# Verificamos se o corpo que entrou tem a função de teleport
	if body.has_method("teleport_to") and destination_marker:
		# Passamos o transform completo (Posição + Rotação)
		body.teleport_to(destination_marker.global_transform)
