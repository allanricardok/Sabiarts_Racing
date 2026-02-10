# WeaponResource.gd
extends Resource
class_name WeaponResource

@export_group("Identidade")
@export var nome: String = ""
@export var icone: Texture2D
@export var cor_tema: Color = Color.WHITE

@export_group("Combate")
@export var dano: float = 10.0
@export var ammo_max: int = 20
@export var projectile_scene: PackedScene # Ex: Míssil da Guerrilha

@export_group("Buffs de Máscara")
@export var speed_mult: float = 1.0 # Kitsune: 1.4
@export var jump_mult: float = 1.0  # Arlequim: 1.4
@export var air_con_mult: float = 1.0
@export var stamina_cost_mult: float = 1.0
