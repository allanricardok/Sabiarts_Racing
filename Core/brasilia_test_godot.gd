extends VehicleBody3D

# --- PRELOADS ---
# TEXTURAS (Máscaras) - Referenciando a pasta Texturas
const TEX_ARLEQUIM = preload("res://Assets/2D/mascara_arlequim.png")
const TEX_KITSUNE = preload("res://Assets/2D/mascara_kitsune.png")
const TEX_GUERRILHA = preload("res://Assets/2D/mascara_guerrilha.png")
const TEX_LUCHADOR = preload("res://Assets/2D/mascara_luchador.webp")
const TEX_CYBERPUNK = preload("res://Assets/2D/cyberpunk_mask.png")

# CENAS (Objetos e Projéteis) - Referenciando a pasta Scenes
const SCENE_MISSIL = preload("res://Scenes/Prefabs/Weapons/Missil.tscn")
const SCENE_IMPACTO = preload("res://Scenes/Prefabs/Weapons/OndaImpacto.tscn")
const SCENE_PARTICULA_PULO_CYBER = preload("res://Scenes/Prefabs/Weapons/ParticulaPuloCyber.tscn")
const SCENE_CHOQUE_CYBER = preload("res://Scenes/Prefabs/Weapons/AreaChoqueCyber.tscn")
# --- AUDIO ---
@onready var sound = $AudioStreamPlayer
@export var fxJump = AudioStream
@export var fxMaskOn = AudioStream
@export var fxMaskOff = AudioStream
@export var fxBoost = AudioStream
@export var fxMissile = AudioStream

# --- CONFIGURAÇÃO DE MULTIPLAYER ---
@export_group("Multiplayer")
@export_enum("K1", "K2", "J0", "J1", "J2", "J3") var input_source: String = "K1"

# --- EXPORTS DE FÍSICA (Originais) ---
@export_group("Física e Movimento")
@export var MAX_STEER = 0.9
@export var ENGINE_POWER = 300
@export var BRAKE_POWER = 50.0 
@export var BRAKE_ASSIST_FORCE = 20.0 
@export var AIR_RESISTANCE = 0.12

@export_group("Boost e Pulo")
@export var START_BOOST = 2.5
@export var BOOST_LIMIT_SPEED = 15.0 
@export var BOOST_IMPULSE = 50.0 
@export var JUMP_IMPULSE = 10.0  
@export var MAX_BOOST_CHARGES = 10
var jump_count: int = 0 # 0 = chão, 1 = primeiro pulo, 2 = pulo duplo usado
var pode_resetar_pulo: bool = true # Controla se o chão pode zerar o contador

@export_group("Controle Aéreo")
@export var AIR_CONTROL_FORCE = 40.0 
@export var AIR_TORQUE_FORCE = 1.0   

@export_group("Fricção Dinâmica")
@export var friction_rear_min := 1.1
@export var friction_rear_max := 3.0
@export var speed_max_friction := 150.0
@export var wheel_rear_left: VehicleWheel3D
@export var wheel_rear_right: VehicleWheel3D
@export var friction_front_min := 1.1
@export var friction_front_max := 3.5
@export var wheel_front_left: VehicleWheel3D
@export var wheel_front_right: VehicleWheel3D

# --- SISTEMA DE MÁSCARAS ---
var current_mask: String = ""
var mask_durability: float = 0.0
var base_stats = {}
var can_fire: bool = true
@export_group("Luchador")
@export var GROUND_POUND_FORCE := 60.0
@export_group("Cyberpunk")
@export var CYBER_JUMP_FORCE := 15.0 # Força do segundo pulo no ar

# --- REFERÊNCIAS ---
@export_group("Interface do Jogador")
@export var durability_bar: ProgressBar
@export var mask_name_label: Label
@export var speed_label: Label
@export var boost_ui: HBoxContainer
@export var mask_sprite: Sprite3D # Se o Sprite3D da máscara estiver aqui
@onready var car_mesh = $corpo
@onready var muzzle = $Muzzle
@onready var all_wheels = [wheel_rear_left, wheel_rear_right, wheel_front_left, wheel_front_right]
@export var cooldown_bar: Range # Pode ser ProgressBar ou TextureProgressBar
@export var cooldown_text: Label # Arraste o CooldownText para cá no Inspetor
@onready var neon_light = $NeonUnderglow # Referência à luz que você criou

