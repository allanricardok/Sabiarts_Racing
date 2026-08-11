extends VehicleBody3D
class_name BaseVehicle

# --- MEMÓRIA DE FÍSICA ---
var original_collision_layer : int = 1
var original_collision_mask : int = 1

# --- VARIÁVEIS DE IDENTIDADE (FIX MULTIPLAYER) ---
var id : int = 0
var pode_mover : bool = true
@export var input_source : String = "K1"

# --- DROPS E RECOMPENSAS (BOTS) ---
@export_group("Recompensas do Bot")
@export var pontos_por_morte : int = 1000
@export var drop_item_scene : PackedScene
@export var drop_item_resource_1 : Resource
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

# ============================================================================
# Fragmentos de destruição ao morrer.
# ============================================================================
@export_group("Fragmentos de Destruição")
@export var spawn_debris_on_death : bool = true
@export var shard_count : int = 14
@export var explosion_force : float = 5.0
@export var upward_bias : float = 4.0
@export var shard_lifetime : float = 1.3
@export var scatter_radius : float = 1.0
@export var shard_min_size : float = 0.2
@export var shard_max_size : float = 0.5

# --- INTERFACE ---
@export_group("Interface")
@export var speed_label: Label 
@onready var name_tag = $NameTag

# ---  CAMERA ---
@export_group("Configurações de Câmera")
@export var hood_camera_pos: Vector3 = Vector3(0, 1.2, 1.2)
@export var far_camera_offset: Vector3 = Vector3(0, 3.0, -5.0)

@export_group("Combate: Efeitos Visuais")
@export var blood_splash_distance: float = 3.0

# --- VARIÁVEIS INTERNAS ---
var teleport_material : StandardMaterial3D
var _hit_cooldowns: Dictionary = {}
var velocidade_de_impacto : float = 0.0 
var _active_gaps : Dictionary = {}
var pedestrians_killed : int = 0

# OTIMIZAÇÃO: Cache da Câmera para não procurar na árvore toda batida
var _cached_camera_shake : Node = null

# --- INICIALIZAÇÃO ---

func _ready():
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
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
	
	_cached_camera_shake = find_child("CameraShake", true, false)
	
	call_deferred("_setup_multiplayer_links")
	
	update_visual_damage(100.0)
	
	body_entered.connect(_on_impacto_corpo)
	
	if movement:
		movement.landed.connect(_on_pousou)
		if movement.has_signal("vehicle_reset"):
			movement.vehicle_reset.connect(_reset_gap_state)
	
	if stats:
		stats.health_depleted.connect(_on_vehicle_destroyed)
	
	if is_instance_valid(Global) and "has_teleport_key" in Global and Global.has_teleport_key:
		if "has_teleportkey" in self:
			self.has_teleportkey = true
		elif stats and "has_teleportkey" in stats:
			stats.has_teleportkey = true

# --- PROCESSAMENTO ---

func _physics_process(delta):
	if not pode_mover or is_frozen():
		if not is_frozen(): 
			engine_force = 0
			brake = 100
		return
	
	# OTIMIZAÇÃO: Evita alocar arrays inúteis se o dict estiver vazio (ex: Bots)
	if not _active_gaps.is_empty():
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

# --- SETUP DE MULTIPLAYER ---

func _setup_multiplayer_links():
	var is_bot = false
	if input and "is_bot" in input:
		is_bot = input.is_bot

	if name_tag:
		name_tag.text = "Player " + str(id + 1)
		var layer_bit = 10 + id 
		name_tag.layers = (1 << layer_bit)
		
		var my_camera = find_child("Camera3D", true, false)
		if my_camera:
			my_camera.cull_mask &= ~(1 << layer_bit)

	if is_bot: 
		return 

	var suffix = "_" + input_source
	
	var my_hud = find_child("*HUD*", true, false)
	if my_hud and my_hud.has_method("setup_hud"):
		my_hud.setup_hud(suffix, self.id)
		print("[BaseVehicle] Player ", id + 1, " conectou à própria HUD!")
	
	if weapons and weapons.has_method("setup_multiplayer"):
		weapons.setup_multiplayer(suffix)
		
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
	if amount > 6.0:
		play_camera_shake("Damage")
	if stats: stats.take_damage(amount, attacker)

