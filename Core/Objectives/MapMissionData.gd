# MapMissionData.gd
extends Resource
class_name MapMissionData

@export var map_name: String = "Mapa"
@export var time_limit: float = 120.0 # Tempo em segundos
@export var missions: Array[MissionItem] = []
@export var next_map_unlock_count: int = 4 # Quantos completar para liberar a próxima fase
