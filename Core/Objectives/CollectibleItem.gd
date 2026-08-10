extends Area3D

@export var mission_id: String = "briefcase" 
@export var score_points: int = 500
@export var grants_teleport_key: bool = false
@export var rotation_speed: float = 1.5 

@export_group("Tipo de Missão")
## Se marcado, este item não pontua na hora. Ele vai para o porta-malas para ser entregue depois!
@export var is_delivery_item: bool = false

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
	add_to_group("itens_missao")
	if Global.current_run_mode != Global.RunMode.STORY:
		# LÊ DIRETO DO GLOBAL (Checa se a missão já foi concluída antes)
		if is_instance_valid(Global) and Global.completed_story_missions.has(mission_id):
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
	# === TRAVA FANTASMA: Se estiver invisível (fora de missão), não existe! ===
	if not visible or is_collected or not can_be_collected: return
	
	if body is BaseVehicle or body.is_in_group("jogadores"):		
		# --- VERIFICA SE QUEM BATEU FOI UM BOT ---
		var is_bot = false
		var input = body.get_node_or_null("%InputComponent")
		if input and "is_bot" in input and input.is_bot:
			is_bot = true
			
		if is_bot:
			_bot_steal(body)
			return
			
		# =======================================================
		# FLUXO NORMAL DO JOGADOR
		# =======================================================
		print("[DEBUG-ITEM] Jogador colidiu e coletou: ", name)
		
		if causes_drunk_effect:
			var cam = body.find_child("Camera3D", true, false)
			if not is_instance_valid(cam) and is_instance_valid(body.owner):
				cam = body.owner.find_child("Camera3D", true, false)
				
			if is_instance_valid(cam):
				var drunk_node = DrunkEffect.new()
				drunk_node.time_left = drunk_duration
				drunk_node.max_intensity = drunk_max_intensity
				drunk_node.fade_time = drunk_fade_time
				drunk_node.camera = cam 
				get_tree().current_scene.add_child(drunk_node)
		
		if grants_teleport_key:
			_entregar_chave_interna(body)
			if input and not input.is_bot:
				var hud = get_tree().get_first_node_in_group("HUD" + input.suffix)
				if not hud: hud = get_tree().get_first_node_in_group("HUD")
				if hud and hud.has_method("criar_toast"):
					hud.criar_toast("Key collected. Teleporters are now unlocked!", Color.DODGER_BLUE)
					
		_collect()

func _bot_steal(bot_body: Node3D):
	print("[Item] O bot ", bot_body.name, " ROUBOU a maleta ", name)
	is_collected = true
	can_be_collected = false
	
	var maletas_roubadas = bot_body.get_meta("maletas_roubadas", [])
	maletas_roubadas.append(self)
	bot_body.set_meta("maletas_roubadas", maletas_roubadas)
	
	if is_delivery_item:
		# TEXTO AMARELO
		get_tree().call_group("HUD", "criar_toast", "OPONENTE ROUBOU A CARGA! DESTRUA-O!", Color.YELLOW)
	
	# Chama a rotina para colar a maleta no carro do bot
	call_deferred("_atrelar_ao_ladrao", bot_body)

func _atrelar_ao_ladrao(ladrao: Node3D):
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.set_deferred("disabled", true)
			
	get_parent().remove_child(self)
	ladrao.add_child(self)
	
	# ALTURA CORRIGIDA: Agora a maleta fica 3 metros acima do bot!
	position = Vector3(0, 3.0, 0)
	rotation = Vector3.ZERO
	visible = true 

func soltar_loot_roubado(nova_posicao: Vector3):
	# A CORREÇÃO DO CRASH: Grava quem é a cena principal ANTES de sair do carro!
	var cena_principal = get_tree().current_scene
	
	get_parent().remove_child(self)
	cena_principal.add_child(self) # Usa a variável salva!
	
	global_position = nova_posicao
	rotation = Vector3.ZERO
	
	is_collected = false
	can_be_collected = true
	for child in get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.set_deferred("disabled", false)

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

	# BIFURCAÇÃO DA MISSÃO: É coleta simples ou é entrega?
	if is_delivery_item:
		# Grito da Entrega: O StoryController soma no "porta-malas" usando a chave "collect"
		get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.DELIVERY, 1.0, "collect")
	else:
		# Grito da Coleta Clássica: O StoryController soma no progresso geral da missão
		get_tree().call_group("StoryController", "notify_progress", StoryMissionData.MissionType.COLLECT, 1.0, mission_id)

	# Ocultamos a maleta
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
