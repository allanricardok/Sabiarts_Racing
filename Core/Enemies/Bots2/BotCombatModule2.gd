extends Node
class_name BotCombatModuleV2

var car: BaseVehicle
var input: Node
var stats: Node
var radar: BotRadarV2

var ammo_regen_timer: float = 5.0
var ammo_added_to_current: int = 0
var disparos_especiais_seguidos: int = 0

var disparou_no_vip: bool = false
var _delay_tiro_especial: float = 0.0 # Cooldown global de tiro do bot

func setup(_car: BaseVehicle, _input: Node, _stats: Node, _radar: BotRadarV2):
	car = _car
	input = _input
	stats = _stats
	radar = _radar

	# --- NOVO: 60% de chance de começar com 8 de munição ---
	if randf() <= 0.6:
		var wm = car.get_node_or_null("%WeaponManager")
		if wm and wm.weapon_pool.size() > 0:
			var random_w = wm.weapon_pool.pick_random()
			random_w.ammo = 8

func get_total_ammo() -> int:
	var ammo = 0
	var wm = car.get_node_or_null("%WeaponManager")
	if wm:
		for w in wm.weapon_pool: ammo += w.ammo
	return ammo

# Nova função enxuta chamada a cada frame pelo BotBrainV2
func processar_combate(delta: float):
	disparou_no_vip = false 
	
	if _delay_tiro_especial > 0.0:
		_delay_tiro_especial -= delta
		
	_gerenciar_regeneracao_municao(delta)

# ==============================================================================
# AÇÕES OFENSIVAS (Injetadas pela Camada 3 do Cérebro)
# ==============================================================================
func tentar_atirar(alvo: Node3D, is_extreme_attack: bool = false):
	# A metralhadora básica (se houver) atira sempre que o alvo está na mira
	input.is_action_pressed = true 
	
	var wm = car.get_node_or_null("%WeaponManager")
	if not wm or not is_instance_valid(wm.shooter): return
	
	var active_w = wm.get_active_special()
	if not active_w or _delay_tiro_especial > 0.0: return
	
	# Verifica o cooldown nativo da arma
	if wm.shooter.special_cooldowns.get(active_w.nome, 0.0) <= 0:
		if wm.shooter.try_fire_special(active_w, false):
			
			# Modula a agressividade dos tiros
			if is_extreme_attack:
				_delay_tiro_especial = randf_range(0.8, 1.5)
			else:
				_delay_tiro_especial = randf_range(1.5, 3.0)
				
			if is_instance_valid(alvo) and alvo.is_in_group("destructible_vips"):
				disparou_no_vip = true 
				
			active_w.ammo -= 1
			if active_w.ammo <= 0: wm._remove_current_weapon()
			
			ammo_added_to_current = 0
			disparos_especiais_seguidos += 1
			
			# Troca de arma automática para manter o dinamismo
			if disparos_especiais_seguidos >= 2:
				disparos_especiais_seguidos = 0
				if wm.weapon_pool.size() > 1:
					wm._switch_weapon(1)
					ammo_added_to_current = 0

func tentar_atirar_pra_tras(alvo_perseguidor: Node3D):
	var wm = car.get_node_or_null("%WeaponManager")
	if not wm or not is_instance_valid(wm.shooter): return
	
	var active_w = wm.get_active_special()
	if not active_w or _delay_tiro_especial > 0.0: return
	
	if wm.shooter.special_cooldowns.get(active_w.nome, 0.0) <= 0:
		# O 'true' passa o comando de atirar para trás (Backshot) no WeaponShooter
		if wm.shooter.try_fire_special(active_w, true):
			_delay_tiro_especial = randf_range(1.5, 3.0)
			
			active_w.ammo -= 1
			if active_w.ammo <= 0: wm._remove_current_weapon()
			ammo_added_to_current = 0

# ==============================================================================
# AÇÕES DEFENSIVAS E MANUTENÇÃO
# ==============================================================================
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
		ammo_regen_timer = 3.0 
		
		if ammo_added_to_current < 8:
			active_w.ammo += 1
			ammo_added_to_current += 1
			
			if ammo_added_to_current >= 8:
				if wm.weapon_pool.size() > 1:
					wm._switch_weapon(1)
					ammo_added_to_current = 0
