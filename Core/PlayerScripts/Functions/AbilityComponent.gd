extends Node
class_name AbilityComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var stats = %StatsComponent
@onready var weapons = %WeaponManager # <-- REFERÊNCIA ADICIONADA AQUI!

# --- SISTEMA DE ENERGIA ---
@export_group("Energy System")
@export var MAX_ENERGY : float = 100.0
@export var REGEN_RATE : float = 3.0
@export var current_energy : float = 100.0

@export_group("Ability Costs")
@export var COST_TELEPORT : float = 70.0
@export var COST_JUMP : float = 20.0
@export var COST_SHIELD : float = 50.0
@export var COST_BOOST : float = 20.0

@export_group("Cooldown")
@export var SHARED_COOLDOWN_TIME : float = .8
var current_cooldown : float = 0.0

@export_group("UI")
@export var energy_bar : ProgressBar
@export var cooldown_bar : ProgressBar
var shield_material : StandardMaterial3D

# --- CONFIGURAÇÃO DE HABILIDADES ---
@export_group("Physics Configs")
@export var JUMP_FORCE : float = 12.0
@export var BOOST_IMPULSE : float = 65.0
@export var SHIELD_TIME : float = 2.5

## Tempo (bem rápido) entre os 5 aparecimentos do flicker de fogo do turbo
@export var sequenced_burst_delay : float = 0.08

# --- LÓGICA DE COMBO (TAP + HOLD) ---
var _was_attribute_pressed : bool = false
var tap_count : int = 0
var sequence_timer : float = 0.0
const SEQUENCE_WINDOW : float = 0.45 

var spawn_transform : Transform3D

func _ready():
	spawn_transform = car.global_transform
	current_energy = MAX_ENERGY
	
	shield_material = StandardMaterial3D.new()
	shield_material.albedo_color = Color(0.42, 0.45, 0.45) 
	shield_material.metallic = 0.8 
	shield_material.roughness = 0.1 
	
	if energy_bar:
		energy_bar.max_value = MAX_ENERGY
	if cooldown_bar:
		cooldown_bar.max_value = SHARED_COOLDOWN_TIME

func _process(delta):
	if car.has_method("is_frozen") and car.is_frozen(): 
		return

	var rage = car.get_node_or_null("%RageComponent")
	var regen_mult = rage.get_ability_recovery_mult() if rage else 1.0

	if current_energy < MAX_ENERGY:
		current_energy = move_toward(current_energy, MAX_ENERGY, (REGEN_RATE * regen_mult) * delta)
		
	if current_cooldown > 0:
		current_cooldown -= delta
		
	if sequence_timer > 0:
		sequence_timer -= delta
		
	if energy_bar: energy_bar.value = current_energy
	if cooldown_bar: cooldown_bar.value = current_cooldown
	
	if not car.pode_mover: return

	var attribute_just_pressed = input.is_attribute_pressed and not _was_attribute_pressed
	
	if attribute_just_pressed:
		if sequence_timer <= 0:
			tap_count = 1 
		else:
			tap_count += 1 
		sequence_timer = SEQUENCE_WINDOW 
		
	if not input.is_attribute_pressed and sequence_timer <= 0:
		tap_count = 0

	# --- HABILIDADES DE CÍRCULO (TELEPORT E SHIELD) ---
	if input.is_attribute_pressed and current_cooldown <= 0:
		_checar_combos_habilidade()
		
	# --- HABILIDADES NOVAS (L1, DOUBLE TAP E TIRO PARA TRÁS) ---
	if current_cooldown <= 0:
		var wall_rider = car.get_node_or_null("%WallRideComponent")
		var is_wallriding = wall_rider and wall_rider.get("is_wallriding")
		
		if input.is_jump_pressed:
			if not is_wallriding:
				if current_energy >= COST_JUMP: 
					_execute_jump()
				else: 
					_erro_falta_energia()
					
		elif input.is_turbo_pressed:
			if current_energy >= COST_BOOST: 
				_execute_boost()
			else: 
				_erro_falta_energia()
			input.is_turbo_pressed = false
			
		# =========================================================
		# HABILIDADE DE TIRO PARA TRÁS MOVIDA PARA CÁ!
		# =========================================================
		elif input.is_fire_backwards_pressed:
			_execute_fire_backwards()
			# Desliga a flag para não metralhar sem querer
			input.is_fire_backwards_pressed = false

func _checar_combos_habilidade():
	if input.ability_left and tap_count >= 2:
		if current_energy >= COST_TELEPORT: _execute_teleport()
		else: _erro_falta_energia()
		
	elif input.ability_right:
		if current_energy >= COST_SHIELD: _execute_shield()
		else: _erro_falta_energia()

# --- FUNÇÕES DE EXECUÇÃO ---

func _erro_falta_energia():
	if energy_bar:
		energy_bar.modulate = Color.RED
		var timer = get_tree().create_timer(0.5)
		timer.timeout.connect(func():
			if is_instance_valid(energy_bar):
				var tween = get_tree().create_tween()
				tween.tween_property(energy_bar, "modulate", Color.WHITE, 0.2)
		)

func _execute_jump():
	get_tree().call_group("TutorialUI", "complete_task", "jump")
	current_energy -= COST_JUMP
	var mult = stats.jump_multiplier if stats else 1.0
	car.apply_central_impulse(Vector3.UP * JUMP_FORCE * mult * car.mass)
	_start_cooldown()

