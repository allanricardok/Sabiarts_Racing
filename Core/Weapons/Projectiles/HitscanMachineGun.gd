extends Node3D
class_name HitscanMachineGun

@export_group("Configurações Hitscan")
@export var max_range: float = 200.0
## Velocidade visual do projétil (em metros por segundo) — também define
## o tempo de atraso do dano, já que o dano só acontece quando o tracer chega
@export var tracer_speed: float = 220.0
## Raio da cápsula de colisão física (não é só visual — agora afeta de
## verdade a facilidade de acertar o alvo)
@export var collision_radius: float = 0.8

@export_group("Visual do Tracer")
@export var tracer_color: Color = Color(1.0, 0.8, 0.1, 1.0)
@export var tracer_length: float = 0.8
@export var tracer_width: float = 0.15

@onready var muzzle: Marker3D = $MuzzleRay

# Objeto leve (RefCounted, sem custo de nó) só pra "se identificar" como
# ataque à distância pro pedestrian.gd — que decide se mostra o splash de
# sangue na tela baseado em is_projectile + distância do atirador real.
class HitscanAttackInfo extends Node3D:
	var shooter: Node3D

# Pool de "balas visuais" — cada slot agora também carrega o dano PENDENTE
# daquele tiro específico, aplicado só quando o tracer chega ao alvo.
var _tracer_pool: Array[MeshInstance3D] = []
var _tracer_data: Array[Dictionary] = []

static var _shared_tracer_mat: StandardMaterial3D = null
static var _shared_tracer_mesh: BoxMesh = null

const POOL_SIZE := 20

func _ready():
	_setup_tracer_pool()

func _setup_tracer_pool():
	if _shared_tracer_mat == null:
		# ====================================================================
		# OTIMIZAÇÃO: Busca o material direto do Cache!
		# ====================================================================
		var cached_mat = MaterialCache.get_mat("WeaponTracerBase")
		if cached_mat:
			_shared_tracer_mat = cached_mat.duplicate()
		else:
			_shared_tracer_mat = StandardMaterial3D.new()
			_shared_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_shared_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_shared_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_shared_tracer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		
		_shared_tracer_mat.albedo_color = tracer_color

		_shared_tracer_mesh = BoxMesh.new()
		_shared_tracer_mesh.size = Vector3(tracer_width, tracer_width, tracer_length)
		_shared_tracer_mesh.surface_set_material(0, _shared_tracer_mat)

	for i in range(POOL_SIZE):
		var tracer = MeshInstance3D.new()
		tracer.mesh = _shared_tracer_mesh
		tracer.visible = false
		add_child(tracer)
		_tracer_pool.append(tracer)
		_tracer_data.append(_make_empty_slot())

func _make_empty_slot() -> Dictionary:
	return {
		"active": false,
		"pos": Vector3.ZERO,
		"dir": Vector3.ZERO,
		"max_dist": 0.0,
		"traveled": 0.0,
		"damage_pending": false,
		"damage": 0.0,
		"target": null,       # referência direta ao collider — checamos is_instance_valid no momento do impacto
		"shooter": null,
	}

func _physics_process(delta):
	for i in range(_tracer_pool.size()):
		var d = _tracer_data[i]
		if not d["active"]:
			continue
		
		d["traveled"] += tracer_speed * delta
		
		if d["traveled"] >= d["max_dist"]:
			# --- O tracer chegou ao destino AGORA. É aqui que o dano
			# acontece de verdade, com o atraso proporcional à distância. ---
			if d["damage_pending"]:
				_apply_damage(d["target"], d["damage"], d["shooter"])
			
			d["active"] = false
			_tracer_pool[i].visible = false
		else:
			_tracer_pool[i].global_position = d["pos"] + (d["dir"] * d["traveled"])

