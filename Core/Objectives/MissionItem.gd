# MissionItem.gd
extends Resource
class_name MissionItem

enum Type { SCORE, DESTROY, SPEED, COLLECT, GAP, EXPLORE, MISSION }

@export var description: String = "Objetivo"
@export var type: Type = Type.SCORE
@export var target_value: float = 0.0 # Pontos, Quantidade de itens ou Velocidade
@export var id: String = "" # Identificador único (ex: "radar_speed", "briefcase")

var is_completed: bool = false
