extends Node
class_name WallRideOrchestrator

@onready var car = owner as VehicleBody3D
@onready var input = car.get_node_or_null("%InputComponent")
@onready var trick_manager = car.get_node_or_null("%TrickManager")
@onready var air_move = car.get_node_or_null("%AirMovementComponent")

# OTIMIZAÇÃO: Cache do AbilityComponent para evitar buscas na árvore durante a física
@onready var ability_component = car.get_node_or_null("%AbilityComponent")

# Nossos submódulos especializados
var scanner : WallScannerComponent
var mechanics : WallRideMechanics

# =================================================================
# VARIÁVEIS CENTRALIZADAS
# =================================================================
@export_group("Configurações do Wallride")
@export_flags_3d_physics var wall_collision_mask : int = 1 
@export var max_wall_distance : float = 3.5 
@export var min_speed_kmh : float = 1.0
@export var min_ground_height : float = 1.0

@export_group("Física Avançada")
@export var anti_gravity_start : float = 3.0 
@export var anti_gravity_end : float = 1.5 
@export var anti_gravity_decay_time : float = 5.0 
@export var wall_target_distance : float = 0.3
@export var wall_magnet_speed : float = 8.0
@export var wall_forward_boost : float = 1.0 
@export var wall_turn_speed : float = 3.0 
@export var jump_up_force : float = 12.0 

@export_group("Balanceamento de Spam")
@export var wall_jump_decay_per_jump : float = 0.20
@export var min_jump_force_multiplier : float = 0.30

@export_group("Pontuação")
@export var validation_time : float = 0.3 

# --- ESTADO DO SISTEMA ---
var is_wallriding : bool = false
var is_exiting_wallride : bool = false 
var exit_wallride_timer : float = 0.0

var current_wall_normal : Vector3 = Vector3.ZERO
var time_in_wallride : float = 0.0
var point_tick_timer : float = 0.0
var is_validated : bool = false

var wall_lost_timer : float = 0.0
var wallride_cooldown : float = 0.0 
var time_since_last_wallride : float = 999.0
var wall_jump_combo_count : int = 0

func _ready():
	scanner = WallScannerComponent.new()
	scanner.name = "WallScanner"
	scanner.car = car 
	scanner.wall_collision_mask = wall_collision_mask
	scanner.max_wall_distance = max_wall_distance
	scanner.min_ground_height = min_ground_height
	add_child(scanner)
	
	mechanics = WallRideMechanics.new()
	mechanics.name = "WallMechanics"
	mechanics.car = car 
	mechanics.anti_gravity_start = anti_gravity_start
	mechanics.anti_gravity_end = anti_gravity_end
	mechanics.anti_gravity_decay_time = anti_gravity_decay_time
	mechanics.wall_target_distance = wall_target_distance
	mechanics.wall_magnet_speed = wall_magnet_speed
	mechanics.wall_forward_boost = wall_forward_boost
	mechanics.wall_turn_speed = wall_turn_speed
	mechanics.jump_up_force = jump_up_force
	add_child(mechanics)

func _physics_process(delta):
	if not is_instance_valid(car) or not car.pode_mover: return
	if not input or not trick_manager or not air_move: return

	if wallride_cooldown > 0:
		wallride_cooldown -= delta

	if is_wallriding:
		time_since_last_wallride = 0.0 
		_process_wallride_active(delta)
	else:
		time_since_last_wallride += delta 
		
		if input.is_stunt_pressed:
			_check_wallride_entry()
			
		if is_exiting_wallride and not is_wallriding:
			_process_wallride_exit(delta)

