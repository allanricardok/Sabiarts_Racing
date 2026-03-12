extends BaseProjectile

# Não declaramos damage, shooter ou hit_done, pois já existem no Pai

func _ready():
	# O pai (BaseProjectile) já conecta os sinais automaticamente.
	super._ready()

# Assinatura idêntica ao pai
func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 50.0):
	# Repassamos para o pai fazer todo o cálculo de velocidade e reset do Pool
	super.setup(dmg_value, car_velocity, source_car, propulsion_speed)

# --- A MÁGICA DA LIMPEZA ---
# Apagamos o _handle_cleanup e o queue_free()!
# Se você precisar de um efeito visual específico para essa bala no futuro, 
# basta usar a função abaixo. O pai já vai cuidar de devolver pro Pool depois!

func _play_impact_vfx():
	# Aqui você pode ligar partículas no futuro:
	# $HitParticles.emitting = true
	
	# Chama a lógica do pai (que desliga a colisão e prepara a devolução pro Pool)
	super._play_impact_vfx()
