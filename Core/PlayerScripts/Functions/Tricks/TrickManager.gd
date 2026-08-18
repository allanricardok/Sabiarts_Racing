extends Node
class_name TrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO ---
@export_group("Timing & Balance")
@export var AIR_TIME_THRESHOLD : float = 1.3
@export var DISPLAY_STAY_TIME : float = 3.0
@export var AIR_TIME_POINTS_MULT : float = 10.0

# --- CORES DO SISTEMA ---
const COLOR_AIR = "#ffaa00"      # Laranja (Padrão)
const COLOR_GROUND = "#ff4444" # Vermelho
const COLOR_GAP = "#00aaff"    # Azul
const COLOR_TIME = "#ffffff"   # Branco
const COLOR_SPECIAL = "#ffd700" # Dourado / Amarelo Escuro (Especiais)

var global_stunt_uses = {}
var air_time := 0.0
var tracking_jump := false

# Listas de Sincronia (Nomes, Pontos e Cores)
var tricks_done : Array = []
var points_per_trick : Array = []
var tricks_colors : Array = []

# --- VARIÁVEIS DE CONTROLE DE GAP (MULTI-GAP) ---
var _active_gaps_ids : Array = []
var _gaps_completed_this_jump : Array = []

var current_jump_uses = {}
var jump_start_timestamp : int = 0
var display_version : int = 0
var is_showing_final_score := false

# --- BLINDAGEM DE COMBO ---
var combo_immunity_timer : float = 0.0

# ==============================================================================
# OTIMIZAÇÃO: MEMÓRIA CACHE
# ==============================================================================
var _trick_builder: Node = null
var _wall_ride_orchestrator: Node = null
var _ground_trick_manager: Node = null
var _ability_component: Node = null
var _rage_component: Node = null
var _manual_component: Node = null # <--- NOVA REFERÊNCIA PARA O MANUAL

func _ready():
	_trick_builder = car.get_node_or_null("%TrickBuilder")
	_wall_ride_orchestrator = car.find_child("WallRide*", true, false)
	_ground_trick_manager = car.get_node_or_null("%GroundTrickManager")
	_ability_component = car.find_child("AbilityComponent", true, false)
	_rage_component = car.get_node_or_null("%RageComponent")
	
	# Busca o script do manual com segurança
	_manual_component = car.get_node_or_null("%ManualTrickComponent")
	if not _manual_component:
		_manual_component = car.find_child("ManualTrick*", true, false)

func _process(delta):
	if combo_immunity_timer > 0.0:
		combo_immunity_timer -= delta

func grant_immunity(duration: float):
	combo_immunity_timer = duration

# --- LOGICA DE GAPS INTEGRADA (MÚLTIPLOS GAPS) ---

func iniciar_deteccao_gap(gap_id: String):
	if not _active_gaps_ids.has(gap_id):
		_active_gaps_ids.append(gap_id)

func marcar_gap_no_ar(gap_id: String, gap_name: String, points: int):
	if _active_gaps_ids.has(gap_id) and not _gaps_completed_this_jump.has(gap_id):
		_gaps_completed_this_jump.append(gap_id)
		add_external_action(gap_name, points, COLOR_GAP)
		get_tree().call_group("TutorialUI", "complete_task", "ramp_jump")

func cancelar_gap():
	_active_gaps_ids.clear()
	_gaps_completed_this_jump.clear()

# --- FUNÇÕES DE REGISTRO E COMUNICAÇÃO ---

func add_external_action(action_name: String, points: int, color_hex: String = "#ffffff"):
	if not tracking_jump: _start_new_jump()
	tricks_done.append(action_name)
	points_per_trick.append(points)
	tricks_colors.append(color_hex)
	_update_live_display()

func add_trick_manually(id: String):
	if is_instance_valid(_trick_builder) and _trick_builder.TRICK_DATA.has(id):
		var data = _trick_builder.TRICK_DATA[id]
		register_builder_trick(id, data.name, data.points)
	else:
		print("[TrickManager] Erro: ID de manobra não encontrado no Builder: ", id)