func _check_wallride_entry() -> bool:
	if wallride_cooldown > 0: return false
	if air_move.get_grounded_wheels_count() >= 3: return false
	
	var min_speed_mps = min_speed_kmh / 3.6
	if car.linear_velocity.length_squared() < (min_speed_mps * min_speed_mps): 
		return false
		
	var is_transfer_attempt = (time_since_last_wallride < 1.5)
	
	if is_transfer_attempt and is_instance_valid(ability_component):
		if "current_cooldown" in ability_component and ability_component.current_cooldown > 0.0:
			return false
		if "current_energy" in ability_component and "COST_JUMP" in ability_component:
			if ability_component.current_energy < ability_component.COST_JUMP:
				if ability_component.has_method("_erro_falta_energia"): ability_component._erro_falta_energia()
				return false

	var wall_info = scanner.find_best_wall_360()
	if wall_info.has("normal"):
		# ====================================================================
		# NOVA REGRA: Filtro de Inclinação da Parede
		# ====================================================================
		var angulo_radianos = acos(wall_info.normal.dot(Vector3.UP))
		var angulo_graus = rad_to_deg(angulo_radianos)
		
		# Só aceita se a inclinação for entre 75º e 105º (Parede quase reta)
		if angulo_graus >= 75.0 and angulo_graus <= 105.0:
			var dist_ground = scanner.get_ground_distance(Vector3.ZERO)
			if dist_ground > scanner.min_ground_height:
				
				if is_transfer_attempt and is_instance_valid(ability_component) and "current_energy" in ability_component:
					ability_component.current_energy -= 1
					if ability_component.has_method("_start_cooldown"): ability_component._start_cooldown()
					
				_start_wallride(wall_info.normal)
				return true
			
	return false

func _start_wallride(normal: Vector3):
	var is_transfer = is_wallriding or (time_since_last_wallride < 1.5)
	
	is_wallriding = true
	is_exiting_wallride = false
	current_wall_normal = normal
	
	if air_move.is_doing_stunt and is_instance_valid(air_move.stunt_processor):
		air_move.stunt_processor.apply_stunt_brake("Wallride interceptou manobra.")
	
	air_move.is_doing_stunt = false
	
	if not is_transfer:
		time_in_wallride = 0.0
		point_tick_timer = 0.0
		wall_lost_timer = 0.0
		is_validated = false 
		wall_jump_combo_count = 0 
	else:
		trick_manager.add_external_action("Wall Transfer", 25, TrickManager.COLOR_SPECIAL)

func _process_wallride_active(delta):
	time_in_wallride += delta

	if not is_validated and time_in_wallride >= validation_time:
		is_validated = true
		trick_manager.add_external_action("Wallride In", 20, TrickManager.COLOR_SPECIAL)

	if not input.is_stunt_pressed:
		_stop_wallride("Botão Triângulo solto.")
		return

	# OTIMIZAÇÃO: Usando length_squared para evitar raiz quadrada na checagem de velocidade
	var min_speed_mps = min_speed_kmh / 3.6
	if car.linear_velocity.length_squared() < (min_speed_mps * min_speed_mps):
		_stop_wallride("Velocidade baixa.")
		return

	var dist_ground = scanner.get_ground_distance(current_wall_normal * 0.1)
	if dist_ground <= scanner.min_ground_height:
		_stop_wallride("Atingiu chão.")
		return

	var ray_start = car.global_position + (current_wall_normal * 1.5)
	var ray_dir = -current_wall_normal * (scanner.max_wall_distance * 2.0)
	var result = scanner.shoot_ray_ignoring_holos(ray_start, ray_start + ray_dir)

	var target_vel_wall = 0.0

	if result:
		# ====================================================================
		# NOVA REGRA (Sua Lógica Aplicada): O raio de manutenção bateu em algo.
		# É uma parede ou o carro escorregou e o raio atingiu o chão/rampa?
		# ====================================================================
		var angulo_rad = acos(result.normal.dot(Vector3.UP))
		var angulo_graus = rad_to_deg(angulo_rad)
		
		if angulo_graus < 75.0 or angulo_graus > 105.0:
			_stop_wallride("O raio de manutenção atingiu um chão/rampa.")
			return
			
		# Se passou pela validação acima, é uma parede de verdade!
		current_wall_normal = result.normal
		wall_lost_timer = 0.0 
		var dist_to_wall = car.global_position.distance_to(result.position)
		var error = dist_to_wall - mechanics.wall_target_distance
		target_vel_wall = clamp(-error * mechanics.wall_magnet_speed, -15.0, 15.0)
	else:
		wall_lost_timer += delta
		if wall_lost_timer > 0.15: 
			_stop_wallride("Parede perdida (Timeout).")
			return

	var current_vel_wall = car.linear_velocity.dot(current_wall_normal)
	car.linear_velocity -= current_wall_normal * current_vel_wall
	car.linear_velocity += current_wall_normal * target_vel_wall

	mechanics.apply_wall_physics(delta, current_wall_normal, time_in_wallride, input.throttle, input.steering)

	if input.is_jump_pressed:
		_attempt_wall_jump()
		return

	if is_validated:
		point_tick_timer += delta
		if point_tick_timer >= 0.25: 
			point_tick_timer -= 0.25
			trick_manager.add_external_action("Wallride", 10, TrickManager.COLOR_SPECIAL)

