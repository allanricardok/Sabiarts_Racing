# UIScannerComponent.gd
extends Node3D
class_name UIScannerComponent

@export_group("Configuração das Gotas")
@export var dist_max_scale: float = 1.0 
@export var dist_min_scale: float = 10.0 

@onready var car = owner

func _process(_delta):
	# Segurança: garante que o carro e o controle existem
	if not is_instance_valid(car): return
	var input = car.get_node_or_null("%InputComponent")
	if not input: return

	# Encontra a HUD específica deste jogador
	var hud = get_tree().get_first_node_in_group("HUD" + input.suffix)
	if not hud: return

	var camera = get_viewport().get_camera_3d()
	if not camera: return

	# 1. Pede para processar as tags 2D e o painel de alvo
	_process_nametags(camera, hud)
	_process_target_info(hud)

# --- MATEMÁTICA DAS GOTAS TÁTICAS ---
func _process_nametags(camera: Camera3D, hud: CanvasLayer):
	var cat_index = hud.get_active_minimap_category()
	var show_tags = (cat_index == 0 or cat_index == 1)
	var tags_data = []

	if show_tags:
		var players = get_tree().get_nodes_in_group("jogadores")
		for p in players:
			if not is_instance_valid(p) or p == car: continue
			if camera.is_position_behind(p.global_position): continue

			var dist = camera.global_position.distance_to(p.global_position)
			var scale_factor = 1.0

			# Cálculo de encolhimento
			if dist > dist_max_scale:
				var shrinking_distance = dist_min_scale - dist_max_scale
				if shrinking_distance > 0:
					var progress = clamp((dist - dist_max_scale) / shrinking_distance, 0.0, 1.0)
					scale_factor = lerp(1.0, 0.5, progress)

			# Projeção 3D para Tela 2D
			var screen_pos = camera.unproject_position(p.global_position + Vector3(0, 2.3, 0))
			var is_locked = (hud._radar_current_target == p)

			# Guarda os dados mastigados para a HUD
			tags_data.append({
				"node": p,
				"screen_pos": screen_pos,
				"scale": scale_factor,
				"is_locked": is_locked
			})

	# Manda a HUD desenhar apenas o resultado!
	hud.sync_nametags(tags_data)

# --- MATEMÁTICA DO PAINEL DE ALVO ---
func _process_target_info(hud: CanvasLayer):
	var display_target = hud._radar_current_target

	# Se não tiver um alvo travado pelo míssil, busca o mais próximo da categoria
	if not is_instance_valid(display_target) or display_target.is_in_group("pedestrians"):
		display_target = null
		var closest_dist = INF

		var cat_index = hud.get_active_minimap_category()
		var search_groups = []

		if cat_index == 0: search_groups = ["jogadores", "inimigos", "destructibles"]
		elif cat_index == 1: search_groups = ["jogadores"] 
		elif cat_index == 2: search_groups = ["inimigos"] 
		elif cat_index == 3: search_groups = ["destructibles"] 

		for group_name in search_groups:
			for t in get_tree().get_nodes_in_group(group_name):
				if is_instance_valid(t) and t != car:
					var dist = car.global_position.distance_to(t.global_position)
					if dist < closest_dist:
						closest_dist = dist
						display_target = t 

	# Envia o alvo eleito para a HUD desenhar a barra de vida
	hud.sync_target_info(display_target)
