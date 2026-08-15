extends Area3D
class_name BaseProjectile

@export_group("Física de Combate")
@export var knockback_force: float = 50.0 
# O valor base de trepidação da câmera gerado por essa munição
@export var base_shake_force: float = 0.10 

# ============================================================================
# NOVO: SISTEMA DE EXPLOSÃO EM ÁREA (AoE)
# ============================================================================
@export_group("Area of Effect (AoE)")
## Se ativo, o projétil explode e causa dano/empurrão em área no impacto
@export var causes_aoe_damage: bool = false
## Raio de alcance da explosão em metros
@export var aoe_radius: float = 5.0
## Dano causado a quem estiver dentro da área
@export var aoe_damage: float = 5.0
## Força do empurrão da explosão
@export var aoe_knockback: float = 20.0
## Porcentagem do dano em área que o PRÓPRIO ATIRADOR recebe (0.0 = 0% | 1.0 = 100%)
@export_range(0.0, 1.0) var self_damage_multiplier: float = 0.25

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
	
	# 1. Aplica o Dano Direto na "vítima principal"
	if actual_target.has_method("take_damage"):
		actual_target.take_damage(damage, self) 
		
	# --- INTEGRAÇÃO DO RAGE COMPONENT ---
	if is_instance_valid(shooter):
		var rage = shooter.get_node_or_null("%RageComponent")
		if rage and rage.has_method("add_hit"):
			rage.add_hit(actual_target, damage, is_special_weapon)
	
	# =====================================================================
	# GATILHO DA EXPLOSÃO EM ÁREA
	# =====================================================================
	if causes_aoe_damage:
		_apply_aoe_damage(actual_target)
	
	_play_impact_vfx()

func _play_impact_vfx():
	# === CORREÇÃO DO SCREENSHAKE INFINITO ===
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
	
	if ProjectilePool.has_method("return_projectile"):
		ProjectilePool.return_projectile(self)
	else:
		queue_free()

func _get_camera_shake(car_node: Node3D) -> CameraShake:
	var shakes = car_node.find_children("*", "CameraShake", true, false)
	if shakes.size() > 0:
		return shakes[0] as CameraShake
	return null

# ============================================================================
# FÍSICA E DANO DA EXPLOSÃO EM ÁREA
# ============================================================================
func _apply_aoe_damage(direct_target: Node3D):
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = aoe_radius
	
	query.shape = sphere
	query.transform = global_transform
	query.exclude = [self.get_rid()]
	
	# Detecta tudo dentro do raio da explosão
	var results = space_state.intersect_shape(query, 32)
	
	# CORREÇÃO: Cria uma referência segura do atirador para passar adiante
	var safe_shooter = shooter if is_instance_valid(shooter) else null
	
	for hit in results:
		var collider = hit.collider
		if not is_instance_valid(collider): continue
		
		# =================================================================
		# NOVA MATEMÁTICA: Falloff de Distância!
		# Calcula a distância do centro da explosão até o alvo.
		# A força vai de 1.0 (no epicentro) caindo até 0.0 (no limite do raio).
		# =================================================================
		var dist_to_explosion = global_position.distance_to(collider.global_position)
		var falloff = 1.0 - clamp(dist_to_explosion / aoe_radius, 0.0, 1.0)
		
		var damage_mult = falloff
		
		# --- REGRA 1: O ATIRADOR ---
		var is_shooter = false
		if is_instance_valid(shooter):
			if collider == shooter or collider == shooter.owner:
				is_shooter = true
				
		if is_shooter:
			if self_damage_multiplier <= 0.0:
				continue # Se for 0, o atirador sai ileso
			# Aplica o self_damage_multiplier SOBRE a força já atenuada pela distância
			damage_mult *= self_damage_multiplier
			
		# --- REGRA 2: O ALVO PRIMÁRIO ---
		elif collider == direct_target:
			# CORREÇÃO: Para dar um bônus de 25% no alvo principal, o valor é 1.25 (e não 0.25).
			# Cravamos esse valor, ignorando o falloff da distância.
			damage_mult = 1.25 
			
		# Se a força final for insignificante (quase na borda), nem processa física para poupar CPU
		if damage_mult <= 0.01: continue
			
		var final_splash_damage = aoe_damage * damage_mult
		var final_splash_knockback = aoe_knockback * damage_mult
		
		# --- APLICA O EMPURRÃO (FÍSICA) ---
		if collider is RigidBody3D or collider is VehicleBody3D:
			if not is_instance_valid(collider) or collider.is_queued_for_deletion() or not collider.is_inside_tree(): 
				continue
				
			if collider.process_mode == Node.PROCESS_MODE_DISABLED or collider.get_collision_layer() == 0:
				continue
				
			if "sleeping" in collider: collider.sleeping = false
			
			var push_dir = (collider.global_position - global_position).normalized()
			push_dir.y = max(0.5, push_dir.y) # Garante que a explosão joga as coisas pra cima
			
			var obj_mass = collider.mass if "mass" in collider else 1.0
			var final_impulse = push_dir * (final_splash_knockback * obj_mass)
			
			collider.apply_impulse(final_impulse)
			
		# --- APLICA O DANO SPLASH ---
		if collider.has_method("take_damage"):
			collider.take_damage(final_splash_damage, safe_shooter)
		else:
			var stats = collider.find_child("StatsComponent*", true, false)
			if stats and stats.has_method("take_damage"):
				stats.take_damage(final_splash_damage, safe_shooter)