func _attempt_wall_jump():
	if is_instance_valid(ability_component) and "current_cooldown" in ability_component and ability_component.current_cooldown > 0.0:
		return
		
	if is_instance_valid(ability_component) and "current_energy" in ability_component and "COST_JUMP" in ability_component:
		if ability_component.current_energy >= ability_component.COST_JUMP:
			ability_component.current_energy -= ability_component.COST_JUMP
			if ability_component.has_method("_start_cooldown"): ability_component._start_cooldown()
		else:
			if ability_component.has_method("_erro_falta_energia"): ability_component._erro_falta_energia()
			return
		
	var current_decay_mult = max(min_jump_force_multiplier, 1.0 - (wall_jump_combo_count * wall_jump_decay_per_jump))
	var applied_jump_force = mechanics.jump_up_force * current_decay_mult
	
	wall_jump_combo_count += 1
	mechanics.apply_wall_jump(current_wall_normal, applied_jump_force)
	
	trick_manager.add_external_action("Wall Jump", 10, TrickManager.COLOR_SPECIAL)
	_stop_wallride("Wall-Jump executado!")

func _stop_wallride(reason: String = ""):
	if not is_wallriding: return
		
	is_wallriding = false
	time_since_last_wallride = 0.0 
	
	if is_instance_valid(air_move):
		if reason != "TRANSITION_JUMP" and reason != "Wall-Jump executado!":
			if air_move.is_doing_stunt and is_instance_valid(air_move.stunt_processor):
				air_move.stunt_processor.apply_stunt_brake("Limpando rotação após saída do muro.")
			car.angular_velocity = Vector3.ZERO
	
	if reason == "TRANSITION_JUMP" or reason == "Wall-Jump executado!":
		is_exiting_wallride = false
		exit_wallride_timer = 0.0
		wallride_cooldown = 0.25 
	else:
		is_exiting_wallride = true
		exit_wallride_timer = 0.5 
		wallride_cooldown = 0.0 

func _process_wallride_exit(delta):
	if is_instance_valid(air_move) and air_move.is_doing_stunt:
		is_exiting_wallride = false
		return

	exit_wallride_timer -= delta
	
	if exit_wallride_timer <= 0:
		is_exiting_wallride = false
		return

	var z_axis = car.global_transform.basis.z
	z_axis.y = 0.0 
	if z_axis.length_squared() < 0.01: 
		z_axis = car.global_transform.basis.x.cross(Vector3.UP)
	z_axis = z_axis.normalized()
	
	var y_axis = Vector3.UP
	var x_axis = y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized() 
	
	var upright_basis = Basis(x_axis, y_axis, z_axis).orthonormalized()
	var clean_current_basis = car.global_transform.basis.orthonormalized()
	
	car.global_transform.basis = clean_current_basis.slerp(upright_basis, delta * 8.0)
	car.angular_velocity = car.angular_velocity.lerp(Vector3.ZERO, delta * 5.0)

# =========================================================
# INTEGRAÇÃO COM TRICK MANAGER (ESCUDO DE COMBO)
# =========================================================
func has_combo_shield() -> bool:
	var grace_period = (time_since_last_wallride < 0.5)
	return is_wallriding or is_exiting_wallride or grace_period
