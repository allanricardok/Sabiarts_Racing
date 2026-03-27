extends ColorRect

var radar_targets : Array = []
var current_target : Node3D = null
var player_pos : Vector3 = Vector3.ZERO
var player_fwd : Vector3 = Vector3.FORWARD
var radar_range : float = 350.0
var active_category_index : int = 0 

func _draw():
	var center = size / 2.0
	draw_circle(center, 4.0, Color.CYAN)
	var radius_px = min(size.x, size.y) / 2.0
	
	var p_fwd = player_fwd.normalized()
	var p_right = p_fwd.cross(Vector3.UP).normalized()
	
	for target in radar_targets:
		if not is_instance_valid(target): continue
		
		# --- 1. FILTRO ESTRITO DE CATEGORIA ---
		var show_target = false
		var dot_color = Color.WHITE
		
		if target.is_in_group("jogadores"):
			dot_color = Color.ORANGE
			# Players só aparecem na aba All(0) ou Adversaries(1)
			if active_category_index == 0 or active_category_index == 1: show_target = true
				
		elif target.is_in_group("inimigos"):
			dot_color = Color.MAGENTA
			# Inimigos só aparecem na aba All(0) ou Fuckers(2)
			if active_category_index == 0 or active_category_index == 2: show_target = true
				
		elif target.is_in_group("destructibles"):
			dot_color = Color.GREEN
			# Objetos só na aba All(0) ou Environment(3)
			if active_category_index == 0 or active_category_index == 3: show_target = true

		if not show_target: continue

		# --- 2. POSICIONAMENTO E BORDA ---
		var offset_3d = target.global_position - player_pos
		var dist_3d = offset_3d.length()
		
		var dist_right = offset_3d.dot(p_right)
		var dist_forward = offset_3d.dot(p_fwd)
		var rotated_2d = Vector2(dist_right, -dist_forward)
		var draw_pos = Vector2.ZERO
		
		if dist_3d > radar_range:
			# LÓGICA DE FICAR PRESO NA BORDA
			var should_draw_on_edge = false
			
			if target.is_in_group("jogadores") and active_category_index == 1:
				should_draw_on_edge = true
			elif target.is_in_group("inimigos") and active_category_index == 2:
				should_draw_on_edge = true
			elif target == current_target:
				should_draw_on_edge = true
				
			if not should_draw_on_edge: continue
			
			var dir_2d = rotated_2d.normalized()
			if dir_2d == Vector2.ZERO: dir_2d = Vector2.UP
			draw_pos = center + dir_2d * (radius_px - 3.0)
		else:
			draw_pos = center + (rotated_2d / radar_range) * radius_px
			
		# --- 3. DESENHO FINAL ---
		if target == current_target:
			dot_color = Color.RED
			draw_arc(draw_pos, 8.0, 0, TAU, 4, Color.RED, 1.0)
			
		draw_circle(draw_pos, 3.0, dot_color)