func _execute_boost():
	# Aviso para a UI pode continuar global, pois a UI do jogador filtra ou gerencia isso
	get_tree().call_group("TutorialUI", "complete_task", "turbo")
	current_energy -= COST_BOOST
	var mult = stats.speed_multiplier if stats else 1.0
	
	# === EFEITOS DE CÂMERA E SHAKE ===
	car.play_camera_shake("Turbo")
	var cam = car.find_child("Camera3D", true, false)
	if cam and cam.has_method("apply_turbo_kickback"):
		cam.apply_turbo_kickback()
	
	# === 1. LIGA A SEQUÊNCIA DE FOGO LOCALMENTE ===
	# Em vez de gritar para o grupo global, chamamos a função exclusiva deste carro
	_disparar_fogo_local(0.5) 

	get_tree().create_timer(sequenced_burst_delay).timeout.connect(func():
		_disparar_fogo_local(1.0)
	)
	get_tree().create_timer(sequenced_burst_delay * 2).timeout.connect(func():
		_disparar_fogo_local(0.75)
	)
	get_tree().create_timer(sequenced_burst_delay * 3).timeout.connect(func():
		_disparar_fogo_local(0.5)
	)
	get_tree().create_timer(sequenced_burst_delay * 4).timeout.connect(func():
		_disparar_fogo_local(0.25)
	)
	# ===============================================

	# === 2. FÍSICA ===
	car.apply_central_impulse(car.global_transform.basis.z * BOOST_IMPULSE * mult * car.mass)
	_start_cooldown()

# NOVA FUNÇÃO AUXILIAR: Procura o nó de fogo APENAS dentro dos filhos deste carro específico
func _disparar_fogo_local(multiplicador: float):
	# Procura nós com a classe/script "TurboCometFX" que sejam filhos deste veículo
	var meus_efeitos = car.find_children("*", "TurboCometFX", true, false)
	for fx in meus_efeitos:
		if fx.has_method("burst_fire_sequenced"):
			fx.burst_fire_sequenced(multiplicador)

func execute_burnout_boost(charge_multiplier: float = 1.0):
	get_tree().call_group("TutorialUI", "complete_task", "turbo")
	var mult = stats.speed_multiplier if stats else 1.0
	
	# === EFEITOS DE CÂMERA E SHAKE ===
	if car.has_method("play_camera_shake"):
		car.play_camera_shake("Turbo")
		
	var cam = car.find_child("Camera3D", true, false)
	if cam and cam.has_method("apply_turbo_kickback"):
		cam.apply_turbo_kickback()
	
	# === 1. LIGA A SEQUÊNCIA DE FOGO LOCALMENTE ===
	_disparar_fogo_local(0.5) 
	get_tree().create_timer(sequenced_burst_delay).timeout.connect(func(): _disparar_fogo_local(1.0))
	get_tree().create_timer(sequenced_burst_delay * 2).timeout.connect(func(): _disparar_fogo_local(0.75))
	get_tree().create_timer(sequenced_burst_delay * 3).timeout.connect(func(): _disparar_fogo_local(0.5))
	get_tree().create_timer(sequenced_burst_delay * 4).timeout.connect(func(): _disparar_fogo_local(0.25))

	# === 2. FÍSICA APLICADA COM O MULTIPLICADOR DO ZERINHO ===
	var final_boost = BOOST_IMPULSE * mult * charge_multiplier
	car.apply_central_impulse(car.global_transform.basis.z * final_boost * car.mass)
	_start_cooldown()

func _execute_teleport():
	var teleport_markers = get_tree().get_nodes_in_group("AbilityTeleport")
	
	if teleport_markers.is_empty():
		return
		
	var closest_marker : Node3D = null
	var closest_dist = INF
	
	for marker in teleport_markers:
		var dist = car.global_position.distance_to(marker.global_position)
		if dist >= 80.0 and dist < closest_dist:
			closest_dist = dist
			closest_marker = marker
			
	if closest_marker:
		current_energy -= COST_TELEPORT
		car.global_transform = closest_marker.global_transform
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		
		var trick_manager = car.get_node_or_null("%TrickManager")
		if trick_manager and trick_manager.has_method("reset_trick"):
			trick_manager.reset_trick()
			print("[Abilities] Teleporte ativado! Pontos de manobra cancelados.")
			
		_start_cooldown()
	else:
		_erro_falta_energia()

func _execute_shield():
	current_energy -= COST_SHIELD
	if stats: stats.is_invulnerable = true
	
	_set_car_silver_effect(true)
	_start_cooldown()
	
	get_tree().create_timer(SHIELD_TIME).timeout.connect(func():
		if stats: stats.is_invulnerable = false
		_set_car_silver_effect(false)
	)

# =========================================================
# NOVA FUNÇÃO DE EXECUÇÃO: TIRO PARA TRÁS
# Se quiser cobrar energia por isso no futuro, é só adicionar aqui!
# =========================================================
func _execute_fire_backwards():
	if is_instance_valid(weapons):
		weapons.fire_special_weapon(true)
		# Se quiser que o tiro para trás ative o cooldown global das habilidades, descomente a linha abaixo:
		# _start_cooldown()

func _set_car_silver_effect(active: bool):
	var all_meshes = car.find_children("*", "MeshInstance3D", true)
	for mesh in all_meshes:
		if active: mesh.material_override = shield_material
		else: mesh.material_override = null

func _start_cooldown():
	current_cooldown = SHARED_COOLDOWN_TIME
