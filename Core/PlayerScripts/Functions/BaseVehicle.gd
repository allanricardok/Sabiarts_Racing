# BaseVehicle.gd
extends VehicleBody3D
class_name BaseVehicle

# --- VARIÁVEIS DE IDENTIDADE (FIX MULTIPLAYER) ---
var id : int = 0
var pode_mover : bool = true
@export var input_source : String = "K1"

# --- CONFIGURAÇÕES DE COMBATE (ATROPELAMENTO) ---
@export_group("Combate: Atropelamento")
@export var divisor_de_massa : float = 1000.0
@export var multiplicador_dano : float = 1.0
@export var dano_maximo_por_batida : float = 50.0
@export var velocidade_minima_dano : float = 3.0

# --- NOVO: Variáveis de Combate Dinâmico ---
@export var hit_weight : float = 5
@export var hit_constant : float = 2 # Dano base mínimo sofrido por quem "ganha" a colisão

# --- COMPONENTES ---
@onready var stats = %StatsComponent
@onready var input = %InputComponent
@onready var movement = %MovementComponent
@onready var weapons = %WeaponManager

# --- REFERÊNCIAS DE VISUAL DAMAGE ---
@export_group("Visual Damage")
@export var mesh_new: MeshInstance3D
@export var mesh_damaged: MeshInstance3D
@export var mesh_skeleton: MeshInstance3D

# --- INTERFACE ---
@export_group("Interface")
@export var speed_label: Label 

# --- VARIÁVEIS INTERNAS ---
var _active_gap_id : String = ""
var teleport_material : StandardMaterial3D
var _hit_cooldowns: Dictionary = {}

# --- INICIALIZAÇÃO ---

func _ready():
	add_to_group("jogadores")
	
	if Global.dados_jogadores.size() > id and Global.dados_jogadores[id] != null:
		input_source = Global.dados_jogadores[id]
	else:
		input_source = "K1"
	
	input.setup(input_source)
	
	teleport_material = StandardMaterial3D.new()
	teleport_material.albedo_color = Color(0.05, 0.05, 0.05) 
	teleport_material.metallic = 0.0
	teleport_material.roughness = 1.0 
	teleport_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED 
	
	call_deferred("_setup_multiplayer_links")
	
	update_visual_damage(100.0)
	
	body_entered.connect(_on_impacto_corpo)
	
	if movement:
		movement.landed.connect(_on_pousou)
		if movement.has_signal("vehicle_reset"):
			movement.vehicle_reset.connect(_reset_gap_state)

# --- PROCESSAMENTO ---

func _physics_process(_delta):
	if not pode_mover:
		engine_force = 0
		brake = 100
		return
	
	if speed_label:
		var kmh = linear_velocity.length() * 2
		speed_label.text = str(int(kmh))
	
	brake = 0

# --- SETUP DE MULTIPLAYER ---

func _setup_multiplayer_links():
	var suffix = "_" + input_source
	var my_hud = get_viewport().find_child("HUD", true, false)
	
	if my_hud and my_hud.has_method("setup_hud"):
		my_hud.setup_hud(suffix, self.id)
		print("[BaseVehicle] Player ", id + 1, " configurado com dispositivo ", input_source)
	
	if weapons and weapons.has_method("setup_multiplayer"):
		weapons.setup_multiplayer(suffix)

# --- LÓGICA DE GAPS E MANOBRAS ---

func _on_pousou(is_clean: bool):
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("check_landing"):
		trick_manager.check_landing(is_clean)
		
	# CORREÇÃO DO BUG DO GAP:
	# Se tocamos no chão e ainda existe um ID de gap ativo (ou seja, 
	# pegamos o Start mas não pegamos o Finish a tempo), nós cancelamos ele!
	if _active_gap_id != "":
		print("[BaseVehicle] Pousou sem terminar o Gap: ", _active_gap_id, ". Cancelando sequência.")
		_reset_gap_state()

