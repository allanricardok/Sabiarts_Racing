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
@export var multiplicador_dano : float = 1.5
@export var dano_maximo_por_batida : float = 50.0
@export var velocidade_minima_dano : float = 1.0
@export var cooldown_batida_ms : int = 400 # Tempo de invencibilidade após bater (em milissegundos)

# --- NOVO: Variáveis de Combate Dinâmico ---
@export var hit_weight : float = 5
@export var hit_constant : float = 2 # Dano base mínimo sofrido por quem "ganha" a colisão

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
var velocidade_de_impacto : float = 0.0 # <--- NOVA MEMÓRIA DE IMPACTO

# --- NOVO: Memória Multi-Gaps (Guarda o ID e o tempo restante de cada um) ---
var _active_gaps : Dictionary = {}

# --- INICIALIZAÇÃO ---

func _ready():
	add_to_group("jogadores")
	
	# --- CORREÇÃO DO TIPO DE DADO (STRING vs DICTIONARY) ---
	if Global.dados_jogadores.size() > id and Global.dados_jogadores[id] != null:
		var data = Global.dados_jogadores[id]
		# Checa se é o novo sistema de dicionário ou um teste antigo passando string
		if data is Dictionary:
			input_source = data["esquema"]
		else:
			input_source = data
	else:
		# Se não tiver input_source definido, garante o K1
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
	
	# --- LÓGICA DO TEMPO PARA MÚLTIPLOS GAPS ---
	var expired_gaps = []
	for gap_id in _active_gaps.keys():
		_active_gaps[gap_id] -= delta
		if _active_gaps[gap_id] <= 0:
			expired_gaps.append(gap_id)
			
	for gap_id in expired_gaps:
		print("[BaseVehicle] Tempo esgotado para o Gap: ", gap_id)
		_active_gaps.erase(gap_id)
	
	if speed_label:
		var kmh = linear_velocity.length() * 2.3
		speed_label.text = str(int(kmh))
	
	brake = 0
	
	# --- NOVA MEMÓRIA DE IMPACTO ---
	# Salva a velocidade de forma inteligente para que raspões no chão não "cancelem" a batida frontal!
	var vel_atual = linear_velocity.length() * 2.3
	if vel_atual > velocidade_de_impacto:
		velocidade_de_impacto = vel_atual
	else:
		velocidade_de_impacto = lerp(velocidade_de_impacto, vel_atual, delta * 8.0)

# --- SETUP DE MULTIPLAYER ---

