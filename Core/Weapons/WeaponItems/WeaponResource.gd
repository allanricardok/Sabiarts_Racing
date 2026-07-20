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
# --- NOVO: Limite de Munição ---
@export var max_ammo: int = 30 

@export_group("Visual do Pickup")
@export var custom_mesh: Mesh
@export var mesh_scale: Vector3 = Vector3.ONE
@export var item_color: Color = Color.WHITE
