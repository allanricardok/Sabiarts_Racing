# GapPoint.gd
extends Area3D

enum PointType { START, END }

@export_group("Gap Settings")
@export var gap_id : String = "gap_balcony"
@export var point_type : PointType = PointType.START

@export_group("Display & Score")
@export var gap_name : String = "GAP DA SACADA"
@export var gap_points : int = 500

func _ready():
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body is BaseVehicle:
		if point_type == PointType.START:
			_start_gap(body)
		else:
			_complete_gap(body)

func _on_body_exited(body):
	if body is BaseVehicle and point_type == PointType.START:
		_start_gap(body)
		print("[Gap] START RENOVADO: ", gap_id, " (Carro saiu da área)")

func _start_gap(player):
	if player.has_method("set_active_gap"):
		player.set_active_gap(gap_id)
		print("[Gap] Validado Início: ", gap_id)

func _complete_gap(player):
	# --- NOVA VERIFICAÇÃO MULTI-GAPS ---
	if player.has_method("has_active_gap") and player.has_active_gap(gap_id):
		
		var is_air = player.get("is_airborne") if "is_airborne" in player else true
		
		if is_air:
			if player.has_method("set_gap_reached_end"):
				player.set_gap_reached_end(gap_id, gap_name, gap_points)
				print("[Gap] COMPLETADO NO AR: ", gap_name)
		else:
			print("[Gap] Falhou: Cruzou o END mas estava no chão.")
