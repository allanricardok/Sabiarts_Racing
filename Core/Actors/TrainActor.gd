extends Node3D
class_name TrainActor

enum EndBehavior { LOOP, TELEPORT_TO_START }

@export_group("Route")
@export var waypoint_root: Node3D
@export var end_behavior: EndBehavior = EndBehavior.LOOP
@export var speed: float = 18.0
@export var arrival_distance: float = 1.0
@export var turn_smoothing: float = 8.0

@export_group("Wagons")
@export var wagon_scene: PackedScene
@export_range(0, 64, 1) var wagon_count: int = 3
@export var wagon_spacing: float = 8.0

var _waypoints: Array[Node3D] = []
var _current_waypoint_index: int = 1
var _wagons: Array[Node3D] = []
var _history: Array[Dictionary] = []
var _distance_traveled: float = 0.0

@onready var wagon_container: Node3D = get_node_or_null("WagonContainer") as Node3D

func _ready():
	_ensure_wagon_container()
	_refresh_waypoints()
	_spawn_wagons()
	_place_at_route_start()

func _physics_process(delta):
	if _waypoints.size() < 2:
		return

	var previous_position = global_position
	var target_position = _waypoints[_current_waypoint_index].global_position
	var movement = target_position - global_position

	if movement.length() <= arrival_distance:
		_advance_waypoint()
		return

	var direction = movement.normalized()
	global_position = global_position.move_toward(target_position, speed * delta)
	_rotate_toward(direction, delta)

	var distance_this_frame = previous_position.distance_to(global_position)
	if distance_this_frame > 0.001:
		_distance_traveled += distance_this_frame
		_record_history()
		_update_wagons()

func _refresh_waypoints():
	_waypoints.clear()

	if not is_instance_valid(waypoint_root):
		push_warning("[TrainActor] Missing waypoint_root.")
		return

	for child in waypoint_root.get_children():
		if child is Node3D:
			_waypoints.append(child)

	if _waypoints.size() < 2:
		push_warning("[TrainActor] waypoint_root needs at least two Node3D children.")

func _ensure_wagon_container():
	if is_instance_valid(wagon_container):
		return

	wagon_container = Node3D.new()
	wagon_container.name = "WagonContainer"
	add_child(wagon_container)

func _spawn_wagons():
	for child in wagon_container.get_children():
		child.queue_free()

	_wagons.clear()
	if wagon_scene == null:
		return

	for i in range(wagon_count):
		var wagon = wagon_scene.instantiate() as Node3D
		if wagon == null:
			push_warning("[TrainActor] wagon_scene must instantiate a Node3D.")
			return

		wagon_container.add_child(wagon)
		_wagons.append(wagon)

func _place_at_route_start():
	if _waypoints.is_empty():
		return

	global_position = _waypoints[0].global_position
	_current_waypoint_index = 1 if _waypoints.size() > 1 else 0

	if _waypoints.size() > 1:
		var direction = (_waypoints[1].global_position - global_position).normalized()
		if direction.length() > 0.001:
			global_basis = Basis.looking_at(direction, Vector3.UP)

	_distance_traveled = 0.0
	_history.clear()
	_record_history()
	_update_wagons(true)

func _advance_waypoint():
	if _current_waypoint_index < _waypoints.size() - 1:
		_current_waypoint_index += 1
		return

	match end_behavior:
		EndBehavior.LOOP:
			_current_waypoint_index = 0
		EndBehavior.TELEPORT_TO_START:
			_place_at_route_start()

func _rotate_toward(direction: Vector3, delta: float):
	if direction.length() <= 0.001:
		return

	var target_basis = Basis.looking_at(direction, Vector3.UP)
	var current_quat = global_basis.get_rotation_quaternion()
	var target_quat = target_basis.get_rotation_quaternion()
	var blend = clamp(turn_smoothing * delta, 0.0, 1.0)
	global_basis = Basis(current_quat.slerp(target_quat, blend))

func _record_history():
	_history.push_front({
		"distance": _distance_traveled,
		"transform": global_transform,
	})

	var max_distance = (wagon_count + 2) * wagon_spacing
	while _history.size() > 2 and _distance_traveled - _history[_history.size() - 1]["distance"] > max_distance:
		_history.pop_back()

func _update_wagons(force_snap: bool = false):
	if _wagons.is_empty():
		return

	for i in range(_wagons.size()):
		var target_distance = _distance_traveled - wagon_spacing * float(i + 1)
		var target_transform = _sample_history(target_distance)
		if force_snap:
			_wagons[i].global_transform = target_transform
		elif _wagons[i].has_method("set_follow_transform"):
			_wagons[i].set_follow_transform(target_transform)
		else:
			_wagons[i].global_transform = target_transform

func _sample_history(target_distance: float) -> Transform3D:
	if _history.is_empty():
		return global_transform

	if target_distance >= _history[0]["distance"]:
		return _history[0]["transform"]

	for i in range(_history.size() - 1):
		var newer = _history[i]
		var older = _history[i + 1]
		if target_distance <= newer["distance"] and target_distance >= older["distance"]:
			var span = newer["distance"] - older["distance"]
			var weight = 0.0 if span <= 0.001 else (target_distance - older["distance"]) / span
			return _interpolate_transform(older["transform"], newer["transform"], weight)

	return _history[_history.size() - 1]["transform"]

func _interpolate_transform(from_transform: Transform3D, to_transform: Transform3D, weight: float) -> Transform3D:
	var result = Transform3D()
	result.origin = from_transform.origin.lerp(to_transform.origin, weight)
	result.basis = Basis(
		from_transform.basis.get_rotation_quaternion().slerp(
			to_transform.basis.get_rotation_quaternion(),
			weight
		)
	)
	return result
