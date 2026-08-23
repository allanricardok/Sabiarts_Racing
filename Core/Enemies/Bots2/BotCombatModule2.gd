extends Node
class_name BotCombatModuleV2

var car: BaseVehicle
var input: Node
var stats: Node
var radar: BotRadarV2

@export_group("Combate Automático")
@export var initial_ammo: int = 12
@export var ammo_regen_rate: float = 4.0
@export_range(20.0, 100.0) var max_damage_per_target: float = 50.0

var target: Node3D = null 

var ammo_regen_timer: float = 0.0
var ammo_added_to_current: int = 0
var disparos_especiais_seguidos: int = 0
var _last_logged_ammo: int = -1
var _last_logged_weapon: String = ""

var disparou_no_vip: bool = false
var _delay_tiro_especial: float = 0.0

var targets_exhausted: Dictionary = {} 
var damage_dealt_to_current: float = 0.0
var _last_target_hp: float = -1.0

# NOVO: Flag para garantir que a arma vai receber a munição
var _arma_inicializada: bool = false

func setup(_car: BaseVehicle, _input: Node, _stats: Node, _radar: BotRadarV2):
	car = _car
	input = _input
	stats = _stats
	radar = _radar
	ammo_regen_timer = ammo_regen_rate

	# PRINTA O REGEN RATE INICIAL
	print("[%s COMBATE] Iniciado! Regen Rate: %.1fs | Initial Ammo Base: %d" % [car.name, ammo_regen_rate, initial_ammo])

func _log_ammo(motivo: String = ""):
	var wm = car.get_node_or_null("%WeaponManager")
	if not wm: return
	var active_w = wm.get_active_special()
	var nome_arma = active_w.nome if active_w else "Nenhuma"
	var qtd = active_w.ammo if active_w else 0
	
	# Só printa se a munição mudou, se trocou de arma, ou se forçarem um motivo
	if qtd != _last_logged_ammo or nome_arma != _last_logged_weapon or motivo != "":
		_last_logged_ammo = qtd
		_last_logged_weapon = nome_arma
		
		var txt = "[%s COMBATE] Arma: %s | Ammo: %d" % [car.name, nome_arma, qtd]
		if motivo != "": txt += " (" + motivo + ")"
		print(txt)

func get_total_ammo() -> int:
	var ammo = 0
	var wm = car.get_node_or_null("%WeaponManager")
	if wm:
		for w in wm.weapon_pool: 
			ammo += w.ammo
	return ammo

func processar_combate(delta: float):
	# ====================================================================
	# INJEÇÃO PREGUIÇOSA: O script espera pacientemente a arma existir. 
	# Quando ela existir, ele coloca a munição.
	# ====================================================================
	if not _arma_inicializada:
		var wm = car.get_node_or_null("%WeaponManager")
		if wm and wm.weapon_pool.size() > 0:
			
			# DIVERSIDADE: Sorteia um valor entre -2 e +2 e soma na munição base.
			# O max() garante que a munição nunca será menor que 1.
			var random_start_ammo = max(1, initial_ammo + randi_range(-2, 2))
			
			for w in wm.weapon_pool:
				w.ammo = random_start_ammo
				
			# Se estiver desarmado, sorteia uma arma aleatória do arsenal para sacar!
			if not wm.get_active_special() and wm.has_method("_switch_weapon"):
				var random_index = randi() % wm.weapon_pool.size()
				wm._switch_weapon(random_index)
				
			_arma_inicializada = true
			_log_ammo("Setup Concluído. Ammo Sorteada: " + str(random_start_ammo))

	disparou_no_vip = false 
	
	if _delay_tiro_especial > 0.0:
		_delay_tiro_especial -= delta
		
	_gerenciar_regeneracao_municao(delta)
	
	var keys = targets_exhausted.keys()
	for k in keys:
		targets_exhausted[k] -= delta
		if targets_exhausted[k] <= 0:
			targets_exhausted.erase(k)

	if is_instance_valid(target):
		var t_stats = target.get_node_or_null("%StatsComponent")
		if t_stats:
			var hp = t_stats.current_health
			if _last_target_hp > 0 and hp < _last_target_hp:
				damage_dealt_to_current += (_last_target_hp - hp)
			_last_target_hp = hp
			
			if damage_dealt_to_current >= max_damage_per_target:
				targets_exhausted[target] = 10.0 
				if get_parent().has_method("notificar_alvo_esgotado"):
					get_parent().notificar_alvo_esgotado(target)

