extends RigidBody3D

@export_group("Mission Settings")
## Escreva aqui o ID para as missões (ex: barril, enemy_car)
@export var mission_id : String = ""

@export_group("Balance")
## Vida máxima do objeto (usado para calcular a barra de vida no HUD)
@export var max_health : float = 20.0
## Energia ganha ao destruir completamente o objeto
@export var energy_on_destroy : float = 20.0
## Energia ganha a cada hit (dano) recebido
@export var energy_on_hit : float = 1.0

# ============================================================================
# NOVO: SISTEMA DE EXPLOSÃO EM ÁREA (AoE)
# ============================================================================
@export_group("Explosão em Área (AoE)")
## Se ativo, o objeto causa dano em área a tudo em volta ao explodir
@export var causes_aoe_damage : bool = false
## Dano máximo no epicentro da explosão
@export var aoe_damage_amount : float = 50.0
## Raio de alcance da explosão em metros (Distância)
@export var aoe_radius : float = 8.0
## Força do empurrão nos objetos próximos
@export var aoe_knockback_force : float = 150.0
## Se ativo, o dano e o empurrão diminuem linearmente (ex: 100% colado, 10% na borda do raio)
@export var aoe_damage_falloff : bool = true

@export_group("Fragmentos de Destruição")
@export var spawn_debris_on_death : bool = true
@export var mesh_instance_path : NodePath
@export var shard_count : int = 10
@export var explosion_force : float = 4.0
@export var upward_bias : float = 3.5
@export var shard_lifetime : float = 1.1
@export var scatter_radius : float = 0.4
@export var shard_min_size : float = 0.15
@export var shard_max_size : float = 0.35
@export var aoe_min_vertical_kick : float = 1.4  # garante decolagem consistente
@export_flags_3d_physics var aoe_collision_mask : int = 0xFFFFFFFF

# ============================================================================
# NOVO: Efeito visual da explosão (flash + luz + fumaça). Só é usado se
# causes_aoe_damage estiver ligado — objetos que causam dano em área também
# "explodem" visualmente; objetos comuns continuam só soltando fragmentos.
# ============================================================================
@export_group("Efeito Visual da Explosão")
## Cor principal do flash/bola de fogo
@export var explosion_visual_color : Color = Color(1.0, 0.55, 0.1)
## Tamanho aproximado da bola de fogo (em unidades do mundo)
@export var explosion_visual_size : float = 3.0
## Quantos "puffs" de fumaça sobem da explosão
@export var explosion_particle_count : int = 10
## Intensidade máxima da luz do flash (0 desliga a luz)
@export var explosion_light_energy : float = 8.0

@onready var health : float = max_health

func take_damage(amount: float, attacker: Node3D = null):
	if health <= 0: return 
	health -= amount
	
	var actual_shooter = attacker
	var final_knockback = amount * 30.0 
	
	if attacker:
		if "shooter" in attacker and is_instance_valid(attacker.shooter):
			actual_shooter = attacker.shooter
		if "knockback_force" in attacker:
			final_knockback = attacker.knockback_force
			
		if is_instance_valid(actual_shooter):
			var hit_dir = (global_position - actual_shooter.global_position).normalized()
			hit_dir.y = .2
			apply_central_impulse(hit_dir * final_knockback)
	
	if actual_shooter:
		if actual_shooter.is_in_group("jogadores"):
			if attacker and "is_special_weapon" in attacker and not attacker.is_special_weapon:
				get_tree().call_group("TutorialUI", "complete_task", "barrels")
			
		_give_energy_to_attacker(actual_shooter, energy_on_hit)
		
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("HIT_OBJECT")
	
	if health <= 0:
		_morrer(actual_shooter)

func _morrer(actual_shooter: Node3D):
	if actual_shooter:
		# 1. Recupera energia por DESTRUIÇÃO
		_give_energy_to_attacker(actual_shooter, energy_on_destroy)
		
		# 2. Registra a destruição para pontos
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("DESTROY_OBJECT")
			
			# 3. Notifica o MissionManager se houver ID
			if mission_id != "" and is_instance_valid(MissionManager):
				MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
	
	# === Aplica o dano em área (Reações em Cadeia!) ===
	_apply_aoe_damage(actual_shooter)
	
	_spawn_debris()
	queue_free()

