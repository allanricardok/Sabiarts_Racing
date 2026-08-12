extends Node
class_name BotRadarV2

# --- ARRAYS DE MEMÓRIA (O Cérebro lê daqui) ---
var inimigos_proximos : Array[Node3D] = []
var vida_proxima : Array[Node3D] = []
var armas_proximas : Array[Node3D] = []
var rampas_proximas : Array[Node3D] = []
var teleporters_proximos : Array[Node3D] = []
var itens_missao_proximos : Array[Node3D] = []
var quadrantes_mapa : Array[Node3D] = []

# --- VARIÁVEIS DE OPORTUNISMO ---
var item_oportunidade : Node3D = null
var _cooldown_oportunidade : float = 0.0

# --- IGNORADOS E AMEAÇAS ---
var itens_ignorados : Dictionary = {} 
var projeteis_ignorados : Array[Node3D] = [] 

# --- TIMERS DE OTIMIZAÇÃO (TIME-SLICING) ---
var _last_scan_time: float = 0.0
var _last_threat_time: float = 0.0

func _ready():
	# Busca os quadrantes do mapa apenas uma vez na vida do bot
	var markers = get_tree().get_nodes_in_group("quadrantes_mapa")
	for m in markers:
		if m is Node3D: quadrantes_mapa.append(m)

func ignorar_item(item: Node3D, tempo_segundos: float):
	var tempo_final = (Time.get_ticks_msec() / 1000.0) + tempo_segundos
	itens_ignorados[item] = tempo_final

func iniciar_cooldown_oportunidade(tempo: float = 8.0):
	_cooldown_oportunidade = tempo
	item_oportunidade = null

func escanear_ambiente(car: Node3D, delta: float):
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if _cooldown_oportunidade > 0.0:
		_cooldown_oportunidade -= delta
	
	# OTIMIZAÇÃO: O bot só faz a varredura pesada a cada 0.5 segundos.
	if current_time - _last_scan_time < 0.5:
		return
		
	_last_scan_time = current_time
	var car_pos = car.global_position
	
	# Limpeza do dicionário de ignorados
	var remover_lista = []
	for item in itens_ignorados.keys():
		if not is_instance_valid(item) or current_time >= itens_ignorados[item]:
			remover_lista.append(item)
	for item in remover_lista:
		itens_ignorados.erase(item)
			
	# Limpeza de projéteis fantasmas
	for i in range(projeteis_ignorados.size() - 1, -1, -1):
		if not is_instance_valid(projeteis_ignorados[i]):
			projeteis_ignorados.remove_at(i)
	
	# PRE-CÁLCULOS (Evita raízes quadradas)
	var range_sq = 90000.0         # 300m * 300m (Itens gerais)
	var range_enemy_sq = 62500.0   # 250m * 250m (Inimigos)
	var oportunidade_sq = 400.0    # 20m * 20m   (Grab instintivo)
	var max_y_diff = 18.0 
	
	# Limpa as memórias para o novo scan
	inimigos_proximos.clear()
	vida_proxima.clear()
	armas_proximas.clear()
	rampas_proximas.clear()
	teleporters_proximos.clear()
	itens_missao_proximos.clear()
	item_oportunidade = null
	
	# 1. ESCANEAR INIMIGOS
	for p in get_tree().get_nodes_in_group("jogadores"):
		if p != car and is_instance_valid(p) and not p.is_queued_for_deletion():
			if p.global_position.distance_squared_to(car_pos) <= range_enemy_sq:
				if abs(p.global_position.y - car_pos.y) <= 10.0:
					inimigos_proximos.append(p)
	
	# 2. FUNÇÃO GENÉRICA DE ESCANEAMENTO DE ITENS
	_escanear_grupo_de_itens("health_pickups", car_pos, range_sq, oportunidade_sq, max_y_diff, vida_proxima)
	_escanear_grupo_de_itens("weapon_pickups", car_pos, range_sq, oportunidade_sq, max_y_diff, armas_proximas)
	_escanear_grupo_de_itens("itens_missao", car_pos, range_sq, oportunidade_sq, max_y_diff, itens_missao_proximos)
	_escanear_grupo_de_itens("rampas", car_pos, range_sq, oportunidade_sq, max_y_diff, rampas_proximas)
	_escanear_grupo_de_itens("LockableTeleporters", car_pos, range_sq, oportunidade_sq, max_y_diff, teleporters_proximos)

# Separado em função para manter o código limpo e permitir o sistema de oportunidade checar tudo.
func _escanear_grupo_de_itens(group_name: String, car_pos: Vector3, range_sq: float, opt_sq: float, max_y: float, array_destino: Array):
	for item in get_tree().get_nodes_in_group(group_name):
		if is_instance_valid(item) and not item.is_queued_for_deletion() and not itens_ignorados.has(item):
			# Ignora itens de missão invisíveis (já coletados/desativados)
			if "visible" in item and not item.visible: continue
				
			var dist_sq = item.global_position.distance_squared_to(car_pos)
			if dist_sq <= range_sq:
				if abs(item.global_position.y - car_pos.y) <= max_y:
					array_destino.append(item)
					
					# Se passar raspando a menos de 20m de um item coletável, e não está em cooldown
					if dist_sq <= opt_sq and _cooldown_oportunidade <= 0.0 and item_oportunidade == null:
						# Rampas e Teleporters não contam como "Grab Object" de susto, apenas itens.
						if group_name in ["health_pickups", "weapon_pickups", "itens_missao"]:
							item_oportunidade = item

func checar_ameacas_imediatas(car: Node3D) -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Checa mísseis a cada 0.1s para não perder reflexos rápidos
	if current_time - _last_threat_time < 0.1:
		return false
		
	_last_threat_time = current_time
	var car_pos = car.global_position
	var threat_range_sq = 3600.0 # 60m * 60m
	
	for proj in car.get_tree().get_nodes_in_group("projetil"):
		if is_instance_valid(proj) and not proj.is_queued_for_deletion() and not proj in projeteis_ignorados:
			if "shooter" in proj and proj.shooter == car:
				projeteis_ignorados.append(proj)
				continue
				
			if proj.global_position.distance_squared_to(car_pos) < threat_range_sq:
				var dir_to_car = (car_pos - proj.global_position).normalized()
				var proj_dir = Vector3.ZERO
				
				if "linear_velocity" in proj and proj.linear_velocity.length_squared() > 0.01:
					proj_dir = proj.linear_velocity.normalized()
				elif "velocity" in proj and proj.velocity.length_squared() > 0.01:
					proj_dir = proj.velocity.normalized()
				else:
					proj_dir = -proj.global_transform.basis.z.normalized() 
					
				if proj_dir.dot(dir_to_car) > 0.7: 
					projeteis_ignorados.append(proj)
					return true # Ameaça iminente validada!
					
	return false