# --- CACHE DE INPUTS ---
var act_forward: String
var act_backward: String
var act_left: String
var act_right: String
var act_jump: String
var act_boost: String
var act_fire: String
var act_pitch_up: String
var act_pitch_down: String

# --- ESTADO ---
var current_boost_charges = 1
var can_boost: bool = true
var current_speed_mps = 0.0
var flipped_timer: float = 0.0
@export var FLIP_WAIT_TIME: float = 0.05 # Tempo esperando de ponta-cabeça antes de desvirar
var is_ground_pounding: bool = false
var was_on_ground: bool = false # Para detectar o momento exato do impacto

var pode_mover : bool = false
@export var intro_overlay: Control
@export var player_intro_label: Label # Arraste o PlayerIntroNum para cá no Inspetor

# --- PROGRESSO DA CORRIDA ---
var proximo_checkpoint_esperado : int = 0
var voltas_completadas : int = 0
var total_checkpoints_no_mapa : int = 0
var finalizou_corrida : bool = false
var tempo_final_jogador : float = 0.0

@export var lap_label: Label
@export var time_label: Label

func _ready():
	# 1. Configura as ações dinamicamente
	var suffix = "_" + input_source
	act_forward = "Forward" + suffix
	act_backward = "Backward" + suffix
	act_left = "Left" + suffix
	act_right = "Right" + suffix
	act_jump = "Jump" + suffix
	act_boost = "Boost" + suffix
	act_fire = "Fire" + suffix
	act_pitch_up = "Pitch_Up" + suffix
	act_pitch_down = "Pitch_Down" + suffix

	base_stats = {
		"engine": ENGINE_POWER,
		"air_res": AIR_RESISTANCE,
		"air_con": AIR_CONTROL_FORCE,
		"jump": JUMP_IMPULSE,
		"boost": BOOST_IMPULSE
	}
	contact_monitor = true
	max_contacts_reported = 10  # Detect up to 10 obstacles
	
	if cooldown_bar:
		cooldown_bar.value = 100.0 # Começa cheia
	if cooldown_text:
		cooldown_text.hide() # Começa escondido
	
	# IMPORTANTE: Removi o set_as_top_level(true) que pode bugar colisões em subviewports
	add_to_group("jogadores")
	
	# Espera o mapa carregar
	await get_tree().process_frame 
	total_checkpoints_no_mapa = get_tree().get_nodes_in_group("checkpoints").size()
	
	# O PULO DO GATO: Começamos esperando o 1, ignorando o 0 da largada
	proximo_checkpoint_esperado = 1
	print("Carro ", input_source, " pronto! Buscando Checkpoint 1.")

	if car_mesh:
		var original_mat = car_mesh.get_active_material(0)
		if original_mat:
			var unique_mat = original_mat.duplicate()
			car_mesh.set_surface_override_material(0, unique_mat)
	
	add_to_group("jogadores")
	
	# Se o Global estiver vazio, criamos o ID de teste antes do RaceManager rodar
	if Global.dados_jogadores[0] == null:
		Global.clonar_jogador_teste(0)
	
	# Agora o carro pode configurar suas variáveis sem dar erro
	configurar_carro_pelo_id(0)

func configurar_carro_pelo_id(id):
	var data = Global.dados_jogadores[id]
	
	if data != null:
		# Se você está usando a lógica do Lobby de enviar "K1", "J1":
		input_source = data # Atribui a String "K1" direto para a sua variável de controle
		print("Carro configurado para o controle: ", input_source)
	else:
		print("Aviso: Slot de jogador vazio.")

