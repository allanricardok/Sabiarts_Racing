extends Resource
class_name StoryMissionTier

@export var tier_name: String = "Nova Tier"
@export var target_value: float = 1.0
@export var reward_points: int = 100

@export_group("Configuração Multi-Task (Apenas para MULTI_TASK)")

## Defina o número correspondente ao tipo de objetivo desta Tier:
## 0 = COMBAT_DESTROY
## 1 = SCORE
## 2 = SPEED
## 3 = COLLECT
## 4 = GAP
## 5 = EXPLORE
## 6 = ROADKILL
## 7 = DESTROY
## 8 = SCORE_COMBO
## 9 = DELIVERY
## 10 = DEFEND
@export var tier_mission_type: int = 0 

## Se precisar de um ID específico (ex: "barril_BA", "maleta_01")
@export var tier_target_id: String = ""
