# Exemplo para BigSlowProjectile.gd (serve para a metralhadora também)
extends RigidBody3D

var damage = 20.0
var hit_done = false

func setup(dmg_value, car_velocity: Vector3):
	damage = dmg_value
	
	# --- 1. VELOCIDADE RELATIVA ---
	# Velocidade Total = Velocidade do Carro + Impulso do Tiro
	var propulsion = -global_transform.basis.z * 50.0 # Velocidade base da bala
	linear_velocity = car_velocity + propulsion

func _ready():
	body_entered.connect(_on_impact)
	
	# --- 2. PRAZO DE VALIDADE ---
	# Despawn após 4 segundos se não acertar nada
	get_tree().create_timer(4.0).timeout.connect(queue_free)
	
	# --- 3. EVITAR AUTO-COLISÃO ---
	# Se você tiver problemas do tiro bater na Brasília assim que sai:
	# Você pode usar: add_collision_exception_with(get_parent_of_car_node)
	# Ou garantir que o Muzzle esteja BEM à frente do colisor do carro.

func _on_impact(body):
	if hit_done: return
	
	# Ignora se bater no próprio carro (verificando se o body é um VehicleBody3D)
	if body is VehicleBody3D: return
	
	hit_done = true
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	# Efeito de sumir
	freeze = true
	visible = false
	await get_tree().create_timer(0.1).timeout
	queue_free()