func _physics_process(delta):
	# 1. ATUALIZAÇÃO DE UI (Sempre roda)
	current_speed_mps = linear_velocity.length()
	var speed_kmh = current_speed_mps * 2
	if is_instance_valid(speed_label):
		speed_label.text = str(int(speed_kmh))
	
	var manager = get_tree().get_first_node_in_group("race_manager")
	
	if manager:
		# Se o jogador já terminou, mostra o tempo em que ele cruzou a linha
		# Se não, mostra o tempo atual do cronômetro global
		var tempo_para_exibir = tempo_final_jogador if finalizou_corrida else manager.tempo_decorrido
		_atualizar_timer_ui(tempo_para_exibir)
		
		if is_instance_valid(lap_label):
			var total_v = manager.voltas_para_vencer
			# O CLAMP garante que, se ele terminou a volta 2, continue mostrando 2/2
			var volta_atual = clamp(voltas_completadas + 1, 1, total_v)
			lap_label.text = "VOLTA: " + str(volta_atual) + "/" + str(total_v)
	
	_check_auto_flip(delta)
	
	if not pode_mover:
		return

# 1. VERIFICAÇÃO DE CHÃO
	var is_on_ground = false
	for wheel in all_wheels:
		if wheel and wheel.is_in_contact():
			is_on_ground = true
			break
			
	# 2. RESET DO CONTADOR (Com trava de segurança)
	if is_on_ground and pode_resetar_pulo:
		if jump_count != 0:
			print("DEBUG: Resete seguro no chão.")
		jump_count = 0

	# 3. LÓGICA DE PULO
	if Input.is_action_just_pressed(act_jump):
		# PRIMEIRO PULO (No Chão)
		if is_on_ground:
			apply_central_impulse(Vector3.UP * JUMP_IMPULSE * mass)
			jump_count = 1
			sound.stream = fxJump
			sound.play()
			
			# BLOQUEIO: Impede o reset imediato por 0.1s
			pode_resetar_pulo = false
			get_tree().create_timer(0.1).timeout.connect(func(): pode_resetar_pulo = true)
			
			print("DEBUG: Pulou! Reset travado por 0.1s.")
		
		# PULO DUPLO (No Ar - Máscara Cyberpunk)
		elif current_mask == "Cyberpunk" and jump_count == 1:
			# Zera a velocidade vertical para o pulo ser limpo e forte
			linear_velocity.y = 0 
			apply_central_impulse(Vector3.UP * (JUMP_IMPULSE * 2) * mass)
			sound.stream = fxJump
			sound.play()
			
			jump_count = 2
			_spawn_particula_pulo()
			print("DEBUG: DOUBLE JUMP!")

# DETECÇÃO DE IMPACTO LUCHADOR
	if is_on_ground and not was_on_ground:
		if is_ground_pounding:
			_gerar_explosao_luchador() # Chama a nova função
			is_ground_pounding = false
			# Se colidimos forte, garantimos que a velocidade Y zere 
			# para o carro não tentar "entrar" no chão no próximo frame
			linear_velocity.y = 0
			
			# Aplica o boost frontal (momentum)
			apply_central_impulse(global_transform.basis.z * 8.0 * mass)
			
			is_ground_pounding = false
			print("IMPACTO LUCHADOR: Pouso seguro com boost!")
	
	was_on_ground = is_on_ground # Salva o estado para o próximo frame
	# LER INPUTS DINÂMICOS (Baseado no input_source)
	var input_steer = Input.get_axis(act_right, act_left)
	var input_forward = Input.get_axis(act_backward, act_forward)

	# 2. PROCESSAMENTO DE SISTEMAS
	_process_dynamic_friction(speed_kmh)
	_process_engine_and_brake(delta, is_on_ground, input_steer, input_forward)
	
	# 3. AÇÕES (Boost, Tiro)

	if can_boost and current_boost_charges > 0 and Input.is_action_just_pressed(act_boost):
		_apply_boost()

	if current_mask == "Guerrilha" and Input.is_action_just_pressed(act_fire) and can_fire:
		_shoot_missile()
		
	# NOVA MECÂNICA: Luchador Fire
	if current_mask == "Luchador" and Input.is_action_just_pressed(act_fire) and can_fire:
		if not is_on_ground: # Só funciona no ar!
			_apply_ground_pound()
			
	if current_mask == "Cyberpunk" and Input.is_action_just_pressed(act_fire) and can_fire:
		_activate_cyber_shockwave()

	# 4. CONTROLE AÉREO E RESISTÊNCIA DO AR
	if not is_on_ground:
		_process_air_control(delta, input_steer, input_forward)
	
	if current_speed_mps > 0.1:
		var drag_force = -linear_velocity.normalized() * (current_speed_mps * current_speed_mps) * AIR_RESISTANCE
		apply_central_force(drag_force * mass * delta)

	# 5. DURABILIDADE DA MÁSCARA
	if current_mask != "":
		mask_durability -= delta * 5.0
		update_mask_ui()
		if mask_durability <= 0:
			remove_mask()
	
	var colliding_bodies = get_colliding_bodies()
	for body in colliding_bodies:
		if body.is_in_group("obstacles"):
			print("Hit obstacle!")
			var rel_velocity = linear_velocity - body.linear_velocity
			var impact_speed = rel_velocity.length()
			
			if impact_speed > 5.0:
				var damage = min(impact_speed * 2.0, 100.0)
				body.take_damage(damage)
				
				# Slow car based on obstacle mass
				var mass_ratio = body.mass / (body.mass + mass)
				linear_velocity *= (1.0 - mass_ratio * 0.5)
				
				print("Damage: ", damage)
				break  # Only process first obstacle per frame
