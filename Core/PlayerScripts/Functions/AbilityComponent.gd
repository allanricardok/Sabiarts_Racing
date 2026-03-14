# AbilityComponent.gd
extends Node
class_name AbilityComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var stats = %StatsComponent

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
@export var SHARED_COOLDOWN_TIME : float = 1
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

# --- LÓGICA DE COMBO (TAP + HOLD) ---
var _was_attribute_pressed : bool = false
var tap_count : int = 0
var sequence_timer : float = 0.0
const SEQUENCE_WINDOW : float = 0.45 # Exatos 450ms, igual ao seu TrickBuilder!

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
	# 1. Recuperação e Cooldown
	if current_energy < MAX_ENERGY:
		current_energy = move_toward(current_energy, MAX_ENERGY, REGEN_RATE * delta)
	if current_cooldown > 0:
		current_cooldown -= delta
		
	# 2. Timer da janela de Combo
	if sequence_timer > 0:
		sequence_timer -= delta
		
	# --- ATUALIZAÇÃO DAS BARRAS ---
	if energy_bar: energy_bar.value = current_energy
	if cooldown_bar: cooldown_bar.value = current_cooldown
	
	if not car.pode_mover: return

	# --- 3. LÓGICA DE TAP (TOQUES) ---
	var attribute_just_pressed = input.is_attribute_pressed and not _was_attribute_pressed
	
	if attribute_just_pressed:
		if sequence_timer <= 0:
			tap_count = 1 # Primeiro toque
		else:
			tap_count += 1 # Segundo toque (ou mais)
		sequence_timer = SEQUENCE_WINDOW # Renova a janela de tempo
		
	# Se o jogador soltou o botão e o tempo expirou, zera a contagem
	if not input.is_attribute_pressed and sequence_timer <= 0:
		tap_count = 0

	# --- 4. EXECUÇÃO ENQUANTO MANTÉM PRESSIONADO ---
	if input.is_attribute_pressed and current_cooldown <= 0:
		_checar_combos_habilidade()

	_was_attribute_pressed = input.is_attribute_pressed

func _checar_combos_habilidade():
	# TELEPORTE: Exige tap_count >= 2 (Toque duplo + Segurar) e Esquerda!
	if input.ability_left and tap_count >= 2:
		if current_energy >= COST_TELEPORT: _execute_teleport()
		else: _erro_falta_energia()
		
	# As outras podem ser ativadas segurando no primeiro toque normal
	elif input.ability_up:
		if current_energy >= COST_BOOST: _execute_boost()
		else: _erro_falta_energia()
		
	elif input.ability_down:
		if current_energy >= COST_JUMP: _execute_jump()
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
	current_energy -= COST_JUMP
	var mult = stats.jump_multiplier if stats else 1.0
	car.apply_central_impulse(Vector3.UP * JUMP_FORCE * mult * car.mass)
	_start_cooldown()

func _execute_boost():
	current_energy -= COST_BOOST
	var mult = stats.speed_multiplier if stats else 1.0
	car.apply_central_impulse(car.global_transform.basis.z * BOOST_IMPULSE * mult * car.mass)
	_start_cooldown()

func _execute_teleport():
	# Puxa os pontos de teleporte e acha o mais próximo que seja válido (> 20m)
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

func _set_car_silver_effect(active: bool):
	var all_meshes = car.find_children("*", "MeshInstance3D", true)
	for mesh in all_meshes:
		if active: mesh.material_override = shield_material
		else: mesh.material_override = null

func _start_cooldown():
	current_cooldown = SHARED_COOLDOWN_TIME
