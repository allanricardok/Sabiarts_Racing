# StoryMissionData.gd
extends Resource
class_name StoryMissionData

# IMPORTANTE: Restaurei o SCORE_ATTACK para não quebrar a ordem dos seus arquivos salvos!
enum MissionType { SCORE_ATTACK, SURVIVAL, CLASSIC_OBJECTIVE, COMBAT_DESTROY }

@export_group("Configuração do Tipo")
@export var mission_type: MissionType = MissionType.CLASSIC_OBJECTIVE

@export_group("Detalhes da Missão")
@export var mission_id: String = "m_01"
@export var mission_name: String = "Nova Missão"
@export_multiline var mission_description: String = "Descrição da missão."
@export var time_limit: float = 60.0 

@export_group("Sistema de Pontos (Recompensa vs Meta)")
## Quantos pontos o jogador DEVE FAZER DURANTE A MISSÃO para vencer (Apenas para modo SCORE_ATTACK)
@export var score_target: int = 1000 
## Quantos pontos o jogador GANHA NO FINAL ao vencer qualquer missão (Progresso da Campanha)
@export var mission_reward_points: int = 500 

@export_group("Regras por Tipo")
## Arraste para aqui o seu MissionItem antigo (recurso de Radar, Maleta, Obake, etc.)
## Obrigatório se o tipo for CLASSIC_OBJECTIVE!
@export var classic_objective: MissionItem

@export_group("Combate Automático")
## Quantos inimigos o jogo deve criar automaticamente para esta missão?
@export var enemy_count: int = 3

@export_group("Atmosfera")
@export var mission_environment: Environment
@export var mission_sun_color: Color = Color.WHITE
@export var mission_sun_energy: float = 1.0

@export_group("Objetos Templates (Opcional)")
## Arraste para aqui os nós do mapa que servem de modelo (Obakes, Alvos, Radar).
@export var nodes_to_enable: Array[NodePath]
