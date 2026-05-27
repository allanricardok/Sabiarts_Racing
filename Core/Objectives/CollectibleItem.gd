# CollectibleItem.gd
extends Area3D

@export var mission_id: String = "briefcase" 
@export var score_points: int = 500
@export var grants_teleport_key: bool = false
@export var rotation_speed: float = 1.5 

var is_collected: bool = false
var can_be_collected: bool = true # <--- TRAVA CONTRA COLETAS INSTANTÂNEAS NO REPLAY

func _ready():
	await get_tree().create_timer(0.2).timeout
	
	if Global.current_run_mode != Global.RunMode.STORY:
		if is_instance_valid(MissionManager) and MissionManager.has_method("is_mission_completed"):
			if MissionManager.is_mission_completed(mission_id):
				print("[Item] Missão '", mission_id, "' já está completa no Open World.")
				if grants_teleport_key:
					_distribute_permanent_key()
				
				# Esconde o item logo no início (usando call_deferred por segurança)
				call_deferred("_hide_and_disable") 
				return

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _process(delta):
	if not is_collected and visible:
		rotate_y(rotation_speed * delta)

func _on_body_entered(body):
	# Se já foi coletado ou se está no tempo de invulnerabilidade do replay, ignora!
	if is_collected or not can_be_collected: return
	
	if body is BaseVehicle or body.is_in_group("jogadores"):
		print("[DEBUG-ITEM] Jogador colidiu e coletou: ", name)
		
		if grants_teleport_key:
			_entregar_chave_interna(body)
			print("[Item] Chave do Teleporte adquirida por ", body.name, "!")
			
			var input = body.get_node_or_null("%InputComponent")
			if input and not input.is_bot:
				var hud = get_tree().get_first_node_in_group("HUD" + input.suffix)
				if not hud: hud = get_tree().get_first_node_in_group("HUD")
				
				if hud and hud.has_method("criar_toast"):
					hud.criar_toast("Key collected. Teleporters are now unlocked!", Color.DODGER_BLUE)
		_collect()

func _entregar_chave_interna(alvo):
	if "has_teleportkey" in alvo:
		alvo.has_teleportkey = true
	else:
		var stats = alvo.get_node_or_null("%StatsComponent")
		if stats and "has_teleportkey" in stats:
			stats.has_teleportkey = true

func _distribute_permanent_key():
	for jogador in get_tree().get_nodes_in_group("jogadores"):
		_entregar_chave_interna(jogador)

func _collect():
	print("[Item] Coletou: ", mission_id)
	is_collected = true
	can_be_collected = false

	if grants_teleport_key:
		if not MissionManager.completed_mission_ids.has(mission_id):
			MissionManager.completed_mission_ids.append(mission_id)
			SaveManager.save_game(MissionManager.completed_mission_ids, {})

	if is_instance_valid(MissionManager):
		MissionManager.notify_progress(MissionItem.Type.COLLECT, 1.0, mission_id)
		get_tree().call_group("HUD", "atualizar_missao_ui")
	
	# --- CORREÇÃO DO ERRO DA ENGINE ---
	# Nunca desligamos física diretamente dentro de colisões, agendamos para o fim do frame!
	call_deferred("_hide_and_disable")

func _hide_and_disable():
	visible = false
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.disabled = true # Aqui é 100% seguro desligar a física
	process_mode = Node.PROCESS_MODE_DISABLED
	print("[DEBUG-ITEM] ", name, " foi ocultado e desativado fisicamente com sucesso.")

func reset():
	print("[DEBUG-ITEM] Resetando e acordando coletável: ", name)
	is_collected = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.set_deferred("disabled", false)
			
	# --- TRAVA ANTI-INSTA-COLETA ---
	# Bloqueia a coleta por 1 segundo para o carro ter tempo de sair de cima do item
	can_be_collected = false
	get_tree().create_timer(1.0).timeout.connect(func():
		can_be_collected = true
		print("[DEBUG-ITEM] ", name, " liberado para captura pós-cooldown.")
	)
