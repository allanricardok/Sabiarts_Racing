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
	collection_progress.clear()
	batch_2_unlocked = false
	
	for m in current_map_data.missions:
		m.is_completed = false
		
	_check_visibility()
	print("MissionManager: Mapa ", data.map_name, " configurado.")

func _check_visibility():
	if not current_map_data: return
	var first_batch_completed = 0
	for i in range(min(6, current_map_data.missions.size())):
		if current_map_data.missions[i].is_completed:
			first_batch_completed += 1
	
	if first_batch_completed >= 5 and not batch_2_unlocked:
		batch_2_unlocked = true
		batch_unlocked.emit()
		print("⭐ BATCH 2 DESBLOQUEADO! Novas missões disponíveis.")

func notify_progress(type: MissionItem.Type, value: float, id: String = ""):
	if current_map_data == null: return
	
	# TRAVA: Se o tempo acabou no LevelController, não conta mais nada
	# (Assume que tens o LevelController como um nó acessível ou sinal)
	
	for i in range(current_map_data.missions.size()):
		var mission = current_map_data.missions[i]
		
		if mission.is_completed: continue
		if i >= 6 and not batch_2_unlocked: continue
		if mission.type != type: continue
		
		var success = false
		match type:
			MissionItem.Type.SCORE:
				if value >= mission.target_value: success = true
			
			MissionItem.Type.SPEED:
				if id == mission.id and value >= mission.target_value: success = true
			
			MissionItem.Type.GAP, MissionItem.Type.EXPLORE, MissionItem.Type.MISSION:
				if id == mission.id: success = true
			
			MissionItem.Type.COLLECT, MissionItem.Type.DESTROY:
				if id == mission.id:
					var current_val = collection_progress.get(id, 0.0) + value
					collection_progress[id] = current_val
					
					if current_val >= mission.target_value:
						success = true
					else:
						print("Progresso ", id, ": ", int(current_val), "/", int(mission.target_value))
		
		# --- CORREÇÃO AQUI: O 'if success' deve ficar fora do match, mas dentro do for ---
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
	
	_check_visibility()
	
	if completed_count >= current_map_data.next_map_unlock_count:
		print("✅ PRÓXIMA FASE LIBERADA!")