# --- SISTEMAS AUXILIARES ---

func _process_dynamic_friction(speed_kmh):
	var speed_clamp = clamp(speed_kmh, 0, speed_max_friction)
	var f_rear = remap(speed_clamp, 0, speed_max_friction, friction_rear_min, friction_rear_max)
	var f_front = remap(speed_clamp, 0, speed_max_friction, friction_front_max, friction_front_min)
	
	if wheel_rear_left: wheel_rear_left.wheel_friction_slip = f_rear
	if wheel_rear_right: wheel_rear_right.wheel_friction_slip = f_rear
	if wheel_front_left: wheel_front_left.wheel_friction_slip = f_front
	if wheel_front_right: wheel_front_right.wheel_friction_slip = f_front

func _process_engine_and_brake(delta, is_on_ground, steer_in, forward_in):
	steering = move_toward(steering, steer_in * MAX_STEER, delta * 10)
	var forward_velocity = linear_velocity.dot(transform.basis.z)
	brake = 0.0
	
	if is_on_ground:
		if (forward_velocity > 0.2 and forward_in < -0.1) or (forward_velocity < -0.2 and forward_in > 0.1):
			brake = BRAKE_POWER * abs(forward_in)
			var assist_dir = transform.basis.z * (BRAKE_ASSIST_FORCE if forward_velocity < 0 else -BRAKE_ASSIST_FORCE)
			apply_central_force(assist_dir * mass)
			engine_force = 0
		else:
			var boost_factor = remap(current_speed_mps, 0, BOOST_LIMIT_SPEED, START_BOOST, 1.0)
			engine_force = forward_in * ENGINE_POWER * clamp(boost_factor, 1.0, START_BOOST)
	else:
		engine_force = 0
		brake = 0.0

func _process_air_control(delta, steer_in, forward_in):
	# Movimentação lateral e empuxo frontal no ar
	#var move_dir = (global_transform.basis.x * steer_in) + (global_transform.basis.z * min(forward_in, 0.0))
	var forward_in_air = max(forward_in, 0.0)  # No reverse thrust
	var move_dir = (global_transform.basis.x * steer_in) + (global_transform.basis.z * forward_in_air)
	apply_central_force(move_dir * AIR_CONTROL_FORCE * mass)
	
	# PITCH DINÂMICO: Usa as ações específicas do input_source
	var pitch = Input.get_axis(act_pitch_down, act_pitch_up)
	
	# Aplica o torque baseado na inclinação
	apply_torque(-global_transform.basis.x * pitch * AIR_TORQUE_FORCE * mass)
	apply_torque(global_transform.basis.y * steer_in * AIR_TORQUE_FORCE * mass)

