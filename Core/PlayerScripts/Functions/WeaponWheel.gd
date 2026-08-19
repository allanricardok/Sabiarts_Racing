extends Control
class_name WeaponWheel

@onready var slots = [
	$CenterSlot,
	$TopSlot,
	$RightSlot,
	$BottomSlot,
	$LeftSlot
]

var current_selected_index: int = -1
var max_available_weapons: int = 0

func _ready():
	hide()

func open_wheel(weapon_pool: Array):
	show()
	max_available_weapons = weapon_pool.size()
	
	# Reseta o visual de todos os slots primeiro
	for slot in slots:
		slot.text = "---"
		slot.modulate = Color(0.5, 0.5, 0.5)
		
	# Preenche as armas na ordem (0: Centro, 1: Cima, 2: Direita, 3: Baixo, 4: Esquerda)
	for i in range(max_available_weapons):
		if i < slots.size():
			var w = weapon_pool[i]
			var w_name = w.nome if "nome" in w and w.nome != "" else w.resource_path.get_file().get_basename()
			slots[i].text = w_name + "\n[" + str(w.ammo) + "]"
			
	highlight_slot(0)

func update_selection(direcao: Vector2) -> int:
	var novo_index = 0
	
	if direcao.length() < 0.3:
		novo_index = 0 # Centro
	else:
		var angulo = direcao.angle()
		
		# CORREÇÃO DEFINITIVA: Trocamos os índices 2 e 4 de lugar!
		if angulo > -PI/4 and angulo <= PI/4:
			novo_index = 4 # Agora força ESQUERDA
		elif angulo > PI/4 and angulo <= 3*PI/4:
			novo_index = 3 # Baixo
		elif angulo > -3*PI/4 and angulo <= -PI/4:
			novo_index = 1 # Cima
		else:
			novo_index = 2 # Agora força DIREITA
			
	if novo_index != current_selected_index:
		highlight_slot(novo_index)
		
	return novo_index

func highlight_slot(index: int):
	current_selected_index = index
	for i in range(slots.size()):
		if i == index:
			slots[i].modulate = Color(1.0, 0.8, 0.0) # Amarelo Destaque
			slots[i].scale = Vector2(1.2, 1.2)
		else:
			slots[i].modulate = Color(0.5, 0.5, 0.5) # Cinza Apagado
			slots[i].scale = Vector2(1.0, 1.0)

func close_wheel():
	hide()