# --- TELEPORTE FIX ---
func teleport_to(target_transform : Transform3D):
	get_tree().call_group("TutorialUI", "complete_task", "teleport")
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
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
			
			play_camera_shake("CarCollision", dano_final)
			
	elif body.has_method("take_damage"):
		var dano_final = min(dano_gerado, dano_maximo_por_batida)
		body.take_damage(dano_final, self)
		
		if not body.is_in_group("ignorar_rage"):
			var rage = get_node_or_null("%RageComponent")
			if rage: rage.add_collision_damage(dano_final)

		var speed_now = linear_velocity.length() * 2.3
		if speed_now < (my_speed * 0.75):
			play_camera_shake("ObjCollision")

# --- SISTEMA DE MORTE E DESTRUIÇÃO ---
var _is_dead : bool = false

func _on_vehicle_destroyed(attacker: Node = null):
	if _is_dead: return
	_is_dead = true
	
	var is_bot = false
	if input and "is_bot" in input:
		is_bot = input.is_bot
		set_physics_process(false)
		set_process(false)
	
	_spawn_debris()
	
	var actual_shooter = attacker
	if attacker and "shooter" in attacker and is_instance_valid(attacker.shooter):
		actual_shooter = attacker.shooter
		
	if is_instance_valid(actual_shooter) and actual_shooter.is_in_group("jogadores"):
		var dist = global_position.distance_to(actual_shooter.global_position)
		if dist <= blood_splash_distance:
			_trigger_blood_splash_ui(actual_shooter)
		
	var controller = get_tree().get_first_node_in_group("LevelController")
	if controller and controller.has_method("registrar_morte_jogador"):
		controller.registrar_morte_jogador()
		
	_spawn_loot_safely(self.global_position)
		
	if not is_bot:
		visible = false
		pode_mover = false
		collision_layer = 0
		collision_mask = 0
		freeze = true 
		set_physics_process(false)
	else:
		if is_instance_valid(attacker) and attacker.is_in_group("jogadores"):
			var g_manager = attacker.get_node_or_null("%GroundTrickManager")
			if g_manager and g_manager.has_method("add_custom_action"):
				g_manager.add_custom_action("Bot Destroyed!", pontos_por_morte)
		
		if is_instance_valid(ExplosionManager):
			var cor_fogo = Color(1.0, 0.4, 0.0, 1.0)
			var cor_fumaca = Color(0.2, 0.2, 0.2, 1.0)
			ExplosionManager.explode(global_position, cor_fogo, 0.0, 15, 0.0, cor_fumaca, 2, 0.5)
		
		var raio_explosao = 20.0
		var dano_explosao = 15.0
		
		var space_state = get_world_3d().direct_space_state
		var sphere = SphereShape3D.new()
		sphere.radius = raio_explosao
		
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.transform = global_transform
		
		var result = space_state.intersect_shape(query)
		for hit in result:
			var objeto = hit.collider
			if objeto != self and objeto != owner:
				if objeto.has_method("take_damage"):
					objeto.take_damage(dano_explosao, self)
				else:
					# OTIMIZAÇÃO: Sem wildcard pesada aqui
					var stats_alvo = objeto.find_child("StatsComponent", true, false)
					if stats_alvo and stats_alvo.has_method("take_damage"):
						stats_alvo.take_damage(dano_explosao, self)
						
				# OTIMIZAÇÃO: Bots e detritos não têm CameraShake! Filtramos apenas jogadores.
				if objeto.is_in_group("jogadores"):
					var shake = objeto.find_child("CameraShake", true, false)
					if shake and shake.has_method("trigger_event"):
						shake.trigger_event("car_collision_max_force", 15)
					
		visible = false
		collision_layer = 0
		collision_mask = 0
		queue_free()

func _trigger_blood_splash_ui(shooter: Node3D):
	if not shooter: return
	var input_comp = shooter.get_node_or_null("%InputComponent")
	
	if input_comp and not input_comp.get("is_bot"):
		var suffix = input_comp.get("suffix") if input_comp.get("suffix") != null else ""
		var hud = get_tree().get_first_node_in_group("HUD" + suffix)
		
		if not hud: 
			hud = get_tree().get_first_node_in_group("HUD")
			
		if hud and hud.has_method("splatter_blood_on_lens"):
			hud.splatter_blood_on_lens()

