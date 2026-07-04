# TrickManager.gd
extends Node
class_name TrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO ---
@export_group("Timing & Balance")
@export var AIR_TIME_THRESHOLD : float = 1.3
@export var DISPLAY_STAY_TIME : float = 3.0
@export var AIR_TIME_POINTS_MULT : float = 10.0

# --- CORES DO SISTEMA ---
const COLOR_AIR = "#ffaa00"     # Laranja (Padrão)
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
	var builder = car.get_node_or_null("%TrickBuilder")
	if builder and builder.TRICK_DATA.has(id):
		var data = builder.TRICK_DATA[id]
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
	var rage = car.get_node_or_null("%RageComponent")
	if rage:
		rage.add_trick(1) 

func _start_new_jump():
	tracking_jump = true
	air_time = 0.0 
	display_version += 1 
	
	tricks_done.clear()
	points_per_trick.clear()
	tricks_colors.clear()
	
	if _active_gaps_ids.is_empty():
		_gaps_completed_this_jump.clear()
	
	var ground_manager = car.get_node_or_null("%GroundTrickManager")
	if ground_manager and ground_manager.tracking_combo:
		for i in range(ground_manager.actions_done.size()):
			tricks_done.append(ground_manager.actions_done[i])
			points_per_trick.append(ground_manager.points_per_action[i])
			tricks_colors.append(COLOR_GROUND)
		ground_manager.tracking_combo = false
	
	current_jump_uses.clear()
	
	var builder = car.get_node_or_null("%TrickBuilder")
	if builder: builder.reset_builder_logic()

# --- CORREÇÃO: FILTRO DE HUD PARA BOTS ---
func _get_local_hud() -> Node:
	if not is_instance_valid(car) or not is_instance_valid(car.input): return null
	
	if "is_bot" in car.input and car.input.is_bot:
		return null
		
	return get_tree().get_first_node_in_group("HUD" + car.input.suffix)


# --- EXIBIÇÃO E FINALIZAÇÃO ---

func _update_live_display():
	if is_showing_final_score: return
	
	# Passa pelo filtro Anti-Bot
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
	
	# Salva a pontuação na Global (Funciona para Bots e Players)
	ScoreManager.add_points(final_score, car.id)
	
	# --- NOVO: CONVERTE PONTUAÇÃO EM ENERGIA (0.5%) COM DEBUGS ---
	var ability = car.find_child("AbilityComponent", true, false)
	if ability and "current_energy" in ability and "MAX_ENERGY" in ability:
		var energy_gained = final_score * 0.005
		var old_energy = ability.current_energy
		
		ability.current_energy += energy_gained
		
		print("=========================================")
		print("[TrickManager] Combo Finalizado! Pontuação: ", final_score)
		print("[TrickManager] Energia Gerada: +", snapped(energy_gained, 0.1))
		
		# Trava no limite máximo
		if ability.current_energy >= ability.MAX_ENERGY:
			ability.current_energy = ability.MAX_ENERGY
			if old_energy < ability.MAX_ENERGY:
				print("[TrickManager] BINGO! Energia carregada ao MÁXIMO (100%)!")
			else:
				print("[TrickManager] Energia já estava no máximo. Desperdiçada.")
		else:
			print("[TrickManager] Energia atual do carro: ", snapped(ability.current_energy, 0.1), " / ", ability.MAX_ENERGY)
		print("=========================================")
	# ----------------------------------------------------
	
	# Avisa o gerente de missões (Apenas para Players)
	var is_bot = (car.input and "is_bot" in car.input and car.input.is_bot)
	if not is_bot:
		for completed_gap in _gaps_completed_this_jump:
			if is_instance_valid(MissionManager) and not MissionManager.is_mission_completed(completed_gap):
				MissionManager.notify_progress(MissionItem.Type.GAP, 1.0, completed_gap)

	_reset_gap_state_internal()
	
	# Se for bot, encerra a função visual aqui!
	var hud = _get_local_hud()
	if not hud:
		is_showing_final_score = false
		return
		
	_update_final_display(hud, final_score, mult)

func reset_trick():
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
	
	air_time += _delta
	
	var builder = car.get_node_or_null("%TrickBuilder")
	if builder:
		builder.process_maneuvers(_delta)
		
	if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0:
		_update_live_display()

func check_landing(is_clean: bool):
	if tracking_jump:
		if is_clean:
			if air_time >= AIR_TIME_THRESHOLD or tricks_done.size() > 0: 
				_finalize_score()
			else: 
				reset_trick()
		else:
			reset_trick()
	tracking_jump = false
