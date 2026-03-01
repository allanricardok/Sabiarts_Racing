# EnemyTurret.gd
extends StaticBody3D
class_name EnemyTurret

@export_group("Combate")
@export var projectile_scene : PackedScene
@export var damage : float = 5.0
@export var fire_rate : float = 0.5
@export var projectile_speed : float = 80.0
@export var enemy_group_name : String = "inimigos"

@onready var head = $Head
@onready var muzzle = $Head/Muzzle
@onready var detection_zone = $DetectionZone
@onready var stats = $StatsComponent

# --- NOVO: Referência para a luz do tiro ---
@onready var muzzle_flash = $Head/Muzzle/OmniLight3D

var targets_in_range : Array = []
var current_target : Node3D = null
var fire_cooldown : float = 0.0

func _ready():
	add_to_group(enemy_group_name)
	
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
	
	var proj = projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)
	
	proj.global_transform = muzzle.global_transform
	
	if proj.has_method("setup"):
		proj.setup(damage, Vector3.ZERO, self, projectile_speed)
		
	# --- EFEITO DE LUZ (MUZZLE FLASH) ---
	if muzzle_flash:
		muzzle_flash.visible = true
		muzzle_flash.light_energy = 5.0 # Força inicial do brilho
		
		# Cria uma animação rápida para apagar a luz
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
	if stats:
		stats.take_damage(amount, attacker)

func _on_death():
	print("[Turret] Torre destruída!")
	queue_free()
