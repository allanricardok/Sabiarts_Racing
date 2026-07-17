# StoryMissionTier.gd
extends Resource
class_name StoryMissionTier

@export var tier_name: String = "Bronze"
## O valor numérico de meta para este tier (ex: 1000 pontos, 3 destruições, 5 maletas)
@export var target_value: float = 1000.0
## A pontuação de história ganha individualmente ao completar este tier pela primeira vez
@export var reward_points: int = 100
