# MissionItem.gd
extends Resource
class_name MissionItem

enum Type { SCORE, SPEED, COLLECT, DESTROY, GAP, EXPLORE, MISSION, ROADKILL }

@export var id: String = ""
@export var description: String = ""
@export var type: Type = Type.SCORE
@export var target_value: float = 0.0
@export var item_icon: Texture2D # Adicionado para os ícones da UI
@export var is_completed: bool = false
