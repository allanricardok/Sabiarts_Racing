extends Area3D

var atirador: VehicleBody3D = null
var corpos_atingidos = [] # Para não dar dano múltiplo no mesmo alvo

func _ready():
	# Dispara as partículas
	if has_node("GPUParticles3D"):
		$GPUParticles3D.emitting = true
	
	# Timer para deletar o efeito
	get_tree().create_timer(1.0).timeout.connect(queue_free)

func _physics_process(_delta):
	# Varre corpos continuamente enquanto a área existir
	var alvos = get_overlapping_bodies()
	for corpo in alvos:
		if (corpo.is_in_group("jogadores") and corpo != atirador) or corpo.is_in_group("obstacles"):
			if not corpos_atingidos.has(corpo):
				if corpo.has_method("take_damage"):
					corpo.take_damage(20)
					corpos_atingidos.append(corpo) # Garante 1 dano por impacto
					
					# Knockback (empurrão)
					var direcao = (corpo.global_position - global_position).normalized()
					corpo.apply_central_impulse(direcao * 10.0 * corpo.mass)
