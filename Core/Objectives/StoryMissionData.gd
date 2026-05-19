# StoryMissionData.gd
extends Resource
class_name StoryMissionData

@export_group("Detalhes da Missão")
@export var mission_id: String = "m_01"
@export var mission_name: String = "Nova Missão"
@export_multiline var mission_description: String = "Descrição do que o jogador deve fazer."
@export var time_limit: float = 0.0 # Se for 0.0, a missão não tem limite de tempo
@export var score_target: int = 1000

@export_group("Atmosfera (Seamless Transition)")
## Coloque aqui o arquivo Environment (.tres) que muda o céu/iluminação
@export var mission_environment: Environment
@export var mission_sun_color: Color = Color.WHITE
@export var mission_sun_energy: float = 1.0

@export_group("Objetos da Missão")
## Adicione os caminhos (NodePaths) dos inimigos, portais extras ou rampas 
## que já estão no mapa (ocultos) e devem aparecer apenas nesta missão.
@export var nodes_to_enable: Array[NodePath]