func iniciar_intro_jogador():
	# DEBUG INICIAL: Verifica se as referências existem
	print("--- DEBUG INTRO CARRO ---")
	print("Carro ID: ", input_source)
	
	if not intro_overlay:
		print("ERRO: intro_overlay não atribuído no carro ", input_source)
		return
	if not player_intro_label:
		print("ERRO: player_intro_label não atribuído no carro ", input_source)
		return

	# 1. MAPEAMENTO DINÂMICO (Lê do Global)
	# Procura em qual posição da lista o meu input_source está
	# Ex: Se Global.dados_jogadores é ["K1", "K2", "J1", null], 
	# e eu sou o "J1", o index é 2. Player = index + 1 = 3.
	var index_na_lista = Global.dados_jogadores.find(input_source)
	var player_num = index_na_lista + 1
	
	if index_na_lista == -1:
		print("ERRO: Não achei ", input_source, " na lista do Global!")
		player_num = 0 # Fallback para erro
	
	player_intro_label.text = "PLAYER " + str(player_num)
	print("Texto definido para: ", player_intro_label.text)
	
	# 2. RESET DE ESTADO
	intro_overlay.show()
	player_intro_label.show()
	intro_overlay.modulate.a = 1.0
	
	# 3. ANIMAÇÃO
	print("Aguardando 1s de exibição...")
	await get_tree().create_timer(1.0).timeout
	
	var tween = create_tween()
	print("Iniciando Fade Out do fundo...")
	tween.tween_property(intro_overlay, "modulate:a", 0.0, 0.5)
	
	await tween.finished
	intro_overlay.hide()
	print("Fim da Intro para ", input_source)


func equip_arlequim_mask():
	sound.stream = fxMaskOn
	sound.play()
	_reset_stats()
	current_mask = "Arlequim"
	mask_durability = 100.0
	_update_visuals("ARLEQUIM", Color(0.91, 0.5, 0.91), TEX_ARLEQUIM)
	ENGINE_POWER = base_stats.engine * 1.15
	AIR_RESISTANCE = base_stats.air_res * 0.80
	AIR_CONTROL_FORCE = 25.0
	JUMP_IMPULSE = base_stats.jump * 1.40

func equip_kitsune_mask():
	sound.stream = fxMaskOn
	sound.play()
	_reset_stats() 
	current_mask = "Kitsune"
	mask_durability = 100.0
	_update_visuals("KITSUNE VELOZ", Color(1.0, 0.4, 0.0), TEX_KITSUNE)
	ENGINE_POWER = base_stats.engine * 1.40
	AIR_RESISTANCE = base_stats.air_res * 0.70
	BOOST_IMPULSE = base_stats.boost * 1.50

func equip_guerrilha_mask():
	sound.stream = fxMaskOn
	sound.play()
	_reset_stats()
	current_mask = "Guerrilha"
	mask_durability = 100.0
	_update_visuals("GUERRILHA", Color(0.1, 0.3, 0.1), TEX_GUERRILHA)
	ENGINE_POWER = base_stats.engine * 1.15 

func equip_luchador_mask():
	sound.stream = fxMaskOn
	sound.play()
	_reset_stats()
	current_mask = "Luchador"
	mask_durability = 100.0
	# Cor Azul para a UI e o Carro
	_update_visuals("LUCHADOR", Color(0.0, 0.4, 1.0), TEX_LUCHADOR)
	# Pulo +10%
	JUMP_IMPULSE = base_stats.jump * 1.40

func equip_cyberpunk_mask():
	sound.stream = fxMaskOn
	sound.play()
	_reset_stats()
	current_mask = "Cyberpunk"
	mask_durability = 100.0
	
	_update_visuals("CYBERPUNK",Color(0.05, 0.05, 0.06), TEX_CYBERPUNK)
	
	# 1. Visual Grafite Escuro Metálico
	var mat = car_mesh.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color = Color(0.05, 0.05, 0.06) # Grafite quase preto
		mat.metallic = 1.0 # Totalmente metálico
		mat.roughness = 0.1 # Brilhante
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 4.0 # Bordas/detalhes neon
	
	# 2. Ativa a luz de baixo
	if neon_light:
		neon_light.show()
		print("Olha o pisca!")

