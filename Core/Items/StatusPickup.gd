@tool
extends Area3D
class_name StatusPickup

@export_group("Conteúdo")
## Arraste o arquivo .tres (StatusResource) aqui!
@export var status_data : StatusResource:
	set(value):
		status_data = value
		# Atualiza o visual na mesma hora em que você troca o .tres no Inspetor!
		if is_inside_tree(): 
			_update_visuals()

@export_group("Animação Arcade")
@export var rotation_speed : float = 2.0
@export var float_speed : float = 2.0
@export var float_amplitude : float = 0.2

@export_group("Debug no Editor")
## Liga/Desliga a animação no editor para você poder mover o objeto livremente
@export var preview_animacao: bool = false

var _start_y : float

func _ready():
	_start_y = position.y
	_update_visuals()
	
	# Só conecta colisões se o jogo estiver rodando de verdade
	if not Engine.is_editor_hint():
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)

func _update_visuals():
	# Usamos get_node_or_null para evitar erros durante a construção da cena no Editor
	var mesh_inst = get_node_or_null("MeshInstance3D") as MeshInstance3D
	
	if not status_data or not mesh_inst: return
	
	if status_data.custom_mesh:
		# 1. Aplica a malha e a escala do Resource
		mesh_inst.mesh = status_data.custom_mesh
		mesh_inst.scale = status_data.mesh_scale
		
		# 2. Material Dinâmico
		var mat = StandardMaterial3D.new()
		mat.albedo_color = status_data.item_color
		mat.emission_enabled = true
		mat.emission = status_data.item_color
		mat.emission_energy_multiplier = 0.5
		
		mesh_inst.material_override = mat

func _process(delta):
	# TRAVA DE EDITOR: Se estiver no editor e o preview estiver desligado, não anima
	if Engine.is_editor_hint() and not preview_animacao:
		# Salva a nova posição que você colocou com o mouse para não pular depois
		_start_y = position.y 
		return
		
	rotate_y(rotation_speed * delta)
	position.y = _start_y + sin(Time.get_ticks_msec() * 0.001 * float_speed) * float_amplitude

func _on_body_entered(body):
	if not status_data:
		push_error("ERRO: O objeto '" + name + "' não tem um StatusResource!")
		return
		
	# Procura o StatsComponent no carro
	var stats = body.find_child("StatsComponent*", true, false)
	
	if stats:
		var applied_effect = false
		
		# Aplica Vida
		if status_data.health_amount > 0 and stats.has_method("repair"):
			stats.repair(status_data.health_amount)
			applied_effect = true
			
		# Aplica Escudo
		if status_data.shield_amount > 0 and stats.has_method("restore_shield"):
			stats.restore_shield(status_data.shield_amount)
			applied_effect = true
			
		# Deleta o item do mapa se o carro conseguiu absorver algo
		if applied_effect:
			_collect_effect()

func _collect_effect():
	# TODO: Instanciar som e partículas de coleta
	print("[Pickup] " + status_data.item_name + " coletado com sucesso!")
	queue_free()
