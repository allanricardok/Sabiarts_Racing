extends Node
class_name VehicleEffects

# --- STATUS: CONGELAMENTO ---
var is_frozen: bool = false
var freeze_timer: float = 0.0

var car : BaseVehicle
var ice_material : StandardMaterial3D 

# ==============================================================================
# OTIMIZAÇÃO: MEMÓRIA CACHE
# ==============================================================================
var _car_meshes: Array[MeshInstance3D] = []

func _ready():
	car = get_parent() as BaseVehicle
	if car == null and owner is BaseVehicle:
		car = owner as BaseVehicle
		
	if car == null:
		push_error("[VehicleEffects] Erro fatal: O nó não conseguiu encontrar o BaseVehicle!")
		return
		
	# --- CRIA O MATERIAL DE GELO ---
	ice_material = StandardMaterial3D.new()
	ice_material.albedo_color = Color(0.2, 0.6, 1.0, 0.7) 
	ice_material.roughness = 0.1 
	ice_material.metallic = 0.3
	ice_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# OTIMIZAÇÃO: Guarda as malhas do carro na memória uma única vez
	var all_meshes = car.find_children("*", "MeshInstance3D", true, false)
	for mesh in all_meshes:
		if mesh is MeshInstance3D:
			_car_meshes.append(mesh)

func _physics_process(delta):
	if not is_instance_valid(car): return
	
	if is_frozen:
		_processar_fisica_congelada(delta)
		
		freeze_timer -= delta
		if freeze_timer <= 0:
			_descongelar()

func aplicar_congelamento(tempo: float):
	freeze_timer = tempo
	
	if not is_frozen:
		is_frozen = true
		
		# --- IMPACTO INICIAL DO GELO ---
		car.linear_velocity.x *= 0.5
		car.linear_velocity.z *= 0.5
		
		# OTIMIZAÇÃO: Uso direto da memória, sem procurar na árvore
		for mesh in _car_meshes:
			if is_instance_valid(mesh):
				mesh.material_overlay = ice_material
		
		print("[VehicleEffects] ", car.name, " CONGELOU!")

func _processar_fisica_congelada(delta):
	var vel = car.linear_velocity
	var horiz_vel = Vector3(vel.x, 0, vel.z)
	
	# OTIMIZAÇÃO: length_squared() poupa o cálculo da raiz quadrada
	if horiz_vel.length_squared() > 0.01:
		var forca_atrito = 5.0 
		var forca_frenagem = -horiz_vel * forca_atrito
		
		car.apply_central_force(forca_frenagem * car.mass)
	
	car.engine_force = 0
	car.brake = 100

func _descongelar():
	is_frozen = false
	freeze_timer = 0.0
	car.brake = 0
	
	# OTIMIZAÇÃO: Uso direto da memória
	for mesh in _car_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
		
	print("[VehicleEffects] ", car.name, " DESCONGELOU!")
