# BaseVehicle.gd
extends VehicleBody3D
class_name BaseVehicle

# --- VARIÁVEIS DE IDENTIDADE (FIX MULTIPLAYER) ---
var id : int = 0
var pode_mover : bool = true
@export var input_source : String = "K1"

# --- DROPS E RECOMPENSAS (BOTS) ---
@export_group("Recompensas do Bot")
@export var pontos_por_morte : int = 1000
## Arraste a cena "UniversalPickup.tscn" aqui
@export var drop_item_scene : PackedScene
## Arraste o arquivo .tres (Ex: Vida.tres)
@export var drop_item_resource_1 : Resource
## Arraste outro arquivo .tres (Ex: Míssil.tres)
@export var drop_item_resource_2 : Resource

# --- CONFIGURAÇÕES DE COMBATE (ATROPELAMENTO) ---
@export_group("Combate: Atropelamento")
@export var divisor_de_massa : float = 1000.0
@export var multiplicador_dano : float = 1.5
@export var dano_maximo_por_batida : float = 50.0
@export var velocidade_minima_dano : float = 1.0
@export var cooldown_batida_ms : int = 400 

# --- NOVO: Variáveis de Combate Dinâmico ---
@export var hit_weight : float = 5
@export var hit_constant : float = 2 

# --- COMPONENTES ---
@onready var stats = %StatsComponent
@onready var input = %InputComponent
@onready var movement = %MovementComponent
@onready var weapons = %WeaponManager
@onready var effects = %VehicleEffects

# --- REFERÊNCIAS DE VISUAL DAMAGE ---
@export_group("Visual Damage")
@export var mesh_new: MeshInstance3D
@export var mesh_damaged: MeshInstance3D
@export var mesh_skeleton: MeshInstance3D

# --- INTERFACE ---
@export_group("Interface")
@export var speed_label: Label 
@onready var name_tag = $NameTag

# --- VARIÁVEIS INTERNAS ---
var teleport_material : StandardMaterial3D
var _hit_cooldowns: Dictionary = {}
var velocidade_de_impacto : float = 0.0 
var _active_gaps : Dictionary = {}

# --- INICIALIZAÇÃO ---

func _ready():
	add_to_group("jogadores")
	
	if Global.dados_jogadores.size() > id and Global.dados_jogadores[id] != null:
		var data = Global.dados_jogadores[id]
		if data is Dictionary:
			input_source = data["esquema"]
		else:
			input_source = data
	else:
		if input_source == "": 
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
	
	if stats:
		stats.health_depleted.connect(_on_vehicle_destroyed)

# --- PROCESSAMENTO ---

func _physics_process(delta):
	if not pode_mover:
		engine_force = 0
		brake = 100
		return
	
	var expired_gaps = []
	for gap_id in _active_gaps.keys():
		_active_gaps[gap_id] -= delta
		if _active_gaps[gap_id] <= 0:
			expired_gaps.append(gap_id)
			
	for gap_id in expired_gaps:
		_active_gaps.erase(gap_id)
	
	if speed_label:
		var kmh = linear_velocity.length() * 2.3
		speed_label.text = str(int(kmh))
	
	brake = 0
	
	var vel_atual = linear_velocity.length() * 2.3
	if vel_atual > velocidade_de_impacto:
		velocidade_de_impacto = vel_atual
	else:
		velocidade_de_impacto = lerp(velocidade_de_impacto, vel_atual, delta * 8.0)

# --- SETUP DE MULTIPLAYER (CORRIGIDO E BLINDADO) ---

