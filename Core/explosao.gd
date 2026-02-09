extends GPUParticles3D
@onready var sound = $AudioStreamPlayer

func _ready():
	emitting = true
	sound.play()
	# Espera o tempo de vida das partículas e se deleta
	await get_tree().create_timer(lifetime).timeout
	queue_free()
