# StoryMissionData.gd
extends Resource
class_name StoryMissionData

enum MissionType { SCORE_ATTACK, SURVIVAL, CLASSIC_OBJECTIVE, COMBAT_DESTROY }

@export_group("Configuração do Tipo")
@export var mission_type: MissionType = MissionType.SCORE_ATTACK

@export_group("Detalhes da Missão")
@export var mission_id: String = "m_01"
@export var mission_name: String = "Nova Missão"
@export_multiline var mission_description: String = "Descrição da missão."
@export var time_limit: float = 60.0 
@export var score_target: int = 1000 

@export_group("Combate Automático")
## Quantos inimigos o jogo deve criar automaticamente para esta missão?
@export var enemy_count: int = 3

@export_group("Atmosfera")
@export var mission_environment: Environment
@export var mission_sun_color: Color = Color.WHITE
@export var mission_sun_energy: float = 1.0

@export_group("Objetos Extras (Opcional)")
## Apenas se precisar ativar algo que não seja inimigo (Rampas, etc)
@export var nodes_to_enable: Array[NodePath]