func fire_hitscan(shooter_node: Node3D, damage: float):
	if not is_instance_valid(muzzle): return
	
	var space_state = get_world_3d().direct_space_state
	var origin: Vector3 = muzzle.global_position
	var forward_dir: Vector3 = -muzzle.global_transform.basis.z.normalized()
	var end_point: Vector3 = origin + (forward_dir * max_range)
	
	var exclude_list: Array = [shooter_node.get_rid()] if shooter_node is CollisionObject3D else []
	
	# =========================================================================
	# PASSO 1: RAYCAST FINO (Linha de Visão Absoluta)
	# Disparamos um raio cirúrgico para encontrar a superfície exata da parede.
	# Isso "corta" o alcance do tiro, impedindo que a bala grossa vá além.
	# =========================================================================
	var ray_query := PhysicsRayQueryParameters3D.create(origin, end_point)
	ray_query.exclude = exclude_list
	# Opcional: Se quiser que o tiro atravesse vidros ou props destrutíveis, 
	# mude a mask aqui para checar apenas o Layer 1 (Cenário Sólido)
	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = false
	
	var ray_result = space_state.intersect_ray(ray_query)
	var actual_max_range = max_range
	var ray_hit_collider = null
	var ray_hit_point = end_point
	
	if ray_result:
		actual_max_range = origin.distance_to(ray_result.position)
		ray_hit_collider = ray_result.collider
		ray_hit_point = ray_result.position
	
	# =========================================================================
	# PASSO 2: DETECÇÃO "GROSSA" (Cápsula Limitada)
	# A cápsula continua garantindo a facilidade de acerto, mas o tamanho 
	# (height) dela foi espremido pelo limite do cenário encontrado acima!
	# =========================================================================
	var capsule := CapsuleShape3D.new()
	capsule.radius = collision_radius
	capsule.height = actual_max_range
	
	var mid_point: Vector3 = origin + forward_dir * (actual_max_range * 0.5)
	
	var up_vec := Vector3.UP
	if abs(up_vec.dot(forward_dir)) > 0.95:
		up_vec = Vector3.RIGHT
	var capsule_x := up_vec.cross(forward_dir).normalized()
	var capsule_z := capsule_x.cross(forward_dir).normalized()
	
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.transform = Transform3D(Basis(capsule_x, forward_dir, capsule_z), mid_point)
	shape_query.exclude = exclude_list
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false
	
	var candidates = space_state.intersect_shape(shape_query, 8)
	
	var hit_collider = null
	var closest_dist: float = actual_max_range
	
	for c in candidates:
		var col = c.collider
		if not is_instance_valid(col): continue
		if col.process_mode == Node.PROCESS_MODE_DISABLED: continue
		
		# Projeta a distância. Se o inimigo tentar "roubar" a prioridade 
		# atrás da parede, o dist_along será maior que o actual_max_range e será ignorado!
		var to_col: Vector3 = col.global_position - origin
		var dist_along: float = to_col.dot(forward_dir)
		if dist_along < 0.0 or dist_along > actual_max_range: continue
		
		if dist_along < closest_dist:
			closest_dist = dist_along
			hit_collider = col
			
	# Se a cápsula não pegou nenhum inimigo raspando (ex: tiro direto num prédio), 
	# nós herdamos o resultado do Raycast fino que bateu no cenário.
	if hit_collider == null and ray_result:
		hit_collider = ray_hit_collider
		closest_dist = actual_max_range
	
	var impact_point: Vector3 = (origin + forward_dir * closest_dist) if hit_collider else ray_hit_point
	
	_spawn_tracer_visual(origin, impact_point, hit_collider, damage, shooter_node)

func _spawn_tracer_visual(start: Vector3, end: Vector3, target, damage: float, shooter_node: Node3D):
	for i in range(_tracer_pool.size()):
		if not _tracer_data[i]["active"]:
			var tracer = _tracer_pool[i]
			var dist: float = start.distance_to(end)
			var dir: Vector3 = (end - start).normalized()
			
			_tracer_data[i]["active"] = true
			_tracer_data[i]["pos"] = start
			_tracer_data[i]["dir"] = dir
			_tracer_data[i]["max_dist"] = dist
			_tracer_data[i]["traveled"] = 0.0
			_tracer_data[i]["damage_pending"] = is_instance_valid(target)
			_tracer_data[i]["damage"] = damage
			_tracer_data[i]["target"] = target
			_tracer_data[i]["shooter"] = shooter_node
			
			tracer.global_position = start
			tracer.look_at(end, Vector3.UP)
			tracer.visible = true
			return
	
	# --- Pool esgotado (20 tiros em voo ao mesmo tempo NESTA arma) ---
	# Não há slot pra segurar o dano pendente. Em vez de simplesmente
	# perder o dano do jogador, aplicamos na hora como fallback — só
	# perde o micro-delay nesse caso raro, nunca o dano em si.
	if is_instance_valid(target):
		_apply_damage(target, damage, shooter_node)

func _apply_damage(target, damage: float, shooter_node: Node3D):
	if not is_instance_valid(target): return
	if target.process_mode == Node.PROCESS_MODE_DISABLED: return
	
	# Só embrulha o atirador quando o alvo é um pedestre — é o único script
	# que sabe desembrulhar ".shooter" pra checar distância do splash de
	# sangue. Outros alvos (props destrutíveis, etc.) continuam recebendo
	# o atirador real diretamente, como sempre funcionou.
	var attacker_arg: Node3D = shooter_node
	var wrapper: HitscanAttackInfo = null
	
	if target.is_in_group("pedestrians"):
		wrapper = HitscanAttackInfo.new()
		wrapper.shooter = shooter_node
		attacker_arg = wrapper
	
	if target.has_method("take_damage"):
		target.take_damage(damage, attacker_arg)
	else:
		var stats = target.find_child("StatsComponent*", true, false)
		if stats:
			stats.take_damage(damage, attacker_arg)
	
	# O wrapper nunca entra na árvore de cena, então não é liberado
	# automaticamente — precisamos liberar manualmente. Isso é seguro
	# aqui porque pedestrian.gd já leu ".shooter" de forma síncrona
	# dentro da própria chamada de take_damage() acima, antes de retornar.
	if wrapper:
		wrapper.free()
