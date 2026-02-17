# MissionManager.gd
extends Node

signal mission_completed(mission: MissionItem)
signal batch_unlocked() # Quando as outras 7 aparecem

var current_map_data: MapMissionData
var active_missions: Array[MissionItem] = []
var completed_count: int = 0

func setup_map(data: MapMissionData):
	current_map_data = data
	completed_count = 0
	_check_visibility()

func _check_visibility():
	var first_batch_completed = 0
	# Conta quantos dos primeiros 6 foram feitos
	for i in range(min(6, current_map_data.missions.size())):
		if current_map_data.missions[i].is_completed:
			first_batch_completed += 1
	
	# Regra: Se completou 5 das 6 primeiras, libera o resto
	if first_batch_completed >= 5:
		batch_unlocked.emit()
		print("Batch 2 desbloqueado!")

func notify_progress(type: MissionItem.Type, value: float, id: String = ""):
	for mission in current_map_data.missions:
		if mission.is_completed: continue
		if mission.type != type: continue
		
		var success = false
		match type:
			MissionItem.Type.SCORE:
				if ScoreManager.total_score >= mission.target_value: success = true
			MissionItem.Type.SPEED:
				if id == mission.id and value >= mission.target_value: success = true
			MissionItem.Type.DESTROY, MissionItem.Type.COLLECT:
				# Aqui você passaria um valor acumulado ou um sinal de incremento
				pass 

		if success:
			_complete_mission(mission)

func _complete_mission(mission: MissionItem):
	mission.is_completed = true
	completed_count += 1
	mission_completed.emit(mission)
	_check_visibility()
	
	if completed_count >= current_map_data.next_map_unlock_count:
		print("Próxima fase liberada!")