func _setup_multiplayer_links():
	# Verifica imediatamente se somos um Bot
	var is_bot = false
	if input and "is_bot" in input:
		is_bot = input.is_bot

	# --- MÁGICA DA NAMETAG (Label3D) ---
	if name_tag:
		name_tag.text = "Player " + str(id + 1)
		var layer_bit = 10 + id 
		name_tag.layers = (1 << layer_bit)
		
		var my_camera = find_child("Camera3D", true, false)
		if my_camera:
			my_camera.cull_mask &= ~(1 << layer_bit)

	# --- FIM DA LINHA PARA OS BOTS ---
	# Se for um bot, ele não precisa e não deve tocar em nenhuma HUD!
	if is_bot: 
		return 

	var suffix = "_" + input_source
	
	# Usamos find_child("*HUD*") direto no carro, garantindo que ele só ache a PRÓPRIA interface
	var my_hud = find_child("*HUD*", true, false)
	if my_hud and my_hud.has_method("setup_hud"):
		my_hud.setup_hud(suffix, self.id)
		print("[BaseVehicle] Player ", id + 1, " conectou à própria HUD!")
	
	if weapons and weapons.has_method("setup_multiplayer"):
		weapons.setup_multiplayer(suffix)
		
	# Conexão direta do Rage na própria HUD para evitar cruzamento de dados
	if my_hud:
		var rage_comp = get_node_or_null("%RageComponent")
		var rage_ui = my_hud.find_child("RageUI", true, false)
		
		if rage_comp and rage_ui:
			if not rage_comp.rage_updated.is_connected(rage_ui._on_rage_updated):
				rage_comp.rage_updated.connect(rage_ui._on_rage_updated)


# --- LÓGICA DE GAPS E MANOBRAS ---

func _on_pousou(is_clean: bool):
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("check_landing"):
		trick_manager.check_landing(is_clean)

func set_active_gap(id_gap: String):
	_active_gaps[id_gap] = 10.0 
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("iniciar_deteccao_gap"):
		trick_manager.iniciar_deteccao_gap(id_gap)

func set_gap_reached_end(id_gap: String, gap_name: String, points: int):
	if _active_gaps.has(id_gap):
		_active_gaps.erase(id_gap)
		var trick_manager = get_node_or_null("%TrickManager")
		if trick_manager and trick_manager.has_method("marcar_gap_no_ar"):
			trick_manager.marcar_gap_no_ar(id_gap, gap_name, points)

func _reset_gap_state():
	_active_gaps.clear()
	var trick_manager = get_node_or_null("%TrickManager")
	if trick_manager and trick_manager.has_method("cancelar_gap"):
		trick_manager.cancelar_gap()

func has_active_gap(id_gap: String) -> bool:
	return _active_gaps.has(id_gap)

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
	if body is GridMap or "Floor" in body.name or "Exteriors" in body.name:
		return
		
	var now = Time.get_ticks_msec()
	var body_id = body.get_instance_id()
	
	if _hit_cooldowns.has(body_id) and (now - _hit_cooldowns[body_id] < cooldown_batida_ms):
		return
	_hit_cooldowns[body_id] = now
	
	var my_speed = velocidade_de_impacto
	var target_speed = 0.0
	
	if body is BaseVehicle:
		target_speed = body.velocidade_de_impacto 
	elif body is RigidBody3D or body is VehicleBody3D:
		target_speed = body.linear_velocity.length() * 2.0
	
	var relative_speed = abs(my_speed - target_speed)
	if not (body is BaseVehicle):
		relative_speed = my_speed
	
	if relative_speed < velocidade_minima_dano:
		return
	
	var dano_gerado = hit_constant + ((my_speed) * hit_weight * 0.03)
	
	if body is BaseVehicle:
		var my_force = my_speed * hit_weight
		var enemy_force = target_speed * body.hit_weight
		
		if my_force > enemy_force:
			var dano_final = min((dano_gerado*0.8), dano_maximo_por_batida)
			body.take_damage(dano_final, self)
			self.take_damage(hit_constant, null)
			
			var rage = get_node_or_null("%RageComponent")
			if rage: rage.add_collision_damage(dano_final)
			
	elif body.has_method("take_damage"):
		var dano_final = min(dano_gerado, dano_maximo_por_batida)
		body.take_damage(dano_final, self)
		
		if not body.is_in_group("ignorar_rage"):
			var rage = get_node_or_null("%RageComponent")
			if rage: rage.add_collision_damage(dano_final)

# --- SISTEMA DE MORTE E DESTRUIÇÃO ---
var _is_dead : bool = false

