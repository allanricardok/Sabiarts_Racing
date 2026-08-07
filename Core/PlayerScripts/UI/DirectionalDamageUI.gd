# DirectionalDamage.gd
extends Control

@export var flash_color : Color = Color(1.0, 0.0, 0.0, 0.8) # Vermelho com 80% de opacidade inicial
@export var fade_speed : float = 2.0 # Velocidade que a mancha some da tela

# Opacidade individual de cada lado
var alpha_top: float = 0.0
var alpha_bottom: float = 0.0
var alpha_left: float = 0.0
var alpha_right: float = 0.0

var player_stats: Node = null

func _ready():
	# Garante que o desenho limpe caso o alpha zere
	set_process(true)

func _process(delta):
	_find_player_and_connect()
	
	var needs_redraw = false
	
	# Faz o "Fade Out" sumindo a cor com o tempo
	if alpha_top > 0: 
		alpha_top = max(0.0, alpha_top - delta * fade_speed)
		needs_redraw = true
	if alpha_bottom > 0: 
		alpha_bottom = max(0.0, alpha_bottom - delta * fade_speed)
		needs_redraw = true
	if alpha_left > 0: 
		alpha_left = max(0.0, alpha_left - delta * fade_speed)
		needs_redraw = true
	if alpha_right > 0: 
		alpha_right = max(0.0, alpha_right - delta * fade_speed)
		needs_redraw = true
		
	if needs_redraw:
		queue_redraw() # Aciona a função _draw() nativa do Godot

# Função que busca o carro principal deste split-screen
func _find_player_and_connect():
	if is_instance_valid(player_stats): return
	
	var todos_jogadores = get_tree().get_nodes_in_group("jogadores")
	for c in todos_jogadores:
		if c.get_viewport() == get_viewport():
			var ic = c.get_node_or_null("%InputComponent")
			if ic and not ic.is_bot:
				var stats = c.get_node_or_null("%StatsComponent")
				if stats and not stats.is_connected("took_damage", _on_player_took_damage):
					stats.took_damage.connect(_on_player_took_damage)
					player_stats = stats
				break

# A MÁGICA MATEMÁTICA DA DIREÇÃO
func _on_player_took_damage(attacker: Node):
	if not is_instance_valid(attacker): 
		# Se tomou dano sem origem clara (ex: queda/veneno), pisca tudo junto levemente
		alpha_top = 0.4; alpha_bottom = 0.4; alpha_left = 0.4; alpha_right = 0.4
		return
		
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	# Pega os eixos da câmera do jogador
	var cam_forward = -cam.global_transform.basis.z.normalized()
	var cam_right = cam.global_transform.basis.x.normalized()
	
	# Direção matemática de onde veio o tiro
	var dir_to_attacker = (attacker.global_position - cam.global_position).normalized()
	
	# Ignoramos a altura (Y) para o cálculo ficar puramente em 2D
	cam_forward.y = 0; cam_forward = cam_forward.normalized()
	cam_right.y = 0; cam_right = cam_right.normalized()
	dir_to_attacker.y = 0; dir_to_attacker = dir_to_attacker.normalized()
	
	# O Dot Product compara a direção. Vai de -1.0 a 1.0.
	var forward_dot = cam_forward.dot(dir_to_attacker)
	var right_dot = cam_right.dot(dir_to_attacker)
	
	# Comparamos qual eixo é mais forte
	if abs(forward_dot) > abs(right_dot):
		if forward_dot > 0:
			alpha_top = 1.0 # Veio da FRENTE
		else:
			alpha_bottom = 1.0 # Veio de TRÁS
	else:
		if right_dot > 0:
			alpha_right = 1.0 # Veio da DIREITA
		else:
			alpha_left = 1.0 # Veio da ESQUERDA

# GERAÇÃO DO DEGRADÊ PROCEDURAL DIRETO NA PLACA DE VÍDEO
func _draw():
	var w = size.x
	var h = size.y
	
	# Os 20% da borda para o centro que você pediu
	var depth_x = w * 0.2
	var depth_y = h * 0.2
	
	var c_base = flash_color

	if alpha_top > 0:
		var c_op = c_base; c_op.a *= alpha_top
		var c_tr = c_base; c_tr.a = 0.0
		draw_polygon(
			PackedVector2Array([Vector2(0,0), Vector2(w,0), Vector2(w, depth_y), Vector2(0, depth_y)]),
			PackedColorArray([c_op, c_op, c_tr, c_tr])
		)
		
	if alpha_bottom > 0:
		var c_op = c_base; c_op.a *= alpha_bottom
		var c_tr = c_base; c_tr.a = 0.0
		draw_polygon(
			PackedVector2Array([Vector2(0,h), Vector2(w,h), Vector2(w, h - depth_y), Vector2(0, h - depth_y)]),
			PackedColorArray([c_op, c_op, c_tr, c_tr])
		)
		
	if alpha_left > 0:
		var c_op = c_base; c_op.a *= alpha_left
		var c_tr = c_base; c_tr.a = 0.0
		draw_polygon(
			PackedVector2Array([Vector2(0,0), Vector2(0,h), Vector2(depth_x, h), Vector2(depth_x, 0)]),
			PackedColorArray([c_op, c_op, c_tr, c_tr])
		)
		
	if alpha_right > 0:
		var c_op = c_base; c_op.a *= alpha_right
		var c_tr = c_base; c_tr.a = 0.0
		draw_polygon(
			PackedVector2Array([Vector2(w,0), Vector2(w,h), Vector2(w - depth_x, h), Vector2(w - depth_x, 0)]),
			PackedColorArray([c_op, c_op, c_tr, c_tr])
		)
