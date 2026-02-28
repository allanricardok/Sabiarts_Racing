extends Control

@onready var lockon_rect = $LockOnRect # Um TextureRect ou Panel com borda vermelha

func _process(_delta):
	# --- SOLUÇÃO MULTIPLAYER (SPLIT-SCREEN) ---
	# Em vez de pegar o primeiro carro geral, procuramos o carro 
	# que está renderizando dentro do MESMO Viewport que este retículo.
	var car = null
	var todos_jogadores = get_tree().get_nodes_in_group("jogadores")
	
	for c in todos_jogadores:
		if c.get_viewport() == get_viewport():
			car = c
			break
	
	# Se não achou um carro neste viewport, esconde o retículo e aborta
	if not car: 
		lockon_rect.visible = false
		return
	
	var weapon_manager = car.find_child("WeaponManager")
	if not weapon_manager:
		lockon_rect.visible = false
		return
		
	var target = weapon_manager.current_target
	
	if target and is_instance_valid(target):
		# Transforma a posição 3D do inimigo em posição 2D na sua tela
		var cam = get_viewport().get_camera_3d()
		
		if cam:
			var screen_pos = cam.unproject_position(target.global_position)
			
			# Se o alvo estiver na frente da câmera (não atrás)
			if not cam.is_position_behind(target.global_position):
				lockon_rect.visible = true
				lockon_rect.position = screen_pos - (lockon_rect.size / 2)
			else:
				lockon_rect.visible = false
		else:
			lockon_rect.visible = false
	else:
		lockon_rect.visible = false
