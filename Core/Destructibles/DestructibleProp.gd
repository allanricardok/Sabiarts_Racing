# DestructibleProp.gd
extends RigidBody3D

@export_group("Mission Settings")
## Escreva aqui o ID para as missões (ex: barril, enemy_car)
@export var mission_id : String = ""

@export_group("Balance")
@export var health : float = 20.0
## Energia ganha ao destruir completamente o objeto
@export var energy_on_destroy : float = 20.0
## Energia ganha a cada hit (dano) recebido
@export var energy_on_hit : float = 1.0

func take_damage(amount: float, attacker: Node3D = null):
	if health <= 0: return 
	health -= amount
	
	if attacker:
		# 1. Recupera energia por HIT
		_give_energy_to_attacker(attacker, energy_on_hit)
		
		# 2. Registra a ação no GroundTrickManager para pontos
		var gtm = attacker.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("HIT_OBJECT")
	
	# VFX de piscar... (opcional: car.anim_player.play("hit"))
	
	if health <= 0:
		_morrer(attacker)

func _morrer(attacker: Node3D):
	if attacker:
		# 1. Recupera energia por DESTRUIÇÃO
		_give_energy_to_attacker(attacker, energy_on_destroy)
		
		# 2. Registra a destruição para pontos
		var gtm = attacker.get_node_or_null("%GroundTrickManager")
		if gtm:
			print("[Prop] Destruído por: ", attacker.name, " +", energy_on_destroy, " energia")
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
