extends Node
class_name BotRadar

var inimigos_proximos : Array = []
var vida_proxima : Array = []
var armas_proximas : Array = []
var rampas_proximas : Array = []
var teleporters_proximos : Array = []

var itens_ignorados : Dictionary = {} 
var projeteis_ignorados : Array = [] 

# TIMERS DE OTIMIZAÇÃO (TIME-SLICING)
var _last_scan_time: float = 0.0
var _last_threat_time: float = 0.0

func ignorar_item(item: Node3D, tempo_segundos: float):
	var tempo_final = (Time.get_ticks_msec() / 1000.0) + tempo_segundos
	itens_ignorados[item] = tempo_final
	print("[RADAR] ", get_parent().name, " ignorando '", item.name, "' por ", tempo_segundos, "s!")

func escanear_ambiente(car: Node3D, current_state: int):
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# OTIMIZAÇÃO 1: Time-Slicing. O bot só olha em volta a cada 0.25 segundos.
	# Entre isso, ele usa a memória (os arrays já preenchidos).
	if current_time - _last_scan_time < 0.25:
		return
		
	_last_scan_time = current_time
	
	var car_pos = car.global_position
	var range_sq = 90000.0 # 300 * 300 pré-calculado
	
	# Limpeza do dicionário de ignorados
	var remover_lista = []
	for item in itens_ignorados.keys():
		if not is_instance_valid(item) or current_time >= itens_ignorados[item]:
			remover_lista.append(item)
	for item in remover_lista:
		itens_ignorados.erase(item)
		if is_instance_valid(item):
			print("[RADAR] ", car.name, " voltou a enxergar o item '", item.name, "'!")
			
	# OTIMIZAÇÃO 2: Limpeza manual do array em vez de lambda (muito mais rápido)
	for i in range(projeteis_ignorados.size() - 1, -1, -1):
		if not is_instance_valid(projeteis_ignorados[i]):
			projeteis_ignorados.remove_at(i)
	
	var max_y_diff_items = 18.0 
	var max_y_diff_players = 10.0 
	
	inimigos_proximos.clear()
	var range_enemy_sq = 62500.0 # 250 * 250 pré-calculado
	for p in get_tree().get_nodes_in_group("jogadores"):
		if p != car and is_instance_valid(p) and not p.is_queued_for_deletion():
			# OTIMIZAÇÃO 3: distance_squared_to para evitar cálculo pesado de raiz quadrada
			if p.global_position.distance_squared_to(car_pos) <= range_enemy_sq:
				if abs(p.global_position.y - car_pos.y) <= max_y_diff_players:
					inimigos_proximos.append(p)
			
	vida_proxima.clear()
	for v in get_tree().get_nodes_in_group("health_pickups"):
		if is_instance_valid(v) and not v.is_queued_for_deletion() and not itens_ignorados.has(v):
			if v.global_position.distance_squared_to(car_pos) <= range_sq:
				if abs(v.global_position.y - car_pos.y) <= max_y_diff_items:
					vida_proxima.append(v)
			
	armas_proximas.clear()
	for a in get_tree().get_nodes_in_group("weapon_pickups"):
		if is_instance_valid(a) and not a.is_queued_for_deletion() and not itens_ignorados.has(a):
			if a.global_position.distance_squared_to(car_pos) <= range_sq:
				if abs(a.global_position.y - car_pos.y) <= max_y_diff_items:
					armas_proximas.append(a)
			
	rampas_proximas.clear()
	for r in get_tree().get_nodes_in_group("rampas"):
		if is_instance_valid(r) and not r.is_queued_for_deletion() and not itens_ignorados.has(r):
			if r.global_position.distance_squared_to(car_pos) <= range_sq:
				if abs(r.global_position.y - car_pos.y) <= max_y_diff_items:
					rampas_proximas.append(r)
	
	teleporters_proximos.clear()
	for t in get_tree().get_nodes_in_group("LockableTeleporters"):
		if is_instance_valid(t) and not t.is_queued_for_deletion() and not itens_ignorados.has(t):
			if t.global_position.distance_squared_to(car_pos) <= range_sq:
				if abs(t.global_position.y - car_pos.y) <= max_y_diff_items:
					teleporters_proximos.append(t)

func checar_ameacas_imediatas(car: Node3D) -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# OTIMIZAÇÃO 4: Checar mísseis a cada 0.1s (10x por segundo).
	# É rápido o bastante para esquivar, mas salva 80% do processamento!
	if current_time - _last_threat_time < 0.1:
		return false
		
	_last_threat_time = current_time
	
	var car_pos = car.global_position
	var has_threat = false
	var todos_projetis = car.get_tree().get_nodes_in_group("projetil")
	
	var threat_range_sq = 3600.0 # 60 * 60 pré-calculado
	
	for proj in todos_projetis:
		if is_instance_valid(proj) and not proj.is_queued_for_deletion() and not proj in projeteis_ignorados:
			if "shooter" in proj and proj.shooter == car:
				projeteis_ignorados.append(proj)
				continue
				
			if proj.global_position.distance_squared_to(car_pos) < threat_range_sq:
				var dir_to_car = (car_pos - proj.global_position).normalized()
				var proj_dir = Vector3.ZERO
				
				# length_squared em vez de length aqui também!
				if "linear_velocity" in proj and proj.linear_velocity.length_squared() > 0.01:
					proj_dir = proj.linear_velocity.normalized()
				elif "velocity" in proj and proj.velocity.length_squared() > 0.01:
					proj_dir = proj.velocity.normalized()
				else:
					proj_dir = -proj.global_transform.basis.z.normalized() 
					
				var dot = proj_dir.dot(dir_to_car)
				
				if dot > 0.7: 
					projeteis_ignorados.append(proj)
					print("[RADAR] AMEAÇA DETECTADA! Míssil em rota de colisão!")
					has_threat = true
	return has_threat