func set_target(novo_alvo: Node3D):
	if target != novo_alvo:
		target = novo_alvo
		damage_dealt_to_current = 0.0
		if is_instance_valid(target):
			var t_stats = target.get_node_or_null("%StatsComponent")
			if t_stats: _last_target_hp = t_stats.current_health
			else: _last_target_hp = -1.0
		else:
			_last_target_hp = -1.0
	
func tentar_atirar(alvo_direto: Node3D, is_extreme_attack: bool = false):
	var alvo_real = target if is_instance_valid(target) else alvo_direto
	if not is_instance_valid(alvo_real): return
	
	input.is_action_pressed = true 
	
	var wm = car.get_node_or_null("%WeaponManager")
	if not wm or not is_instance_valid(wm.shooter): return
	
	var active_w = wm.get_active_special()
	if not active_w or _delay_tiro_especial > 0.0: return
	
	if wm.shooter.special_cooldowns.get(active_w.nome, 0.0) <= 0:
		if wm.shooter.try_fire_special(active_w, false):
			
			if is_extreme_attack: _delay_tiro_especial = randf_range(0.8, 1.5)
			else: _delay_tiro_especial = randf_range(1.5, 3.0)
				
			if alvo_real.is_in_group("destructible_vips"):
				disparou_no_vip = true 
				
			active_w.ammo -= 1
			_log_ammo("Disparo Frontal")
			
			if active_w.ammo <= 0: 
				wm._remove_current_weapon()
				_log_ammo("Ficou Sem Munição")
			
			ammo_added_to_current = 0
			disparos_especiais_seguidos += 1
			
			if disparos_especiais_seguidos >= 2:
				disparos_especiais_seguidos = 0
				if wm.weapon_pool.size() > 1:
					wm._switch_weapon(1)
					ammo_added_to_current = 0
					_log_ammo("Troca de Arma Automática (Pós-Disparo)")

func tentar_atirar_pra_tras(alvo_perseguidor: Node3D):
	var wm = car.get_node_or_null("%WeaponManager")
	if not wm or not is_instance_valid(wm.shooter): return
	
	var active_w = wm.get_active_special()
	if not active_w or _delay_tiro_especial > 0.0: return
	
	if wm.shooter.special_cooldowns.get(active_w.nome, 0.0) <= 0:
		if wm.shooter.try_fire_special(active_w, true):
			_delay_tiro_especial = randf_range(1.5, 3.0)
			active_w.ammo -= 1
			_log_ammo("Disparo Traseiro (Fuga)")
			
			if active_w.ammo <= 0: 
				wm._remove_current_weapon()
				_log_ammo("Ficou Sem Munição")
				
			ammo_added_to_current = 0

func reagir_a_ameaca(qtd_ameacas: int):
	var ability = car.get_node_or_null("%AbilityComponent")
	if not ability or ability.current_cooldown > 0: return
	
	if qtd_ameacas % 3 == 0:
		if ability.current_energy >= ability.COST_SHIELD:
			ability._execute_shield()
			return 
			
	if qtd_ameacas % 5 == 0:
		if ability.current_energy >= ability.COST_JUMP:
			ability._execute_jump()
			return

func _gerenciar_regeneracao_municao(delta: float):
	var wm = car.get_node_or_null("%WeaponManager")
	if not wm or wm.weapon_pool.is_empty(): return
	
	var active_w = wm.get_active_special()
	if not active_w: return
	
	ammo_regen_timer -= delta
	if ammo_regen_timer <= 0:
		ammo_regen_timer = ammo_regen_rate 
		
		active_w.ammo += 1
		ammo_added_to_current += 1
		_log_ammo("Recarga Automática")
		
		if ammo_added_to_current >= initial_ammo:
			if wm.weapon_pool.size() > 1:
				wm._switch_weapon(1)
				ammo_added_to_current = 0
				_log_ammo("Troca Automática (Ciclo de Carga)")
