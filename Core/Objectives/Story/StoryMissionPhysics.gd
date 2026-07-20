# StoryMissionPhysics.gd
extends Node
class_name StoryMissionPhysics

var ctrl: Node # Referência ao StoryModeController

func setup(controller: Node):
	ctrl = controller

func restore_all_health_and_energy():
	var vehicles = get_tree().get_nodes_in_group("jogadores") + get_tree().get_nodes_in_group("inimigos")
	for v in vehicles:
		if is_instance_valid(v) and v.has_method("revive"):
			v.revive()

func check_player_death() -> bool:
	var players = get_tree().get_nodes_in_group("jogadores")
	if players.is_empty(): return false
	
	for p1 in players:
		if not is_instance_valid(p1): continue
		
		var is_dead = false
		if "_is_dead" in p1 and p1._is_dead:
			is_dead = true
		elif p1.find_child("StatsComponent", true, false) and p1.find_child("StatsComponent", true, false).get("current_health") <= 0:
			is_dead = true
				
		if is_dead:
			executar_reset_fisico_veiculo(p1)
			if ctrl.is_mission_running:
				ctrl.is_mission_running = false
				ctrl.end_mission(false)
			return true
			
	return false

func executar_reset_fisico_veiculo(vehicle: Node3D):
	var spawn_transform : Transform3D
	
	if ctrl.is_mission_running and is_instance_valid(ctrl.active_portal):
		var z_axis = ctrl.active_portal.global_transform.basis.z
		var spawn_pos = ctrl.active_portal.global_position + (z_axis * 15.0)
		spawn_pos.y += 2.0 
		
		z_axis.y = 0.0
		if z_axis.length_squared() < 0.01: z_axis = ctrl.active_portal.global_transform.basis.x.cross(Vector3.UP)
		z_axis = z_axis.normalized()
		var y_axis = Vector3.UP
		var x_axis = y_axis.cross(z_axis).normalized()
		
		spawn_transform = Transform3D(Basis(x_axis, y_axis, z_axis), spawn_pos)
	else:
		var spawn_point = get_tree().get_first_node_in_group("SpawnPoint")
		if not spawn_point:
			var container_spawns = get_tree().current_scene.find_child("SpawnPoints", true, false)
			if container_spawns and container_spawns.get_child_count() > 0:
				spawn_point = container_spawns.get_child(0)
		
		if spawn_point:
			spawn_transform = spawn_point.global_transform
		else:
			spawn_transform = vehicle.global_transform
	
	vehicle.freeze = true
	vehicle.global_transform = spawn_transform
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.freeze = false
	
	if vehicle.has_method("revive"):
		vehicle.revive()
