extends MeshInstance3D

func _ready():
	# Assim que o jogo começar de verdade, eu me deleto sozinho!
	queue_free()
