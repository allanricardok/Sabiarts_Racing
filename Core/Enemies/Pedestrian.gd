# Pedestrian.gd
extends CharacterBody3D

var is_dead: bool = false

@export_group("Pedestrian Settings")
@export var base_speed: float = 6.0
## Se ativo, ele foge magicamente dos carros e não morre atropelado (Estilo Driver)
@export var is_invincible: bool = false
@export var energy_on_death: float = 5.0

@export_group("Wander Settings")
## A distância máxima que ele pode se afastar de onde nasceu (em metros)
@export var max_wander_radius: float = 30.0

var current_direction: Vector3 = Vector3.ZERO
var panic_timer: float = 0.0

# Guarda a posição de onde ele nasceu
var spawn_position: Vector3 = Vector3.ZERO

func _ready():
	# Registra a casa dele!
	spawn_position = global_position
	
	_pick_new_direction()
	
	# Garante que a animação esteja rodando
	var anim = find_child("AnimatedSprite3D")
	if anim: anim.play()

func _physics_process(delta):
	# Gravidade básica
	if not is_on_floor():
		velocity.y -= 9.8 * delta
		
	# Lógica de Pânico (Muda de direção aleatoriamente)
	panic_timer -= delta
	if panic_timer <= 0:
		_pick_new_direction()
		
	var move_vel = current_direction * base_speed
	
	# --- A MÁGICA DO JOGO DRIVER (SABÃO) ---
	var dodge_vel = Vector3.ZERO
	if is_invincible:
		var players = get_tree().get_nodes_in_group("jogadores")
		for p in players:
			if not is_instance_valid(p): continue
			var dist = global_position.distance_to(p.global_position)
			
			if dist < 8.0:
				var away_dir = (global_position - p.global_position).normalized()
				away_dir.y = 0
				dodge_vel = away_dir * 30.0 
				break

	# Aplica a velocidade de corrida + a velocidade de esquiva (se houver)
	velocity.x = move_vel.x + dodge_vel.x
	velocity.z = move_vel.z + dodge_vel.z
	
	move_and_slide()

func _pick_new_direction():
	# --- SISTEMA DE COLEIRA (TETHER) ---
	# Pergunta: Eu estou muito longe de casa?
	var dist_from_spawn = global_position.distance_to(spawn_position)
	
	if dist_from_spawn > max_wander_radius:
		# Se sim, força a direção para apontar de volta para o Spawn
		current_direction = (spawn_position - global_position).normalized()
		# Adiciona uma levinha variação (ruído) para ele não andar numa linha perfeitamente reta como um robô
		current_direction = current_direction.rotated(Vector3.UP, randf_range(-0.5, 0.5))
	else:
		# Se estiver perto de casa, escolhe um ângulo aleatório em 360 graus
		var random_angle = randf() * TAU 
		current_direction = Vector3(cos(random_angle), 0, sin(random_angle)).normalized()
		
	# Corre nessa direção por 1 a 3 segundos
	panic_timer = randf_range(1.0, 3.0)

func _on_hitbox_body_entered(body):
	if body is VehicleBody3D or body.is_in_group("jogadores"):
		if is_invincible: return 
		take_damage(100.0, body)

func take_damage(amount: float, attacker: Node3D = null):
	var attacker_name = attacker.name if is_instance_valid(attacker) else "Desconhecido"
	
	# NOVO LOG: O pedestre escutou a chamada de dano
	print("[PEDESTRE DEBUG] O Pedestre ", self.name, " recebeu a chamada de dano do atacante: ", attacker_name)

	# --- BLINDAGEM CONTRA METRALHADORA (MULTI-HITS) ---
	if is_invincible or is_dead: 
		print(" -> Mas o pedestre ignorou o tiro (Invencível ou já estava morto).")
		return 
	is_dead = true # Morreu!
	
	var actual_shooter = attacker
	if attacker and "shooter" in attacker and is_instance_valid(attacker.shooter):
		actual_shooter = attacker.shooter
		
	if is_instance_valid(actual_shooter):
		var ability = actual_shooter.get_node_or_null("%AbilityComponent")
		if ability:
			ability.current_energy = min(ability.current_energy + energy_on_death, ability.MAX_ENERGY)
			
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("HIT_OBJECT")
			
	if GameStats:
		GameStats.add_pedestrian_kill()
		
	# TODO: Instanciar VFX/SFX de morte (Isso vai resolver a sua sensação de tiros falsos!)
	queue_free()
