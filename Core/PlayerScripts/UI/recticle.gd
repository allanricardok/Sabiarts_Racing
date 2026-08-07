extends Control

@onready var lockon_rect = $LockOnRect # Mantemos para não quebrar a sua cena

# --- PARÂMETROS DO RETÍCULO PROCEDURAL ---
@export var reticle_color : Color = Color(1.0, 0.0, 0.0, 0.65) 
@export var radius : float = 20.0
@export var line_width : float = 3.0
@export var rotation_speed : float = 3.0 # Velocidade do giro da mira

# Variáveis internas para a animação
var current_rotation : float = 0.0
var is_locked : bool = false
var target_screen_pos : Vector2 = Vector2.ZERO

func _ready():
	# Mantemos a opacidade do fundo/quadrado em 25% conforme pedido anterior
	if lockon_rect:
		lockon_rect.modulate.a = 0.25

func _process(delta):
	# --- SOLUÇÃO MULTIPLAYER (SPLIT-SCREEN) ---
	var car = null
	var todos_jogadores = get_tree().get_nodes_in_group("jogadores")
	
	for c in todos_jogadores:
		if c.get_viewport() == get_viewport():
			var input_comp = c.get_node_or_null("%InputComponent")
			if input_comp and not input_comp.is_bot:
				car = c
				break
	
	if not car: 
		_set_locked(false)
		return
	
	# === CORREÇÃO DE ARQUITETURA ===
	# Agora o retículo busca a informação direto no TargetingComponent, ignorando as armas
	var targeting = car.find_child("TargetingComponent*", true, false)
	if not targeting:
		_set_locked(false)
		return
		
	# Pega o alvo atual direto da fonte
	var target = targeting.current_target
	
	if target and is_instance_valid(target):
		var cam = get_viewport().get_camera_3d()
		
		if cam:
			# Transforma a posição 3D do alvo em coordenadas 2D da tela
			var screen_pos = cam.unproject_position(target.global_position)
			
			# Verifica se o alvo está na frente da câmera
			if not cam.is_position_behind(target.global_position):
				_set_locked(true, screen_pos)
				# Move o lockon_rect original para a posição
				lockon_rect.position = screen_pos - (lockon_rect.size / 2)
			else:
				_set_locked(false)
		else:
			_set_locked(false)
	else:
		_set_locked(false)

	# Se estiver travado, atualiza a rotação e solicita o redesenho (_draw)
	if is_locked:
		current_rotation += rotation_speed * delta
		queue_redraw()

# Função auxiliar para gerenciar o estado do lock e visibilidade
func _set_locked(locked: bool, pos: Vector2 = Vector2.ZERO):
	if is_locked != locked or pos != target_screen_pos:
		is_locked = locked
		target_screen_pos = pos
		if lockon_rect: lockon_rect.visible = locked
		if not locked: queue_redraw() 

func _draw():
	# Só desenha o retículo procedural se tivermos um alvo travado na frente
	if not is_locked: return

	# --- MÁGICA PROCEDURAL DO GIRO ---
	draw_set_transform(target_screen_pos, current_rotation, Vector2.ONE)

	# 1. Desenha o círculo principal vazado
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, reticle_color, line_width, true)

	# 2. Desenha o pontinho minúsculo central
	draw_circle(Vector2.ZERO, 3.0, reticle_color)

	# 3. Desenha as 4 "perninhas" (ticks) cardeais apontando para fora
	var tick_length = 12.0
	
	# Direita
	draw_line(Vector2(radius, 0), Vector2(radius + tick_length, 0), reticle_color, line_width, true)
	# Esquerda
	draw_line(Vector2(-radius, 0), Vector2(-radius - tick_length, 0), reticle_color, line_width, true)
	# Baixo
	draw_line(Vector2(0, radius), Vector2(0, radius + tick_length), reticle_color, line_width, true)
	# Cima
	draw_line(Vector2(0, -radius), Vector2(0, -radius - tick_length), reticle_color, line_width, true)

	# Reseta a transformação
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
