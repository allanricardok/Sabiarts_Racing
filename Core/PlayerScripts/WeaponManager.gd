# WeaponManager.gd
extends Node3D

@export var basic_weapon_resource: WeaponResource # Arraste o .tres da metralhadora aqui
@onready var machine_gun_raycast = %MachineGunRayCast
@onready var input_node = %InputComponent

# Sistema de Slots
var weapon_slots: Array[WeaponResource] = [null, null, null, null, null]
var current_slot_index: int = 0

@onready var mount_points = {
	"top": %MountTop,
	"left": %MountLeft,
	"right": %MountRight
}

# WeaponManager.gd
func _process(_delta):
	var input = input_node# Só atira se o ACTION estiver pressionado E nenhum direcional de habilidade estiver ativo
	if input.is_action_pressed:
		var is_doing_ability = (input.ability_up or input.ability_down or input.ability_left or input.ability_right)
		
		if not is_doing_ability:
			fire_basic_weapon()

func fire_basic_weapon():
	if not basic_weapon_resource: return
	
	# Raycast para performance em metralha infinita (12 carros atirando)
	if machine_gun_raycast.is_colliding():
		var target = machine_gun_raycast.get_collider()
		if target.has_method("take_damage"):
			target.take_damage(basic_weapon_resource.dano)
			# Aqui você pode instanciar uma fagulha no ponto de colisão
			print("Acertou: ", target.name)

func fire_special_weapon():
	var active_weapon = weapon_slots[current_slot_index]
	if active_weapon == null or active_weapon.ammo <= 0: return
	
	# 1. Instancia o projétil
	var projectile = active_weapon.projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	
	# 2. Posiciona no Mount Point (Padrão: Top)
	projectile.global_transform = mount_points["top"].global_transform
	
	# 3. Lógica de Atirador (Para evitar fogo amigo se necessário)
	if projectile.has_method("set_shooter"):
		projectile.set_shooter(get_parent())

	# 4. Consumo de munição e buffs
	active_weapon.ammo -= 1
	if active_weapon.ammo <= 0:
		_remover_arma_atual()

func add_weapon(new_weapon: WeaponResource):
	# Procura o primeiro slot vazio ou substitui o atual
	for i in range(weapon_slots.size()):
		if weapon_slots[i] == null:
			weapon_slots[i] = new_weapon.duplicate() # Duplicate para não gastar o recurso original
			return
	weapon_slots[current_slot_index] = new_weapon.duplicate()

func _remover_arma_atual():
	weapon_slots[current_slot_index] = null
	# Se for uma máscara, podemos chamar o reset de stats aqui
	get_parent().stats.reset_to_base()
