extends Resource
class_name StoryMissionData

enum MissionType { COMBAT_DESTROY, SCORE, SPEED, COLLECT, GAP, EXPLORE, ROADKILL, DESTROY, SCORE_COMBO, DELIVERY, DEFEND, MULTI_TASK }

@export_group("Configuração do Tipo")
@export var mission_type: MissionType = MissionType.SCORE

@export_group("Detalhes da Missão")
@export var mission_id: String = "m_01"
@export var mission_name: String = "Nova Missão"
@export_multiline var mission_description: String = "Descrição da missão."
@export var time_limit: float = 60.0 
@export var base_target_value: float = 0.0

@export_group("Configuração de Tiers")
@export var mission_tiers: Array[StoryMissionTier] = []

@export_group("Atmosfera")
@export var mission_environment: Environment
@export var mission_sun_color: Color = Color.WHITE
@export var mission_sun_energy: float = 1.0

@export_group("Objetos Templates (Opcional)")
@export var nodes_to_enable: Array[NodePath]

@export_group("Combate Automático")
@export var enemy_count: int = 3
@export var enemy_damage_dealt_mult: float = 1.0
@export var enemy_damage_received_mult: float = 1.0

@export_group("Desbloqueio")
@export var required_unlock_points: int = 0