func _apply_ground_pound():
	if not can_fire: return
	
	can_fire = false
	is_ground_pounding = true
	
	# Em vez de impulso, definimos a velocidade vertical diretamente.
	# Tente um valor entre 30.0 e 50.0 para GROUND_POUND_FORCE.
	linear_velocity.y = -GROUND_POUND_FORCE
	
	# UI de Cooldown (0.5s)
	if is_instance_valid(cooldown_bar):
		cooldown_bar.value = 0.0
		if cooldown_text: cooldown_text.show()
		
		var tween = create_tween()
		tween.tween_property(cooldown_bar, "value", 100.0, 1)
		tween.finished.connect(func(): if cooldown_text: cooldown_text.hide())
	
	await get_tree().create_timer(1).timeout
	can_fire = true
	
func _gerar_explosao_luchador():
	var impacto = SCENE_IMPACTO.instantiate()
	impacto.atirador = self
	
	# Adiciona como FILHO do carro para seguir a velocidade
	add_child(impacto)
	
	# Reseta a posição local para o centro do carro (ou um pouco abaixo)
	impacto.position = Vector3.ZERO 
	
	# Boost frontal de momentum que você já tinha
	apply_central_impulse(global_transform.basis.z * 30.0 * mass)
	
	print("POW! Onda de choque móvel ativada.")

func _spawn_particula_pulo():
	if not SCENE_PARTICULA_PULO_CYBER: return
	var part = SCENE_PARTICULA_PULO_CYBER.instantiate()
	get_tree().current_scene.add_child(part)
	
	# Posiciona um pouco mais abaixo (0.8m) para não clipar no chassi
	part.global_position = global_position - transform.basis.y * 0.8
	
	# FORÇA A ATIVAÇÃO: Procura por emissores dentro da cena instanciada
	if part is GPUParticles3D:
		part.emitting = true
	for child in part.get_children():
		if child is GPUParticles3D:
			child.emitting = true
			
	# Timer de segurança para limpeza de memória
	get_tree().create_timer(1.5).timeout.connect(func(): part.queue_free())

func _activate_cyber_shockwave():
	if not can_fire or not SCENE_CHOQUE_CYBER: return
	can_fire = false
	
	# Instancia a área de choque como FILHO (para seguir o carro igual o Luchador)
	var choque = SCENE_CHOQUE_CYBER.instantiate()
	choque.atirador = self
	add_child(choque)
	choque.position = Vector3.ZERO

	# UI de Cooldown (Usei 2 segundos como exemplo, ajuste se quiser)
	if is_instance_valid(cooldown_bar):
		cooldown_bar.value = 0.0
		if cooldown_text: cooldown_text.show()
		var tween = create_tween()
		tween.tween_property(cooldown_bar, "value", 100.0, 2.0)
		tween.finished.connect(func(): if cooldown_text: cooldown_text.hide())
	
	await get_tree().create_timer(2.0).timeout
	can_fire = true

func _update_visuals(m_name: String, m_color: Color, m_tex: Texture):
	if mask_name_label:
		mask_name_label.text = m_name
		mask_name_label.show()
	if durability_bar:
		var sb = durability_bar.get_theme_stylebox("fill").duplicate()
		sb.bg_color = m_color
		durability_bar.add_theme_stylebox_override("fill", sb)
		durability_bar.show()
	
	if mask_sprite:
		mask_sprite.texture = m_tex
		mask_sprite.show()
		
	if cooldown_bar:
		cooldown_bar.modulate = m_color
		# ATUALIZADO: Inclui CYBERPUNK na visibilidade da barra
		cooldown_bar.visible = (m_name == "GUERRILHA" or m_name == "LUCHADOR" or m_name == "CYBERPUNK")
		
	if cooldown_text:
		cooldown_text.hide()

	# RESET DE PROPRIEDADES ESPECIAIS (Metálico e Neon)
	var mat = car_mesh.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		# Se NÃO for Cyberpunk, garantimos que o metal e a emissão desliguem
		if m_name != "CYBERPUNK":
			mat.metallic = 0.0
			mat.roughness = 0.5
			mat.emission_enabled = false
			if neon_light: 
				neon_light.hide()
				print("Para o pisca!")
		
		mat.albedo_color = m_color

