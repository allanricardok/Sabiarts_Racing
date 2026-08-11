# WeaponResource.gd
extends Resource
class_name WeaponResource

@export_group("Identidade")
@export var nome: String = "" 

@export_group("Visual e Combate")
@export var projectile_scene: PackedScene 
@export var dano: float = 0
@export var fire_rate: float = 0.2
@export var lockon_range: float = 120.0 

@export_group("Munição")
@export var ammo: int = 6
@export var max_ammo: int = 30 

@export_group("Explosão (AoE)")
@export var causes_aoe_damage: bool = false
@export var aoe_radius: float = 5.0
@export var aoe_damage: float = 30.0
@export var aoe_knockback: float = 100.0
@export_range(0.0, 1.0) var self_damage_multiplier: float = 0.0

@export_group("Visual do Pickup")
@export var custom_mesh: Mesh
@export var mesh_scale: Vector3 = Vector3.ONE
@export var item_color: Color = Color.WHITE

# ============================================================================
# NOVO: CONFIGURAÇÕES DE DANO EM ÁREA (AoE) PARA O .TRES
# ============================================================================
