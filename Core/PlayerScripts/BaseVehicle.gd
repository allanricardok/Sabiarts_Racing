extends VehicleBody3D
class_name BaseVehicle

# Adicione estas linhas no topo para matar os erros da imagem
var id : int = 0
var pode_mover : bool = true
@export var input_source : String = "K1"

@onready var stats = %StatsComponent
@onready var input = %InputComponent
@onready var movement = %MovementComponent
@onready var weapons = %WeaponManager

# --- REFERÊNCIAS DE VISUAL ---
@export_group("Visual Damage")
@export var mesh_new: MeshInstance3D
@export var mesh_damaged: MeshInstance3D
@export var mesh_skeleton: MeshInstance3D

@export_group("Interface")
@export var speed_label: Label # Arraste o Label da velocidade aqui no Inspector

var teleport_material : StandardMaterial3D

func _ready():
	add_to_group("jogadores")
	# Se o Global estiver vazio (Teste F6), garantimos um valor inicial
	if Global.dados_jogadores[0] == null:
		input_source = "K1"
	input.setup(input_source)
	# Sincroniza a cor inicial
	update_visual_damage(100.0)
	
	# Criamos o material de "Sombra/Vazio"
	teleport_material = StandardMaterial3D.new()
	teleport_material.albedo_color = Color(0.05, 0.05, 0.05) # Quase preto
	teleport_material.metallic = 0.0
	teleport_material.roughness = 1.0 # Fosco total
	teleport_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED # Não recebe luz (vira um vulto)

func _physics_process(delta):
	if not pode_mover:
		engine_force = 0
		brake = 100
		return
	
	brake = 0
	
	# --- ATUALIZAÇÃO DO VELOCÍMETRO ---
	if speed_label:
		# linear_velocity.length() dá metros por segundo. * 3.6 = KM/H
		var kmh = linear_velocity.length() * 2
		speed_label.text = str(int(kmh))
	
	# Aqui virá a lógica de movimento refatorada ou a sua antiga
	# Por enquanto, mantemos o freio solto se puder mover
	brake = 0

# --- FUNÇÕES QUE OS COMPONENTES VÃO CHAMAR ---

func update_visual_damage(percent: float):
	# Se as meshes forem iguais (como no seu caso atual), elas ficam visíveis
	# Se forem diferentes, o código alterna entre elas.
	
	if mesh_new:
		mesh_new.visible = percent > 60
	
	if mesh_damaged and mesh_damaged != mesh_new:
		mesh_damaged.visible = percent <= 60 and percent > 0
		
	if mesh_skeleton and mesh_skeleton != mesh_new:
		mesh_skeleton.visible = percent <= 0

func set_pode_mover(valor: bool):
	pode_mover = valor
	print("Carro ", input_source, " liberado: ", valor)

func take_damage(amount: float):
	# Delega o dano para o componente de Stats
	if stats:
		stats.take_damage(amount)

func teleport_to(target_transform : Transform3D):
	# Em vez de travar o movimento, vamos apenas desativar a colisão 
	# temporariamente para não bater em nada durante o snap
	
	var tween = create_tween()
	var all_meshes = find_children("*", "MeshInstance3D", true)
	
	# 1. FLASH NEGRO (0.1s) - O carro vira uma sombra
	for mesh in all_meshes:
		mesh.material_override = teleport_material
	
	# Aguarda os 0.1s
	tween.tween_interval(0.1)
	
	# 2. O SALTO
	tween.tween_callback(func():
		global_transform = target_transform
		# Mantemos a velocidade, mas limpamos a rotação para bater com o Marker
		var current_speed = linear_velocity.length()
		var new_forward = -global_transform.basis.z # Direção do marker
		linear_velocity = new_forward * current_speed
		angular_velocity = Vector3.ZERO
	)
	
	# 3. VOLTA AO NORMAL (0.1s)
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		for mesh in all_meshes:
			mesh.material_override = null
	)
