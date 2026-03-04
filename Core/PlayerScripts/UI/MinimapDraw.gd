# MinimapDraw.gd
extends ColorRect

var radar_targets : Array = []
var current_target : Node3D = null
var player_pos : Vector3 = Vector3.ZERO
var player_fwd : Vector3 = Vector3.FORWARD
var radar_range : float = 350.0

# NOVA VARIÁVEL: Sabe qual é a categoria selecionada agora (0, 1 ou 2)
var active_category_index : int = 0 

func _draw():
	var center = size / 2.0
	draw_circle(center, 4.0, Color.CYAN)
	
	var radius_px = min(size.x, size.y) / 2.0
	
	# --- A MÁGICA INFALÍVEL DOS VETORES ---
	# Pegamos a "Frente" do carro e usamos Produto Vetorial (Cross Product) 
	# para descobrir exatamente para onde fica a "Direita" dele no mundo 3D.
	var p_fwd = player_fwd.normalized()
	var p_right = p_fwd.cross(Vector3.UP).normalized()
	
	for target in radar_targets:
		if not is_instance_valid(target): continue
		
		var offset_3d = target.global_position - player_pos
		if offset_3d.length() > radar_range: continue
		
		# Perguntamos fisicamente a distância do inimigo nos nossos eixos locais:
		var dist_right = offset_3d.dot(p_right)   # Positivo = Direita, Negativo = Esquerda
		var dist_forward = offset_3d.dot(p_fwd)   # Positivo = Frente, Negativo = Trás
		
		# Montamos o 2D: No Godot 2D, Y negativo é para cima, então invertemos o Y!
		var rotated_2d = Vector2(dist_right, -dist_forward)
		
		var draw_pos = center + (rotated_2d / radar_range) * radius_px
		
# --- LÓGICA DE CORES E TRANSPARÊNCIA ---
		var dot_color = Color.WHITE
		var is_active_category = false
		
		if target.is_in_group("jogadores"):
			dot_color = Color.ORANGE
			# Fica ativo se for a categoria de Players (1) OU a categoria ALL (0)
			if active_category_index == 0 or active_category_index == 1: is_active_category = true
				
		elif target.is_in_group("inimigos"):
			dot_color = Color.MAGENTA
			if active_category_index == 0 or active_category_index == 2: is_active_category = true
				
		elif target.is_in_group("destructibles"):
			dot_color = Color.GREEN
			if active_category_index == 0 or active_category_index == 3: is_active_category = true

		# Se não for a categoria ativa, aplica 70% de transparência! (Melhorei de 50% pra 70% pra sumir mais)
		if not is_active_category:
			dot_color.a = 0.3
			
		# Sobrescreve para Vermelho Opaco se for o seu alvo travado atual
		if target == current_target:
			dot_color = Color.RED
			draw_arc(draw_pos, 8.0, 0, TAU, 4, Color.RED, 1.0)
			
		draw_circle(draw_pos, 3.0, dot_color)
