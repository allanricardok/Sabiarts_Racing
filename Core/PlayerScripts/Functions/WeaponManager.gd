# WeaponManager.gd
extends Node3D

# --- SISTEMA DE ALVOS TÁTICO ---
var target_categories = ["All Targets", "Adversaries", "Fuckers", "Environment"]
var current_category_index : int = 0
var manual_target_index : int = 0
var active_targets_sorted : Array = []

@export_group("Radar e Sensores")
## Distância máxima (em metros) que o radar consegue enxergar
@export var radar_range : float = 350.0 
var radar_update_timer : float = 0.0
# --- A CORREÇÃO DE PERFORMANCE ---
const RADAR_UPDATE_INTERVAL : float = 0.1

@export_group("Configurações de Visão (LoS)")
@export_flags_3d_physics var los_collision_mask = 1 # Máscara do cenário (Mude se necessário)

# --- CONFIGURAÇÕES ---
@export_group("Armas")
@export var basic_weapon_resource: WeaponResource 
@export var fire_rate_basic : float = 0.12
@export var MAX_POOL_SIZE : int = 5 # Limite de 5 armas especiais

# --- REFERÊNCIAS ---
@onready var car = owner
@onready var input = %InputComponent

@onready var weapon_nodes = {
	"MachineGun": %MachineGun,
	"BigSlow": %BigSlow,
	"HomingMissile": %HomingMissile,
	"GrapplingMissile": %GrapplingMissile 
}

# --- ESTADO INTERNO (INVENTÁRIO) ---
var weapon_pool : Array[WeaponResource] = [] 
var current_weapon_index : int = -1 
var current_target: Node3D = null
var basic_cooldown : float = 0.0
var special_cooldowns : Dictionary = {}

# --- VARIÁVEL DE MULTIPLAYER ---
var player_suffix : String = "" 

func _ready():
	_reset_weapon_visibility()
	if weapon_nodes.has("MachineGun"):
		weapon_nodes["MachineGun"].visible = true
	_atualizar_interface()

func setup_multiplayer(suffix: String):
	player_suffix = suffix
	print("[WeaponManager] Vinculado ao sufixo: ", player_suffix)
	_atualizar_interface()
	call_deferred("_validate_initial_category")

func _process(delta):
	var real_delta = delta
	if is_instance_valid(car) and car.is_in_group("jogadores"):
		real_delta = delta / Engine.time_scale

	if basic_cooldown > 0:
		basic_cooldown -= real_delta
	
	for weapon_name in special_cooldowns.keys():
		if special_cooldowns[weapon_name] > 0:
			special_cooldowns[weapon_name] -= real_delta
		
	if not car.pode_mover: return

	# 1. TIRO BÁSICO
	if input.is_action_pressed and basic_cooldown <= 0:
		var is_doing_ability = (input.ability_up or input.ability_down or input.ability_left or input.ability_right)
		if not is_doing_ability:
			fire_basic_weapon()

	# 2. TROCA DE ARMAS
	if Input.is_action_just_pressed("prev_weapon" + input.suffix): 
		_switch_weapon(-1)
	if Input.is_action_just_pressed("next_weapon" + input.suffix): 
		_switch_weapon(1)

	# 3. TIRO ESPECIAL
	if Input.is_action_just_pressed("Fire" + input.suffix):
		fire_special_weapon()
	
	# 4. NAVEGAÇÃO DE ALVOS E CATEGORIAS
	if Input.is_action_just_pressed("cat_left" + input.suffix):
		_cycle_category(-1)
	if Input.is_action_just_pressed("cat_right" + input.suffix):
		_cycle_category(1)
	if Input.is_action_just_pressed("target_up" + input.suffix):
		_cycle_target(-1)
	if Input.is_action_just_pressed("target_down" + input.suffix):
		_cycle_target(1)

	# 5. RADAR E LOCK-ON OTIMIZADO (Roda apenas a cada 0.2s)
	radar_update_timer -= real_delta
	if radar_update_timer <= 0:
		radar_update_timer = RADAR_UPDATE_INTERVAL
		_update_radar_and_lockon()
		
	# 6. ATUALIZAÇÃO DO RETÍCULO (Visualização precisa rodar todo frame para ser suave)
	_atualizar_posicao_reticulo()

# --- GESTÃO DO INVENTÁRIO (POOL) ---

func get_active_special() -> WeaponResource:
	if current_weapon_index >= 0 and current_weapon_index < weapon_pool.size():
		return weapon_pool[current_weapon_index]
	return null

