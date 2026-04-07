# WeaponManager.gd
extends Node3D
class_name WeaponManager

# --- CONFIGURAÇÕES ---
@export_group("Armas")
@export var basic_weapon_resource: WeaponResource 
@export var fire_rate_basic : float = 0.12
@export var MAX_POOL_SIZE : int = 5 
var _previous_radar_mode : int = -1

# --- REFERÊNCIAS ---
@onready var car = owner
@onready var input = %InputComponent
@onready var targeting = %TargetingComponent

# --- DICIONÁRIO DE ARMAS ---
@onready var weapon_nodes = {
	"MachineGun": %MachineGun,
	"BigSlow": %BigSlow,
	"HomingMissile": %HomingMissile,
	"GrapplingMissile": %GrapplingMissile,
	"FreezingMissile": %FreezingMissile 
}

# --- ESTADO INTERNO ---
var weapon_pool : Array[WeaponResource] = [] 
var current_weapon_index : int = -1 
var basic_cooldown : float = 0.0
var special_cooldowns : Dictionary = {}
var player_suffix : String = "" 

# --- VISUAL E DESTAQUE ---
var highlight_material : StandardMaterial3D

# --- PONTE PARA A HUD NÃO QUEBRAR ---
var current_target: Node3D:
	get:
		if is_instance_valid(targeting) and is_instance_valid(targeting.current_target):
			return targeting.current_target
		return null

# --- SUPERAQUECIMENTO ---
var _basic_fire_time : float = 0.0
var _recovery_timer : float = 0.0
var _is_recovering : bool = false
var _was_firing : bool = false

func _ready():
	highlight_material = StandardMaterial3D.new()
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.albedo_color = Color(1.0, 0.8, 0.0, 0.4)
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	
	_update_visual_selection()

func setup_multiplayer(suffix: String):
	player_suffix = suffix
	if is_instance_valid(targeting):
		targeting.setup_multiplayer(suffix)
	_atualizar_interface()

func _process(delta):
	var is_bot = (input and "is_bot" in input and input.is_bot)
	var real_delta = delta / Engine.time_scale if is_instance_valid(car) and car.is_in_group("jogadores") and not is_bot else delta

	if basic_cooldown > 0: basic_cooldown -= real_delta
	for w in special_cooldowns.keys():
		if special_cooldowns[w] > 0: special_cooldowns[w] -= real_delta
		
	if not car.pode_mover: return
	
	# CADEADO DO GELO
	if car.has_method("is_frozen") and car.is_frozen(): 
		_was_firing = false 
		return 

	# --- CORREÇÃO DO INPUT COMPARTILHADO ---
	var is_firing = false
	
	if is_bot:
		# Se for Bot, ele atira quando o Cérebro manda
		is_firing = input.is_action_pressed 
	else:
		# Se for Player, ele lê a variável que o InputComponent JÁ SEPAROU pra ele!
		var is_doing_ability = (input.ability_up or input.ability_down or input.ability_left or input.ability_right)
		
		# USANDO O COMPONENTE para a Metralhadora
		is_firing = input.is_action_pressed and not is_doing_ability

		# --- RECUPERANDO O TIRO ESPECIAL E A TROCA DE ARMAS! ---
		if Input.is_action_just_pressed("prev_weapon" + input.suffix): _switch_weapon(-1)
		if Input.is_action_just_pressed("next_weapon" + input.suffix): _switch_weapon(1)
		if Input.is_action_just_pressed("Fire" + input.suffix): fire_special_weapon()

	if not is_firing and _was_firing:
		_is_recovering = true
		_recovery_timer = 0.0

	if _is_recovering:
		_recovery_timer += real_delta
		if _recovery_timer >= 2.0:
			_basic_fire_time = 0.0
			_is_recovering = false

	if is_firing:
		_basic_fire_time += real_delta
		if basic_cooldown <= 0:
			fire_basic_weapon()

	_was_firing = is_firing

# --- GESTÃO DO INVENTÁRIO (POOL) ---

func get_active_special() -> WeaponResource:
	if current_weapon_index >= 0 and current_weapon_index < weapon_pool.size():
		return weapon_pool[current_weapon_index]
	return null

# --- CORREÇÃO: FUNÇÃO DE EQUIPAR BLINDADA CONTRA DUPLICATAS ---
func equip_special_weapon(new_weapon_res: WeaponResource):
	# 1. Pega o nome verdadeiro da arma de forma segura
	var resource_name_to_check = ""
	if "nome" in new_weapon_res and new_weapon_res.nome != "":
		resource_name_to_check = new_weapon_res.nome
	else:
		resource_name_to_check = new_weapon_res.resource_path.get_file().get_basename()

	# 2. Procura na mochila se já temos essa arma
	for i in range(weapon_pool.size()):
		var w = weapon_pool[i]
		var current_w_name = ""
		
		if "nome" in w and w.nome != "":
			current_w_name = w.nome
		else:
			current_w_name = w.resource_path.get_file().get_basename()

		# Se o nome bater OR o caminho do arquivo for idêntico: É A MESMA ARMA! Empilha!
		if current_w_name == resource_name_to_check or (w.resource_path != "" and w.resource_path == new_weapon_res.resource_path):
			w.ammo += new_weapon_res.ammo
			current_weapon_index = i
			_update_visual_selection()
			_atualizar_interface()
			get_tree().call_group("TutorialUI", "complete_task", "grab_weapon")
			return

	# 3. Se passou do loop, é uma arma inédita. Coloca num novo slot da mochila.
	if weapon_pool.size() < MAX_POOL_SIZE:
		var dup = new_weapon_res.duplicate()
		weapon_pool.append(dup)
		current_weapon_index = weapon_pool.size() - 1
		_update_visual_selection()
	
	_atualizar_interface()
	get_tree().call_group("TutorialUI", "complete_task", "grab_weapon")


