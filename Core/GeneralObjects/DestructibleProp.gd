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

# ============================================================================
# NOVO: Fragmentos de destruição (visual). Cada tipo de objeto (carro,
# prédio, barril) pode ter valores diferentes direto no Inspector, sem
# precisar de nenhum script ou nó adicional — a explosão em si é calculada
# pelo DebrisManager (autoload), este script só decide COMO ela deve parecer
# para este objeto específico.
# ============================================================================
@export_group("Fragmentos de Destruição")
## Liga/desliga o efeito de explosão em fragmentos ao morrer
@export var spawn_debris_on_death : bool = true
## Caminho pro MeshInstance3D deste objeto (deixe vazio pra detectar automaticamente)
@export var mesh_instance_path : NodePath
## Quantidade de fragmentos (objetos pequenos: 5-8 / carros: 10-14 / prédios: 16-24)
@export var shard_count : int = 10
## Força lateral da explosão
@export var explosion_force : float = 4.0
## Quanto os fragmentos são impulsionados pra cima
@export var upward_bias : float = 3.5
## Tempo (segundos) até cada fragmento sumir
@export var shard_lifetime : float = 1.1
## Dispersão do ponto de origem dos fragmentos (objetos maiores = raio maior)
@export var scatter_radius : float = 0.4
## Tamanho mínimo de cada fragmento (aresta aproximada, em unidades do mundo)
@export var shard_min_size : float = 0.15
## Tamanho máximo de cada fragmento (prédios/carros: aumente bastante)
@export var shard_max_size : float = 0.35

# A vida atual começa igual à vida máxima quando o objeto nasce
@onready var health : float = max_health

func take_damage(amount: float, attacker: Node3D = null):
	if health <= 0: return 
	health -= amount
	
	var actual_shooter = attacker
	var final_knockback = amount * 30.0 
	
	if attacker:
		if "shooter" in attacker and is_instance_valid(attacker.shooter):
			actual_shooter = attacker.shooter
		if "knockback_force" in attacker:
			final_knockback = attacker.knockback_force
			
		if is_instance_valid(actual_shooter):
			var hit_dir = (global_position - actual_shooter.global_position).normalized()
			hit_dir.y = 0.2
			apply_central_impulse(hit_dir * final_knockback)
	
	if actual_shooter:
		# --- CORREÇÃO: SÓ RISCA SE FOR A METRALHADORA BÁSICA ---
		if actual_shooter.is_in_group("jogadores"):
			# Checa se o 'attacker' (a bala) NÃO é uma arma especial
			if attacker and "is_special_weapon" in attacker and not attacker.is_special_weapon:
				get_tree().call_group("TutorialUI", "complete_task", "barrels")
			
		_give_energy_to_attacker(actual_shooter, energy_on_hit)
		
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("HIT_OBJECT")
	
	if health <= 0:
		_morrer(actual_shooter)

func _morrer(actual_shooter: Node3D):
	if actual_shooter:
		# 1. Recupera energia por DESTRUIÇÃO
		_give_energy_to_attacker(actual_shooter, energy_on_destroy)
		
		# 2. Registra a destruição para pontos
		var gtm = actual_shooter.get_node_or_null("%GroundTrickManager")
		if gtm:
			gtm.add_ground_action("DESTROY_OBJECT")
			
			# 3. Notifica o MissionManager se houver ID
			if mission_id != "" and is_instance_valid(MissionManager):
				MissionManager.notify_progress(MissionItem.Type.DESTROY, 1.0, mission_id)
	
	_spawn_debris()
	queue_free()

# NOVO: dispara a explosão de fragmentos usando o DebrisManager (autoload).
# Este objeto não precisa saber COMO a explosão funciona, só pede pra
# acontecer com os parâmetros configurados no Inspector.
func _spawn_debris() -> void:
	if not spawn_debris_on_death:
		return
	if not is_instance_valid(DebrisManager):
		push_warning("[DestructibleProp] DebrisManager não encontrado. Configure como Autoload.")
		return
	
	var mesh_inst := _find_mesh_instance()
	var mat: Material = null
	if mesh_inst and mesh_inst.mesh:
		mat = mesh_inst.get_active_material(0)
	
	DebrisManager.explode(
		global_position,
		mat,
		shard_count,
		explosion_force,
		upward_bias,
		shard_lifetime,
		scatter_radius,
		shard_min_size,
		shard_max_size
	)

func _find_mesh_instance() -> MeshInstance3D:
	if mesh_instance_path != NodePath(""):
		var node := get_node_or_null(mesh_instance_path)
		if node is MeshInstance3D:
			return node
	return find_child("*", true, false) as MeshInstance3D

# --- FUNÇÃO AUXILIAR DE ENERGIA ---
func _give_energy_to_attacker(attacker: Node3D, amount: float):
	var ability = attacker.get_node_or_null("%AbilityComponent")
	if ability:
		# Adiciona a energia respeitando o limite máximo definido no componente
		ability.current_energy = min(ability.current_energy + amount, ability.MAX_ENERGY)
