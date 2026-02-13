# HUD.gd
extends CanvasLayer

@onready var weapon_label = $UI_Base/WeaponLabel

func _ready():
	# Adicionamos o HUD a um grupo para o WeaponManager achá-lo fácil
	add_to_group("HUD")

func atualizar_arma(nome: String, munição: int):
	var texto_mun = str(munição)
	
	weapon_label.text = nome.to_upper() + "\n" + texto_mun