func _reset_stats():
	ENGINE_POWER = base_stats.engine
	AIR_RESISTANCE = base_stats.air_res
	AIR_CONTROL_FORCE = base_stats.air_con
	JUMP_IMPULSE = base_stats.jump
	BOOST_IMPULSE = base_stats.boost

func remove_mask():
	current_mask = ""
	mask_durability = 0.0
	if mask_name_label: mask_name_label.hide()
	if durability_bar: durability_bar.hide()
	if mask_sprite: mask_sprite.hide()
	_reset_stats()
	sound.stream = fxMaskOff
	sound.play()
	
	# Desliga a luz sob o carro
	if neon_light: 
		neon_light.hide()
		print("Para o pisca!")
		
	# Reset profundo do material do corpo
	var mat = car_mesh.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color = Color(1, 1, 1) # Volta ao branco original
		mat.metallic = 0.0
		mat.roughness = 0.5
		mat.emission_enabled = false
		mat.emission_energy_multiplier = 1.0 # Reseta a intensidade do brilho
	
	if cooldown_bar: 
		cooldown_bar.hide()
	if cooldown_text: 
		cooldown_text.hide()

func update_mask_ui():
	if durability_bar:
		durability_bar.value = mask_durability
		durability_bar.modulate = Color(1, 0, 0) if mask_durability < 25 else Color(1, 1, 1)

func take_damage(amount: float):
	if current_mask != "":
		mask_durability -= amount
		update_mask_ui()
		
		# Inicia o efeito de piscar
		_efeito_flicker_visibilidade()
		
		# Se quiser manter o brilho vermelho junto:
		var mat = car_mesh.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat.emission_enabled = true
			mat.emission = Color(2, 0, 0)
			get_tree().create_timer(.3).timeout.connect(func(): 
				mat.emission_enabled = false
				_update_visual_color_back()
			)

func _efeito_flicker_visibilidade():
	var duration = 1 # Duração total do efeito (tempo de "invulnerabilidade")
	var frequency = 0.1 # Velocidade do pisca (menor = mais rápido)
	var loops = int(duration / (frequency * 2))
	
	var tween = create_tween()
	for i in range(loops):
		tween.tween_callback(func(): car_mesh.visible = false).set_delay(frequency)
		tween.tween_callback(func(): car_mesh.visible = true).set_delay(frequency)
	
	# Garante que ao final o carro esteja visível
	tween.finished.connect(func(): car_mesh.visible = true)

func _update_visual_color_back():
	var color = Color(1,1,1)
	if current_mask == "Arlequim": color = Color(0.91, 0.5, 0.91)
	elif current_mask == "Kitsune": color = Color(1.0, 0.4, 0.0)
	elif current_mask == "Guerrilha": color = Color(0.1, 0.3, 0.1)
	var mat = car_mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		mat.albedo_color = color

func _shoot_missile():
	if not SCENE_MISSIL or not can_fire: return
	
	can_fire = false
	
	if is_instance_valid(cooldown_bar):
		cooldown_bar.value = 0.0 # "Acaba" quando atira
		if cooldown_text: cooldown_text.show()
		
		var tween = create_tween()
		# Enche a barra de 0 a 100 em 2 segundos
		tween.tween_property(cooldown_bar, "value", 100.0, 2.0)
		# Quando terminar de encher, esconde o texto
		tween.finished.connect(func(): if cooldown_text: cooldown_text.hide())
	
	# --- Instanciação do Míssil ---
	var missile_inst = SCENE_MISSIL.instantiate()
	sound.stream = fxMissile
	sound.play()
	missile_inst.atirador = self
	get_tree().current_scene.add_child(missile_inst)
	missile_inst.global_transform = muzzle.global_transform
	missile_inst.altura_fixa = muzzle.global_position.y
	
	await get_tree().create_timer(2.0).timeout
	can_fire = true