func equip_special_weapon(new_weapon_res: WeaponResource):
	for i in range(weapon_pool.size()):
		var w = weapon_pool[i]
		if w.nome == new_weapon_res.nome:
			w.ammo += new_weapon_res.ammo
			print("Munição adicionada ao pool: ", w.nome)
			
			current_weapon_index = i
			_update_visual_selection()
			_atualizar_interface()
			return

	if weapon_pool.size() < MAX_POOL_SIZE:
		var dup = new_weapon_res.duplicate()
		weapon_pool.append(dup)
		current_weapon_index = weapon_pool.size() - 1
		_update_visual_selection()
		print("Nova arma adicionada ao pool: ", dup.nome)
	else:
		print("Pool cheio! Não é possível carregar mais armas.")
	
	_atualizar_interface()

func _switch_weapon(direction: int):
	if weapon_pool.size() <= 1: return 
	
	current_weapon_index += direction
	
	if current_weapon_index >= weapon_pool.size():
		current_weapon_index = 0
	elif current_weapon_index < 0:
		current_weapon_index = weapon_pool.size() - 1
		
	_update_visual_selection()
	_atualizar_interface()

func _update_visual_selection():
	_reset_weapon_visibility()
	var active = get_active_special()
	if active and weapon_nodes.has(active.nome):
		weapon_nodes[active.nome].visible = true

func _reset_weapon_visibility():
	for key in weapon_nodes:
		if key != "MachineGun":
			weapon_nodes[key].visible = false

# --- LÓGICA DE TIRO ---

func fire_basic_weapon():
	if not basic_weapon_resource: return
	basic_cooldown = fire_rate_basic 
	_muzzle_flash_effect("MachineGun")
	_spawn_projectile(basic_weapon_resource, "MachineGun")

func fire_special_weapon():
	var active = get_active_special()
	if not active or active.ammo <= 0: return
		
	if special_cooldowns.get(active.nome, 0.0) > 0: return
	
	special_cooldowns[active.nome] = active.fire_rate
	_muzzle_flash_effect(active.nome)
	_spawn_projectile(active, active.nome)
	
	active.ammo -= 1
	if active.ammo <= 0:
		_remove_current_weapon()
	
	_atualizar_interface()

func _remove_current_weapon():
	weapon_pool.remove_at(current_weapon_index)
	
	if weapon_pool.size() == 0:
		current_weapon_index = -1
		_reset_weapon_visibility()
	else:
		current_weapon_index = clamp(current_weapon_index - 1, 0, weapon_pool.size() - 1)
		_update_visual_selection()
	
	_atualizar_interface()

func _spawn_projectile(res: WeaponResource, node_name: String):
	var proj = ProjectilePool.get_projectile(res.projectile_scene)
	var muzzle = weapon_nodes[node_name].find_child("Muzzle", true, false)
	
	if muzzle:
		proj.global_transform = muzzle.global_transform
	
	if proj.has_method("setup"):
		if node_name == "HomingMissile" or node_name == "GrapplingMissile":
			proj.setup(res.dano, car.linear_velocity, car, current_target)
		else:
			proj.setup(res.dano, car.linear_velocity, car)

func _muzzle_flash_effect(node_name: String):
	var light = weapon_nodes[node_name].find_child("OmniLight3D", true, false)
	if light:
		light.visible = true
		get_tree().create_timer(0.05).timeout.connect(func(): light.visible = false)

# --- ATUALIZAÇÃO DE INTERFACE MULTIPLAYER ---

func _atualizar_interface():
	var target_group = "HUD" + player_suffix
	var hud = get_tree().get_first_node_in_group(target_group)
	
	if hud and hud.has_method("atualizar_arma"):
		var active = get_active_special()
		if active:
			hud.atualizar_arma(active.nome, active.ammo)
		else:
			hud.atualizar_arma("None", 0)

func _cycle_category(direction: int):
	for i in range(4): 
		current_category_index += direction
		if current_category_index > 3: current_category_index = 0
		elif current_category_index < 0: current_category_index = 3
		
		if _get_category_count(current_category_index) > 0:
			break
	
	manual_target_index = 0 
	_update_radar_and_lockon() 
	print("[Targeting] Categoria alterada para: ", target_categories[current_category_index])

func _get_category_count(index: int) -> int:
	var count = 0
	if index == 0:
		return 1 
	elif index == 1:
		for p in get_tree().get_nodes_in_group("jogadores"):
			if p != car and is_instance_valid(p): count += 1
	elif index == 2:
		for t in get_tree().get_nodes_in_group("inimigos"):
			if is_instance_valid(t): count += 1
	elif index == 3:
		for p in get_tree().get_nodes_in_group("destructibles"):
			if is_instance_valid(p): count += 1
			
	return count

func _validate_initial_category():
	if _get_category_count(current_category_index) == 0:
		_cycle_category(1)

func _cycle_target(direction: int):
	if active_targets_sorted.is_empty(): return
	
	manual_target_index += direction
	if manual_target_index >= active_targets_sorted.size(): manual_target_index = 0
	elif manual_target_index < 0: manual_target_index = active_targets_sorted.size() - 1
	
	_update_radar_and_lockon()

