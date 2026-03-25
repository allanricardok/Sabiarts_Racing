# DestructibleProp.gd
extends RigidBody3D

@export_group("Mission Settings")
## Escreva aqui o ID para as missões (ex: barril, enemy_car)
@export var mission_id : String = ""

@export_group("Balance")
## Vida máxima do objeto (usado para calcular a barra de vida no HUD)
@export var max_health : float = 20.0
## Energia ganha ao destruir completamente o objeto
@export var energy_on_destroy : float = 20.0
## Energia ganha a cada hit (dano) recebido
@export var energy_on_hit : float = 1.0

# A vida atual começa igual à vida máxima quando o objeto nasce
@onready var health : float = max_health

func take_damage(amount: float, attacker: Node3D = null):
	if health <= 0: return 
	health -= amount
	
	# --- EXTRAÇÃO DE DADOS DA BALA ---
	var actual_shooter = attacker
	var final_knockback = amount * 30.0 # Força padrão caso seja um atropelamento
	
	if attacker:
		if "shooter" in attacker and is_instance_valid(attacker.shooter):
			actual_shooter = attacker.shooter
		if "knockback_force" in attacker:
			final_knockback = attacker.knockback_force
			
		# --- EMPURRÃO FÍSICO CONTROLADO ---
		if is_instance_valid(actual_shooter):
			var hit_dir = (global_position - actual_shooter.global_position).normalized()
			hit_dir.y = 0.2 # Dá aquele saltinho para cima
			apply_central_impulse(hit_dir * final_knockback)
	
	# Passamos o 'actual_shooter' (o Carro) para garantir que ele ganhe a energia e pontos
	if actual_shooter:
		# 1. Recupera energia por HIT
		_give_energy_to_attacker(actual_shooter, energy_on_hit)
		
		# 2. Registra a ação no GroundTrickManager para pontos
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("HIT_OBJECT")
	
	# VFX de piscar... (opcional: car.anim_player.play("hit"))
	
	if health <= 0:
		_morrer(actual_shooter)

func _morrer(actual_shooter: Node3D):
	if actual_shooter:
		# 1. Recupera energia por DESTRUIÇÃO
		_give_energy_to_attacker(actual_shooter, energy_on_destroy)
		
		# 2. Registra a destruição para pontos
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			print("[Prop] Destruído por: ", actual_shooter.name, " +", energy_on_destroy, " energia")
			gtm.add_ground_action("DESTROY_OBJECT")
			
			# 3. Notifica o MissionManager se houver ID
			if mission_id != "" and is_instance_valid(MissionManager):
				MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
	
	queue_free()

# --- FUNÇÃO AUXILIAR DE ENERGIA ---
func _give_energy_to_attacker(attacker: Node3D, amount: float):
	var ability = attacker.get_node_or_null("%AbilityComponent")
	if ability:
		# Adiciona a energia respeitando o limite máximo definido no componente
		ability.current_energy = min(ability.current_energy + amount, ability.MAX_ENERGY)
