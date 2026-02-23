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

func _on_body_entered(body):
	if body is BaseVehicle:
		# Removida a trava de missão concluída daqui. 
		# O Gap deve sempre registrar para o combo/score.
		if point_type == PointType.START:
			_start_gap(body)
		else:
			_complete_gap(body)

func _start_gap(player):
	if player.has_method("set_active_gap"):
		player.set_active_gap(gap_id)
		print("[Gap] START: ", gap_id)

func _complete_gap(player):
	if player.has_method("get_active_gap") and player.get_active_gap() == gap_id:
		if player.has_method("set_gap_reached_end"):
			player.set_gap_reached_end(gap_id, gap_name, gap_points)
