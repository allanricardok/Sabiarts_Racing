extends Area3D
@export var speed := 150.0
@export var damage := 20.0
@export var lifetime := 5.0
const SCENE_EXPLOSAO = preload("res://Scenes/Prefabs/Weapons/explosao.tscn")
var atirador = null
var altura_fixa : float
func _ready():
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
func _physics_process(delta):
	# Trava de altura no Y (Muzzle Position)
	global_position.y = altura_fixa
	var movimento = -global_transform.basis.z * speed * delta
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + movimento, collision_mask)
	if atirador:
		query.exclude = [atirador.get_rid()]
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)
	if result:
		_gerar_impacto(result.collider, result.position)
	else:
		global_translate(movimento)
func _on_body_entered(body):
	if body == atirador: return
	_gerar_impacto(body, global_position)
func _on_area_entered(area):
	var alvo = area.get_parent()
	if alvo == atirador: return
	_gerar_impacto(alvo, global_position)
func _gerar_impacto(alvo, ponto_posicao):
	# OFFSET: Recuamos a explosão 0.8 metros na direção do míssil (+basis.z)
	# Isso garante que ela nasça fora da lataria do inimigo.
	var posicao_ajustada = ponto_posicao + (global_transform.basis.z * 0.8)
	
	if SCENE_EXPLOSAO:
		var exp_inst = SCENE_EXPLOSAO.instantiate()
		get_tree().current_scene.add_child(exp_inst)
		exp_inst.global_position = posicao_ajustada
		
		# Debug visual: se a explosão falhar, esse print avisa
		print("[EXPLOSÃO] Gerada em: ", posicao_ajustada)
	
	if alvo and alvo.has_method("take_damage"):
		alvo.take_damage(damage)
	
	queue_free()