func _apply_boost():
	sound.stream = fxBoost
	sound.play()
	current_boost_charges -= 1
	apply_central_impulse(global_transform.basis.z * BOOST_IMPULSE * mass)
	update_boost_hud()
	can_boost = false
	get_tree().create_timer(0.5).timeout.connect(func(): can_boost = true)

func add_boost(amount: int):
	current_boost_charges = clamp(current_boost_charges + amount, 0, MAX_BOOST_CHARGES)
	update_boost_hud()

func update_boost_hud():
	if boost_ui is HBoxContainer:
		var bars = boost_ui.get_children()
		for i in range(bars.size()):
			bars[i].visible = i < current_boost_charges

func _check_auto_flip(delta):
	var rot = global_rotation_degrees
	# Checa se o carro está inclinado além do limite (X ou Z)
	var is_upside_down = abs(rot.x) > 140 or abs(rot.z) > 140
	
	# Se estiver de ponta-cabeça e quase parado (ou se você quiser checar colisão do corpo)
	if is_upside_down and current_speed_mps < 10.0:
		flipped_timer += delta
		if flipped_timer >= FLIP_WAIT_TIME:
			_perform_flip()
	else:
		flipped_timer = 0.0

func _perform_flip():
	# 1. Mantém a posição, mas sobe um pouquinho para não bugar no chão
	var new_transform = global_transform
	new_transform.origin.y += 2.0 
	
	# 2. Reseta a rotação para zero (Identidade)
	# O orthonormalized garante que a escala do carro não mude
	new_transform.basis = Basis.IDENTITY
	
	global_transform = new_transform
	
	# 3. Zera as velocidades para o carro não sair voando ao desvirar
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	flipped_timer = 0.0
	print("Carro desvirado!")
	
func set_pode_mover(valor: bool):
	pode_mover = valor
	if not pode_mover:
		engine_force = 0
		brake = 100 # Garante que o carro não role ladeira abaixo
	else:
		brake = 0

func registrar_checkpoint(id_atingido: int):
	if finalizou_corrida: return 

	if id_atingido == proximo_checkpoint_esperado:
		if id_atingido == 0:
			voltas_completadas += 1
			var manager = get_tree().get_first_node_in_group("race_manager")
			
			if manager:
				if voltas_completadas >= manager.voltas_para_vencer:
					finalizou_corrida = true
					tempo_final_jogador = manager.tempo_decorrido
					
					# Para o carro e atualiza UI local
					set_pode_mover(false) 
					time_label.modulate = Color(0, 1, 0)
					lap_label.text = "FINALIZADO!"
					
					# Formata o nome: "ID (Player #)"
					var nome_completo = input_source + " (" + player_intro_label.text + ")"
					manager.registrar_chegada_jogador(input_source, nome_completo, tempo_final_jogador)
					return

		proximo_checkpoint_esperado += 1
		if proximo_checkpoint_esperado >= total_checkpoints_no_mapa:
			proximo_checkpoint_esperado = 0

# Função auxiliar para garantir que ele não roubou caminho
func _veio_do_ultimo_checkpoint() -> bool:
	# Se ele esperava o 0, significa que ele já passou pelo último ID do mapa
	return proximo_checkpoint_esperado == 0

func _atualizar_ui_corrida():
	if is_instance_valid(lap_label):
		var manager = get_tree().get_first_node_in_group("race_manager")
		var total_v = manager.voltas_para_vencer if manager else 2
		
		# O CLAMP garante que o número exibido fique entre 1 e o total de voltas
		# Assim, mesmo que voltas_completadas seja 2, ele mostrará 2/2 e não 3/2
		var volta_exibida = clamp(voltas_completadas + 1, 1, total_v)
		
		lap_label.text = "VOLTA: " + str(volta_exibida) + "/" + str(total_v)

func _atualizar_timer_ui(tempo: float):
	if is_instance_valid(time_label):
		var minutos = int(tempo / 60)
		var segundos = int(tempo) % 60
		var milissegundos = int((tempo - int(tempo)) * 100)
		time_label.text = "%02d:%02d.%02d" % [minutos, segundos, milissegundos]
