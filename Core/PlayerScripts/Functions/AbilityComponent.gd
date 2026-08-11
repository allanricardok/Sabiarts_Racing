extends Node
class_name AbilityComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var stats = %StatsComponent
@onready var weapons = %WeaponManager 

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

@export var sequenced_burst_delay : float = 0.08

# --- LÓGICA DE COMBO (TAP + HOLD) ---
var _was_attribute_pressed : bool = false
var tap_count : int = 0
var sequence_timer : float = 0.0
const SEQUENCE_WINDOW : float = 0.45 

var spawn_transform : Transform3D

# ==============================================================================
# OTIMIZAÇÃO: MEMÓRIA CACHE
# ==============================================================================
var _rage_component: Node
var _wall_ride_component: Node
var _trick_manager: Node
var _camera_3d: Node
var _turbo_fx_nodes: Array[Node] = []
var _car_meshes: Array[MeshInstance3D] = []

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

	# --- PREENCHE OS CACHES NA INICIALIZAÇÃO ---
	_rage_component = car.get_node_or_null("%RageComponent")
	_wall_ride_component = car.get_node_or_null("%WallRideComponent")
	_trick_manager = car.get_node_or_null("%TrickManager")
	_camera_3d = car.find_child("Camera3D", true, false)
	
	var turbos = car.find_children("*", "TurboCometFX", true, false)
	for t in turbos: _turbo_fx_nodes.append(t)
		
	var meshes = car.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		if m is MeshInstance3D:
			_car_meshes.append(m)

func _process(delta):
	if car.has_method("is_frozen") and car.is_frozen(): 
		return

	# OTIMIZAÇÃO: Busca em cache!
	var regen_mult = _rage_component.get_ability_recovery_mult() if is_instance_valid(_rage_component) else 1.0

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

	if input.is_attribute_pressed and current_cooldown <= 0:
		_checar_combos_habilidade()
		
	if current_cooldown <= 0:
		# OTIMIZAÇÃO: Busca em cache!
		var is_wallriding = is_instance_valid(_wall_ride_component) and _wall_ride_component.get("is_wallriding")
		
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
			
		elif input.is_fire_backwards_pressed:
			_execute_fire_backwards()
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
	get_tree().call_group("TutorialUI", "complete_task", "turbo")
	current_energy -= COST_BOOST
	var mult = stats.speed_multiplier if stats else 1.0
	
	car.play_camera_shake("Turbo")
	if is_instance_valid(_camera_3d) and _camera_3d.has_method("apply_turbo_kickback"):
		_camera_3d.apply_turbo_kickback()
	
	_disparar_fogo_local(0.5) 
	get_tree().create_timer(sequenced_burst_delay).timeout.connect(func(): _disparar_fogo_local(1.0))
	get_tree().create_timer(sequenced_burst_delay * 2).timeout.connect(func(): _disparar_fogo_local(0.75))
	get_tree().create_timer(sequenced_burst_delay * 3).timeout.connect(func(): _disparar_fogo_local(0.5))
	get_tree().create_timer(sequenced_burst_delay * 4).timeout.connect(func(): _disparar_fogo_local(0.25))

	car.apply_central_impulse(car.global_transform.basis.z * BOOST_IMPULSE * mult * car.mass)
	_start_cooldown()

func _disparar_fogo_local(multiplicador: float):
	# OTIMIZAÇÃO: Usa o array já salvo na memória em vez de procurar na árvore!
	for fx in _turbo_fx_nodes:
		if is_instance_valid(fx) and fx.has_method("burst_fire_sequenced"):
			fx.burst_fire_sequenced(multiplicador)

func execute_burnout_boost(charge_multiplier: float = 1.0):
	get_tree().call_group("TutorialUI", "complete_task", "turbo")
	var mult = stats.speed_multiplier if stats else 1.0
	
	if car.has_method("play_camera_shake"):
		car.play_camera_shake("Turbo")
		
	if is_instance_valid(_camera_3d) and _camera_3d.has_method("apply_turbo_kickback"):
		_camera_3d.apply_turbo_kickback()
	
	_disparar_fogo_local(0.5) 
	get_tree().create_timer(sequenced_burst_delay).timeout.connect(func(): _disparar_fogo_local(1.0))
	get_tree().create_timer(sequenced_burst_delay * 2).timeout.connect(func(): _disparar_fogo_local(0.75))
	get_tree().create_timer(sequenced_burst_delay * 3).timeout.connect(func(): _disparar_fogo_local(0.5))
	get_tree().create_timer(sequenced_burst_delay * 4).timeout.connect(func(): _disparar_fogo_local(0.25))

	var final_boost = BOOST_IMPULSE * mult * charge_multiplier
	car.apply_central_impulse(car.global_transform.basis.z * final_boost * car.mass)
	_start_cooldown()

func _execute_teleport():
	var teleport_markers = get_tree().get_nodes_in_group("AbilityTeleport")
	
	if teleport_markers.is_empty():
		return
		
	var closest_marker : Node3D = null
	var closest_dist_sq = INF
	
	for marker in teleport_markers:
		# OTIMIZAÇÃO: Substituição por distance_squared_to (80.0 ^ 2 = 6400.0)
		var dist_sq = car.global_position.distance_squared_to(marker.global_position)
		if dist_sq >= 6400.0 and dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			closest_marker = marker
			
	if closest_marker:
		current_energy -= COST_TELEPORT
		car.global_transform = closest_marker.global_transform
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		
		# OTIMIZAÇÃO: Usando a referência em cache
		if is_instance_valid(_trick_manager) and _trick_manager.has_method("reset_trick"):
			_trick_manager.reset_trick()
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

func _execute_fire_backwards():
	if is_instance_valid(weapons):
		var active_weapon = weapons.get_active_special()
		if active_weapon:
			if weapons.shooter.try_fire_special(active_weapon, true):
				active_weapon.ammo -= 1
				if active_weapon.ammo <= 0: 
					weapons._remove_current_weapon()
				weapons._atualizar_interface()

func _set_car_silver_effect(active: bool):
	# OTIMIZAÇÃO: Usa o array já salvo na memória em vez de procurar na árvore!
	for mesh in _car_meshes:
		if is_instance_valid(mesh):
			if active: mesh.material_override = shield_material
			else: mesh.material_override = null

func _start_cooldown():
	current_cooldown = SHARED_COOLDOWN_TIME
