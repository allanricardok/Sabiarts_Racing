# StatusResource.gd
extends Resource
class_name StatusResource

@export_group("Identidade")
@export var item_name: String = "Status Item"

@export_group("Efeitos de Status")
## Quantidade de vida a curar (0 = não cura)
@export var health_amount: float = 0.0
## Quantidade de escudo a restaurar (0 = não restaura)
@export var shield_amount: float = 0.0

@export_group("Visual")
## A malha 3D que este item usará (ex: uma cruz médica ou um escudo)
@export var custom_mesh: Mesh
@export var mesh_scale: Vector3 = Vector3.ONE
## A cor que pintará a malha e o brilho do item
@export var item_color: Color = Color.WHITE
