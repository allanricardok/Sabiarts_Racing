# EnemyTurret.gd
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

@onready var head = $Head
@onready var muzzle = $Head/Muzzle
@onready var detection_zone = $DetectionZone
@onready var stats = $StatsComponent

# Referência para a luz do tiro
@onready var muzzle_flash = $Head/Muzzle/OmniLight3D

var targets_in_range : Array = []
var current_target : Node3D = null
var fire_cooldown : float = 0.0
var is_dead : bool = false # <--- ADICIONE ESTA LINHA AQUI

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
		# Primeiro descobre se o objeto físico que bateu na torre é uma arma especial
		if "is_special_weapon" in attacker:
			is_special = attacker.is_special_weapon
			
		# Depois descobre quem foi o jogador que atirou essa arma
		if "shooter" in attacker and is_instance_valid(attacker.shooter):
			actual_attacker = attacker.shooter
			
	# Se quem atirou foi o jogador E a arma usada foi a especial:
	if is_instance_valid(actual_attacker) and actual_attacker.is_in_group("jogadores"):
		if is_special:
			get_tree().call_group("TutorialUI", "complete_task", "shoot_enemy")

	if stats:
		stats.take_damage(amount, attacker)

func _on_death(attacker: Node = null):
	# CADEADO DUPLO: Garante que só morre uma vez
	if is_dead: return
	is_dead = true
	
	# Salva a posição exata de onde morreu antes da engine se perder
	var death_pos = self.global_position
	
	# Desliga a torre imediatamente (Fica invisível e intocável)
	set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	visible = false
	
	# AGENDAMENTO: Pede pro Godot gerar o loot assim que for seguro (fim do frame)
	call_deferred("_spawn_loot_safely", death_pos)

# --- NOVA FUNÇÃO SEGURA PARA O LOOT ---
func _spawn_loot_safely(origin_pos: Vector3):
	if drop_item_scene and drop_item_resource:
		print("[Turret] Torre destruída! Gerando Loot...")
		
		var space_state = get_world_3d().direct_space_state
		var destination = origin_pos + (Vector3.DOWN * 100.0)
		
		# Não precisamos mais ignorar a torre, pois ela já está desativada!
		var query = PhysicsRayQueryParameters3D.create(origin_pos, destination)
		
		var result = space_state.intersect_ray(query)
		var final_pos = origin_pos 
		
		if result:
			final_pos = result.position + Vector3(0, 1.5, 0)
			
		# Cria o elevador fantasma para cair
		var drop_carrier = Node3D.new()
		drop_carrier.global_position = origin_pos
		get_tree().current_scene.add_child(drop_carrier)
		
		var drop = drop_item_scene.instantiate()
		drop.position = Vector3.ZERO 
		
		if "weapon_resource" in drop:
			drop.weapon_resource = drop_item_resource
		elif "item_data" in drop:
			drop.item_data = drop_item_resource
			
		drop_carrier.add_child(drop)
		
		# Auto-destruição do elevador quando a caixa for coletada
		drop.tree_exited.connect(func():
			if is_instance_valid(drop_carrier):
				drop_carrier.queue_free()
		)
		
		# Animação de queda pesada
		var distance = origin_pos.distance_to(final_pos)
		if distance > 0.1:
			var fall_time = sqrt((2.0 * distance) / 50.0)
			var tween = get_tree().create_tween()
			tween.tween_property(drop_carrier, "global_position", final_pos, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			
	else:
		print("[Turret] Sem loot configurado para esta torre.")
	
	# Agora que o loot nasceu em segurança, podemos jogar o cadáver no lixo de vez!
	queue_free()
