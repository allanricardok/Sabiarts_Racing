extends Node
class_name BrakeLightManager

@export_group("Referências")
@export var left_taillight: MeshInstance3D
@export var right_taillight: MeshInstance3D

@export_group("Cores e Brilho")
@export var color_idle: Color = Color("8b0000") 
@export var energy_idle: float = 0.0

@export var color_brake: Color = Color("ff0000") 
@export var energy_brake: float = 20.0

# OTIMIZAÇÃO: Um único material compartilhado entre as duas lanternas DESSA instância do carro
var _car_mat: StandardMaterial3D

@onready var car = owner as VehicleBody3D
@onready var input = car.get_node_or_null("%InputComponent")

# ESTADOS DE OTIMIZAÇÃO
var _was_braking: bool = false
var _is_sleeping: bool = false

func _ready():
	if left_taillight or right_taillight:
		_setup_shared_material()

func _setup_shared_material():
	var base_mat = null
	
	# Pega o material original de qualquer uma das lanternas como base
	if left_taillight and left_taillight.get_active_material(0):
		base_mat = left_taillight.get_active_material(0)
	elif right_taillight and right_taillight.get_active_material(0):
		base_mat = right_taillight.get_active_material(0)
	
	if base_mat:
		_car_mat = base_mat.duplicate()
	else:
		# ====================================================================
		# OTIMIZAÇÃO: Fallback seguro via Cache para evitar a engasgada 
		# de compilação caso o artista importe o carro sem material!
		# ====================================================================
		var cached_mat = MaterialCache.get_mat("BrakeLightBase")
		if cached_mat:
			_car_mat = cached_mat.duplicate()
		else:
			_car_mat = StandardMaterial3D.new()
		
	# BLINDAGEM CONTRA O BUG DA LUZ PRETA: Força a exclusividade na memória
	_car_mat.resource_local_to_scene = true
	_car_mat.emission_enabled = true
	
	# Aplica o MESMO material para as duas lanternas. O Godot desenha as duas de uma vez só!
	if left_taillight:
		left_taillight.set_surface_override_material(0, _car_mat)
	if right_taillight:
		right_taillight.set_surface_override_material(0, _car_mat)

func _process(delta):
	if not is_instance_valid(car) or not is_instance_valid(input): 
		set_process(false)
		return
	
	var is_braking = false
	
	if "is_braking" in input and input.is_braking:
		is_braking = true
	elif "throttle" in input and input.throttle < -0.1:
		is_braking = true
		
	var target_color = color_brake if is_braking else color_idle
	var target_energy = energy_brake if is_braking else energy_idle
	
	# OTIMIZAÇÃO: Acorda o script instantaneamente se o estado do freio mudou
	if is_braking != _was_braking:
		_was_braking = is_braking
		_is_sleeping = false
		
	# Se a luz já chegou no limite, não faz nada neste frame!
	if _is_sleeping:
		return
	
	var lerp_speed = 18.0 * delta
	
	if is_instance_valid(_car_mat):
		_car_mat.albedo_color = _car_mat.albedo_color.lerp(target_color, lerp_speed)
		_car_mat.emission = _car_mat.emission.lerp(target_color, lerp_speed)
		_car_mat.emission_energy_multiplier = lerp(_car_mat.emission_energy_multiplier, target_energy, lerp_speed)
		
		# Verifica se já está perto o suficiente do alvo para dormir
		if abs(_car_mat.emission_energy_multiplier - target_energy) < 0.05:
			# Crava no valor exato para evitar valores quebrados invisíveis e manda dormir
			_car_mat.albedo_color = target_color
			_car_mat.emission = target_color
			_car_mat.emission_energy_multiplier = target_energy
			_is_sleeping = true
