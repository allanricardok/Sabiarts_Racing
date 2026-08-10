# TireBloodManager.gd
extends Node
class_name TireBloodManager

@export_group("Referências")
@export var wheel_front_left: VehicleWheel3D
@export var wheel_front_right: VehicleWheel3D
@export var wheel_rear_left: VehicleWheel3D
@export var wheel_rear_right: VehicleWheel3D

@export_group("Configurações do Rastro")
# Aumentado para criar seções de rastro muito maiores e economizar recursos
@export var spawn_distance: float = 1.2 
@export var tire_blood_duration: float = 5.0 
@export var stain_life_time: float = 5.0 
@export var pool_size: int = 360 # Reduzido para melhorar a performance de memória

var _is_human: bool = true
var _current_blood_time: float = 0.0
var _is_bleeding: bool = false

var _last_spawn_pos_fl: Vector3
var _last_spawn_pos_fr: Vector3
var _last_spawn_pos_rl: Vector3
var _last_spawn_pos_rr: Vector3

var _generated_blood_tex: ImageTexture
var _sprite_pool: Array[Sprite3D] = []
var _pool_index: int = 0
var _active_tweens: Dictionary = {}

@onready var car = owner as VehicleBody3D

func _ready():
	# --- FILTRO DE OTIMIZAÇÃO: Verifica se o dono do carro é um bot ---
	var input = car.get_node_or_null("%InputComponent")
	if input and "is_bot" in input and input.is_bot:
		_is_human = false
		
	# Se for bot, desliga o processamento de física e aborta a criação da Pool! (Salva muito FPS)
	if not _is_human:
		set_physics_process(false)
		return
		
	# Fluxo normal apenas para o jogador
	_last_spawn_pos_fl = Vector3.ZERO
	_last_spawn_pos_fr = Vector3.ZERO
	_last_spawn_pos_rl = Vector3.ZERO
	_last_spawn_pos_rr = Vector3.ZERO
	
	_generate_blood_texture()
	_initialize_pool()

func infect_tires():
	# Trava de segurança: Se não for humano, ignora a infecção
	if not _is_human: return
	
	_current_blood_time = tire_blood_duration
	
	if not _is_bleeding:
		_is_bleeding = true
		
		if is_instance_valid(wheel_front_left):
			_last_spawn_pos_fl = wheel_front_left.get_contact_point()
		if is_instance_valid(wheel_front_right):
			_last_spawn_pos_fr = wheel_front_right.get_contact_point()
		if is_instance_valid(wheel_rear_left):
			_last_spawn_pos_rl = wheel_rear_left.get_contact_point()
		if is_instance_valid(wheel_rear_right):
			_last_spawn_pos_rr = wheel_rear_right.get_contact_point()

func _generate_blood_texture():
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var base_color = Color(0.49, 0.0, 0.0, 0.949)
	
	for x in range(64):
		for y in range(64):
			var dist_x = abs(x - 32.0) / 32.0
			var alpha = 1.0
			
			if dist_x > 0.7: 
				alpha = 1.0 - ((dist_x - 0.7) / 0.3)
				
			var final_color = base_color
			final_color.a *= alpha
			img.set_pixel(x, y, final_color)
			
	_generated_blood_tex = ImageTexture.create_from_image(img)

func _initialize_pool():
	var container = Node3D.new()
	container.name = "BloodTracksContainer"
	container.set_as_top_level(true) 
	add_child(container)
	
	for i in range(pool_size):
		var sprite = Sprite3D.new()
		sprite.texture = _generated_blood_tex
		sprite.axis = Vector3.AXIS_Y 
		sprite.transparent = true
		sprite.visible = false
		sprite.pixel_size = 0.005
		
		container.add_child(sprite)
		_sprite_pool.append(sprite)


func _physics_process(delta):
	if not _is_bleeding or not is_instance_valid(car): return
	
	_current_blood_time -= delta
	if _current_blood_time <= 0:
		_is_bleeding = false
		return
		
	var time_spent = tire_blood_duration - _current_blood_time
	var intensity = 1.0
	
	if time_spent < 0.2:
		intensity = remap(time_spent, 0.0, 0.2, 0.0, 1.0)
	else:
		intensity = remap(_current_blood_time, tire_blood_duration - 0.2, 0.0, 1.0, 0.0)
	
	_last_spawn_pos_fl = _check_and_spawn_track(wheel_front_left, _last_spawn_pos_fl, intensity)
	_last_spawn_pos_fr = _check_and_spawn_track(wheel_front_right, _last_spawn_pos_fr, intensity)
	_last_spawn_pos_rl = _check_and_spawn_track(wheel_rear_left, _last_spawn_pos_rl, intensity)
	_last_spawn_pos_rr = _check_and_spawn_track(wheel_rear_right, _last_spawn_pos_rr, intensity)

func _check_and_spawn_track(wheel: VehicleWheel3D, last_pos: Vector3, intensity: float) -> Vector3:
	if not is_instance_valid(wheel) or not wheel.is_in_contact(): 
		return last_pos
	
	var current_pos = wheel.get_contact_point()
	
	if current_pos.length_squared() < 0.1:
		current_pos = wheel.global_position - (wheel.global_transform.basis.y * wheel.wheel_radius)
	
	var dist = current_pos.distance_to(last_pos)
	
	if dist >= spawn_distance:
		_spawn_sprite(current_pos, last_pos, intensity, dist)
		return current_pos
		
	return last_pos

func _spawn_sprite(current_pos: Vector3, last_pos: Vector3, intensity: float, dist: float):
	var sprite = _sprite_pool[_pool_index]
	
	if _active_tweens.has(sprite) and is_instance_valid(_active_tweens[sprite]):
		_active_tweens[sprite].kill()
	
	var mid_pos = (current_pos + last_pos) / 2.0
	sprite.global_position = mid_pos
	
	sprite.global_position.y = current_pos.y + randf_range(0.01, 0.02)
	
	var look_target = current_pos
	look_target.y = sprite.global_position.y 
	
	if dist > 0.001:
		sprite.look_at(look_target, Vector3.UP)
		
	var base_length = 64.0 * 0.005 
	sprite.scale = Vector3(1.0, 1.0, dist / base_length)
	
	sprite.modulate.a = intensity
	sprite.visible = true
	
	# === AS DUAS BLINDAGENS ESTÃO AQUI ===
	# 1. bind_node(sprite) atrela a vida do Tween à vida do Sprite
	var tween = get_tree().create_tween().bind_node(sprite)
	
	tween.tween_interval(4.0)
	tween.tween_property(sprite, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
	
	# 2. is_instance_valid() garante que o código só roda se o sprite existir
	tween.tween_callback(func(): 
		if is_instance_valid(sprite):
			sprite.visible = false
	)
	
	_active_tweens[sprite] = tween
	_pool_index = (_pool_index + 1) % pool_size
