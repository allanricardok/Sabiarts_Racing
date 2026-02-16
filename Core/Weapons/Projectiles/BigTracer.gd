extends BaseProjectile

# Não precisamos declarar damage, shooter ou hit_done, elas já existem no BaseProjectile

func _ready():
	# super._ready() executa a conexão de sinais e o timer de 4s que está no Pai
	super._ready()
	damage = 20.0 

# CORREÇÃO DA ASSINATURA: Adicionamos o 4º argumento (propulsion_speed) 
# para dar "match" com o BaseProjectile.gd
func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 50.0):
	# Chamamos o setup do pai passando os 4 valores.
	# Aqui você pode forçar 50.0 ou usar o propulsion_speed que vier da arma
	super.setup(dmg_value, car_velocity, source_car, propulsion_speed)

# Sobrescrita da limpeza para manter o delay de 0.1s que você tinha originalmente
func _handle_cleanup():
	freeze = true
	visible = false
	
	# Delay para som ou partículas antes de sumir
	await get_tree().create_timer(0.1).timeout
	queue_free()
