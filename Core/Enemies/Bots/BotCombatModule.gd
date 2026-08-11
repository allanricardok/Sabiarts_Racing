extends Node
class_name BotCombatModule

var car: BaseVehicle
var input: Node
var stats: Node
var radar: BotRadar

var ammo_regen_timer: float = 5.0
var ammo_added_to_current: int = 0
var disparos_especiais_seguidos: int = 0

var disparou_no_vip: bool = false

func setup(_car: BaseVehicle, _input: Node, _stats: Node, _radar: BotRadar):
	car = _car
	input = _input
	stats = _stats
	radar = _radar

func get_total_ammo() -> int:
	var ammo = 0
	var wm = car.get_node_or_null("%WeaponManager")
	if wm:
		for w in wm.weapon_pool: ammo += w.ammo
	return ammo

func processar_combate(delta: float, current_state: int, alvo_atual: Node3D):
	disparou_no_vip = false 
	_gerenciar_regeneracao_municao(delta)
	_gerenciar_armas_do_bot(current_state, alvo_atual)
	_gerenciar_habilidades_do_bot(current_state, alvo_atual)

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
		ammo_regen_timer = 5.0 
		
		if ammo_added_to_current < 6:
			active_w.ammo += 1
			ammo_added_to_current += 1
			
			if ammo_added_to_current >= 6:
				if wm.weapon_pool.size() > 1:
					wm._switch_weapon(1)
					ammo_added_to_current = 0 

func _gerenciar_armas_do_bot(current_state: int, alvo_atual: Node3D):
	input.is_action_pressed = false 
	var alvo_tiro = null
	
	if current_state == 3 and is_instance_valid(alvo_atual):
		alvo_tiro = alvo_atual
	elif (current_state == 4 or current_state == 6) and radar.inimigos_proximos.size() > 0:
		alvo_tiro = radar.inimigos_proximos[0]
	
	if is_instance_valid(alvo_tiro):
		var wm = car.get_node_or_null("%WeaponManager")
		if not wm or not is_instance_valid(wm.shooter): return
		
		var forward = car.global_transform.basis.z
		var dir = (alvo_tiro.global_position - car.global_position).normalized()
		var dot_p = forward.dot(dir)
		
		var is_vip = alvo_tiro.is_in_group("destructible_vips")
		var dot_limite_ataque = 0.6 if is_vip else 0.85
		
		if dot_p > 0.4: 
			input.is_action_pressed = true 
			
			if current_state == 4 or current_state == 6:
				var active_w = wm.get_active_special()
				if active_w and wm.shooter.special_cooldowns.get(active_w.nome, 0.0) <= 0:
					if wm.shooter.try_fire_special(active_w, false):
						active_w.ammo -= 1
						if active_w.ammo <= 0: wm._remove_current_weapon()
					ammo_added_to_current = 0 
		
		if current_state == 3 and dot_p > dot_limite_ataque:
			var active_w = wm.get_active_special()
			if active_w and wm.shooter.special_cooldowns.get(active_w.nome, 0.0) <= 0:
				if wm.shooter.try_fire_special(active_w, false):
					
					if is_vip: 
						disparou_no_vip = true 
						
					active_w.ammo -= 1
					if active_w.ammo <= 0: wm._remove_current_weapon()
					
				ammo_added_to_current = 0
				
				disparos_especiais_seguidos += 1
				if disparos_especiais_seguidos >= 2:
					disparos_especiais_seguidos = 0
					if wm.weapon_pool.size() > 1:
						wm._switch_weapon(1)
						ammo_added_to_current = 0

func _gerenciar_habilidades_do_bot(current_state: int, alvo_atual: Node3D):
	var ability = car.get_node_or_null("%AbilityComponent")
	if not ability or ability.current_cooldown > 0: return
	
	var health_pct = (stats.current_health / stats.max_health) * 100.0
	
	if current_state == 4 or health_pct < 40.0:
		if ability.current_energy >= ability.COST_SHIELD:
			ability._execute_shield()
			return
			
	# =====================================================================
	# OTIMIZAÇÃO: distance_squared_to para evitar o cálculo da raiz!
	# 40 * 40 = 1600.0
	# =====================================================================
	if current_state == 4 or (current_state == 3 and is_instance_valid(alvo_atual) and car.global_position.distance_squared_to(alvo_atual.global_position) > 1600.0):
		if ability.current_energy >= ability.COST_BOOST:
			ability._execute_boost()
			return