func _on_vehicle_destroyed(attacker: Node = null):
	if _is_dead: return
	_is_dead = true
	
	var is_bot = false
	if input and "is_bot" in input:
		is_bot = input.is_bot
		
	if not is_bot:
		# --- MORTE DE JOGADOR REAL ---
		var controller = get_tree().get_first_node_in_group("LevelController")
		if controller and controller.has_method("registrar_morte_jogador"):
			controller.registrar_morte_jogador()
			
		visible = false
		pode_mover = false
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
	else:
		# --- MORTE DO BOT ---
		# 1. Dá os pontos NA TELA DE COMBO do Atirador!
		if is_instance_valid(attacker) and attacker.is_in_group("jogadores"):
			var g_manager = attacker.get_node_or_null("%GroundTrickManager")
			if g_manager and g_manager.has_method("add_custom_action"):
				g_manager.add_custom_action("Bot Destroyed!", pontos_por_morte)
		
		# 2. Desliga a colisão para não interferir no drop
		visible = false
		collision_layer = 0
		collision_mask = 0
		
		# 3. Spawna o loot IMEDIATAMENTE antes do carro sumir (Sem o call_deferred)
		_spawn_loot_safely(self.global_position)
		
		# 4. Agora sim, joga no lixo com segurança!
		queue_free()

# --- SISTEMA DE DROPS SEGURO ---
func _spawn_loot_safely(origin_pos: Vector3):
	if drop_item_scene:
		var left_pos = origin_pos + (global_transform.basis.x * -2.5) + Vector3(0, 1.0, 0)
		var right_pos = origin_pos + (global_transform.basis.x * 2.5) + Vector3(0, 1.0, 0)
		
		if drop_item_resource_1: _create_drop_carrier(left_pos, drop_item_resource_1)
		if drop_item_resource_2: _create_drop_carrier(right_pos, drop_item_resource_2)

func _create_drop_carrier(start_pos: Vector3, resource_to_drop: Resource):
	# Proteção máxima
	if not is_inside_tree(): return 
	
	var space_state = get_world_3d().direct_space_state
	var destination = start_pos + (Vector3.DOWN * 100.0)
	var query = PhysicsRayQueryParameters3D.create(start_pos, destination)
	
	# CRUCIAL: Manda o Raycast ignorar o próprio carro morto
	query.exclude = [self.get_rid()] 
	
	var result = space_state.intersect_ray(query)
	var final_pos = start_pos 
	
	if result:
		final_pos = result.position + Vector3(0, 1.5, 0)
		
	var drop_carrier = Node3D.new()
	drop_carrier.global_position = start_pos
	get_tree().current_scene.add_child(drop_carrier)
	
	var drop = drop_item_scene.instantiate()
	drop.position = Vector3.ZERO 
	
	if "weapon_resource" in drop:
		drop.weapon_resource = resource_to_drop
	elif "item_data" in drop:
		drop.item_data = resource_to_drop
		
	drop_carrier.add_child(drop)
	
	drop.tree_exited.connect(func():
		if is_instance_valid(drop_carrier):
			drop_carrier.queue_free()
	)
	
	var distance = start_pos.distance_to(final_pos)
	if distance > 0.1:
		var fall_time = sqrt((2.0 * distance) / 50.0)
		var tween = get_tree().create_tween()
		tween.tween_property(drop_carrier, "global_position", final_pos, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# --- CONTROLE DE VISIBILIDADE DO NAMETAG ---
func atualizar_visao_nametags(categoria_index: int):
	var my_camera = find_child("Camera3D", true, false)
	if not my_camera: return

	# Fechamos os olhos para TODAS as nametags (Camadas 10 até 19, para suportar mais bots)
	for i in range(10):
		var layer_bit = 10 + i
		my_camera.cull_mask &= ~(1 << layer_bit)

	if categoria_index == 0 or categoria_index == 1:
		for i in range(10):
			if i != self.id: 
				var layer_bit = 10 + i
				my_camera.cull_mask |= (1 << layer_bit)

# --- EFEITOS DE STATUS ---
func aplicar_congelamento(tempo: float = 3.0):
	if effects:
		effects.aplicar_congelamento(tempo)

func is_frozen() -> bool:
	return effects.is_frozen if effects else false