func _setup_multiplayer_links():
	var suffix = "_" + input_source
	
	var my_hud = get_viewport().find_child("HUD", true, false)
	if my_hud and my_hud.has_method("setup_hud"):
		my_hud.setup_hud(suffix, self.id)
		print("[BaseVehicle] Player ", id + 1, " configurado com dispositivo ", input_source)
	
	if weapons and weapons.has_method("setup_multiplayer"):
		weapons.setup_multiplayer(suffix)
		
	var hud_correta = get_tree().get_first_node_in_group("HUD" + suffix)
	var rage_comp = get_node_or_null("%RageComponent")
	var rage_ui = hud_correta.find_child("RageUI", true, false) if hud_correta else null
	
	if rage_comp and rage_ui:
		if not rage_comp.rage_updated.is_connected(rage_ui._on_rage_updated):
			rage_comp.rage_updated.connect(rage_ui._on_rage_updated)
			print("[RAGE SETUP] Sinal conectado com sucesso à HUD do Player ", id + 1)
	else:
		print("[RAGE ERROR] Faltou o RageComponent no carro OU o RageUI na HUD para: ", suffix)
		# --- MÁGICA DA NAMETAG (Label3D) ---
	if name_tag:
		# 1. Define o texto correto (ex: "Player 1")
		name_tag.text = "Player " + str(id + 1)
		
		# 2. O Truque da Camada Visual (Cull Mask)
		# Vamos usar as camadas de renderização 11, 12, 13 e 14 para os jogadores 1, 2, 3 e 4.
		var layer_bit = 10 + id 
		
		# Coloca a Nametag DESTE carro APENAS na camada específica dele
		name_tag.layers = (1 << layer_bit)
		
		# Pega a câmera DESTE jogador e manda ela fechar os olhos para a PRÓPRIA camada!
		# Assim, ele vê os adversários (que estão nas outras camadas), mas fica cego para o próprio nome.
		var my_camera = find_child("Camera3D", true, false)
		if my_camera:
			my_camera.cull_mask &= ~(1 << layer_bit)


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
	# 1. FILTRO DE CHÃO (Ignora o mapa estático para não estragar o cálculo)
	if body is GridMap or "Floor" in body.name or "Exteriors" in body.name:
		return
		
	var now = Time.get_ticks_msec()
	var body_id = body.get_instance_id()
	
	if _hit_cooldowns.has(body_id) and (now - _hit_cooldowns[body_id] < cooldown_batida_ms):
		return
	_hit_cooldowns[body_id] = now
	
	# 2. USA A NOSSA NOVA MEMÓRIA DE VELOCIDADE
	var my_speed = velocidade_de_impacto
	var target_speed = 0.0
	
	if body is BaseVehicle:
		target_speed = body.velocidade_de_impacto # Usa a memória do inimigo também!
	elif body is RigidBody3D or body is VehicleBody3D:
		target_speed = body.linear_velocity.length() * 2.0
	
	var relative_speed = abs(my_speed - target_speed)
	if not (body is BaseVehicle):
		relative_speed = my_speed
	
	# --- DEBUG LOG: INÍCIO DO IMPACTO ---
	print("\n[DEBUG IMPACTO] 💥 Bateu em: ", body.name, " | Vel. Carro (Memória): ", int(my_speed), " | Vel. Relativa: ", int(relative_speed))
	
	if relative_speed < velocidade_minima_dano:
		print(" -> [IGNORADO] Batida muito fraca (Abaixo de ", velocidade_minima_dano, ")")
		return
	
	# LÓGICA DE DANO E RAGE
	var dano_gerado = hit_constant + ((my_speed) * hit_weight * 0.03)
	
	if body is BaseVehicle:
		var my_force = my_speed * hit_weight
		var enemy_force = target_speed * body.hit_weight
		
		if my_force > enemy_force:
			var dano_final = min((dano_gerado*0.8), dano_maximo_por_batida)
			
			print(" -> [DANO PVP] Amassou o Player ", body.id + 1, "! Dano: ", int(dano_final))
			body.take_damage(dano_final, self)
			self.take_damage(hit_constant, null)
			
			var rage = get_node_or_null("%RageComponent")
			if rage: rage.add_collision_damage(dano_final)
			
	elif body.has_method("take_damage"):
		var dano_final = min(dano_gerado, dano_maximo_por_batida)
		
		# --- DEBUG LOG: SUCESSO NO DANO PVE ---
		print(" -> [DANO PVE] Causou ", int(dano_final), " de dano no objeto ", body.name)
		
		body.take_damage(dano_final, self)
		
# O carro só ganha Rage se o objeto NÃO for uma parede do cenário!
		if not body.is_in_group("ignorar_rage"):
			var rage = get_node_or_null("%RageComponent")
			if rage: rage.add_collision_damage(dano_final)
		
	else:
		# --- DEBUG LOG: O GRANDE REVELADOR DE BUGS ---
		print(" -> [FALHA] O objeto '", body.name, "' NÃO TEM a função take_damage() ou o script está no nó errado!")

# --- MORTE E DESTRUIÇÃO ---
func _on_vehicle_destroyed():
	print("[BaseVehicle] Veículo destruído: Player ", id + 1)
	
	var controller = get_tree().get_first_node_in_group("LevelController")
	if controller and controller.has_method("registrar_morte_jogador"):
		controller.registrar_morte_jogador()
		
	queue_free()

# --- CONTROLE DE VISIBILIDADE DO NAMETAG ---
func atualizar_visao_nametags(categoria_index: int):
	var my_camera = find_child("Camera3D", true, false)
	if not my_camera: return

	# 1. Fechamos os olhos para TODAS as nametags (Camadas 11 a 14) primeiro
	for i in range(4):
		var layer_bit = 10 + i
		my_camera.cull_mask &= ~(1 << layer_bit)

	# 2. Se a categoria for 0 (All Targets) ou 1 (Adversaries), abrimos os olhos!
	if categoria_index == 0 or categoria_index == 1:
		for i in range(4):
			# Nunca olhar para a PRÓPRIA nametag (evita ver o próprio nome)
			if i != self.id: 
				var layer_bit = 10 + i
				my_camera.cull_mask |= (1 << layer_bit)

# --- EFEITOS DE STATUS ---
func aplicar_congelamento(tempo: float = 3.0):
	if effects:
		effects.aplicar_congelamento(tempo)

func is_frozen() -> bool:
	return effects.is_frozen if effects else false
