# No seu HUD.gd ou um script de Reticulo.gd
extends Control

@onready var lockon_rect = $LockOnRect # Um TextureRect ou Panel com borda vermelha

func _process(_delta):
	var car = get_tree().get_first_node_in_group("jogadores") # Garanta que seu carro está nesse grupo
	if not car: return
	
	var weapon_manager = car.find_child("WeaponManager")
	var target = weapon_manager.current_target
	
	if target and is_instance_valid(target):
		# Transforma a posição 3D do inimigo em posição 2D na sua tela
		var cam = get_viewport().get_camera_3d()
		var screen_pos = cam.unproject_position(target.global_position)
		
		# Se o alvo estiver na frente da câmera (não atrás)
		if not cam.is_position_behind(target.global_position):
			lockon_rect.visible = true
			lockon_rect.position = screen_pos - (lockon_rect.size / 2)
		else:
			lockon_rect.visible = false
	else:
		lockon_rect.visible = false
