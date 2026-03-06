# WeaponResource.gd
extends Resource
class_name WeaponResource

@export_group("Identidade")
## O nome deve ser EXATAMENTE igual ao nome do nó (%) no WeaponManager (ex: MachineGun ou BigSlow)
@export var nome: String = "" 

@export_group("Visual e Combate")
## A cena do projétil que esta arma dispara
@export var projectile_scene: PackedScene 
## Dano causado por cada projétil
@export var dano: float = 0
## Tempo entre disparos
@export var fire_rate: float = 0.2

@export_group("Munição")
## Quantidade de balas. Use -1 para munição infinita (Metralhadora)
@export var ammo: int = 6

@export_group("Visual do Pickup")
## O modelo 3D que vai girar no mapa quando este item for dropado
@export var custom_mesh: Mesh
## Tamanho do modelo no mapa
@export var mesh_scale: Vector3 = Vector3.ONE
## Cor do brilho do item no mapa
@export var item_color: Color = Color.WHITE
