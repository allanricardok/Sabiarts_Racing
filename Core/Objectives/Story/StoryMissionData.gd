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

@export_group("Comportamento da IA (Bots)")
## Faz os bots tentarem roubar as maletas com este ID (Ex: "maleta_01"):
@export var bot_target_collect_id: String = ""
## Faz os bots tentarem destruir o objeto VIP com este ID (Ex: "barril_vip"):
@export var bot_target_destroy_id: String = ""
## Agressividade: Probabilidade base (0 a 100) do bot focar no Player em modo Batalha:
@export_range(0.0, 100.0) var player_focus_base: float = 10.0
## Variação de agressividade (0 a 33) que cada bot individual terá na partida:
@export_range(0.0, 33.0) var player_focus_variance: float = 33.0
## Amizade entre bots: 100 = ataca geral / 0 = ignora bots e caça só o player
@export_range(0.0, 100.0) var bot_hostility_base: float = 100.0
## Variação de amizade (0 a 33) que cada bot individual terá na partida:
@export_range(0.0, 33.0) var bot_hostility_variance: float = 0.0

@export_group("Desbloqueio")
@export var required_unlock_points: int = 0