# --- FUNÇÃO AUXILIAR DE VISÃO (LoS) ---
func _has_line_of_sight(target: Node3D) -> bool:
	var space_state = car.get_world_3d().direct_space_state
	# Dispara um raio do teto do carro até o alvo
	var origin = car.global_position + Vector3.UP * 1.5
	var destination = target.global_position + Vector3.UP * 1.0 # Mira no centro da massa
	
	var query = PhysicsRayQueryParameters3D.create(origin, destination, los_collision_mask)
	query.exclude = [car.get_rid(), target.get_rid()] # Ignora o próprio carro e o alvo
	
	var result = space_state.intersect_ray(query)
	
	# Se bateu em algo (que não seja o próprio alvo), significa que não tem visão
	return result.is_empty()

func _update_radar_and_lockon():
	if not is_instance_valid(car): return
	
	var all_players = get_tree().get_nodes_in_group("jogadores")
	var all_turrets = get_tree().get_nodes_in_group("inimigos")
	var all_props = get_tree().get_nodes_in_group("destructibles")
	var all_peds = get_tree().get_nodes_in_group("pedestrians")
	
	var all_targets = all_players + all_turrets + all_props + all_peds
	var car_pos = car.global_position
	var car_forward = car.global_transform.basis.z 
	
	var radar_data = []
	var category_bucket = [] 

	for t in all_targets:
		if not is_instance_valid(t) or t == car: continue
		
		if t.is_in_group("pedestrians") and "is_invincible" in t and t.is_invincible:
			continue
			
		var dist = car_pos.distance_to(t.global_position)
		
		if dist <= radar_range:
			# SEMPRE adiciona no radar (Minimapa) se não for pedestre invencível
			if not t.is_in_group("pedestrians"): 
				radar_data.append(t)
			
			# SÓ adiciona na lista de MIRA se tiver visão livre!
			if _has_line_of_sight(t):
				if current_category_index == 0: 
					category_bucket.append(t)
				elif current_category_index == 1 and t.is_in_group("jogadores"): 
					category_bucket.append(t)
				elif current_category_index == 2 and t.is_in_group("inimigos"): 
					category_bucket.append(t)
				elif current_category_index == 3 and (t.is_in_group("destructibles") or t.is_in_group("pedestrians")): 
					category_bucket.append(t)

	category_bucket.sort_custom(func(a, b):
		var pos_a = a.global_position
		var pos_b = b.global_position
		
		var dir_a = (pos_a - car_pos).normalized()
		var score_a = rad_to_deg(car_forward.angle_to(dir_a)) + (car_pos.distance_to(pos_a) * 0.1)
		
		var dir_b = (pos_b - car_pos).normalized()
		var score_b = rad_to_deg(car_forward.angle_to(dir_b)) + (car_pos.distance_to(pos_b) * 0.1)
		
		return score_a < score_b
	)
	
	active_targets_sorted = category_bucket
	var closest_radar_target = null
	
	if not active_targets_sorted.is_empty():
		manual_target_index = clampi(manual_target_index, 0, active_targets_sorted.size() - 1)
		closest_radar_target = active_targets_sorted[manual_target_index]
		
	current_target = null
	var active = get_active_special()
	
	if is_instance_valid(closest_radar_target) and active and (active.nome == "HomingMissile" or active.nome == "GrapplingMissile"):
		var dist = car_pos.distance_to(closest_radar_target.global_position)
		var angle = rad_to_deg(car_forward.angle_to((closest_radar_target.global_position - car_pos).normalized()))
		
		if dist <= active.lockon_range and angle <= 45.0:
			current_target = closest_radar_target 

	var target_group = "HUD" + player_suffix
	var hud = get_tree().get_first_node_in_group(target_group)
	if hud and hud.has_method("update_radar_data"):
		var cat_name = target_categories[current_category_index]
		hud.update_radar_data(radar_data, closest_radar_target, car_pos, car_forward, current_category_index, cat_name)

func _atualizar_posicao_reticulo():
	var active = get_active_special()
	var target_group = "HUD" + player_suffix
	var hud = get_tree().get_first_node_in_group(target_group)
	
	if not hud: return
	
	var reticle = hud.find_child("Reticle", true, false)
	if not reticle: return

	if active and (active.nome == "HomingMissile" or active.nome == "GrapplingMissile") and is_instance_valid(current_target):
		var camera = get_viewport().get_camera_3d()
		
		if camera and not camera.is_position_behind(current_target.global_position):
			var screen_pos = camera.unproject_position(current_target.global_position)
			reticle.visible = true
			reticle.global_position = hud.get_viewport().get_screen_transform() * screen_pos
		else:
			reticle.visible = false
	else:
		reticle.visible = false
