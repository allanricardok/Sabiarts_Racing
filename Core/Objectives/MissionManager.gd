# MissionManager.gd
extends Node

signal mission_completed(mission: MissionItem)
signal mission_updated(mission: MissionItem, current: float, target: float)
signal batch_unlocked() 

var current_map_data: MapMissionData
var completed_count: int = 0
var collection_progress : Dictionary = {}
var batch_2_unlocked: bool = false
var completed_mission_ids: Array = []

func setup_map(data: MapMissionData):
	print("[MissionManager] Iniciando setup do mapa: ", data.map_name)
	current_map_data = data
	completed_count = 0
	
	if is_instance_valid(ScoreManager):
		ScoreManager.reset_score()
	
	collection_progress.clear()
	
	var saved_data = SaveManager.load_game()
	completed_mission_ids = saved_data.get("completed_ids", [])
	
	batch_2_unlocked = false
	
	for m in current_map_data.missions:
		m.is_completed = false 
		if m.id != "" and m.id in completed_mission_ids:
			m.is_completed = true
			completed_count += 1
		
	_check_visibility()
	print("[MissionManager] Setup finalizado. Missões concluídas: ", completed_count)

func _check_visibility():
	if not current_map_data: return
	
	var first_batch_completed = 0
	for i in range(min(6, current_map_data.missions.size())):
		if current_map_data.missions[i].is_completed:
			first_batch_completed += 1
	
	if first_batch_completed >= 4 and not batch_2_unlocked:
		batch_2_unlocked = true
		batch_unlocked.emit()
		print("[MissionManager] ⭐ BATCH 2 REVELADO!")

func notify_progress(type: MissionItem.Type, value: float, id: String = ""):
	if current_map_data == null: return
	
	for i in range(current_map_data.missions.size()):
		var mission = current_map_data.missions[i]
		
		if mission.is_completed: continue
		if mission.type != type: continue
		
		var success = false
		match type:
			MissionItem.Type.SCORE:
				if value >= mission.target_value: 
					success = true
			
			MissionItem.Type.SPEED:
				if id == mission.id and value >= mission.target_value:
					success = true
			
			# MELHORIA: Para GAPs, agora exigimos que o 'value' seja 1.0 (Validação do Carro)
			MissionItem.Type.GAP:
				if id == mission.id and value >= 1.0: 
					success = true
					
			MissionItem.Type.EXPLORE, MissionItem.Type.MISSION:
				if id == mission.id: 
					success = true
			
			MissionItem.Type.COLLECT, MissionItem.Type.DESTROY:
				if id == mission.id:
					var current_val = collection_progress.get(id, 0.0) + value
					collection_progress[id] = current_val
					
					mission_updated.emit(mission, current_val, mission.target_value)
					
					if current_val >= mission.target_value:
						success = true
		
		if success:
			_complete_mission(mission)

func _complete_mission(mission: MissionItem):
	if mission.is_completed: return
	
	mission.is_completed = true
	completed_count += 1
	
	if not mission.id in completed_mission_ids:
		completed_mission_ids.append(mission.id)
	
	SaveManager.save_game(completed_mission_ids, {}) 
	
	# --- NOVO: AVISA A CHECKLIST DO TUTORIAL ---
	if mission.type == MissionItem.Type.COLLECT:
		get_tree().call_group("TutorialUI", "complete_task", "letters")
	
	mission_completed.emit(mission)
	_check_visibility()
	print("[MissionManager] Missão validada e salva: ", mission.description)

func is_mission_completed(mission_id: String) -> bool:
	return mission_id in completed_mission_ids
