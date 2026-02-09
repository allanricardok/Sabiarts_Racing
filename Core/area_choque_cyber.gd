extends Area3D

var atirador: VehicleBody3D = null
var corpos_atingidos = []

func _ready():
	# SOLUÇÃO PARA 2 EMISSORES: Itera por todos os filhos e ativa cada um
	for child in get_children():
		if child is GPUParticles3D or child is CPUParticles3D:
			child.emitting = true
			# Garante que as partículas não fiquem presas ao carro (rastro)
			if child is GPUParticles3D:
				child.fixed_fps = 0 # Melhora fluidez
		
	# A área dura 1 segundo para o efeito visual completar
	await get_tree().create_timer(1.0).timeout
	queue_free()

func _physics_process(_delta):
	var alvos = get_overlapping_bodies()
	for corpo in alvos:
		if corpo.is_in_group("jogadores") and corpo != atirador:
			if not corpos_atingidos.has(corpo):
				# Aplica o slow de 30%
				corpo.linear_velocity *= 0.7
				corpos_atingidos.append(corpo)
				print("HACKEADO: ", corpo.name)
