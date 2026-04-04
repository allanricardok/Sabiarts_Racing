# CameraShake.gd (Anexe no Node filho da Camera3D)
extends Node
class_name CameraShake

@export_group("Configurações Base (Ondas)")
@export var max_offset := Vector2(0.2, 0.2) 
@export var max_roll := 3.0 
@export var shake_speed := 40.0 

@export_group("Velocidade Contínua")
@export var speed_shake_min_kmh := 50.0
@export var speed_shake_max_kmh := 140.0
@export var speed_shake_max_force := 0.12 # 12%

@export_group("Gatilhos de Impacto (Força e Duração)")
@export var turbo_force := 0.25
@export var turbo_duration := 0.8

@export var hard_land_force := 0.15
@export var hard_land_duration := 0.3

@export var weapon_fire_force := 0.05
@export var weapon_fire_duration := 0.3

@export var damage_force := 0.15
@export var damage_duration := 0.5

@export var obj_collision_force := 0.15
@export var obj_collision_duration := 0.5

# O de batida de carro usa um "Mínimo e Máximo" baseado no dano
@export var car_collision_min_force := 0.15
@export var car_collision_max_force := 0.50
@export var car_collision_duration := 0.5

@export var stunt_force := 0.10
@export var stunt_duration := 0.3

# --- VARIÁVEIS INTERNAS ---
var time_passed := 0.0
var impulse_force := 0.0
var shake_timer := 0.0
var shake_duration := 1.0

var car : BaseVehicle
var cam : Camera3D

func _ready():
	cam = get_parent() as Camera3D
	var current_node = self
	while current_node and not current_node is BaseVehicle:
		current_node = current_node.get_parent()
	car = current_node as BaseVehicle

# NOVO: O gerenciador de Eventos! Ele lê o nome e puxa as variáveis do Inspector
func trigger_event(event_name: String, modifier: float = 1.0):
	var force = 0.0
	var duration = 0.0
	
	match event_name:
		"Turbo":
			force = turbo_force; duration = turbo_duration
		"HardLand":
			force = hard_land_force; duration = hard_land_duration
		"WeaponFire":
			force = weapon_fire_force; duration = weapon_fire_duration
		"Damage":
			force = damage_force; duration = damage_duration
		"ObjCollision":
			force = obj_collision_force; duration = obj_collision_duration
		"Stunt":
			force = stunt_force; duration = stunt_duration
		"CarCollision":
			# O modifier aqui será o dano sofrido (de 8 a 50)
			force = clamp(remap(modifier, 8.0, 50.0, car_collision_min_force, car_collision_max_force), car_collision_min_force, car_collision_max_force)
			duration = car_collision_duration
	
	print("[SHAKE] Evento: '", event_name, "' | Força: ", int(force * 100), "% | Duração: ", duration, "s")
	
	if duration > 0:
		impulse_force = max(impulse_force, force)
		shake_timer = max(shake_timer, duration)
		shake_duration = max(shake_duration, duration)

func _process(delta):
	if not is_instance_valid(car) or not is_instance_valid(cam): return
	
	time_passed += delta * shake_speed
	
	var current_impulse = 0.0
	if shake_timer > 0:
		shake_timer -= delta
		var progress = max(shake_timer / shake_duration, 0.0)
		current_impulse = impulse_force * (progress * progress)
	else:
		impulse_force = 0.0 

	# --- SHAKE DE VELOCIDADE (APENAS NO CHÃO) ---
	var speed_shake = 0.0
	var is_grounded = true
	var input_comp = car.get_node_or_null("%InputComponent")
	if input_comp and "is_grounded" in input_comp:
		is_grounded = input_comp.is_grounded
		
	if is_grounded:
		var kmh = car.linear_velocity.length() * 2.3
		if kmh > speed_shake_min_kmh:
			speed_shake = clamp(remap(kmh, speed_shake_min_kmh, speed_shake_max_kmh, 0.0, speed_shake_max_force), 0.0, speed_shake_max_force)
		
	var total_trauma = min(current_impulse + speed_shake, 1.0)
	
	if total_trauma > 0.0:
		cam.h_offset = max_offset.x * total_trauma * sin(time_passed * 1.1) * cos(time_passed * 0.8)
		cam.v_offset = max_offset.y * total_trauma * total_trauma * sin(time_passed * 1.3) * cos(time_passed * 0.9)
		cam.rotation_degrees.z = max_roll * total_trauma * sin(time_passed * 1.0) * cos(time_passed * 0.7)
	else:
		cam.h_offset = lerp(cam.h_offset, 0.0, delta * 10.0)
		cam.v_offset = lerp(cam.v_offset, 0.0, delta * 10.0)
		cam.rotation_degrees.z = lerp(cam.rotation_degrees.z, 0.0, delta * 10.0)
		time_passed = 0.0
