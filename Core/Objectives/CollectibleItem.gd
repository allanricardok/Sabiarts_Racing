extends Area3D

@export var mission_id: String = "briefcase" 
@export var score_points: int = 500
@export var grants_teleport_key: bool = false
@export var rotation_speed: float = 1.5 

@export_group("Efeitos de Bebida")
@export var causes_drunk_effect: bool = false
@export var drunk_duration: float = 10.0
## Intensidade máxima do efeito (1.0 = normal, 2.0 = fortíssimo, 0.5 = leve)
@export var drunk_max_intensity: float = 1.0 
## Tempo (em segundos) que demora para o efeito entrar e sair suavemente
@export var drunk_fade_time: float = 2.0

var is_collected: bool = false
var can_be_collected: bool = true

func _ready():
	await get_tree().create_timer(0.2).timeout
	
	if Global.current_run_mode != Global.RunMode.STORY:
		if is_instance_valid(MissionManager) and MissionManager.has_method("is_mission_completed"):
			if MissionManager.is_mission_completed(mission_id):
				print("[Item] Missão '", mission_id, "' já está completa no Open World.")
				if grants_teleport_key:
					_distribute_permanent_key()
				
				call_deferred("_hide_and_disable") 
				return

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _process(delta):
	if not is_collected and visible:
		rotate_y(rotation_speed * delta)

func _on_body_entered(body):
	if is_collected or not can_be_collected: return
	
	if body is BaseVehicle or body.is_in_group("jogadores"):
		print("[DEBUG-ITEM] Jogador colidiu e coletou: ", name)
		
		# =======================================================
		# NOVO: Instancia o efeito de Bebida se estiver ativado
		# =======================================================
# =======================================================
		# NOVO: Instancia o efeito de Bebida apenas para quem coletou
		# =======================================================
		if causes_drunk_effect:
			var cam = body.find_child("Camera3D", true, false)
			
			# Se o corpo que encostou não tiver câmera direta (ex: colisores internos), 
			# tentamos achar a câmera no owner ou no veículo base.
			if not is_instance_valid(cam) and is_instance_valid(body.owner):
				cam = body.owner.find_child("Camera3D", true, false)
				
			if is_instance_valid(cam):
				var drunk_node = DrunkEffect.new()
				drunk_node.time_left = drunk_duration
				drunk_node.max_intensity = drunk_max_intensity
				drunk_node.fade_time = drunk_fade_time
				drunk_node.camera = cam # Vincula exclusivamente à câmera deste alvo
				
				get_tree().current_scene.add_child(drunk_node)
			else:
				print("[DEBUG-ITEM] Aviso: Tentou aplicar efeito de bebida em ", body.name, ", mas nenhuma Camera3D foi encontrada.")
		# =======================================================
		
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
	
	# NOVO: persiste a conquista da chave em Global e salva em disco na
	# hora — assim ela sobrevive mesmo que o jogo feche antes de terminar
	# a run atual, não só entre mapas dentro da mesma sessão.
	if is_instance_valid(Global) and "has_teleport_key" in Global:
		if not Global.has_teleport_key:
			Global.has_teleport_key = true
			if Global.has_method("save_story_progress"):
				Global.save_story_progress()

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
	
	call_deferred("_hide_and_disable")

func _hide_and_disable():
	visible = false
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.disabled = true 
	process_mode = Node.PROCESS_MODE_DISABLED
	print("[DEBUG-ITEM] ", name, " foi ocultado e desativado fisicamente com sucesso.")

func reset():
	# =====================================================================
	# TRAVA DE SEGURANÇA: IDENTIDADE DA MISSÃO
	# Protege contra o "find_child" acordar itens da missão errada!
	# =====================================================================
	if Global.current_run_mode == Global.RunMode.STORY:
		var controller = get_tree().get_first_node_in_group("StoryController")
		if is_instance_valid(controller) and controller.get("active_classic_objective") != null:
			# Compara o ID da missão clássica rodando com o ID deste coletável
			if controller.active_classic_objective.id != mission_id:
				print("[DEBUG-ITEM] Falso despertar evitado em '", name, "'. Pertence a: ", mission_id)
				return
	
	print("[DEBUG-ITEM] Resetando e acordando coletável: ", name)
	is_collected = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.set_deferred("disabled", false)
			
	can_be_collected = false
	get_tree().create_timer(1.0).timeout.connect(func():
		can_be_collected = true
		print("[DEBUG-ITEM] ", name, " liberado para captura pós-cooldown.")
	)
