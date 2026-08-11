extends Node3D
class_name UIScannerComponent

@export_group("Configuração das Gotas")
@export var dist_max_scale: float = 1.0 
@export var dist_min_scale: float = 10.0 

@onready var car = owner

# --- OTIMIZAÇÃO: CACHE ---
var _input: Node
var _hud: CanvasLayer
var _camera: Camera3D
var _is_human: bool = true
var _target_update_timer: float = 0.0

func _ready():
	# Atrasamos um frame para garantir que o InputComponent recebeu a flag is_bot do BotBrain
	call_deferred("_delayed_setup")

func _delayed_setup():
	_input = car.get_node_or_null("%InputComponent")
	
	if _input and "is_bot" in _input and _input.is_bot:
		_is_human = false
		# A MÁGICA: Se for bot, DESLIGA este script! Bots não desenham UI.
		set_process(false)
		return
		
	if _input:
		_hud = get_tree().get_first_node_in_group("HUD" + _input.suffix)
	
	_camera = get_viewport().get_camera_3d()

func _process(delta):
	if not _is_human or not is_instance_valid(car): return
	
	# Tenta achar a HUD/Camera se ainda não achou na inicialização
	if not is_instance_valid(_hud):
		if is_instance_valid(_input):
			_hud = get_tree().get_first_node_in_group("HUD" + _input.suffix)
		if not is_instance_valid(_hud): return
		
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if not is_instance_valid(_camera): return

	_process_nametags(_camera, _hud)
	
	# OTIMIZAÇÃO: Varre a árvore em busca de alvos apenas 10x por segundo
	_target_update_timer -= delta
	if _target_update_timer <= 0:
		_target_update_timer = 0.1
		_process_target_info(_hud)

# --- MATEMÁTICA DAS GOTAS TÁTICAS ---
func _process_nametags(camera: Camera3D, hud: CanvasLayer):
	var cat_index = hud.get_active_minimap_category()
	var show_tags = (cat_index == 0 or cat_index == 1)
	var tags_data = []

	if show_tags:
		var players = get_tree().get_nodes_in_group("jogadores")
		for p in players:
			if not is_instance_valid(p) or p.is_queued_for_deletion() or p == car: continue
			if camera.is_position_behind(p.global_position): continue

			# Aqui mantemos distance_to porque precisamos do valor linear exato para o Lerp
			var dist = camera.global_position.distance_to(p.global_position)
			var scale_factor = 1.0

			if dist > dist_max_scale:
				var shrinking_distance = dist_min_scale - dist_max_scale
				if shrinking_distance > 0:
					var progress = clamp((dist - dist_max_scale) / shrinking_distance, 0.0, 1.0)
					scale_factor = lerp(1.0, 0.5, progress)

			var screen_pos = camera.unproject_position(p.global_position + Vector3(0, 2.3, 0))
			var is_locked = (hud._radar_current_target == p)

			tags_data.append({
				"node": p,
				"screen_pos": screen_pos,
				"scale": scale_factor,
				"is_locked": is_locked
			})

	hud.sync_nametags(tags_data)

# --- MATEMÁTICA DO PAINEL DE ALVO ---
func _process_target_info(hud: CanvasLayer):
	var display_target = hud._radar_current_target

	if not is_instance_valid(display_target) or display_target.is_in_group("pedestrians") or display_target.is_queued_for_deletion():
		display_target = null
		var closest_dist_sq = INF # OTIMIZAÇÃO: Distância ao quadrado!

		var cat_index = hud.get_active_minimap_category()
		var search_groups = []

		if cat_index == 0: search_groups = ["jogadores", "inimigos", "destructibles"]
		elif cat_index == 1: search_groups = ["jogadores"] 
		elif cat_index == 2: search_groups = ["inimigos"] 
		elif cat_index == 3: search_groups = ["destructibles"] 

		for group_name in search_groups:
			for t in get_tree().get_nodes_in_group(group_name):
				if is_instance_valid(t) and not t.is_queued_for_deletion() and t != car:
					var dist_sq = car.global_position.distance_squared_to(t.global_position)
					if dist_sq < closest_dist_sq:
						closest_dist_sq = dist_sq
						display_target = t 

	hud.sync_target_info(display_target)