func _apply_aoe_damage(original_shooter: Node3D):
	if not causes_aoe_damage: return
	
	# NOVO: efeito visual da explosão. Reaproveita a mesma flag
	# causes_aoe_damage — só objetos que já causam dano em área fazem
	# sentido "explodir" visualmente também.
	_spawn_explosion_effect()

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = aoe_radius

	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.exclude = [self.get_rid()]
	query.collision_mask = aoe_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	# aumenta o limite padrão (32) para não perder alvos em reações em cadeia
	var results = space_state.intersect_shape(query, 64)

	for hit in results:
		var collider = hit["collider"]
		if not is_instance_valid(collider): continue

		# 1. Aproxima o "raio" do objeto para medir distância até a SUPERFÍCIE, não o pivot
		var approx_radius = _estimate_collider_radius(collider)
		var raw_dist = global_position.distance_to(collider.global_position)
		var dist = max(0.0, raw_dist - approx_radius)

		if dist > aoe_radius: continue

		var percent = 1.0
		if aoe_damage_falloff and aoe_radius > 0:
			percent = clamp(1.0 - (dist / aoe_radius), 0.0, 1.0)

		var final_damage = aoe_damage_amount * percent

		if collider is RigidBody3D or collider is VehicleBody3D:
			# 2. ACORDA o corpo antes de aplicar impulso — senão o impulso é perdido
			if "sleeping" in collider:
				collider.sleeping = false

			var pos_alvo = collider.global_position
			var pos_explosao = global_position
			var dir_horizontal = Vector3(pos_alvo.x - pos_explosao.x, 0, pos_alvo.z - pos_explosao.z)

			if dir_horizontal.length_squared() < 0.1:
				dir_horizontal = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
			dir_horizontal = dir_horizontal.normalized()

			# 3. Vertical mínimo garantido: força o objeto a perder contato com o chão
			#    de forma consistente, evitando o efeito "atrito engole o impulso"
			var vertical_component = max(0.8, aoe_min_vertical_kick * percent)
			var push_dir = dir_horizontal
			push_dir.y = vertical_component
			push_dir = push_dir.normalized()

			var obj_mass = collider.mass if "mass" in collider else 1.0
			var final_impulse = push_dir * (aoe_knockback_force * percent * obj_mass)

			collider.apply_impulse(final_impulse, Vector3(0, 0.5, 0))

		if collider.has_method("take_damage"):
			collider.take_damage(final_damage, original_shooter if original_shooter else self)


func _estimate_collider_radius(collider: Node3D) -> float:
	# Usa a AABB do primeiro MeshInstance3D como aproximação do "tamanho" do objeto
	var mesh_inst := collider.find_child("*", true, false) as MeshInstance3D
	if mesh_inst and mesh_inst.mesh:
		var aabb = mesh_inst.mesh.get_aabb()
		var size = aabb.size * mesh_inst.global_transform.basis.get_scale()
		return size.length() * 0.5
	return 0.5  # fallback conservador

# NOVO: dispara o efeito visual (flash + luz + fumaça) usando o
# ExplosionManager (autoload). Segue o mesmo princípio do DebrisManager —
# este objeto não sabe COMO o efeito funciona, só pede pra acontecer com
# os parâmetros configurados no Inspector.
func _spawn_explosion_effect() -> void:
	if not is_instance_valid(ExplosionManager):
		push_warning("[DestructibleProp] ExplosionManager não encontrado. Configure como Autoload.")
		return
	
	ExplosionManager.explode(
		global_position,
		explosion_visual_color,
		explosion_visual_size,
		explosion_particle_count,
		explosion_light_energy
	)

func _spawn_debris() -> void:
	if not spawn_debris_on_death:
		return
	if not is_instance_valid(DebrisManager):
		push_warning("[DestructibleProp] DebrisManager não encontrado. Configure como Autoload.")
		return
	
	var meshes = _get_all_mesh_instances()
	
	if meshes.is_empty():
		# Fallback de segurança caso o objeto seja invisível ou não tenha malhas
		DebrisManager.explode(
			global_position, null, shard_count, explosion_force,
			upward_bias, shard_lifetime, scatter_radius, shard_min_size, shard_max_size
		)
		return
		
	# Para cada estilhaço que precisamos gerar, escolhemos um ponto aleatório
	for i in range(shard_count):
		# Escolhe uma malha aleatória do objeto (ex: pode cair no Tronco ou nas Folhas)
		var mesh_inst = meshes[randi() % meshes.size()]
		
		var mat: Material = null
		if mesh_inst.mesh:
			mat = mesh_inst.get_active_material(0)
			
			# Calcula a caixa delimitadora (AABB) da malha para saber o volume dela
			var aabb = mesh_inst.mesh.get_aabb()
			
			# Sorteia um ponto perfeitamente dentro desse volume no espaço LOCAL
			var random_local_pos = aabb.position + Vector3(
				randf() * aabb.size.x,
				randf() * aabb.size.y,
				randf() * aabb.size.z
			)
			
			# Converte esse ponto local para a posição GLOBAL correta do mundo
			var explosion_origin = mesh_inst.to_global(random_local_pos)
			
			# Chama o DebrisManager para soltar APENAS 1 estilhaço nesta posição exata.
			# Como a posição já foi espalhada por nós, passamos o scatter_radius como 0.0
			DebrisManager.explode(
				explosion_origin,
				mat,
				1, # Quantidade de estilhaços por chamada
				explosion_force,
				upward_bias,
				shard_lifetime,
				0.0, # Scatter zerado, pois o espalhamento já foi feito na área da malha
				shard_min_size,
				shard_max_size
			)

# Substituímos a função antiga por esta que retorna uma Array com TODAS as malhas
func _get_all_mesh_instances() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	
	if mesh_instance_path != NodePath(""):
		var node = get_node_or_null(mesh_instance_path)
		if node is MeshInstance3D:
			result.append(node)
			return result
			
	# Busca todas as malhas filhas (Pega o Tronco, a Base, as Folhas, etc.)
	var children = find_children("*", "MeshInstance3D", true, false)
	for c in children:
		# Ignora malhas sem geometria ou invisíveis
		if c is MeshInstance3D and c.mesh and c.visible:
			result.append(c)
			
	return result

func _give_energy_to_attacker(attacker: Node3D, amount: float):
	var ability = attacker.get_node_or_null("%AbilityComponent")
	if ability:
		ability.current_energy = min(ability.current_energy + amount, ability.MAX_ENERGY)