func _spawn_debris() -> void:
	if not spawn_debris_on_death:
		return
	if not is_instance_valid(DebrisManager):
		push_warning("[BaseVehicle] DebrisManager não encontrado. Configure como Autoload.")
		return
	
	var source_mesh: MeshInstance3D = null
	if mesh_new and mesh_new.visible:
		source_mesh = mesh_new
	elif mesh_damaged and mesh_damaged.visible:
		source_mesh = mesh_damaged
	elif mesh_skeleton and mesh_skeleton.visible:
		source_mesh = mesh_skeleton
	elif mesh_new:
		source_mesh = mesh_new
	
	var mat: Material = null
	if source_mesh and source_mesh.mesh:
		mat = source_mesh.get_active_material(0)
	
	DebrisManager.explode(
		global_position,
		mat,
		shard_count,
		explosion_force,
		upward_bias,
		shard_lifetime,
		scatter_radius,
		shard_min_size,
		shard_max_size
	)

func _spawn_loot_safely(origin_pos: Vector3):
	if drop_item_scene:
		if is_instance_valid(LootDropManager):
			var dir_left = (global_transform.basis.x * -1.0 + Vector3(0, 0.5, 0)).normalized()
			var dir_right = (global_transform.basis.x * 1.0 + Vector3(0, 0.5, 0)).normalized()
			
			if drop_item_resource_1:
				LootDropManager.spawn_ejected_loot(origin_pos, dir_left, drop_item_scene, drop_item_resource_1, 6.0)
			
			if drop_item_resource_2:
				LootDropManager.spawn_ejected_loot(origin_pos, dir_right, drop_item_scene, drop_item_resource_2, 6.0)
		else:
			push_warning("[BaseVehicle] LootDropManager Autoload não encontrado!")

func atualizar_visao_nametags(categoria_index: int):
	var my_camera = find_child("Camera3D", true, false)
	if not my_camera: return

	for i in range(10):
		var layer_bit = 10 + i
		my_camera.cull_mask &= ~(1 << layer_bit)

	if categoria_index == 0 or categoria_index == 1:
		for i in range(10):
			if i != self.id: 
				var layer_bit = 10 + i
				my_camera.cull_mask |= (1 << layer_bit)

func aplicar_congelamento(tempo: float = 3.0):
	if effects and effects.has_method("aplicar_congelamento"):
		effects.aplicar_congelamento(tempo)

func is_frozen() -> bool:
	if effects and "is_frozen" in effects:
		return effects.is_frozen
	return false

func play_camera_shake(event_name: String, modifier: float = 1.0):
	var is_bot = (input and "is_bot" in input and input.is_bot)
	if is_bot: return 
	
	# OTIMIZAÇÃO: Usa o nó salvo na memória em vez de rodar o find_child na árvore
	if is_instance_valid(_cached_camera_shake) and _cached_camera_shake.has_method("trigger_event"):
		_cached_camera_shake.trigger_event(event_name, modifier)

func set_camera_mode(mode_index: int):
	var my_camera = find_child("Camera3D", true, false)
	if my_camera and my_camera.has_method("set_camera_mode"):
		my_camera.set_camera_mode(mode_index)
		
func revive():
	print("[Vehicle-DEBUG] Comando de reviver recebido!")
	
	_is_dead = false
	
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	freeze = false 
	set_physics_process(true)
	pode_mover = true
	
	collision_layer = original_collision_layer 
	collision_mask = original_collision_mask
	
	var todas_as_meshes = find_children("*", "MeshInstance3D", true)
	for mesh in todas_as_meshes:
		mesh.visible = true
		
	var visual_damage = find_child("VisualDamageComponent", true, false)
	if visual_damage and visual_damage.has_method("reset"):
		visual_damage.reset()
	update_visual_damage(100.0) 
		
	if stats:
		print("[Vehicle-DEBUG] StatsComponent encontrado. Curando Vida e Shield...")
		if stats.has_method("heal_full"): 
			stats.heal_full()
		else:
			if "current_health" in stats: stats.current_health = stats.max_health
			if "current_shield" in stats: stats.current_shield = stats.max_shield
			if "is_dead" in stats: stats.is_dead = false
			if "is_invulnerable" in stats: stats.is_invulnerable = false
			
	var ability = get_node_or_null("%AbilityComponent")
	if not ability:
		ability = find_child("AbilityComponent", true, false)
		
	if ability and "current_energy" in ability:
		ability.current_energy = ability.get("MAX_ENERGY") if "MAX_ENERGY" in ability else 100.0