func register_builder_trick(id: String, trick_name: String, base_pts: int):
	if not tracking_jump: _start_new_jump()
	
	var g_count = global_stunt_uses.get(id, 0)
	var g_mult = max(0.1, 1.0 - (g_count * 0.05))
	var j_count = current_jump_uses.get(id, 0)
	var j_mult = max(0.1, pow(0.5, j_count))
	var final_pts = int(base_pts * g_mult * j_mult)
	
	tricks_done.append(trick_name)
	points_per_trick.append(final_pts)
	
	var special_ids = ["FIREBALL", "SHOCKWAVE", "SHIELD_SPIN", "EMOTE"]
	if id in special_ids:
		tricks_colors.append(COLOR_SPECIAL)
	else:
		tricks_colors.append(COLOR_AIR)
	
	current_jump_uses[id] = j_count + 1
	global_stunt_uses[id] = g_count + 1
	_update_live_display()
	
	if is_instance_valid(_rage_component):
		_rage_component.add_trick(1) 

func _start_new_jump():
	tracking_jump = true
	air_time = 0.0 
	display_version += 1 
	
	tricks_done.clear()
	points_per_trick.clear()
	tricks_colors.clear()
	
	if _active_gaps_ids.is_empty():
		_gaps_completed_this_jump.clear()
	
	if is_instance_valid(_ground_trick_manager) and _ground_trick_manager.tracking_combo:
		for i in range(_ground_trick_manager.actions_done.size()):
			tricks_done.append(_ground_trick_manager.actions_done[i])
			points_per_trick.append(_ground_trick_manager.points_per_action[i])
			tricks_colors.append(COLOR_GROUND)
		_ground_trick_manager.tracking_combo = false
	
	current_jump_uses.clear()
	
	if is_instance_valid(_trick_builder): 
		_trick_builder.reset_builder_logic()

# --- FILTRO DE HUD PARA BOTS ---
func _get_local_hud() -> Node:
	if not is_instance_valid(car) or not is_instance_valid(car.input): return null
	if "is_bot" in car.input and car.input.is_bot: return null
	return get_tree().get_first_node_in_group("HUD" + car.input.suffix)


# --- EXIBIÇÃO E FINALIZAÇÃO ---

func _update_live_display():
	if is_showing_final_score: return
	
	var hud = _get_local_hud()
	if not hud: return
	
	var grouped_tricks = {} 
	var order = []
	for i in range(tricks_done.size()):
		var t_name = tricks_done[i]
		if not grouped_tricks.has(t_name):
			grouped_tricks[t_name] = {"count": 0, "points": 0, "color": tricks_colors[i]}
			order.append(t_name)
		grouped_tricks[t_name].count += 1
		grouped_tricks[t_name].points += points_per_trick[i]

	var names_bbcode = ""
	var pts_text = ""
	for t_name in order:
		var data = grouped_tricks[t_name]
		if data.count >= 3:
			names_bbcode += "[color=" + data.color + "](x" + str(data.count) + " " + t_name + ")[/color] + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_bbcode += "[color=" + data.color + "]" + t_name + "[/color] + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	var current_mult = _get_dynamic_multiplier()
	var info = names_bbcode + "[color=" + COLOR_TIME + "]" + ("%.2fs" % air_time) + " airtime[/color]"
	info += "\n" + str(current_mult) + "x " + pts_text + str(int(air_time * AIR_TIME_POINTS_MULT))
	hud.update_combo_live(info)

func _finalize_score():
	is_showing_final_score = true 
	
	var total_base = int(air_time * AIR_TIME_POINTS_MULT)
	for p in points_per_trick: total_base += p
	var mult = _get_dynamic_multiplier()
	var final_score = int(total_base * mult)
	
	ScoreManager.add_points(final_score, car.id)
	
	var stats = car.get_node_or_null("%StatsComponent")
	if stats and stats.has_method("add_heal_score"):
		stats.add_heal_score(final_score)
	
	if is_instance_valid(_ability_component) and "current_energy" in _ability_component and "MAX_ENERGY" in _ability_component:
		var energy_gained = final_score * 0.005
		var old_energy = _ability_component.current_energy
		
		_ability_component.current_energy += energy_gained
		
		if _ability_component.current_energy >= _ability_component.MAX_ENERGY:
			_ability_component.current_energy = _ability_component.MAX_ENERGY

	var is_bot = (car.input and "is_bot" in car.input and car.input.is_bot)
	if not is_bot:
		for completed_gap in _gaps_completed_this_jump:
			get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.GAP, 1.0, completed_gap)
				
		get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.SCORE_COMBO, final_score, "")

	_reset_gap_state_internal()
	
	var hud = _get_local_hud()
	if not hud:
		is_showing_final_score = false
		return
		
	_update_final_display(hud, final_score, mult)

