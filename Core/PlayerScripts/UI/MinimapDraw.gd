# MinimapDraw.gd
extends ColorRect

# O HUD vai preencher essas variáveis de fora para dentro!
var radar_targets : Array = []
var current_target : Node3D = null
var player_pos : Vector3 = Vector3.ZERO
var player_fwd : Vector3 = Vector3.FORWARD
var radar_range : float = 150.0

func _draw():
	# O centro do ColorRect será a posição do nosso carro
	var center = size / 2.0
	
	# Desenhamos a gente mesmo no centro (um pontinho ciano)
	draw_circle(center, 4.0, Color.CYAN)
	
	var radius_px = min(size.x, size.y) / 2.0
	
	# Precisamos saber para onde o carro está olhando (Rotação no eixo Y em radianos)
	var player_yaw = atan2(player_fwd.x, player_fwd.z)
	
	for target in radar_targets:
		if not is_instance_valid(target): continue
		
		# 1. Distância e Direção cruas (no mundo 3D)
		var offset_3d = target.global_position - player_pos
		
		# Se estiver fora do alcance, não desenha
		var dist = offset_3d.length()
		if dist > radar_range: continue
		
		# 2. Converte as coordenadas 3D para um mapa 2D (X e Z viram X e Y)
		var map_pos_2d = Vector2(offset_3d.x, offset_3d.z)
		
		# 3. ROTACIONA O MAPA (Removido o + PI para girar 180 graus e compensar o eixo do carro!)
		var rotated_2d = map_pos_2d.rotated(-player_yaw)
		
		# 4. Escala a distância real (metros) para o tamanho da tela (pixels)
		var draw_pos = center + (rotated_2d / radar_range) * radius_px
		
		# 5. Define a cor: Vermelho piscante se for o alvo travado, amarelo se for inimigo comum
		var dot_color = Color.YELLOW
		if target == current_target:
			dot_color = Color.RED
			draw_arc(draw_pos, 8.0, 0, TAU, 4, Color.RED, 1.0)
			
		# Pinta o inimigo no minimapa!
		draw_circle(draw_pos, 3.0, dot_color)
