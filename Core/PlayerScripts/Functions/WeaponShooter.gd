# WeaponShooter.gd
extends Node
class_name WeaponShooter

var car: VehicleBody3D
var targeting: Node
var weapon_nodes: Dictionary
var basic_weapon_resource: WeaponResource
var fire_rate_basic: float

var basic_cooldown: float = 0.0
var special_cooldowns: Dictionary = {}

var _basic_fire_time: float = 0.0

func setup(_car, _targeting, _weapon_nodes, _basic_res, _fire_rate):
	car = _car
	targeting = _targeting
	weapon_nodes = _weapon_nodes
	basic_weapon_resource = _basic_res
	fire_rate_basic = _fire_rate

func process_shooting(delta: float, is_firing_basic: bool):
	if basic_cooldown > 0: basic_cooldown -= delta
	for w in special_cooldowns.keys():
		if special_cooldowns[w] > 0: special_cooldowns[w] -= delta
		
	if not is_firing_basic:
		_basic_fire_time = 0.0
	else:
		_basic_fire_time += delta
		if basic_cooldown <= 0:
			_fire_basic_weapon()

func _fire_basic_weapon():
	if not basic_weapon_resource: return
	
	var rage = car.get_node_or_null("%RageComponent")
	var rage_mult = rage.get_fire_rate_mult() if rage else 1.0
	
	var heat_efficiency = 1.0
	if _basic_fire_time > 1.0:
		heat_efficiency = remap(clamp(_basic_fire_time, 1.0, 4.0), 1.0, 4.0, 1.0, 0.25)
		
	basic_cooldown = fire_rate_basic / (heat_efficiency * rage_mult) 
	var weapon_name = basic_weapon_resource.nome
	
	_muzzle_flash_effect(weapon_name)
	var proj = _spawn_projectile(basic_weapon_resource, weapon_name, false)
	
	if is_instance_valid(proj) and "is_special_weapon" in proj:
		proj.is_special_weapon = false

func try_fire_special(active_weapon: WeaponResource, backwards: bool = false) -> bool:
	if not active_weapon or active_weapon.ammo <= 0: return false
	if special_cooldowns.get(active_weapon.nome, 0.0) > 0: return false
	
	var rage = car.get_node_or_null("%RageComponent")
	var rate_mult = rage.get_fire_rate_mult() if rage else 1.0
	
	special_cooldowns[active_weapon.nome] = active_weapon.fire_rate / rate_mult
	
	_muzzle_flash_effect(active_weapon.nome)
	_spawn_projectile(active_weapon, active_weapon.nome, backwards)
	return true # Disparo bem sucedido

func _spawn_projectile(res: WeaponResource, node_name: String, backwards: bool = false):
	var proj = ProjectilePool.get_projectile(res.projectile_scene)
	var muzzle = weapon_nodes[node_name].find_child("Muzzle", true, false)
	
	var car_forward = car.global_transform.basis.z.normalized()
	var spawn_pos = car.global_position
	var shoot_dir = car_forward
	
	if muzzle:
		spawn_pos = muzzle.global_position
		shoot_dir = -muzzle.global_transform.basis.z.normalized()
		
	if backwards:
		shoot_dir = -car_forward
		spawn_pos = car.global_position + (shoot_dir * 4.0) + Vector3(0, 0.8, 0)
		
	proj.global_position = spawn_pos
	proj.look_at(spawn_pos + shoot_dir, Vector3.UP)
	
	if "is_special_weapon" in proj: 
		proj.is_special_weapon = (node_name != "MachineGun")
	
	proj.set("is_shot_backwards", backwards)
	
	if proj.has_method("setup"):
		var prop_speed: float = res.speed if "speed" in res else 80.0
		
		if node_name == "HomingMissile" or node_name == "GrapplingMissile" or node_name == "FreezingMissile":
			var valid_target = null
			if is_instance_valid(targeting) and not backwards:
				var potential_target = targeting.current_target
				if is_instance_valid(potential_target) and not potential_target.is_queued_for_deletion():
					valid_target = potential_target
			proj.setup(res.dano, car.linear_velocity, car, prop_speed, valid_target)
		else:
			proj.setup(res.dano, car.linear_velocity, car, prop_speed)
			
	return proj

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
