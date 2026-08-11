extends StaticBody3D
class_name EnemyTurret

@export_group("Combate")
@export var projectile_scene : PackedScene
@export var damage : float = 5.0
@export var fire_rate : float = 0.5
@export var projectile_speed : float = 80.0
@export var enemy_group_name : String = "inimigos"

@export_group("Loot / Recompensas")
## Arraste a cena "UniversalPickup.tscn" aqui
@export var drop_item_scene : PackedScene
## Arraste o arquivo .tres (Weapon ou Status) que ela vai dropar aqui
@export var drop_item_resource : Resource

# ============================================================================
# Fragmentos de destruição ao morrer. Mesmo padrão usado em
# DestructibleProp e BaseVehicle — a torre não sabe COMO a explosão
# funciona, só pede pro DebrisManager (autoload) fazer acontecer.
# ============================================================================
@export_group("Fragmentos de Destruição")
@export var spawn_debris_on_death : bool = true
## Caminho pro MeshInstance3D da torre (deixe vazio pra detectar automaticamente)
@export var mesh_instance_path : NodePath
@export var shard_count : int = 12
@export var explosion_force : float = 4.5
@export var upward_bias : float = 3.5
@export var shard_lifetime : float = 1.2
@export var scatter_radius : float = 0.6
## Tamanho mínimo de cada fragmento (aresta aproximada, em unidades do mundo)
@export var shard_min_size : float = 0.15
## Tamanho máximo de cada fragmento
@export var shard_max_size : float = 0.4

@onready var head = $Head
@onready var muzzle = $Head/Muzzle
@onready var detection_zone = $DetectionZone
@onready var stats = $StatsComponent

# Referência para a luz do tiro
@onready var muzzle_flash = $Head/Muzzle/OmniLight3D

var targets_in_range : Array = []
var current_target : Node3D = null
var fire_cooldown : float = 0.0
var is_dead : bool = false

func _ready():
	add_to_group(enemy_group_name)
	
	if detection_zone:
		detection_zone.body_entered.connect(_on_target_entered)
		detection_zone.body_exited.connect(_on_target_exited)
	
	if stats:
		stats.health_depleted.connect(_on_death)
		
	# Garante que a luz começa desligada
	if muzzle_flash:
		muzzle_flash.visible = false
		muzzle_flash.light_energy = 0.0

func _physics_process(delta):
	if fire_cooldown > 0:
		fire_cooldown -= delta
		
	_update_target()
	
	if current_target and is_instance_valid(current_target):
		_aim_and_fire(delta)

# --- INTELIGÊNCIA DE MIRA ---

func _update_target():
	targets_in_range = targets_in_range.filter(func(t): return is_instance_valid(t))
	
	if targets_in_range.is_empty():
		current_target = null
		return
		
	var closest_dist = INF
	var closest_target = null
	
	for target in targets_in_range:
		var dist = global_position.distance_to(target.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_target = target
			
	current_target = closest_target

func _aim_and_fire(_delta):
	var aim_pos = current_target.global_position + Vector3(0, 0.5, 0)
	
	if not head.global_position.is_equal_approx(aim_pos) and Vector3.UP.cross(aim_pos - head.global_position).length() > 0.01:
		head.look_at(aim_pos, Vector3.UP)
	
	if fire_cooldown <= 0:
		_fire_projectile()
		fire_cooldown = fire_rate

func _fire_projectile():
	if not projectile_scene: return
	
	# --- A MÁGICA DA PERFORMANCE (OBJECT POOLING) ---
	# Em vez de instantiate() e add_child(), a gente puxa do Autoload
	var proj = ProjectilePool.get_projectile(projectile_scene)
	
	proj.global_transform = muzzle.global_transform
	
	if proj.has_method("setup"):
		if "target" in proj:
			proj.setup(damage, Vector3.ZERO, self, current_target)
		else:
			proj.setup(damage, Vector3.ZERO, self, projectile_speed)
		
	if muzzle_flash:
		muzzle_flash.visible = true
		muzzle_flash.light_energy = 5.0
		var tween = create_tween()
		tween.tween_property(muzzle_flash, "light_energy", 0.0, 0.1)
		tween.tween_callback(func(): muzzle_flash.visible = false)

# --- RADAR DE DETECÇÃO ---

func _on_target_entered(body):
	if body.is_in_group("jogadores"):
		if not targets_in_range.has(body):
			targets_in_range.append(body)

func _on_target_exited(body):
	if targets_in_range.has(body):
		targets_in_range.erase(body)

# --- SISTEMA DE DANO ---

func take_damage(amount: float, attacker: Node = null):
	# --- ESCUDO FINAL ANTI-METRALHADORA ---
	if is_dead: 
		return 
		
	# --- CORREÇÃO DO TUTORIAL: IDENTIFICAÇÃO SEGURA DA BALA ---
	var actual_attacker = attacker
	var is_special = false
	
	if attacker:
		if "is_special_weapon" in attacker:
			is_special = attacker.is_special_weapon
			
		if "shooter" in attacker and is_instance_valid(attacker.shooter):
			actual_attacker = attacker.shooter
			
	if is_instance_valid(actual_attacker) and actual_attacker.is_in_group("jogadores"):
		if is_special:
			get_tree().call_group("TutorialUI", "complete_task", "shoot_enemy")

	if stats:
		stats.take_damage(amount, attacker)

func _on_death(attacker: Node = null):
	if is_dead: return
	is_dead = true
	
	var death_pos = self.global_position
	
	_spawn_debris()
	
	set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	visible = false
	
	call_deferred("_spawn_loot_safely", death_pos)

func _spawn_debris() -> void:
	if not spawn_debris_on_death:
		return
	if not is_instance_valid(DebrisManager):
		push_warning("[EnemyTurret] DebrisManager não encontrado. Configure como Autoload.")
		return
	
	var mesh_inst := _find_mesh_instance()
	var mat: Material = null
	if mesh_inst and mesh_inst.mesh:
		mat = mesh_inst.get_active_material(0)
	
	DebrisManager.explode(
		global_position,
		mat,
		shard_count,
		explosion_force,
		upward_bias,
		shard_lifetime,
		scatter_radius,
		shard_min_size,
		shard_max_size
	)

func _find_mesh_instance() -> MeshInstance3D:
	if mesh_instance_path != NodePath(""):
		var node := get_node_or_null(mesh_instance_path)
		if node is MeshInstance3D:
			return node
	return find_child("*", true, false) as MeshInstance3D

# ============================================================================
# NOVO: CHAMADA ENXUTA PARA O LOOT DROPMANAGER
# ============================================================================
func _spawn_loot_safely(origin_pos: Vector3):
	if drop_item_scene and drop_item_resource:
		print("[Turret] Torre destruída! Gerando Loot...")
		
		if is_instance_valid(LootDropManager):
			# Direção para onde a torre está "olhando" (Geralmente o eixo -Z)
			var dir_forward = -global_transform.basis.z.normalized()
			
			LootDropManager.spawn_ejected_loot(
				origin_pos, 
				dir_forward, 
				drop_item_scene, 
				drop_item_resource, 
				5.0 # Distância do arremesso
			)
		else:
			push_warning("[EnemyTurret] LootDropManager Autoload não encontrado!")
	else:
		print("[Turret] Sem loot configurado para esta torre.")
	
	# Agora que o loot nasceu em segurança pelo Autoload, podemos jogar o cadáver no lixo de vez!
	queue_free()
