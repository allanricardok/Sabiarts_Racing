extends Node
class_name TrickTrailFX

# ============================================================================
# Anexe este script como um nó filho do carro (irmão do TrickManager e do
# AirMovementComponent), do mesmo jeito que os outros componentes.
#
# Enquanto o carro está executando uma manobra rotacional (is_doing_stunt),
# um anel de pontos fixos ao redor do carro — no plano perpendicular ao eixo
# de rotação daquele truque — desenha faixas luminosas seguindo o giro.
# ============================================================================

@onready var car = owner as VehicleBody3D

@export_group("Faixas de Rastro (Stunt Trail)")
## Diâmetro do círculo onde as faixas ficam ao redor do carro
@export var trail_diameter : float = 2.4
## Cor das faixas luminosas
@export var trail_color : Color = Color(0.1, 0.9, 1.0)
## Quantos pontos de rastro existem ao redor do círculo (mais = trilha mais "cheia")
@export var trail_point_count : int = 4
## Espessura de cada segmento da faixa
@export var trail_width : float = 0.08
## Quanto tempo cada segmento leva pra desaparecer (afeta o "rastro" deixado)
@export var trail_fade_time : float = 0.18
## Deslocamento vertical do centro do anel em relação ao centro do carro
@export var trail_vertical_offset : float = 0.0

const SEGMENT_POOL_SIZE := 80

var _pool: Array[TrickTrailSegment] = []
var _quad_mesh: QuadMesh

var _ring_local_offsets: Array = []
var _prev_world_positions: Array = []
var _was_active: bool = false

var _air_move: Node = null

func _ready() -> void:
	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = Vector2(1.0, 1.0)
	
	for i in range(SEGMENT_POOL_SIZE):
		var seg := TrickTrailSegment.new()
		seg.mesh = _quad_mesh
		seg.visible = false
		seg.set_process(false)
		add_child(seg)
		_pool.append(seg)
	
	if is_instance_valid(car):
		_air_move = car.get_node_or_null("%AirMovementComponent")
		if not _air_move:
			_air_move = car.find_child("AirMovementComponent", true, false)

func _get_free_segment() -> TrickTrailSegment:
	for s in _pool:
		if not s.active:
			return s
	return null # pool esgotado — mesma filosofia dos outros sistemas, só ignora

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(car) or not is_instance_valid(_air_move):
		return
	
	var is_spinning: bool = _air_move.get("is_doing_stunt") == true
	
	if is_spinning and not _was_active:
		_recompute_ring(_get_current_axis())
	
	if is_spinning:
		_update_trail()
	
	_was_active = is_spinning

func _get_current_axis() -> Vector3:
	var stunt_processor = _air_move.get("stunt_processor")
	if stunt_processor and "current_stunt_axis" in stunt_processor:
		var axis: Vector3 = stunt_processor.current_stunt_axis
		if axis.length() > 0.01:
			return axis.normalized()
	return Vector3.UP

# Monta os pontos do anel uma vez, no plano perpendicular ao eixo de
# rotação DESTA manobra específica — assim cada truque (roll, flip,
# shield spin) desenha o anel na orientação certa pro que está girando.
func _recompute_ring(axis: Vector3) -> void:
	_ring_local_offsets.clear()
	_prev_world_positions.clear()
	
	var perp := axis.cross(Vector3.UP)
	if perp.length() < 0.01:
		perp = axis.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var other := axis.cross(perp).normalized()
	
	var radius := trail_diameter * 0.5
	for i in range(trail_point_count):
		var angle := (TAU / float(trail_point_count)) * i
		var offset := (perp * cos(angle) + other * sin(angle)) * radius
		offset.y += trail_vertical_offset
		_ring_local_offsets.append(offset)
		_prev_world_positions.append(null)

# A cada frame, calcula onde cada ponto do anel está AGORA (seguindo a
# rotação real do carro) e desenha um segmento entre a posição anterior e
# a atual. Esse desenho persiste independente da atualização — o
# comprimento do segmento é o próprio indicador de velocidade da manobra.
func _update_trail() -> void:
	for i in range(_ring_local_offsets.size()):
		var world_pos: Vector3 = car.global_transform * _ring_local_offsets[i]
		var prev = _prev_world_positions[i]
		
		if prev != null:
			var seg := _get_free_segment()
			if seg:
				seg.launch(prev, world_pos, trail_width, trail_color, trail_fade_time)
		
		_prev_world_positions[i] = world_pos
