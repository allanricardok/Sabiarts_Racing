# BaseVehicle.gd
extends VehicleBody3D
class_name BaseVehicle

# --- VARIÁVEIS ORIGINAIS (PRESERVADAS) ---
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
@export var speed_label: Label 

# --- VARIÁVEIS DE CONTROLE DE GAP ---
var _active_gap_id : String = ""
var teleport_material : StandardMaterial3D
var _hit_cooldowns: Dictionary = {}

func _ready():
	add_to_group("jogadores")
	if Global.dados_jogadores[0] == null:
		input_source = "K1"
	input.setup(input_source)
	update_visual_damage(100.0)
	
	body_entered.connect(_on_impacto_corpo)
	body_entered.connect(_on_vehicle_collision)
	
	# --- CONEXÃO COM O MOVEMENT COMPONENT ---
	if movement:
		# Quando o movimento detecta o chão, ele avisa se o pouso foi limpo
		movement.landed.connect(_on_pousou)
		# Se o carro resetar (R ou Auto-flip), o Gap é cancelado
		if movement.has_signal("vehicle_reset"):
			movement.vehicle_reset.connect(_reset_gap_state)
	
	teleport_material = StandardMaterial3D.new()
	teleport_material.albedo_color = Color(0.05, 0.05, 0.05) 
	teleport_material.metallic = 0.0
	teleport_material.roughness = 1.0 
	teleport_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED 

func _physics_process(delta):
	if not pode_mover:
		engine_force = 0
		brake = 100
		return
	
	if speed_label:
		var kmh = linear_velocity.length() * 2
		speed_label.text = str(int(kmh))
	
	brake = 0

# --- LÓGICA DE GAPS (PONTE PARA O TRICK MANAGER) ---

func _on_pousou(is_clean: bool):
	# REPASSA O SINAL PARA O TRICK MANAGER VALIDAR O COMBO/GAP
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("check_landing"):
		trick_manager.check_landing(is_clean)

func set_active_gap(id_gap: String):
	_active_gap_id = id_gap
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("iniciar_deteccao_gap"):
		trick_manager.iniciar_deteccao_gap(id_gap)

func set_gap_reached_end(id_gap: String, gap_name: String, points: int):
	if _active_gap_id == id_gap:
		# TRAVA: Limpamos o ID ativo IMEDIATAMENTE. 
		# Isso impede que o Ponto B dispare o sinal várias vezes no mesmo frame/voo.
		_active_gap_id = "" 
		
		var trick_manager = get_node_or_null("%TrickManager")
		if trick_manager and trick_manager.has_method("marcar_gap_no_ar"):
			trick_manager.marcar_gap_no_ar(id_gap, gap_name, points)
			print("[Gap] END: Validado e aguardando pouso.")

func _reset_gap_state():
	_active_gap_id = ""
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("cancelar_gap"):
		trick_manager.cancelar_gap()

func _check_gap_cancel():
	pass

func update_visual_damage(percent: float):
	if mesh_new: mesh_new.visible = percent > 60
	if mesh_damaged and mesh_damaged != mesh_new: mesh_damaged.visible = percent <= 60 and percent > 0
	if mesh_skeleton and mesh_skeleton != mesh_new: mesh_skeleton.visible = percent <= 0

func set_pode_mover(valor: bool):
	pode_mover = valor
	print("Carro ", input_source, " liberado: ", valor)

func take_damage(amount: float, attacker: Node = null):
	if stats: stats.take_damage(amount, attacker)

func teleport_to(target_transform : Transform3D):
	var tween = create_tween()
	var all_meshes = find_children("*", "MeshInstance3D", true)
	for mesh in all_meshes: mesh.material_override = teleport_material
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		global_transform = target_transform
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	)
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		for mesh in all_meshes: mesh.material_override = null
	)

func _on_impacto_corpo(body):
	var now = Time.get_ticks_msec()
	var body_id = body.get_instance_id()
	if _hit_cooldowns.has(body_id):
		if now - _hit_cooldowns[body_id] < 1000: return
	_hit_cooldowns[body_id] = now
	var vel_alvo = body.linear_velocity if body is RigidBody3D else Vector3.ZERO
	var velocidade_relativa = (linear_velocity - vel_alvo).length()
	if velocidade_relativa < velocidade_minima_dano: return
	var massa_normalizada = mass / divisor_de_massa
	var dano_calculado = clamp((massa_normalizada * velocidade_relativa) * multiplicador_dano, 0.0, dano_maximo_por_batida)
	if body.has_method("take_damage"): body.take_damage(dano_calculado, self)

func _on_vehicle_collision(body: Node):
	var now = Time.get_ticks_msec()
	var body_id = body.get_instance_id()
	if _hit_cooldowns.has(body_id):
		if now - _hit_cooldowns[body_id] < 1000: return
	_hit_cooldowns[body_id] = now
	if body.has_method("take_damage"):
		var impact_damage = linear_velocity.length() * 0.5 
		if impact_damage > 2.0: body.take_damage(impact_damage, self)

func get_active_gap() -> String:
	return _active_gap_id