func set_active_gap(id_gap: String):
	_active_gap_id = id_gap
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("iniciar_deteccao_gap"):
		trick_manager.iniciar_deteccao_gap(id_gap)

func set_gap_reached_end(id_gap: String, gap_name: String, points: int):
	if _active_gap_id == id_gap:
		_active_gap_id = "" 
		var trick_manager = get_node_or_null("%TrickManager")
		if trick_manager and trick_manager.has_method("marcar_gap_no_ar"):
			trick_manager.marcar_gap_no_ar(id_gap, gap_name, points)

func _reset_gap_state():
	_active_gap_id = ""
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("cancelar_gap"):
		trick_manager.cancelar_gap()

func get_active_gap() -> String:
	return _active_gap_id

# --- SAÚDE E VISUAL ---

func update_visual_damage(percent: float):
	if mesh_new: mesh_new.visible = percent > 60
	if mesh_damaged and mesh_damaged != mesh_new: 
		mesh_damaged.visible = percent <= 60 and percent > 0
	if mesh_skeleton and mesh_skeleton != mesh_new: 
		mesh_skeleton.visible = percent <= 0

func set_pode_mover(valor: bool):
	pode_mover = valor

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

# --- COLISÕES E IMPACTO ---

func _on_impacto_corpo(body: Node):
	var now = Time.get_ticks_msec()
	var body_id = body.get_instance_id()
	
	if _hit_cooldowns.has(body_id) and (now - _hit_cooldowns[body_id] < 1000):
		return
	_hit_cooldowns[body_id] = now
	
	var my_speed = linear_velocity.length() * 2.0
	var target_speed = 0.0
	
	if body is RigidBody3D or body is VehicleBody3D:
		target_speed = body.linear_velocity.length() * 2.0
	
	# Mudança: Contra objetos não-carros, consideramos a nossa própria velocidade como relativa
	var relative_speed = abs(my_speed - target_speed)
	if not (body is BaseVehicle):
		relative_speed = my_speed
	
	if relative_speed < velocidade_minima_dano:
		return
	
	# --- LÓGICA DE DANO ASSIMÉTRICO (Bullying Automotivo) ---
	var dano_gerado = hit_constant + ((my_speed*1.4) * hit_weight * 0.01)
	
	if body is BaseVehicle:
		var my_force = my_speed * hit_weight
		var enemy_force = target_speed * body.hit_weight
		
		if my_force > enemy_force:
			var dano_final = min(dano_gerado, dano_maximo_por_batida)
			
			# LÓGICA DE DEBUG PARA BALANCEAMENTO:
			print("=========================================")
			print("[COMBATE] BATEU! Agressor: Player ", self.id + 1, " | Vítima: Player ", body.id + 1)
			print(" -> Força Agressor: ", int(my_force), " (Velocidade ", int(my_speed), " x Peso ", hit_weight, ")")
			print(" -> Força Vítima:   ", int(enemy_force), " (Velocidade ", int(target_speed), " x Peso ", body.hit_weight, ")")
			print(" -> Dano aplicado na vítima: ", dano_final)
			print("=========================================")
			
			# Inimigo toma o dano e NÓS recebemos os pontos (self = source)
			body.take_damage(dano_final, self)
			
			# MUDANÇA SÊNIOR: Nós tomamos um arranhão de leve, 
			# mas passamos "null" para que a vítima NÃO receba bônus de combo!
			self.take_damage(hit_constant, null)
		else:
			# Se formos mais fracos, apenas aguardamos o script do inimigo resolver a colisão.
			pass
			
	elif body.has_method("take_damage"):
		# Atropelamento de objetos estáticos destrutíveis (caixas, etc)
		var dano_final = min(dano_gerado, dano_maximo_por_batida)
		print("[COMBATE] Player ", self.id + 1, " atropelou objeto: ", body.name, " | Dano: ", dano_final)
		body.take_damage(dano_final, self)
