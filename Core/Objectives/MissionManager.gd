# MissionManager.gd
extends Node

signal mission_completed(mission: MissionItem)
signal batch_unlocked() 

var current_map_data: MapMissionData
var completed_count: int = 0
var collection_progress : Dictionary = {}
var batch_2_unlocked: bool = false

func setup_map(data: MapMissionData):
	current_map_data = data
	completed_count = 0
	collection_progress.clear() # Limpa as maletas do mapa anterior
	batch_2_unlocked = false
	
	# Reseta o status das missões no Resource para começar do zero
	for m in current_map_data.missions:
		m.is_completed = false
		
	_check_visibility()
	print("MissionManager: Mapa ", data.map_name, " configurado.")

func _check_visibility():
	if not current_map_data: return
	
	var first_batch_completed = 0
	# Conta quantos dos primeiros 6 objetivos (0 a 5) foram feitos
	for i in range(min(6, current_map_data.missions.size())):
		if current_map_data.missions[i].is_completed:
			first_batch_completed += 1
	
	# Regra: Se completou 5 das 6 primeiras, libera o resto
	if first_batch_completed >= 5 and not batch_2_unlocked:
		batch_2_unlocked = true
		batch_unlocked.emit()
		print("⭐ BATCH 2 DESBLOQUEADO! Novas missões disponíveis.")

func notify_progress(type: MissionItem.Type, value: float, id: String = ""):
	if current_map_data == null: return
	
	for i in range(current_map_data.missions.size()):
		var mission = current_map_data.missions[i]
		
		if mission.is_completed: continue
		
		# Bloqueio de Batch: Missões do índice 6 em diante só contam se Batch 2 estiver liberado
		if i >= 6 and not batch_2_unlocked: continue
		
		if mission.type != type: continue
		
		var success = false
		match type:
			MissionItem.Type.SCORE:
				if value >= mission.target_value: 
					success = true
			MissionItem.Type.SPEED:
				if id == mission.id and value >= mission.target_value: 
					success = true
			MissionItem.Type.GAP:
				if id == mission.id: 
					success = true
			MissionItem.Type.COLLECT:
				if id == mission.id:
					var current_val = collection_progress.get(id, 0.0) + value
					collection_progress[id] = current_val
					
					if current_val >= mission.target_value:
						success = true
					else:
						print("Progresso ", id, ": ", int(current_val), "/", int(mission.target_value))

		if success:
			_complete_mission(mission)

func _complete_mission(mission: MissionItem):
	mission.is_completed = true
	completed_count += 1
	mission_completed.emit(mission)
	
	print("-----------------------------------------")
	print("⭐ MISSÃO CONCLUÍDA: ", mission.description)
	print("📊 PROGRESSO TOTAL: ", completed_count, "/", current_map_data.missions.size())
	print("-----------------------------------------")
	
	# Verifica se esta conclusão libera as próximas 7 missões
	_check_visibility()
	
	# Verifica se liberou a próxima fase (ex: 4 missões concluídas)
	if completed_count >= current_map_data.next_map_unlock_count:
		print("✅ PRÓXIMA FASE LIBERADA!")
