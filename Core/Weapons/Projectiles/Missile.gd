extends BaseProjectile

@export_group("Física do Míssil")
@export var speed = 80.0
@export var steering_force = 18.0 

# ============================================================================
# EFEITOS VISUAIS
# ============================================================================
@export_group("Efeitos da Explosão Final")
@export var explosion_color : Color = Color(1.0, 0.5, 0.0)
@export var explosion_size : float = 15.0 
@export var explosion_particles : int = 15
@export var explosion_smoke_size : float = 20.0 
@export var explosion_smoke_color : Color = Color(0.1, 0.1, 0.1, 1.0)
@export var fire_duration : float = 1.0 # NOVO: Tempo do fogo na tela!

@export_group("Efeitos de Lançamento")
@export var launch_smoke_size : float = 4.0
@export var launch_smoke_color : Color = Color(0.7, 0.7, 0.7, 1.0)

var target : Node3D = null

func _ready():
	super._ready()

# Sobrescrevemos o setup para aceitar o "incoming_target" do míssil
func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 80.0, incoming_target: Node3D = null):
	# O pai faz a matemática de inércia, tiros reversos e ativa o monitoramento
	super.setup(dmg_value, car_velocity, source_car, propulsion_speed)
	
	target = incoming_target if (is_instance_valid(incoming_target) and not incoming_target.is_queued_for_deletion()) else null
		
	# === EFEITO DE LANÇAMENTO (Apenas Fumaça) ===
	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(
			global_position, 
			launch_smoke_color, 
			0.0,                # Tamanho do Fogo zerado
			4,                  # Poucas partículas
			0.0,                # Sem luz
			launch_smoke_color, # Cor da Fumaça
			launch_smoke_size,
			0.2
		)

func _physics_process(delta):
	# NOTA: Não chamamos o super._physics_process(delta) porque a movimentação 
	# base é em linha reta, e o míssil precisa fazer curvas teleguiadas!
	var real_delta = delta
	if is_instance_valid(shooter) and shooter.is_in_group("jogadores"):
		real_delta = delta / Engine.time_scale

	# --- CRONÔMETRO DE RECICLAGEM ---
	if life_timer > 0:
		life_timer -= real_delta
		if life_timer <= 0:
			_deactivate_and_pool()
			return
			
	if hit_done: return # Se bateu, congela no ar esperando a animação sumir
	
	# --- LÓGICA DE TELEGUIDO (HOMING) ---
	if target and is_instance_valid(target) and not target.is_queued_for_deletion():
		# ====================================================================
		# AJUSTE DA MIRA: Eleva o alvo em 0.5m no eixo Y para não bater no chão
		# ====================================================================
		var target_pos = target.global_position + Vector3(0, 0.5, 0)
		
		# Detecção de impacto manual por proximidade (segurança contra mísseis muito rápidos)
		if global_position.distance_to(target_pos) < 2.0:
			_on_impact(target) 
			return

		var desired_dir = (target_pos - global_position).normalized()
		var steering = (desired_dir * speed - velocity) * steering_force * real_delta
		velocity += steering
	else:
		velocity = velocity.move_toward(velocity.normalized() * speed, real_delta * 100.0)
	
	global_position += velocity * real_delta
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP)

func _play_impact_vfx():
	# === A GRANDE EXPLOSÃO DO IMPACTO ===
	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(
			global_position, 
			explosion_color,         
			explosion_size,          
			explosion_particles,     
			8.0,                     
			explosion_smoke_color,   
			explosion_smoke_size,
			fire_duration            # Variável nova conectada!
		)
		
	# Chama o pai! Ele cuida de acionar o Camera Shake com a distância correta,
	# frear o míssil, desativar a colisão, e acionar o timer pra devolver pro Pool.
	super._play_impact_vfx()
