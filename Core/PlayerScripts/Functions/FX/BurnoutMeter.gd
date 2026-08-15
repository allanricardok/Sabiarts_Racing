extends Sprite3D

var viewport: SubViewport
var draw_node: Node2D
var current_charge: float = 0.0
var base_pos: Vector3

# OTIMIZAÇÃO: Guarda a última carga desenhada para evitar engasgar a GPU
var _last_drawn_charge: float = -1.0 

func _ready():
	# ====================================================================
	# 1. VALIDAÇÃO: MATAR O NÓ SE FOR UM BOT!
	# ====================================================================
	var car = owner if owner else get_parent()
	if car:
		var input = car.get_node_or_null("%InputComponent")
		if input and "is_bot" in input and input.is_bot:
			queue_free()
			return
			
		# ====================================================================
		# 2. ISOLAMENTO DE TELA DIVIDIDA (SPLIT-SCREEN)
		# Cada jogador é jogado em uma 'layer' visual única.
		# ====================================================================
		if "id" in car:
			# Joga o Sprite3D para uma camada específica (Ex: P1 = Layer 2, P2 = Layer 3)
			layers = 1 << (car.id + 1)

	base_pos = position
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	transparent = true
	pixel_size = 0.004 

	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.size = Vector2(256, 128)
	
	# OTIMIZAÇÃO: Começa com a tela virtual desligada!
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	draw_node = Node2D.new()
	draw_node.draw.connect(_on_draw_node_draw)
	viewport.add_child(draw_node)

	texture = viewport.get_texture()
	hide()

func update_charge(charge_ratio: float):
	current_charge = clamp(charge_ratio, 0.0, 1.0)
	
	if current_charge > 0.0:
		show()
		
		# OTIMIZAÇÃO: Só pede pra placa de vídeo redesenhar o Viewport se a 
		# barra realmente andou 1% ou se atingiu o máximo.
		if abs(current_charge - _last_drawn_charge) > 0.01 or current_charge == 1.0:
			draw_node.queue_redraw()
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_last_drawn_charge = current_charge
		
		# EFEITO NO MÁXIMO (Roda solto em 60fps porque altera apenas o Transform, e não o Viewport)
		if current_charge >= 1.0:
			position = base_pos + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0)
			modulate = Color(1.0, randf_range(0.6, 1.0), 0.0) 
		else:
			position = base_pos
			modulate = Color.WHITE
	else:
		hide()
		position = base_pos
		_last_drawn_charge = -1.0

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
		
		var bar_color = Color.YELLOW.lerp(Color.RED, current_charge)
		draw_node.draw_polygon(fill_points, PackedColorArray([bar_color]))
