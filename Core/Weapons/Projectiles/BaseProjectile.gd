# BaseProjectile.gd
extends Area3D
class_name BaseProjectile

@export_group("Física de Combate")
@export var knockback_force: float = 50.0 
# O valor base de trepidação da câmera gerado por essa munição
@export var base_shake_force: float = 0.10 

var damage: float = 0.0
var shooter: Node3D = null
var hit_done: bool = false
var velocity: Vector3 = Vector3.ZERO 

# Variáveis do Pool
var pool_key: String = ""
var life_timer: float = 0.0
var is_special_weapon: bool = false

func _ready():
	if not body_entered.is_connected(_on_impact):
		body_entered.connect(_on_impact)
	if not area_entered.is_connected(_on_impact):
		area_entered.connect(_on_impact)

# Setup é chamado toda vez que a bala "nasce" (ou renasce do Pool)
func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 50.0):
	damage = dmg_value
	shooter = source_car
	
	# A direção pura que o míssil está apontando (já rotacionada 180 graus pelo WeaponManager)
	var shot_direction = -global_transform.basis.z.normalized()
	var propulsion = shot_direction * propulsion_speed
	
	# --- A CORREÇÃO DE INÉRCIA PARA TIROS REVERSOS ---
	var is_shooting_backwards = false
	
	# Se o carro estiver em movimento (velocidade maior que algo mínimo para não bugar parado)
	if car_velocity.length() > 2.0:
		var car_move_direction = car_velocity.normalized()
		
		# Dot Product: Se o ângulo entre o movimento do carro e a mira do tiro for maior que ~90 graus, 
		# o resultado será negativo. Isso significa que o tiro está indo contra o movimento!
		if shot_direction.dot(car_move_direction) < -0.3:
			is_shooting_backwards = true

	if is_shooting_backwards:
		# Se atirou para trás, IGNORA a velocidade pra frente do carro para o míssil não ser arrastado.
		# O míssil vai sair voando limpo para trás com sua própria força.
		velocity = propulsion
	else:
		# Se atirou para a frente, soma a inércia normalmente (tiro normal)
		velocity = car_velocity + propulsion
	
	# --- RESET DO POOL (ACORDA A BALA) ---
	hit_done = false
	visible = true
	set_deferred("monitoring", true)
	life_timer = 4.0 # 4 Segundos de vida até voltar pro pool
	
	# === SHAKE DE LANÇAMENTO ===
	# Só executa se for arma especial ou se quisermos filtrar a metralhadora
	if is_special_weapon and is_instance_valid(shooter) and shooter.is_in_group("jogadores"):
		var shake = _get_camera_shake(shooter)
		if shake:
			shake.trigger_event("CustomFire", base_shake_force)

func _physics_process(delta):
	var real_delta = delta
	if is_instance_valid(shooter) and shooter.is_in_group("jogadores"):
		real_delta = delta / Engine.time_scale
		
	# --- CRONÔMETRO SEM LIXO DE MEMÓRIA ---
	if life_timer > 0:
		life_timer -= real_delta
		if life_timer <= 0:
			_deactivate_and_pool()
			return
			
	if hit_done: return # Congela o movimento se bateu

	global_position += velocity * real_delta

func _on_impact(target_node):
	if hit_done: return
	
	if not is_instance_valid(target_node) or target_node.is_queued_for_deletion(): return
	
	var actual_target = target_node
	if target_node is Area3D:
		if is_instance_valid(target_node.owner): actual_target = target_node.owner
		elif is_instance_valid(target_node.get_parent()): actual_target = target_node.get_parent()
		
	if is_instance_valid(shooter):
		if actual_target == shooter or actual_target == shooter.owner: return
			
	hit_done = true
	
	if actual_target.has_method("take_damage"):
		actual_target.take_damage(damage, self) 
		
	# --- INTEGRAÇÃO DO RAGE COMPONENT ---
	if is_instance_valid(shooter):
		var rage = shooter.get_node_or_null("%RageComponent")
		if rage and rage.has_method("add_hit"):
			# Agora passamos o alvo, o dano, e se é arma especial!
			rage.add_hit(actual_target, damage, is_special_weapon)
	
	_play_impact_vfx()

func _play_impact_vfx():
	# === CORREÇÃO DO SCREENSHAKE INFINITO ===
	# Só executamos o tremor de impacto em área se a arma for uma explosão real (is_special_weapon).
	# Isso impede que a MachineGun cause "terremotos" a cada 0.1s.
	if is_special_weapon:
		var jogadores = get_tree().get_nodes_in_group("jogadores")
		
		for jog in jogadores:
			if is_instance_valid(jog):
				var distance = global_position.distance_to(jog.global_position)
				
				if distance <= 100.0:
					var mult = clamp(remap(distance, 5.0, 100.0, 2.0, 0.1), 0.1, 2.0)
					var final_shake = base_shake_force * mult
					
					var shake = _get_camera_shake(jog)
					if shake:
						shake.trigger_event("Explosion", final_shake)
			
	set_deferred("monitoring", false)
	visible = false
	velocity = Vector3.ZERO
	
	life_timer = 0.1

func _deactivate_and_pool():
	set_deferred("monitoring", false)
	visible = false
	velocity = Vector3.ZERO
	is_special_weapon = false
	
	# Devolve a bala pro almoxarifado em vez de jogar no lixo!
	if ProjectilePool.has_method("return_projectile"):
		ProjectilePool.return_projectile(self)
	else:
		queue_free()

# === FUNÇÃO AUXILIAR PARA ACHAR O NODE ===
# Como o CameraShake é filho da câmera e não do script do carro diretamente,
# essa função faz uma busca segura pelos filhos para garantir que vamos achar o script.
func _get_camera_shake(car_node: Node3D) -> CameraShake:
	var shakes = car_node.find_children("*", "CameraShake", true, false)
	if shakes.size() > 0:
		return shakes[0] as CameraShake
	return null
