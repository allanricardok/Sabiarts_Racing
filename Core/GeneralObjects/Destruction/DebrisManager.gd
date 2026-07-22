extends Node

# ============================================================================
# DebrisManager (AUTOLOAD)
# Configure em Project Settings > Autoload:
#   Path: res://DebrisManager.gd   Nome: DebrisManager
#
# Mantém um pool fixo de DebrisShard pré-criados. Nenhum fragmento é
# instanciado ou destruído durante o jogo — só reciclado. Isso evita picos
# de alocação de memória, que é o que mais derruba o FPS em PCs fracos
# quando várias explosões acontecem em sequência.
# ============================================================================

const POOL_SIZE := 48
## Quantas formas diferentes existem no banco. Mais variantes = mais
## variedade visual, mas isso é gerado só uma vez no início, então pode
## ser um número generoso sem custar nada durante o jogo.
const SHAPE_VARIANTS := 14
## Multiplicador global de velocidade da explosão (aplicado em cima de
## qualquer force/upward_bias que cada objeto configurar no Inspector).
## Ajuste este valor pra afinar a "sensação" de todas as explosões do jogo
## de uma vez, sem precisar tocar em cada objeto individualmente.
const GLOBAL_SPEED_MULTIPLIER := 1.2

var pool: Array[DebrisShard] = []
var _shard_shapes: Array[Mesh] = []

func _ready() -> void:
	# Gera o banco de formas (triângulos e quadriláteros irregulares) uma
	# única vez. Nenhuma forma é criada durante o gameplay — os fragmentos
	# só sorteiam qual dessas malhas prontas usar.
	for i in range(SHAPE_VARIANTS):
		_shard_shapes.append(_build_random_shard_mesh())
	
	for i in range(POOL_SIZE):
		var shard := DebrisShard.new()
		shard.visible = false
		shard.set_process(false)
		add_child(shard)
		pool.append(shard)

# Cria uma malha plana e irregular (triângulo ou quadrilátero), com vértices
# espalhados em ângulos e distâncias aleatórias ao redor do centro — isso é
# o que gera o visual de "pedaço quebrado" em vez de losangos/quadrados
# perfeitos. A malha é normalizada num raio ~0.5, então o tamanho final na
# tela é controlado depois só pela escala (scale) do nó, sem precisar gerar
# geometria nova por fragmento.
func _build_random_shard_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	
	var is_quad := randf() > 0.35 # ~65% quadriláteros, ~35% triângulos
	var point_count := 4 if is_quad else 3
	
	var base_angle := randf_range(0.0, TAU) # rotação inicial aleatória do formato
	for i in range(point_count):
		# Ângulo com variação irregular (não são pontos perfeitamente
		# espaçados) — é isso que quebra a simetria e evita quads/triângulos
		# "certinhos" demais.
		base_angle += (TAU / float(point_count)) * randf_range(0.6, 1.4)
		var dist := randf_range(0.32, 0.55)
		var p := Vector3(cos(base_angle) * dist, sin(base_angle) * dist, 0.0)
		verts.append(p)
		uvs.append(Vector2(p.x + 0.5, p.y + 0.5))
	
	if is_quad:
		indices.append_array([0, 1, 2, 0, 2, 3])
	else:
		indices.append_array([0, 1, 2])
	
	var normals := PackedVector3Array()
	for i in range(verts.size()):
		normals.append(Vector3(0, 0, 1))
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh

func _get_free_shard() -> DebrisShard:
	for s in pool:
		if not s.active:
			return s
	# Pool esgotado: em vez de criar mais (custaria caro), simplesmente
	# ignora o fragmento extra. Jogos de PS1/PS2 faziam a mesma coisa —
	# sob carga alta, algumas partículas simplesmente não apareciam.
	return null

## Chama a explosão de fragmentos numa posição do mundo.
## origin: posição de onde os fragmentos devem sair
## base_material: material do objeto original (os fragmentos herdam a cor/textura)
## shard_count: quantos fragmentos soltar (8~14 já parece bem "quebrado")
## force: velocidade horizontal/lateral da explosão
## upward_bias: quanto o impulso inicial empurra pra cima
## lifetime: quanto tempo (segundos) até cada fragmento sumir
## scatter_radius: dispersão do ponto de origem de cada fragmento
## min_size / max_size: faixa de tamanho (aresta aproximada, em unidades do
## mundo) sorteada individualmente para cada fragmento
func explode(
	origin: Vector3,
	base_material: Material,
	shard_count: int = 10,
	force: float = 4.0,
	upward_bias: float = 3.5,
	lifetime: float = 1.1,
	scatter_radius: float = 0.25,
	min_size: float = 0.15,
	max_size: float = 0.35
) -> void:
	for i in range(shard_count):
		var shard := _get_free_shard()
		if shard == null:
			break
		
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.1, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var vel := dir * force * randf_range(0.6, 1.4)
		vel.y += upward_bias * randf_range(0.7, 1.3)
		vel *= GLOBAL_SPEED_MULTIPLIER
		
		var spin := Vector3(
			randf_range(-9.0, 9.0),
			randf_range(-9.0, 9.0),
			randf_range(-9.0, 9.0)
		)
		
		var spawn_pos := origin + Vector3(
			randf_range(-scatter_radius, scatter_radius),
			randf_range(-scatter_radius, scatter_radius),
			randf_range(-scatter_radius, scatter_radius)
		)
		
		var shape := _shard_shapes[randi() % _shard_shapes.size()]
		var size := randf_range(min_size, max(min_size, max_size))
		
		shard.launch(spawn_pos, vel, spin, lifetime * randf_range(0.8, 1.2), base_material, shape, size)

# ============================================================================
# NOVO: Pré-aquecimento de shaders (resolve a travada na primeira explosão).
#
# A trava que você viu na primeira destruição é a GPU compilando, na hora,
# a variante de shader usada pelos fragmentos (transparência + duas faces +
# sombreamento por vértice). Isso é compilado só na PRIMEIRA vez que esse
# material é efetivamente desenhado na tela — depois fica em cache e nunca
# mais trava (por isso "depois roda normal").
#
# A solução é forçar esse primeiro desenho de propósito, escondido atrás da
# tela de carregamento do mapa, ANTES do jogador poder destruir algo.
# Chame isto uma vez, durante o loading, passando um material de exemplo
# de cada "família" visual que existe no mapa (ex: material do carro,
# material dos prédios, material das torres). Não precisa passar todos os
# objetos — só um representante de cada tipo de material já resolve, porque
# o que é compilado é a variante do SHADER, não o objeto em si.
# ============================================================================
func warmup(materials: Array) -> void:
	if materials.is_empty():
		return
	
	# Usa a posição da própria câmera atual (se houver) pra garantir que o
	# fragmento entra no frustum e é realmente desenhado pelo menos 1 frame —
	# sem isso, a GPU poderia "cortar" o desenho por estar fora de visão e o
	# shader nunca seria compilado de verdade.
	var viewport = get_viewport()
	var cam = viewport.get_camera_3d() if viewport else null
	var warm_pos: Vector3 = (cam.global_position + cam.global_transform.basis.z * -2.0) if cam else Vector3.ZERO
	
	for mat in materials:
		var shard := _get_free_shard()
		if shard == null:
			break
		# Vida bem curta: só precisa existir por 1-2 frames pra forçar o desenho.
		var shape := _shard_shapes[0] if not _shard_shapes.is_empty() else null
		shard.launch(warm_pos, Vector3.ZERO, Vector3.ZERO, 0.05, mat, shape, 0.25)
