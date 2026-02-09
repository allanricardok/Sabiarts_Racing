extends Area3D

func _ready():
	body_entered.connect(_on_body_entered)

func _process(delta):
	# Animação de rotação para destacar a máscara
	rotate_y(delta * 3.0)

func _on_body_entered(body):
	if body.has_method("equip_guerrilha_mask"):
		body.equip_guerrilha_mask()
		# Aqui você pode instanciar um efeito de partículas colorido antes de sumir
		queue_free()