func _switch_weapon(direction: int):
	if weapon_pool.size() <= 1: return 
	current_weapon_index += direction
	if current_weapon_index >= weapon_pool.size(): current_weapon_index = 0
	elif current_weapon_index < 0: current_weapon_index = weapon_pool.size() - 1
		
	_update_visual_selection()
	_atualizar_interface()

func _set_weapon_highlight(weapon_name: String, is_active: bool):
	var node = weapon_nodes.get(weapon_name)
	if not is_instance_valid(node): return
	var meshes = node.find_children("*", "MeshInstance3D", true)
	for mesh in meshes:
		if is_active: mesh.material_overlay = highlight_material
		else: mesh.material_overlay = null

# --- LÓGICA DE TIRO ---

func fire_basic_weapon():
	if not basic_weapon_resource: return
	
	var rage = car.get_node_or_null("%RageComponent")
	var rage_mult = rage.get_fire_rate_mult() if rage else 1.0
	
	var heat_efficiency = 1.0
	if _basic_fire_time > 2.0:
		heat_efficiency = remap(clamp(_basic_fire_time, 1.0, 10.0), 1.0, 10.0, 1.0, 0.25)
		
	basic_cooldown = fire_rate_basic / (heat_efficiency * rage_mult) 
	
	var weapon_name = basic_weapon_resource.nome
	
	_muzzle_flash_effect(weapon_name)
	_spawn_projectile(basic_weapon_resource, weapon_name)

func fire_special_weapon():
	var active = get_active_special()
	if not active or active.ammo <= 0: return
	if special_cooldowns.get(active.nome, 0.0) > 0: return
	
	var rage = car.get_node_or_null("%RageComponent")
	var rate_mult = rage.get_fire_rate_mult() if rage else 1.0
	
	special_cooldowns[active.nome] = active.fire_rate / rate_mult
	_muzzle_flash_effect(active.nome)
	_spawn_projectile(active, active.nome)
	car.play_camera_shake("WeaponFire")
	
	active.ammo -= 1
	if active.ammo <= 0: _remove_current_weapon()
	_atualizar_interface()

func _remove_current_weapon():
	weapon_pool.remove_at(current_weapon_index)
	if weapon_pool.size() == 0:
		current_weapon_index = -1
	else:
		current_weapon_index = clamp(current_weapon_index - 1, 0, weapon_pool.size() - 1)
	
	_update_visual_selection()
	_atualizar_interface()

func _spawn_projectile(res: WeaponResource, node_name: String):
	var proj = ProjectilePool.get_projectile(res.projectile_scene)
	var muzzle = weapon_nodes[node_name].find_child("Muzzle", true, false)
	
	if muzzle: proj.global_transform = muzzle.global_transform
	
	if "is_special_weapon" in proj: proj.is_special_weapon = (node_name != "MachineGun")
	
	if proj.has_method("setup"):
		if node_name == "HomingMissile" or node_name == "GrapplingMissile" or node_name == "FreezingMissile":
			var target = targeting.current_target if is_instance_valid(targeting) else null
			proj.setup(res.dano, car.linear_velocity, car, target)
		else:
			proj.setup(res.dano, car.linear_velocity, car)

func _muzzle_flash_effect(node_name: String):
	if not weapon_nodes.has(node_name) or not is_instance_valid(weapon_nodes[node_name]): 
		return
		
	var light = weapon_nodes[node_name].find_child("OmniLight3D", true, false)
	if is_instance_valid(light):
		light.visible = true
		get_tree().create_timer(0.05).timeout.connect(func(): 
			if is_instance_valid(light):
				light.visible = false
		)

func _update_visual_selection():
	for key in weapon_nodes:
		if key != "MachineGun": weapon_nodes[key].visible = false
		_set_weapon_highlight(key, false)
		
	if weapon_nodes.has("MachineGun"): weapon_nodes["MachineGun"].visible = true

	for w in weapon_pool:
		if weapon_nodes.has(w.nome): weapon_nodes[w.nome].visible = true

	var active = get_active_special()
	if active and weapon_nodes.has(active.nome): 
		_set_weapon_highlight(active.nome, true)
		
	if is_instance_valid(targeting) and "current_category_index" in targeting:
		if active and active.nome == "GrapplingMissile":
			if _previous_radar_mode == -1:
				_previous_radar_mode = targeting.current_category_index
			targeting.current_category_index = 0
		else:
			if _previous_radar_mode != -1:
				targeting.current_category_index = _previous_radar_mode
				_previous_radar_mode = -1

func _atualizar_interface():
	if input and "is_bot" in input and input.is_bot: 
		return
		
	var hud = get_tree().get_first_node_in_group("HUD" + player_suffix)
	if hud and hud.has_method("atualizar_arma"):
		var active = get_active_special()
		
		if active: 
			hud.atualizar_arma(active.nome, active.ammo)
		else: 
			hud.atualizar_arma("None", 0)
