extends Node
class_name WallScannerComponent

var car : VehicleBody3D

@export_group("Configurações de Scanner")
@export_flags_3d_physics var wall_collision_mask : int = 1 
@export var max_wall_distance : float = 3.5 
@export var min_ground_height : float = 1.0

func shoot_ray_ignoring_holos(start_pos: Vector3, end_pos: Vector3) -> Dictionary:
	if not is_instance_valid(car): return {}
	
	var space_state = car.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.exclude = [car.get_rid()]
	query.collision_mask = wall_collision_mask
	query.hit_from_inside = true 
	
	var result = {}
	for i in range(4): 
		result = space_state.intersect_ray(query)
		if not result: break
		
		if result.collider.is_in_group("ignorar_gancho") or "Holo" in result.collider.name:
			var ex = query.exclude
			ex.append(result.collider.get_rid())
			query.exclude = ex
		else:
			break 
			
	return result

func find_best_wall_360() -> Dictionary:
	var best_normal = Vector3.ZERO
	var closest_dist = INF
	var found = false
	
	var steps = 12
	var angle_step = (PI * 2.0) / steps
	
	for i in range(steps):
		var angle = i * angle_step
		var dir = Vector3(cos(angle), 0, sin(angle)).normalized()
		var result = shoot_ray_ignoring_holos(car.global_position, car.global_position + (dir * max_wall_distance))
		
		if result:
			if abs(result.normal.y) < 0.4:
				var dist = car.global_position.distance_to(result.position)
				if dist < closest_dist:
					closest_dist = dist
					best_normal = result.normal
					found = true

	if found: return {"normal": best_normal}
	return {}

func get_ground_distance(offset_from_wall: Vector3) -> float:
	var ray_start = car.global_position + offset_from_wall
	var result = shoot_ray_ignoring_holos(ray_start, ray_start + Vector3.DOWN * 15.0)
	
	if result:
		if result.normal.y > 0.85:
			return ray_start.distance_to(result.position)
	return INF
