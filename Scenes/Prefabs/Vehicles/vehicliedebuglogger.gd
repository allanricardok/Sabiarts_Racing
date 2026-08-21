extends Node
class_name VehicleDebugLogger

# Anexa esse node como filho do carro (ou de qualquer node com "owner" apontando
# pro VehicleBody3D). Ele detecta as rodas automaticamente, igual ao MovementComponent.

@export var debug_enabled: bool = true
@export var min_distance_between_logs: float = 2.0 # metros percorridos entre cada print
@export var label: String = "DEBUG" # Troque pra "PLANO" ou "RAMPA" em cada teste, fica mais fácil comparar

@onready var car: VehicleBody3D = owner as VehicleBody3D

var _wheels: Array[VehicleWheel3D] = []
var _last_log_pos: Vector3 = Vector3.INF

func _ready():
	if not is_instance_valid(car):
		push_warning("[VehicleDebugLogger] 'owner' não é um VehicleBody3D. Anexe este node como filho direto do carro.")
		return
	var found = car.find_children("*", "VehicleWheel3D", true, false)
	for w in found:
		_wheels.append(w)

func _physics_process(_delta):
	if not debug_enabled or not is_instance_valid(car):
		return

	if _last_log_pos == Vector3.INF:
		_last_log_pos = car.global_position

	if car.global_position.distance_to(_last_log_pos) < min_distance_between_logs:
		return
	_last_log_pos = car.global_position

	_print_debug_block()

func _print_debug_block():
	var pos = car.global_position
	var vel_kmh = car.linear_velocity.length() * 3.6
	var y_turn = car.angular_velocity.y

	var basis = car.global_transform.basis
	var pitch_rad = asin(clamp(-basis.z.dot(Vector3.UP), -1.0, 1.0))
	var roll_rad = asin(clamp(basis.x.dot(Vector3.UP), -1.0, 1.0))
	var pitch_deg = rad_to_deg(pitch_rad)
	var roll_deg = rad_to_deg(roll_rad)

	var steer = car.steering
	var engine = car.engine_force
	var brake = car.brake

	print("\n--- %s (%.1f, %.1f, %.1f) ---" % [label, pos.x, pos.y, pos.z])
	print("VEL: %.1f km/h | Y-TURN: %.2f rad/s" % [vel_kmh, y_turn])
	print("INCLINAÇÃO: Pitch = %.1f° | Roll = %.1f°" % [pitch_deg, roll_deg])
	print("INPUT: Steer = %.2f | Engine = %d | Brake = %d" % [steer, int(engine), int(brake)])
	print("RODAS:")
	for i in range(_wheels.size()):
		var w = _wheels[i]
		if not is_instance_valid(w):
			continue
		var grounded = w.is_in_contact()
		var skid = w.get_skidinfo() if w.has_method("get_skidinfo") else -1.0
		var rpm = w.get_rpm() if w.has_method("get_rpm") else 0.0
		print("  [%s %d] Chão: %s | Skid: %.2f | RPM: %d | FrictionSlip: %.2f | SteerAngle: %.2f°" % [
			w.name, i, str(grounded), skid, rpm, w.wheel_friction_slip, rad_to_deg(w.steering)
		])
	print("------------------------------------------")
