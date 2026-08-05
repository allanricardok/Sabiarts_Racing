extends Node

# ============================================================================
# ExplosionManager (AUTOLOAD)
# ============================================================================
# SLIDERS DE RUIDO (NOISE):
# Frequência menor (ex: 0.02) = Manchas gigantes, formato mais arredondado
# Frequência maior (ex: 0.15) = Chiado intenso, formato mais ruidoso e espalhado
@export_group("Texturas Procedurais (Requer reiniciar o jogo)")
@export_range(0.01, 0.2, 0.01) var fire_noise_frequency: float = 0.02
@export_range(0.01, 0.2, 0.01) var smoke_noise_frequency: float = 0.03

const FLASH_POOL_SIZE := 8
const LIGHT_POOL_SIZE := 6
const SMOKE_POOL_SIZE := 40

var _flash_mesh: QuadMesh
var _smoke_mesh: QuadMesh

var _flashes: Array[ExplosionFlash] = []
var _lights: Array[ExplosionLight] = []
var _smoke: Array[ExplosionSmokePuff] = []

# ---> ADICIONE ESTAS DUAS LINHAS AQUI <---
var _tex_fogo: Texture2D
var _tex_fumaca: Texture2D

func _ready() -> void:
	# 1. GERA AS TEXTURAS PROCEDURAIS ESTILO PS1 NA MEMÓRIA
	_tex_fogo = _gerar_textura_fogo()
	_tex_fumaca = _gerar_textura_fumaca()
	
	_flash_mesh = QuadMesh.new()
	_flash_mesh.size = Vector2(1.0, 1.0)
	_smoke_mesh = QuadMesh.new()
	_smoke_mesh.size = Vector2(1.0, 1.0)
	
	for i in range(FLASH_POOL_SIZE):
		var f := ExplosionFlash.new()
		f.mesh = _flash_mesh
		f.visible = false
		f.set_process(false)
		
		# ---> A LINHA QUE TINHA SIDO APAGADA NO ROLLBACK <---
		f.set_texture(_tex_fogo) 
		
		add_child(f)
		_flashes.append(f)
	
	for i in range(LIGHT_POOL_SIZE):
		var l := ExplosionLight.new()
		l.visible = false
		l.set_process(false)
		l.shadow_enabled = false 
		add_child(l)
		_lights.append(l)
	
	for i in range(SMOKE_POOL_SIZE):
		var s := ExplosionSmokePuff.new()
		s.mesh = _smoke_mesh
		s.visible = false
		s.set_process(false)
		
		# ---> A LINHA QUE TINHA SIDO APAGADA NO ROLLBACK <---
		s.set_texture(_tex_fumaca) 
		
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
## Dispara uma explosão visual completa (flash de luz + bola de fogo + fumaça).
func explode(
	origin: Vector3,
	color: Color = Color(1.0, 0.6, 0.1),
	size: float = 3.0,
	particle_count: int = 10,
	light_energy: float = 8.0,
	smoke_color: Color = Color(0.15, 0.15, 0.15, 1.0), 
	smoke_size: float = 3.0,
	fire_duration: float = .33 # NOVO: Tempo que o fogo fica na tela
) -> void:
	
	# 1. Flash da bola de fogo 
	if size > 0.0:
		var flash := _get_free_flash()
		if flash:
			# Passamos o fire_duration pro flash
			flash.launch(origin, color, size, fire_duration)
		
		# A luz agora também acompanha o tempo do fogo
		if light_energy > 0.0:
			var light := _get_free_light()
			if light:
				light.launch(origin, color, light_energy, fire_duration * 1.2, size * 3.0)
	
	# 2. Fumaça (Mantida inalterada, dura de 0.8 a 1.4s)
	for i in range(particle_count):
		var puff := _get_free_smoke()
		if puff == null:
			break 
		
		var dir: Vector3 = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.4, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var vel: Vector3 = dir * randf_range(1.0, 3.0) * (smoke_size * 0.3)
		var puff_size: float = randf_range(smoke_size * 0.7, smoke_size * 1.3)
		var spread_radius = max(size, smoke_size) * 0.2
		var spawn_pos: Vector3 = origin + Vector3(
			randf_range(-spread_radius, spread_radius),
			randf_range(0.0, spread_radius),
			randf_range(-spread_radius, spread_radius)
		)
		
		puff.launch(spawn_pos, vel, smoke_color, puff_size, randf_range(0.8, 1.4))

# =======================================================================
# MATEMÁTICA PROCEDURAL DOS SPRITES 
# =======================================================================
func _gerar_textura_fogo() -> Texture2D:
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	# NOVO: Usa a variável do Slider
	noise.frequency = fire_noise_frequency 
	noise.seed = randi() 
	
	for x in range(64):
		for y in range(64):
			var dx = (x - 32.0) / 32.0
			var dy = (y - 32.0) / 32.0
			var dist = sqrt(dx * dx + dy * dy)
			
			if dist >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0)) 
				continue
			
			var n_val = (noise.get_noise_2d(x * 3.0, y * 3.0) + 1.0) / 2.0
			var mask = clamp(1.0 - (dist * dist), 0.0, 1.0)
			var final_alpha = n_val * mask
			
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, final_alpha))
			
	return ImageTexture.create_from_image(img)

func _gerar_textura_fumaca() -> Texture2D:
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX 
	# NOVO: Usa a variável do Slider
	noise.frequency = smoke_noise_frequency 
	noise.seed = randi()
	
	for x in range(64):
		for y in range(64):
			var dx = (x - 32.0) / 32.0
			var dy = (y - 32.0) / 32.0
			var dist = sqrt(dx * dx + dy * dy)
			
			if dist >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			var n_val = (noise.get_noise_2d(x * 2.0, y * 2.0) + 1.0) / 2.0
			var mask = clamp(1.0 - pow(dist, 1.5), 0.0, 1.0)
			var final_alpha = n_val * mask * 0.9 
			
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, final_alpha))
			
	return ImageTexture.create_from_image(img)
