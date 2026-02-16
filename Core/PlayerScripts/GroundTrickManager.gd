extends Node
class_name GroundTrickManager

@onready var car = owner as VehicleBody3D

const GROUND_DATA = {
	"HIT_OBJECT": {"name": "Acertou Objeto", "points": 50},
	"DESTROY_OBJECT": {"name": "Destruiu Objeto", "points": 500}
}

var actions_done : Array = []
var points_per_action : Array = []
var tracking_combo := false

# Variáveis de controle de "versão" do timer
var last_action_time := 0
var last_finalize_time := 0

func add_ground_action(id: String):
	if not GROUND_DATA.has(id): return
	
	if not tracking_combo:
		_start_combo()
	
	_register_action_logic(id)
	_restart_inactivity_timer()

func _start_combo():
	tracking_combo = true
	actions_done.clear()
	points_per_action.clear()

func _register_action_logic(id: String):
	var data = GROUND_DATA[id]
	actions_done.append(data.name)
	points_per_action.append(data.points)
	_update_live_display()

func _update_live_display():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	var names_text = " + ".join(actions_done)
	var pts_text = ""
	for p in points_per_action:
		pts_text += str(p) + " + "
	
	pts_text = pts_text.left(pts_text.length() - 3)
	
	hud.air_time_label.text = names_text
	hud.air_time_label.text += "\n" + str(actions_done.size()) + "x " + pts_text
	hud.air_time_label.visible = true
	hud.air_message_label.visible = false

# --- CORREÇÃO AQUI: TIMER COM VALIDAÇÃO ---
func _restart_inactivity_timer():
	# Marcamos o tempo exato em que este timer foi criado
	var current_timer_id = Time.get_ticks_msec()
	last_action_time = current_timer_id
	
	await get_tree().create_timer(3.0).timeout
	
	# Se o 'last_action_time' mudou, significa que outro hit aconteceu depois desse
	# Então este timer específico deve morrer em silêncio.
	if last_action_time != current_timer_id:
		return
		
	if tracking_combo:
		_finalize_ground_score()

func _finalize_ground_score():
	var hud = get_tree().get_first_node_in_group("HUD")
	if not hud: return
	
	var total_base = 0
	for p in points_per_action: 
		total_base += p
	
	var mult = actions_done.size()
	var final_score = total_base * mult
	
	ScoreManager.add_points(final_score)
	
	var msg = "Cool trick!" if mult > 1 else "Nice hit!"
	hud.air_message_label.text = msg + "\n" + str(final_score) + " points"
	hud.air_message_label.visible = true
	
	tracking_combo = false
	
	# --- SEGUNDA VALIDAÇÃO: PARA SUMIR DA TELA ---
	var finalize_id = Time.get_ticks_msec()
	last_finalize_time = finalize_id
	
	await get_tree().create_timer(3.0).timeout
	
	# Se um novo combo começou, não escondemos o HUD
	if last_finalize_time != finalize_id or tracking_combo:
		return
		
	hud.air_time_label.visible = false
	hud.air_message_label.visible = false

func reset_ground_trick():
	tracking_combo = false
	last_action_time = 0 # Reseta os IDs para invalidar timers antigos
	var hud = get_tree().get_first_node_in_group("HUD")
	if hud:
		hud.air_time_label.visible = false
		hud.air_message_label.visible = false
