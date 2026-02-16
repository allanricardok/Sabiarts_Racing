extends BaseProjectile

# Não declaramos damage, shooter ou hit_done, pois já existem no Pai

func _ready():
	# Executa a conexão de sinais e o timer de 4s do BaseProjectile
	super._ready()
	# Valor original da metralhadora
	damage = 5.0 

# Assinatura idêntica ao pai para evitar erros de compilação
func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 50.0):
	# Repassamos para o pai processar a velocidade relativa e o shooter
	super.setup(dmg_value, car_velocity, source_car, propulsion_speed)

# Mantemos o delay de 0.1s para garantir que o impacto seja processado 
# visualmente antes do queue_free
func _handle_cleanup():
	freeze = true
	visible = false
	
	await get_tree().create_timer(0.1).timeout
	queue_free()
