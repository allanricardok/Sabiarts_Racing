extends Node
class_name BotRadar

var inimigos_proximos : Array = []
var vida_proxima : Array = []
var armas_proximas : Array = []
var rampas_proximas : Array = []
var itens_ignorados : Array = [] 
var projeteis_ignorados : Array = [] 

func escanear_ambiente(car: Node3D, current_state: int):
	var car_pos = car.global_position
	
	# MUDANÇA: Visão expandida para 300 metros para todos os itens!
	var range_sq = 300.0 * 300.0 
	
	itens_ignorados = itens_ignorados.filter(func(i): return is_instance_valid(i))
	projeteis_ignorados = projeteis_ignorados.filter(func(p): return is_instance_valid(p))
	
	# MUDANÇA: Altura ajustada para 18 metros
	var max_y_diff_items = 18.0 
	var max_y_diff_players = 10.0 
	
	inimigos_proximos.clear()
	var range_enemy_sq = 250.0 * 250.0 
	for p in get_tree().get_nodes_in_group("jogadores"):
		if p != car and is_instance_valid(p) and p.global_position.distance_squared_to(car_pos) <= range_enemy_sq:
			if abs(p.global_position.y - car_pos.y) <= max_y_diff_players:
				inimigos_proximos.append(p)
			
	vida_proxima.clear()
	var search_range_health = range_sq 
	for v in get_tree().get_nodes_in_group("health_pickups"):
		if is_instance_valid(v) and v.global_position.distance_squared_to(car_pos) <= search_range_health and not v in itens_ignorados:
			if abs(v.global_position.y - car_pos.y) <= max_y_diff_items:
				vida_proxima.append(v)
			
	armas_proximas.clear()
	for a in get_tree().get_nodes_in_group("weapon_pickups"):
		if is_instance_valid(a) and a.global_position.distance_squared_to(car_pos) <= range_sq and not a in itens_ignorados:
			if abs(a.global_position.y - car_pos.y) <= max_y_diff_items:
				armas_proximas.append(a)
			
	rampas_proximas.clear()
	for r in get_tree().get_nodes_in_group("rampas"):
		if is_instance_valid(r) and r.global_position.distance_squared_to(car_pos) <= range_sq:
			if abs(r.global_position.y - car_pos.y) <= max_y_diff_items:
				rampas_proximas.append(r)

func checar_ameacas_imediatas(car: Node3D) -> bool:
	var car_pos = car.global_position
	var has_threat = false
	var todos_projetis = car.get_tree().get_nodes_in_group("projetil")
	
	for proj in todos_projetis:
		if is_instance_valid(proj) and not proj in projeteis_ignorados:
			if "shooter" in proj and proj.shooter == car:
				projeteis_ignorados.append(proj)
				continue
				
			var dist = proj.global_position.distance_to(car_pos)
			if dist < 60.0:
				var dir_to_car = (car_pos - proj.global_position).normalized()
				var proj_dir = Vector3.ZERO
				
				if "linear_velocity" in proj and proj.linear_velocity.length() > 0.1:
					proj_dir = proj.linear_velocity.normalized()
				elif "velocity" in proj and proj.velocity.length() > 0.1:
					proj_dir = proj.velocity.normalized()
				else:
					proj_dir = -proj.global_transform.basis.z.normalized() 
					
				var dot = proj_dir.dot(dir_to_car)
				
				if dot > 0.7: 
					projeteis_ignorados.append(proj)
					print("[RADAR] AMEAÇA DETECTADA! Míssil em rota de colisão!")
					has_threat = true
	return has_threat
