extends Node

# ============================================================================
# ExplosionManager (AUTOLOAD)
# Configure em Project Settings > Autoload:
#   Path: res://ExplosionManager.gd   Nome: ExplosionManager
#
# Gerencia pools de flash de luz, bola de fogo e fumaça — nada é criado ou
# destruído durante o jogo, só reciclado, seguindo o mesmo princípio do
# DebrisManager.
# ============================================================================

const FLASH_POOL_SIZE := 8
const LIGHT_POOL_SIZE := 6
const SMOKE_POOL_SIZE := 40

var _flash_mesh: QuadMesh
var _smoke_mesh: QuadMesh

var _flashes: Array[ExplosionFlash] = []
var _lights: Array[ExplosionLight] = []
var _smoke: Array[ExplosionSmokePuff] = []

func _ready() -> void:
	_flash_mesh = QuadMesh.new()
	_flash_mesh.size = Vector2(1.0, 1.0)
	_smoke_mesh = QuadMesh.new()
	_smoke_mesh.size = Vector2(1.0, 1.0)
	
	for i in range(FLASH_POOL_SIZE):
		var f := ExplosionFlash.new()
		f.mesh = _flash_mesh
		f.visible = false
		f.set_process(false)
		add_child(f)
		_flashes.append(f)
	
	for i in range(LIGHT_POOL_SIZE):
		var l := ExplosionLight.new()
		l.visible = false
		l.set_process(false)
		l.shadow_enabled = false # visual PS1: sem sombra dinâmica, mais barato
		add_child(l)
		_lights.append(l)
	
	for i in range(SMOKE_POOL_SIZE):
		var s := ExplosionSmokePuff.new()
		s.mesh = _smoke_mesh
		s.visible = false
		s.set_process(false)
		add_child(s)
		_smoke.append(s)

func _get_free_flash() -> ExplosionFlash:
	for f in _flashes:
		if not f.active:
			return f
	return null

func _get_free_light() -> ExplosionLight:
	for l in _lights:
		if not l.active:
			return l
	return null

func _get_free_smoke() -> ExplosionSmokePuff:
	for s in _smoke:
		if not s.active:
			return s
	return null

## Dispara uma explosão visual completa (flash de luz + bola de fogo + fumaça).
## origin: posição no mundo
## color: cor principal da explosão (fogo/flash)
## size: tamanho aproximado da bola de fogo, em unidades do mundo
## particle_count: quantos "puffs" de fumaça soltar ao redor
## light_energy: intensidade máxima do flash de luz (0 desliga a luz)
func explode(
	origin: Vector3,
	color: Color = Color(1.0, 0.6, 0.1),
	size: float = 3.0,
	particle_count: int = 10,
	light_energy: float = 8.0
) -> void:
	# 1. Flash da bola de fogo (rápido, ~0.25s)
	var flash := _get_free_flash()
	if flash:
		flash.launch(origin, color, size, 0.25)
	
	# 2. Luz de flash pra iluminar a cena por um instante
	if light_energy > 0.0:
		var light := _get_free_light()
		if light:
			light.launch(origin, color, light_energy, 0.3, size * 3.0)
	
	# 3. Fumaça subindo e se espalhando ao redor do epicentro
	var smoke_color := Color(0.15, 0.15, 0.15, 1.0)
	for i in range(particle_count):
		var puff := _get_free_smoke()
		if puff == null:
			break # pool esgotado — mesma filosofia do DebrisManager, só ignora
		
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.4, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var vel := dir * randf_range(1.0, 3.0) * (size * 0.3)
		var puff_size := randf_range(size * 0.15, size * 0.35)
		var spawn_pos := origin + Vector3(
			randf_range(-size * 0.2, size * 0.2),
			randf_range(0.0, size * 0.2),
			randf_range(-size * 0.2, size * 0.2)
		)
		
		puff.launch(spawn_pos, vel, smoke_color, puff_size, randf_range(0.8, 1.4))
