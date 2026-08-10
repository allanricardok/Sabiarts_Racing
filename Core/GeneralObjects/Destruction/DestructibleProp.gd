extends RigidBody3D

@export_group("Mission Settings")
## Escreva aqui o ID para as missões (ex: barril, enemy_car)
@export var mission_id : String = ""
@export var is_defend_vip: bool = false

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

@export_group("Efeito Visual da Explosão")
@export var explosion_visual_color : Color = Color(1.0, 0.55, 0.1)
@export var explosion_visual_size : float = 3.0
@export var explosion_particle_count : int = 10
@export var explosion_light_energy : float = 8.0

@onready var health : float = max_health

var _initial_transform: Transform3D
var _initial_health: float

# === VARIÁVEIS PARA SALVAR A COLISÃO ORIGINAL ===
var _initial_layer: int
var _initial_mask: int

func _ready():
	add_to_group("destructible_vips")
	
	_initial_transform = global_transform
	_initial_health = health
	
	# Salva como as colisões eram antes de morrer
	_initial_layer = collision_layer
	_initial_mask = collision_mask

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

func _morrer(actual_shooter: Node3D = null):
	if is_defend_vip:
		get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.DEFEND, -1.0, "vip_destroyed")
	else:
		if mission_id != "":
			get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.DESTROY, 1.0, mission_id)

	if actual_shooter:
		_give_energy_to_attacker(actual_shooter, energy_on_destroy)
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("DESTROY_OBJECT")
			
	_apply_aoe_damage(actual_shooter)
	_spawn_debris()
	
	if is_defend_vip or mission_id != "":
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		
		# =====================================================================
		# A CORREÇÃO MÁXIMA DO RADAR: Esconde de tudo e de todos!
		# =====================================================================
		collision_layer = 0
		collision_mask = 0
		global_position = Vector3(0, -5000, 0) # Teleporta pro centro da terra!
		
		if is_in_group("destructible_vips"):
			remove_from_group("destructible_vips")
		# =====================================================================
		
		for child in get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D:
				child.set_deferred("disabled", true)
	else:
		queue_free() 

func reset():
	global_transform = _initial_transform
	health = _initial_health
	
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	
	# =====================================================================
	# RESTAURA AS COLISÕES E GRUPOS
	# =====================================================================
	collision_layer = _initial_layer
	collision_mask = _initial_mask
	
	if not is_in_group("destructible_vips"):
		add_to_group("destructible_vips")
	
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.set_deferred("disabled", false)
			
	print("[Destructible] VIP restaurado para a posição original e com vida cheia!")

func _apply_aoe_damage(original_shooter: Node3D):
	if not causes_aoe_damage: return
	
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

	var results = space_state.intersect_shape(query, 64)

	for hit in results:
		var collider = hit["collider"]
		if not is_instance_valid(collider): continue

		var approx_radius = _estimate_collider_radius(collider)
		var raw_dist = global_position.distance_to(collider.global_position)
		var dist = max(0.0, raw_dist - approx_radius)

		if dist > aoe_radius: continue

		var percent = 1.0
		if aoe_damage_falloff and aoe_radius > 0:
			percent = clamp(1.0 - (dist / aoe_radius), 0.0, 1.0)

		var final_damage = aoe_damage_amount * percent

		if collider is RigidBody3D or collider is VehicleBody3D:
			if not collider.is_inside_tree():
				continue
			
			if "sleeping" in collider:
				collider.sleeping = false

			var pos_alvo = collider.global_position
			var pos_explosao = global_position
			var dir_horizontal = Vector3(pos_alvo.x - pos_explosao.x, 0, pos_alvo.z - pos_explosao.z)

			if dir_horizontal.length_squared() < 0.1:
				dir_horizontal = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
			dir_horizontal = dir_horizontal.normalized()

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
	var mesh_inst := collider.find_child("*", true, false) as MeshInstance3D
	if mesh_inst and mesh_inst.mesh:
		var aabb = mesh_inst.mesh.get_aabb()
		var size = aabb.size * mesh_inst.global_transform.basis.get_scale()
		return size.length() * 0.5
	return 0.5 

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
		DebrisManager.explode(
			global_position, null, shard_count, explosion_force,
			upward_bias, shard_lifetime, scatter_radius, shard_min_size, shard_max_size
		)
		return
		
	for i in range(shard_count):
		var mesh_inst = meshes[randi() % meshes.size()]
		
		var mat: Material = null
		if mesh_inst.mesh:
			mat = mesh_inst.get_active_material(0)
			var aabb = mesh_inst.mesh.get_aabb()
			
			var random_local_pos = aabb.position + Vector3(
				randf() * aabb.size.x,
				randf() * aabb.size.y,
				randf() * aabb.size.z
			)
			
			var explosion_origin = mesh_inst.to_global(random_local_pos)
			
			DebrisManager.explode(
				explosion_origin,
				mat,
				1, 
				explosion_force,
				upward_bias,
				shard_lifetime,
				0.0, 
				shard_min_size,
				shard_max_size
			)

func _get_all_mesh_instances() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	
	if mesh_instance_path != NodePath(""):
		var node = get_node_or_null(mesh_instance_path)
		if node is MeshInstance3D:
			result.append(node)
			return result
			
	var children = find_children("*", "MeshInstance3D", true, false)
	for c in children:
		if c is MeshInstance3D and c.mesh and c.visible:
			result.append(c)
			
	return result

func _give_energy_to_attacker(attacker: Node3D, amount: float):
	var ability = attacker.get_node_or_null("%AbilityComponent")
	if ability:
		ability.current_energy = min(ability.current_energy + amount, ability.MAX_ENERGY)
