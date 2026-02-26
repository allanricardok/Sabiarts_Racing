# WeaponManager.gd
extends Node3D

# --- CONFIGURAÇÕES ---
@export_group("Armas")
@export var basic_weapon_resource: WeaponResource # Arraste o Metralhadora.tres aqui
@export var fire_rate_basic : float = 0.12

# --- REFERÊNCIAS ---
@onready var car = owner
@onready var input = %InputComponent

# ADIÇÃO: Chave padronizada para "GrapplingMissile" para bater com o Nó Único (%)
@onready var weapon_nodes = {
	"MachineGun": %MachineGun,
	"BigSlow": %BigSlow,
	"HomingMissile": %HomingMissile,
	"GrapplingMissile": %GrapplingMissile 
}

# Variável para o alvo atual
var current_target: Node3D = null

# --- ESTADO INTERNO ---
var special_weapon: WeaponResource = null
var basic_cooldown : float = 0.0
var special_cooldowns : Dictionary = {} # Guarda { "NomeDaArma": tempo }

func _ready():
	# Começa escondendo as especiais e mostrando a básica
	_reset_weapon_visibility()
	if weapon_nodes.has("MachineGun"):
		weapon_nodes["MachineGun"].visible = true
	_atualizar_interface()

func _process(delta):
	# Diminui o cooldown da básica
	if basic_cooldown > 0:
		basic_cooldown -= delta
	
	# Diminui o cooldown de todas as especiais no dicionário
	for weapon_name in special_cooldowns.keys():
		if special_cooldowns[weapon_name] > 0:
			special_cooldowns[weapon_name] -= delta
		
	if not car.pode_mover: return

	# 1. TIRO BÁSICO (Metralhadora - Segurar Botão)
	if input.is_action_pressed and basic_cooldown <= 0:
		# Trava de segurança: não atira se estiver usando habilidades (direcionais)
		var is_doing_ability = (input.ability_up or input.ability_down or input.ability_left or input.ability_right)
		if not is_doing_ability:
			fire_basic_weapon()

	# 2. TIRO ESPECIAL (Aperto Único)
	var action_name = "Fire" + input.suffix
	if Input.is_action_just_pressed(action_name):
		fire_special_weapon()
	
	# CORREÇÃO: Busca alvo se for HomingMissile OU GrapplingMissile
	if special_weapon and (special_weapon.nome == "HomingMissile" or special_weapon.nome == "GrapplingMissile"):
		_find_lockon_target()

# --- LÓGICA DE EQUIPAMENTO ---

func equip_special_weapon(new_weapon_res: WeaponResource):
	# 1. Se o jogador já tem ESSA MESMA arma, apenas somamos a munição
	if special_weapon and special_weapon.nome == new_weapon_res.nome:
		special_weapon.ammo += new_weapon_res.ammo
		print("Munição acumulada! Total: ", special_weapon.ammo)
		_atualizar_interface()
		return 
	
	# 2. Se for uma arma diferente, equipa do zero
	special_weapon = new_weapon_res.duplicate()
	_reset_weapon_visibility()
	
	if weapon_nodes.has(special_weapon.nome):
		weapon_nodes[special_weapon.nome].visible = true
		weapon_nodes["MachineGun"].visible = true 
		
	# Inicializa o cooldown dessa arma no dicionário caso seja nova
	if not special_cooldowns.has(special_weapon.nome):
		special_cooldowns[special_weapon.nome] = 0.0
		
	print("Nova Arma Especial: ", special_weapon.nome, " | Munição: ", special_weapon.ammo)
	_atualizar_interface()

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
	if not special_weapon or special_weapon.ammo <= 0:
		return
		
	if special_cooldowns.get(special_weapon.nome, 0.0) > 0:
		return
	
	special_cooldowns[special_weapon.nome] = special_weapon.fire_rate
	
	_muzzle_flash_effect(special_weapon.nome)
	_spawn_projectile(special_weapon, special_weapon.nome)
	
	if special_weapon.ammo > 0:
		special_weapon.ammo -= 1
	
	if special_weapon.ammo <= 0:
		_deplete_special_weapon()
	_atualizar_interface()

func _spawn_projectile(res: WeaponResource, node_name: String):
	var proj = res.projectile_scene.instantiate()
	# Aqui o node_name precisa bater com as chaves do weapon_nodes ("GrapplingMissile")
	var muzzle = weapon_nodes[node_name].find_child("Muzzle", true, false)
	
	if muzzle:
		proj.global_transform = muzzle.global_transform
	
	get_tree().current_scene.add_child(proj)
	
	if proj.has_method("setup"):
		# CORREÇÃO: GrapplingMissile também recebe o alvo (current_target)
		if node_name == "HomingMissile" or node_name == "GrapplingMissile":
			proj.setup(res.dano, car.linear_velocity, car, current_target)
		else:
			proj.setup(res.dano, car.linear_velocity, car)

func _muzzle_flash_effect(node_name: String):
	var light = weapon_nodes[node_name].find_child("OmniLight3D", true, false)
	if light:
		light.visible = true
		await get_tree().create_timer(0.05).timeout
		light.visible = false

func _deplete_special_weapon():
	if weapon_nodes.has(special_weapon.nome):
		weapon_nodes[special_weapon.nome].visible = false
	special_weapon = null
	print("Arma especial acabou!")
	_atualizar_interface()

func _atualizar_interface():
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		if special_weapon:
			hud.atualizar_arma(special_weapon.nome, special_weapon.ammo)
		else:
			hud.atualizar_arma("None", 0)
			
func _find_lockon_target():
	var targets = get_tree().get_nodes_in_group("Enemies")
	var best_target = null
	var min_angle = 35.0 
	var max_dist = 120.0 
	
	# "Frente" do modelo é o Z positivo
	var car_forward = car.global_transform.basis.z 

	for t in targets:
		if not is_instance_valid(t): continue
		var dir = (t.global_position - car.global_position).normalized()
		
		var angle = rad_to_deg(car_forward.angle_to(dir))
		var dist = car.global_position.distance_to(t.global_position)
		
		if angle < min_angle and dist < max_dist:
			best_target = t
			min_angle = angle 
			
	current_target = best_target
