extends Node
class_name VehicleEffects

@onready var car = owner as BaseVehicle

# --- STATUS DE CONGELAMENTO ---
var is_frozen : bool = false
var freeze_timer : float = 0.0
var freeze_material : StandardMaterial3D

func _ready():
	# Prepara o material de gelo (Azul claro, brilhante e meio transparente)
	freeze_material = StandardMaterial3D.new()
	freeze_material.albedo_color = Color(0.2, 0.6, 1.0, 0.6) 
	freeze_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	freeze_material.emission_enabled = true
	freeze_material.emission = Color(0.1, 0.5, 1.0)
	freeze_material.emission_energy_multiplier = 2.0

func _process(delta):
	if is_frozen:
		freeze_timer -= delta
		if freeze_timer <= 0:
			_remover_congelamento()

func aplicar_congelamento(tempo: float = 3.0):
	if is_frozen:
		freeze_timer = tempo # Apenas renova o tempo se já estiver congelado
		return
		
	is_frozen = true
	freeze_timer = tempo
	
	# Pinta TODAS as partes do carro com a camada de gelo
	var all_meshes = car.find_children("*", "MeshInstance3D", true)
	for mesh in all_meshes: 
		mesh.material_overlay = freeze_material

func _remover_congelamento():
	is_frozen = false
	
	# Tira a camada de gelo do carro
	var all_meshes = car.find_children("*", "MeshInstance3D", true)
	for mesh in all_meshes: 
		mesh.material_overlay = null