func reset_trick():
	if is_instance_valid(_wall_ride_orchestrator) and _wall_ride_orchestrator.has_method("has_combo_shield"):
		if _wall_ride_orchestrator.has_combo_shield():
			return 

	tracking_jump = false
	_reset_gap_state_internal()
	if is_showing_final_score: return
	display_version += 1
	
	var hud = _get_local_hud()
	if hud:
		if hud.has_method("clear_combo_display"):
			hud.clear_combo_display()
		else:
			hud.air_time_label.visible = false
			hud.air_message_label.visible = false

func _update_final_display(hud, final_score, mult):
	var grouped_tricks = {} 
	var order = []
	for i in range(tricks_done.size()):
		var t_name = tricks_done[i]
		if not grouped_tricks.has(t_name):
			grouped_tricks[t_name] = {"count": 0, "points": 0, "color": tricks_colors[i]}
			order.append(t_name)
		grouped_tricks[t_name].count += 1
		grouped_tricks[t_name].points += points_per_trick[i]

	var names_bbcode = ""
	var pts_text = ""
	for t_name in order:
		var data = grouped_tricks[t_name]
		if data.count >= 3:
			names_bbcode += "[color=" + data.color + "](x" + str(data.count) + " " + t_name + ")[/color] + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_bbcode += "[color=" + data.color + "]" + t_name + "[/color] + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	if names_bbcode.ends_with(" + "): names_bbcode = names_bbcode.left(-3)
	if pts_text.ends_with(" + "): pts_text = pts_text.left(-3)

	var info = names_bbcode + " [color=" + COLOR_TIME + "]" + ("%.2fs" % air_time) + " airtime[/color]"
	info += "\n" + str(mult) + "x " + pts_text + " + " + str(int(air_time * AIR_TIME_POINTS_MULT))
	
	var msg = "Awesome trick!" if tricks_done.size() > 0 else "Nice air!"
	var result = msg + "\n" + ScoreManager.format_score_with_dots(final_score) + " points"
	
	hud.show_combo_final(info, result)
	await get_tree().create_timer(DISPLAY_STAY_TIME).timeout
	is_showing_final_score = false

func _reset_gap_state_internal():
	_gaps_completed_this_jump.clear()

func _get_dynamic_multiplier() -> float:
	var mult = 1.0
	var trick_counts = {}
	
	for t_name in tricks_done:
		if not trick_counts.has(t_name):
			trick_counts[t_name] = 0
		trick_counts[t_name] += 1
		if trick_counts[t_name] == 1: mult += 1.0 
		elif trick_counts[t_name] <= 5: mult += 0.5 
	return mult

# --- LOOP DE AR ---

func process_air_time(_delta: float, _is_near_ground: bool):
	if not tracking_jump:
		if not _is_near_ground: _start_new_jump()
		else: return
	
	# ==============================================================================
	# CORREÇÃO 1: Congela o contador de AirTime se o carro estiver no chão em manual
	# ==============================================================================
	if not _is_near_ground:
		air_time += _delta
	
	if is_instance_valid(_trick_builder):
		_trick_builder.process_maneuvers(_delta)
		
	if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0:
		_update_live_display()

func check_landing(is_clean: bool):
	if tracking_jump:
		if is_instance_valid(_wall_ride_orchestrator) and _wall_ride_orchestrator.has_method("has_combo_shield"):
			if _wall_ride_orchestrator.has_combo_shield():
				return 
				
		# ==============================================================================
		# CORREÇÃO 2: Escudo do Combo (Respeita a flag is_manual_armed e o Estado)
		# ==============================================================================
		if is_instance_valid(_manual_component):
			var is_armed = _manual_component.get("is_manual_armed")
			var state = _manual_component.get("current_state")
			# Se estiver engatilhado aguardando o chão, OU já estiver fazendo o manual (estado diferente de IDLE que é 0)
			if is_armed == true or (state != null and state != 0):
				return # Ignora o check de pouso e mantém o combo vivo!

		if is_clean:
			if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0: 
				_finalize_score()
			else: 
				reset_trick()
		else:
			reset_trick()
			
	tracking_jump = false

# ==============================================================================
# CORREÇÃO 3: Nova função que o Manual chama para "sacar" o dinheiro do combo
# ==============================================================================
func cash_out_combo():
	if tracking_jump and not is_showing_final_score:
		if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0:
			_finalize_score()
		else:
			reset_trick()
		tracking_jump = false
