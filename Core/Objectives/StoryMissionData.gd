# StoryMissionData.gd
extends Resource
class_name StoryMissionData

enum MissionType { CLASSIC_OBJECTIVE, COMBAT_DESTROY }

@export_group("Configuração do Tipo")
@export var mission_type: MissionType = MissionType.CLASSIC_OBJECTIVE

@export_group("Detalhes da Missão")
@export var mission_id: String = "m_01"
@export var mission_name: String = "Nova Missão"
@export_multiline var mission_description: String = "Descrição da missão."
@export var time_limit: float = 60.0 

@export_group("Recompensa da História")
## Quantos pontos o jogador GANHA NO FINAL ao vencer esta missão
@export var mission_reward_points: int = 500 

@export_group("Regras por Tipo")
## Arraste para aqui o seu MissionItem antigo (Radar, Maleta, Obake, etc.)
## Obrigatório se o tipo for CLASSIC_OBJECTIVE!
@export var classic_objective: MissionItem

@export_group("Atmosfera")
@export var mission_environment: Environment
@export var mission_sun_color: Color = Color.WHITE
@export var mission_sun_energy: float = 1.0

@export_group("Objetos Templates (Opcional)")
@export var nodes_to_enable: Array[NodePath]

@export_group("Combate Automático")
@export var enemy_count: int = 3
## Multiplicador de dano que os bots CAUSAM nesta missão (1.0 = normal, 1.2 = 20% a mais)
@export var enemy_damage_dealt_mult: float = 1.0
## Multiplicador de dano que os bots RECEBEM nesta missão (1.0 = normal, 0.8 = 20% de resistência)
@export var enemy_damage_received_mult: float = 1.0
