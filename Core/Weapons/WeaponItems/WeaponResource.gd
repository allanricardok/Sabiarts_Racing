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
