extends VehicleBody3D
class_name BaseVehicle

# Adicione estas linhas no topo para matar os erros da imagem
var id : int = 0
var pode_mover : bool = true
@export var input_source : String = "K1"

@export_group("Combate: Atropelamento")
@export var divisor_de_massa : float = 1000.0
@export var multiplicador_dano : float = 1.0
@export var dano_maximo_por_batida : float = 50.0
@export var velocidade_minima_dano : float = 3.0

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
	
	# Conecta o sinal de colisão se não fez pelo editor
	body_entered.connect(_on_impacto_corpo)
	body_entered.connect(_on_vehicle_collision)
	
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
	# Criamos o tween para gerenciar o tempo do efeito visual
	var tween = create_tween()
	var all_meshes = find_children("*", "MeshInstance3D", true)
	
	# 1. FLASH NEGRO (0.1s) - Feedback visual de "sumiço"
	for mesh in all_meshes:
		mesh.material_override = teleport_material
	
	# Aguarda o tempo do flash
	tween.tween_interval(0.1)
	
	# 2. O SALTO E O RESET FÍSICO
	tween.tween_callback(func():
		# Define posição e rotação idênticas ao Marker
		global_transform = target_transform
		
		# RESET TOTAL: O carro aparece parado (sem inércia do movimento anterior)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		
		# Dica: Se o carro "tremer" ao aparecer, você pode forçar 
		# o repouso da física por um frame:
		# sleeping = true 
	)
	
	# 3. VOLTA AO NORMAL (0.1s)
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		for mesh in all_meshes:
			mesh.material_override = null
		# Se usou o 'sleeping = true' acima, lembre de acordar o carro:
		# sleeping = false
	)

func _on_impacto_corpo(body):
	# 1. Pegamos a velocidade do alvo (se ele for físico)
	var vel_alvo = Vector3.ZERO
	if body is RigidBody3D:
		vel_alvo = body.linear_velocity
	
	# 2. CALCULO DA VELOCIDADE RELATIVA
	# Isso subtrai os vetores: se ambos vão para a mesma direção, o resultado é pequeno.
	# Se vierem de frente (opostos), o resultado é a soma das velocidades!
	var velocidade_relativa = (linear_velocity - vel_alvo).length()
	
	# 3. Filtro de segurança usando a velocidade de impacto real
	if velocidade_relativa < velocidade_minima_dano:
		return

	# 4. Cálculo do dano baseado na massa da Brasília e na força do choque
	var massa_normalizada = mass / divisor_de_massa
	var dano_calculado = (massa_normalizada * velocidade_relativa) * multiplicador_dano
	
	dano_calculado = clamp(dano_calculado, 0.0, dano_maximo_por_batida)
	
	if body.has_method("take_damage"):
		body.take_damage(dano_calculado)
		print("COLISÃO REAL: Dano ", int(dano_calculado), " | Vel Relativa: ", int(velocidade_relativa))
		
func _aplicar_impacto_visual(intensity):
	# Aqui você pode chamar um tremor de câmera proporcional à porrada
	pass
	
func _on_vehicle_collision(body: Node):
	# Se o que eu bati tem a função de tomar dano
	if body.has_method("take_damage"):
		# Calculamos o dano com base na velocidade do carro para dar "feeling" de peso
		var impact_damage = linear_velocity.length() * 0.5 
		
		if impact_damage > 2.0: # Evita dar dano encostando parado
			body.take_damage(impact_damage, self) # 'self' passa o carro como attacker
