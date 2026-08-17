extends Node
class_name VehicleEffects

# --- STATUS: CONGELAMENTO ---
var is_frozen: bool = false
var freeze_timer: float = 0.0

# --- STATUS: PERDA DE GRIP (NOVO) ---
var is_grip_reduced: bool = false
var grip_loss_timer: float = 0.0

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
		
	# --- OTIMIZAÇÃO: BUSCA O MATERIAL PRONTO NO CACHE ---
	ice_material = MaterialCache.get_mat("VehicleIce")

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
			
	# ====================================================================
	# ATUALIZAÇÃO DO STATUS DE GRIP (PNEUS ESCORREGADIOS)
	# ====================================================================
	if is_grip_reduced:
		grip_loss_timer -= delta
		if grip_loss_timer <= 0:
			is_grip_reduced = false
			_alterar_grip_geral(2.0) # Tempo esgotou, devolve os 2 pontos de grip
			print("[VehicleEffects] ", car.name, " RECUPEROU A TRAÇÃO!")

func aplicar_congelamento(tempo: float):
	freeze_timer = tempo
	
	if not is_frozen:
		is_frozen = true
		
		# --- IMPACTO INICIAL DO GELO ---
		car.linear_velocity.x *= 0.5
		car.linear_velocity.z *= 0.5
		
		for mesh in _car_meshes:
			if is_instance_valid(mesh):
				mesh.material_overlay = ice_material
		
		print("[VehicleEffects] ", car.name, " CONGELOU!")

func _processar_fisica_congelada(delta):
	var vel = car.linear_velocity
	var horiz_vel = Vector3(vel.x, 0, vel.z)
	
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
	
	for mesh in _car_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
		
	print("[VehicleEffects] ", car.name, " DESCONGELOU!")

# ====================================================================
# NOVO: SISTEMA DE PERDA DE GRIP + IMPACTO FÍSICO (DRIFT E TRANCO)
# ====================================================================
func aplicar_perda_de_grip(tempo: float):
	grip_loss_timer = tempo
	
	if not is_grip_reduced:
		is_grip_reduced = true
		
		# 1. Tira 2 pontos de grip de TODAS as rodas (Dianteiras e Traseiras)
		_alterar_grip_geral(-2.0)
		
		# 2. Aplica peso na traseira para "amassar" a suspensão
		# Pegamos um ponto que fica 1.5 metros para trás do centro do carro
		var offset_traseira = car.global_transform.basis.z * -2.0
		var forca_amassar = Vector3.DOWN * (car.mass * 300.0) # Multiplicador de força pra baixo
		car.apply_impulse(forca_amassar, offset_traseira)
		
		# 3. Força de rotação aleatória (Giro/Yaw do carro)
		# 50% de chance de ser pra direita (1) ou pra esquerda (-1)
		var direcao = 1.0 if randf() > 0.5 else -1.0
		var forca_giro = car.mass * 4.5 * direcao 
		car.apply_torque_impulse(car.global_transform.basis.y * forca_giro)
		
		print("[VehicleEffects] ", car.name, " PERDEU TRAÇÃO TOTAL E TOMOU TRANCO!")

func _alterar_grip_geral(modificador: float):
	if not is_instance_valid(car): return
	
	# Agora não filtramos mais. Aplica o debuff (ou buff) em TODAS as rodas da cena!
	for node in car.get_children():
		if node is VehicleWheel3D:
			node.wheel_friction_slip += modificador
