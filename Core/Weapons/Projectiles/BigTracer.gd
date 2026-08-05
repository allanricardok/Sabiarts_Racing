extends BaseProjectile

# ============================================================================
# EFEITOS VISUAIS
# ============================================================================
@export_group("Efeitos da Explosão Final")
@export var explosion_color : Color = Color(1.0, 0.5, 0.0)
@export var explosion_size : float = 35.0
@export var explosion_particles : int = 15
@export var explosion_smoke_size : float = 6.0
@export var explosion_smoke_color : Color = Color(0.1, 0.1, 0.1, 1.0)

# NOVO: Controle individual de quanto tempo o fogo fica na tela
@export var fire_duration : float = 1.0 

@export_group("Efeitos de Lançamento")
@export var launch_smoke_size : float = 1.0
@export var launch_smoke_color : Color = Color(0.7, 0.7, 0.7, 1.0)


func _ready():
	super._ready()

func setup(dmg_value: float, car_velocity: Vector3, source_car: Node3D, propulsion_speed: float = 50.0):
	super.setup(dmg_value, car_velocity, source_car, propulsion_speed)
	
	# === EFEITO DE LANÇAMENTO ===
	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(
			global_position, 
			launch_smoke_color, 
			0.0,                # Fogo zerado (só queremos fumaça)
			3,                  # Menos partículas pro lançamento
			0.0,                # Sem luz
			launch_smoke_color, # Cor da fumaça
			launch_smoke_size,
			0.2                 # Tempo do fogo irrelevante aqui
		)

func _play_impact_vfx():
	# === A GRANDE EXPLOSÃO DO IMPACTO ===
	# Nós chamamos o efeito do Manager ANTES da bala sumir
	if is_instance_valid(ExplosionManager):
		ExplosionManager.explode(
			global_position, 
			explosion_color,         
			explosion_size,          
			explosion_particles,     
			8.0,                     
			explosion_smoke_color,   
			explosion_smoke_size,
			fire_duration            
		)
		
	# Chama a rotina original do BaseProjectile! 
	# O pai vai se encarregar de desativar o monitoramento, frear a bala (velocity = ZERO), 
	# esconder o visual e acionar o timer de 0.1s para devolver pro Pool com segurança.
	super._play_impact_vfx()
