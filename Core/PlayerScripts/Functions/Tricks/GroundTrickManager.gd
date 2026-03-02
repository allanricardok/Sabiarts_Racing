# GroundTrickManager.gd
extends Node
class_name GroundTrickManager

@onready var car = owner as VehicleBody3D

# --- VARIÁVEIS DE BALANCEAMENTO ---
@export_group("Timing")
## Tempo de inatividade (segundos) para fechar o combo no chão
@export var COMBO_TIMEOUT : float = 3.0
## Tempo que o resultado final do combo de solo fica na tela
@export var DISPLAY_STAY_TIME : float = 3.0

@export_group("Limites")
## Multiplicador máximo que o jogador pode alcançar no chão
@export var MAX_COMBO_MULTIPLIER : float = 10.0

# Cor padrão para ações de combate/chão
const COLOR_GROUND = "#ff4444" # Vermelho

const GROUND_DATA = {
	"HIT_OBJECT": {"name": "Hit object", "points": 5},
	"DESTROY_OBJECT": {"name": "Destroyed object", "points": 500},
	"COMBAT_HIT": {"name": "Impact!", "points": 150}
}

var actions_done : Array = []
var points_per_action : Array = []
var tracking_combo := false
var last_action_time := 0
var display_version : int = 0

func add_ground_action(id: String):
	if not GROUND_DATA.has(id): return
	
	# Se o carro estiver no ar, envia a ação para o TrickManager (Combo Aéreo)
	# Passamos o nome, os pontos e a cor VERMELHA
	var air_tricks = car.get_node_or_null("%TrickManager") as TrickManager
	if air_tricks and air_tricks.tracking_jump:
		air_tricks.add_external_action(GROUND_DATA[id].name, GROUND_DATA[id].points, COLOR_GROUND)
		return
		
	# Inicia combo de solo se não estiver ativo
	if not tracking_combo: _start_combo()
	
	_register_action_logic(id)
	_restart_inactivity_timer()

func _start_combo():
	tracking_combo = true
	actions_done.clear()
	points_per_action.clear()
	display_version += 1

func _register_action_logic(id: String):
	var data = GROUND_DATA[id]
	actions_done.append(data.name)
	points_per_action.append(data.points)
	_update_live_display()

# --- MULTIPLICADOR DINÂMICO ---
func _get_dynamic_multiplier() -> float:
	if actions_done.size() == 0: return 1.0
	
	var mult = 1.0 
	var seen_in_this_combo = {}
	
	for i in range(actions_done.size()):
		var a_name = actions_done[i]
		if i == 0:
			seen_in_this_combo[a_name] = true
			continue
			
		if seen_in_this_combo.has(a_name):
			mult += 0.5 
		else:
			mult += 1.0 
			seen_in_this_combo[a_name] = true
			
	# MUDANÇA SÊNIOR: Retorna o multiplicador ou o limite máximo (o que for menor)
	return min(mult, MAX_COMBO_MULTIPLIER)

# --- Função auxiliar para encontrar a HUD correta do Split-Screen ---
func _get_local_hud() -> Node:
	for hud in get_tree().get_nodes_in_group("HUD"):
		if hud.get_viewport() == car.get_viewport():
			return hud
	return null

# --- EXIBIÇÃO COM BBCODE ---
func _update_live_display():
	var hud = _get_local_hud()
	if not hud: return
	
	var grouped = {}
	var order = []
	for i in range(actions_done.size()):
		var a_name = actions_done[i]
		var a_pts = points_per_action[i]
		if not grouped.has(a_name):
			grouped[a_name] = {"count": 0, "points": 0}
			order.append(a_name)
		grouped[a_name].count += 1
		grouped[a_name].points += a_pts

	var names_bbcode = ""
	var pts_text = ""
	
	for a_name in order:
		var data = grouped[a_name]
		if data.count >= 3:
			names_bbcode += "[color=" + COLOR_GROUND + "](x" + str(data.count) + " " + a_name + ")[/color] + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_bbcode += "[color=" + COLOR_GROUND + "]" + a_name + "[/color] + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	if names_bbcode.ends_with(" + "): names_bbcode = names_bbcode.left(-3)
	if pts_text.ends_with(" + "): pts_text = pts_text.left(-3)

	var current_mult = _get_dynamic_multiplier()
	# Envia a string formatada para o HUD
	var info = names_bbcode + "\n" + str(current_mult) + "x " + pts_text
	
	hud.update_combo_live(info)

func _finalize_ground_score():
	var hud = _get_local_hud()
	if not hud: return
	
	var total_base = 0
	for p in points_per_action: total_base += p
	var mult = _get_dynamic_multiplier()
	var final_score = int(total_base * mult)
	
	# Usamos a lógica de Multiplayer do ScoreManager (passando o ID do carro que pontuou)
	ScoreManager.add_points(final_score, car.id)
	
	# --- RECONSTRUÇÃO DA STRING DETALHADA ---
	var grouped = {}
	var order = []
	for i in range(actions_done.size()):
		var a_name = actions_done[i]
		if not grouped.has(a_name):
			grouped[a_name] = {"count": 0, "points": 0}
			order.append(a_name)
		grouped[a_name].count += 1
		grouped[a_name].points += points_per_action[i]

	var names_bbcode = ""
	var pts_text = ""
	for a_name in order:
		var data = grouped[a_name]
		if data.count >= 3:
			names_bbcode += "[color=" + COLOR_GROUND + "](x" + str(data.count) + " " + a_name + ")[/color] + "
			pts_text += str(data.points) + " + "
		else:
			for k in range(data.count):
				names_bbcode += "[color=" + COLOR_GROUND + "]" + a_name + "[/color] + "
				pts_text += str(int(data.points / data.count)) + " + "
	
	if names_bbcode.ends_with(" + "): names_bbcode = names_bbcode.left(-3)
	if pts_text.ends_with(" + "): pts_text = pts_text.left(-3)

	var info = names_bbcode + "\n" + str(mult) + "x " + pts_text
	
	var msg = "Cool combo!" if mult > 1.5 else "Nice hit!"
	
	# Se o jogador bateu no teto de multiplicador, damos um feedback visual diferente!
	if mult >= MAX_COMBO_MULTIPLIER:
		msg = "MAX COMBO!"
		
	var result = msg + "\n" + ScoreManager.format_score_with_dots(final_score) + " points"
	
	hud.show_combo_final(info, result)
	tracking_combo = false

func _restart_inactivity_timer():
	var current_timer_id = Time.get_ticks_msec()
	last_action_time = current_timer_id
	await get_tree().create_timer(COMBO_TIMEOUT).timeout
	if last_action_time == current_timer_id:
		if tracking_combo: _finalize_ground_score()
