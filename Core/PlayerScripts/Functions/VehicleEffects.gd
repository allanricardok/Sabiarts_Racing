# VehicleEffects.gd
extends Node
class_name VehicleEffects

# --- STATUS: CONGELAMENTO ---
var is_frozen: bool = false
var freeze_timer: float = 0.0

var car : BaseVehicle
var ice_material : StandardMaterial3D # O material visual do gelo

func _ready():
	# 1. Tenta pegar o pai imediato ou a raiz da cena
	car = get_parent() as BaseVehicle
	if car == null and owner is BaseVehicle:
		car = owner as BaseVehicle
		
	if car == null:
		push_error("[VehicleEffects] Erro fatal: O nó não conseguiu encontrar o BaseVehicle!")
		
	# --- CRIA O MATERIAL DE GELO ---
	ice_material = StandardMaterial3D.new()
	ice_material.albedo_color = Color(0.2, 0.6, 1.0, 0.7) # Azul claro semi-transparente
	ice_material.roughness = 0.1 # Bem liso/brilhante
	ice_material.metallic = 0.3
	ice_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _physics_process(delta):
	if not is_instance_valid(car): return
	
	if is_frozen:
		_processar_fisica_congelada(delta)
		
		# Conta o tempo para derreter
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
		
		# --- APLICA A CAPA DE GELO NO VISUAL ---
		var all_meshes = car.find_children("*", "MeshInstance3D", true)
		for mesh in all_meshes:
			mesh.material_overlay = ice_material
		
		print("[VehicleEffects] ", car.name, " CONGELOU!")

func _processar_fisica_congelada(delta):
	# --- FRICÇÃO PESADA (Damping Customizado) ---
	# Em vez de sobrescrever a velocidade (que esmaga a suspensão), 
	# nós pegamos a velocidade horizontal e aplicamos uma força contrária.
	
	var vel = car.linear_velocity
	var horiz_vel = Vector3(vel.x, 0, vel.z)
	
	if horiz_vel.length() > 0.1:
		# Multiplicador do freio (Ajuste para mais ou menos escorregadio)
		var forca_atrito = 5.0 
		
		# Cria uma força no sentido oposto ao movimento
		var forca_frenagem = -horiz_vel * forca_atrito
		
		# Aplica a força no centro de massa (não amassa as molas)
		car.apply_central_force(forca_frenagem * car.mass)
	
	# Zera os comandos do motorista
	car.engine_force = 0
	car.brake = 100

func _descongelar():
	is_frozen = false
	freeze_timer = 0.0
	car.brake = 0
	
	# --- REMOVE A CAPA DE GELO ---
	var all_meshes = car.find_children("*", "MeshInstance3D", true)
	for mesh in all_meshes:
		mesh.material_overlay = null
		
	print("[VehicleEffects] ", car.name, " DESCONGELOU!")
