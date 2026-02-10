# AbilityComponent.gd
extends Node
class_name AbilityComponent

@onready var car = owner as VehicleBody3D
@onready var input = %InputComponent
@onready var stats = %StatsComponent

@export var SHARED_COOLDOWN_TIME : float = 1.0
var current_cooldown : float = 0.0

# --- CONFIGURAÇÃO DE HABILIDADES ---
@export_group("Configs")
@export var JUMP_FORCE : float = 12.0
@export var BOOST_IMPULSE : float = 65.0
@export var TELEPORT_DIST : float = 15.0
@export var SHIELD_TIME : float = 2.5

# AbilityComponent.gd
func _process(delta):
	if current_cooldown > 0:
		current_cooldown -= delta
	
	if not car.pode_mover: return

	# Só entra na lógica se o botão ACTION estiver pressionado
	if input.is_action_pressed and current_cooldown <= 0:
		_checar_combos_digitais()

func _checar_combos_digitais():
	# Cima -> PULO
	if input.ability_up:
		_execute_jump()
	
	# Baixo -> BOOST
	elif input.ability_down:
		_execute_boost()
	
	# Esquerda -> TELEPORT
	elif input.ability_left:
		_execute_teleport()
	
	# Direita -> SHIELD
	elif input.ability_right:
		_execute_shield()

func _checar_combos_direcionais():
	# Cima (Throttle > 0) -> PULO
	if input.throttle > 0.5:
		_execute_jump()
	
	# Baixo (Throttle < 0) -> BOOST
	elif input.throttle < -0.5:
		_execute_boost()
	
	# Esquerda (Steering > 0 no seu InputComponent) -> TELEPORT
	elif input.steering > 0.5:
		_execute_teleport()
	
	# Direita (Steering < 0) -> SHIELD
	elif input.steering < -0.5:
		_execute_shield()

# --- EXECUÇÃO DAS FUNÇÕES ---

func _execute_jump():
	print("HABILIDADE: Pulo Vertical")
	var mult = stats.jump_multiplier if stats else 1.0
	car.apply_central_impulse(Vector3.UP * JUMP_FORCE * mult * car.mass)
	_start_cooldown()

func _execute_boost():
	print("HABILIDADE: Turbo")
	var mult = stats.speed_multiplier if stats else 1.0
	car.apply_central_impulse(car.global_transform.basis.z * BOOST_IMPULSE * mult * car.mass)
	_start_cooldown()

func _execute_teleport():
	print("HABILIDADE: Teleport")
	car.global_position += car.global_transform.basis.z * TELEPORT_DIST
	car.global_position.y += 0.5 # Segurança para não prender no chão
	_start_cooldown()

func _execute_shield():
	print("HABILIDADE: Shield")
	if stats: stats.is_invulnerable = true
	# Se tiver um visual de escudo: %ShieldVisual.show()
	_start_cooldown()
	get_tree().create_timer(SHIELD_TIME).timeout.connect(func():
		if stats: stats.is_invulnerable = false
		# %ShieldVisual.hide()
	)

func _start_cooldown():
	current_cooldown = SHARED_COOLDOWN_TIME
