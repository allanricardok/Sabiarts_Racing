# CollectibleItem.gd (Script genérico para itens e chaves)
extends Area3D

@export var mission_id: String = "briefcase" 
@export var score_points: int = 500
@export var grants_teleport_key: bool = false # Define se dá a chave ao coletar!
@export var rotation_speed: float = 1.5 # Velocidade do giro (em radianos por segundo)

func _ready():
	# Espera um tempinho para garantir que os carros já nasceram e entraram no grupo
	await get_tree().create_timer(0.2).timeout
	
	if MissionManager.is_mission_completed(mission_id):
		print("[Item] Missão '", mission_id, "' já está completa.")
		
		# --- O TRUQUE DA CHAVE PERMANENTE ---
		# Se a chave já foi coletada em sessões passadas, dá a chave a todos os jogadores silenciosamente
		if grants_teleport_key:
			print("[Item] Distribuindo chave permanente para os jogadores na sessão...")
			for jogador in get_tree().get_nodes_in_group("jogadores"):
				_entregar_chave_interna(jogador)
				
		queue_free() # Some do mapa
		return

	body_entered.connect(_on_body_entered)

# --- EFEITO VISUAL DE ROTAÇÃO ---
func _process(delta):
	rotate_y(rotation_speed * delta)

func _on_body_entered(body):
	if body is BaseVehicle or body.is_in_group("jogadores"):
		
		# --- ENTREGA DA CHAVE (PRIMEIRA VEZ) ---
		if grants_teleport_key:
			_entregar_chave_interna(body)
			print("[Item] Chave do Teleporte adquirida por ", body.name, "!")
			
			# --- MENSAGEM NO TOAST ---
			var input = body.get_node_or_null("%InputComponent")
			if input and not input.is_bot:
				var hud = get_tree().get_first_node_in_group("HUD" + input.suffix)
				if not hud: hud = get_tree().get_first_node_in_group("HUD")
				
				if hud and hud.has_method("criar_toast"):
					print("[Item] Enviando sucesso para HUD: ", hud.name)
					hud.criar_toast("Key collected. Teleporters are now unlocked!", Color.DODGER_BLUE)
				else:
					print("[Item] ERRO: Nenhuma HUD encontrada na cena!")
		_collect()

# Função auxiliar para não repetir código
func _entregar_chave_interna(alvo):
	if "has_teleportkey" in alvo:
		alvo.has_teleportkey = true
	else:
		var stats = alvo.get_node_or_null("%StatsComponent")
		if stats and "has_teleportkey" in stats:
			stats.has_teleportkey = true

func _collect():
	print("[Item] Coletou: ", mission_id)

	MissionManager.notify_progress(MissionItem.Type.COLLECT, 1.0, mission_id)
	
	# Efeito visual/sonoro antes de sumir
	# spawn_particles()
	
	queue_free()
