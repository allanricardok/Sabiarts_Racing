extends Node3D
class_name MissionPointer

# O Maestro (StoryMissionMarkers) vai ler essa variável para saber o que fazer com esta seta!
@export_enum("general", "dropoff", "collectable") var pointer_type: String = "general"

func _ready():
	add_to_group("mission_pointers")
