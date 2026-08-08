extends Sprite3D

var viewport: SubViewport
var draw_node: Node2D
var current_charge: float = 0.0
var base_pos: Vector3

func _ready():
	base_pos = position
	# Faz a barra sempre olhar para a câmera do jogador
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	transparent = true
	# Define o tamanho físico da barra no mundo 3D (ajuste se ficar muito grande/pequeno)
	pixel_size = 0.004 

	# 1. Cria a tela virtual (Viewport)
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.size = Vector2(256, 128)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	# 2. Cria o Nó que vai desenhar o triângulo 2D
	draw_node = Node2D.new()
	draw_node.draw.connect(_on_draw_node_draw)
	viewport.add_child(draw_node)

	# 3. Aplica o desenho como textura do nosso Sprite3D
	texture = viewport.get_texture()
	hide()

func update_charge(charge_ratio: float):
	current_charge = clamp(charge_ratio, 0.0, 1.0)
	
	if current_charge > 0.0:
		show()
		draw_node.queue_redraw()
		
		# ========================================================
		# EFEITO NO MÁXIMO: Tremedeira e piscar na cor
		# ========================================================
		if current_charge >= 1.0:
			position = base_pos + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0)
			# Dá uns flashes amarelos pra parecer que está fritando
			modulate = Color(1.0, randf_range(0.6, 1.0), 0.0) 
		else:
			position = base_pos
			modulate = Color.WHITE
	else:
		hide()
		position = base_pos

func _on_draw_node_draw():
	var w = 256.0
	var h = 128.0
	
	# --- 1. FUNDO DO TRIÂNGULO (Preto Translúcido) ---
	var bg_points = PackedVector2Array([
		Vector2(0, h),      # Canto inferior esquerdo
		Vector2(w, h),      # Canto inferior direito
		Vector2(w, 0)       # Canto superior direito (A hipotenusa)
	])
	draw_node.draw_polygon(bg_points, PackedColorArray([Color(0, 0, 0, 0.5)]))
	
	# --- 2. BARRA DE PREENCHIMENTO ---
	if current_charge > 0:
		var fill_w = w * current_charge
		var fill_y = h - (h * current_charge) # Calcula a altura exata cortando a hipotenusa
		
		var fill_points = PackedVector2Array([
			Vector2(0, h),            # Fixo no canto inferior esquerdo
			Vector2(fill_w, h),       # Vai até onde a carga chegou na base
			Vector2(fill_w, fill_y)   # Sobe reto até bater na hipotenusa
		])
		
		# Transição térmica de cor: Amarelo -> Laranja -> Vermelho vivo
		var bar_color = Color.YELLOW.lerp(Color.RED, current_charge)
		draw_node.draw_polygon(fill_points, PackedColorArray([bar_color]))
