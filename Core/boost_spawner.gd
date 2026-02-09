extends Node3D

@export_group("Configurações do Spawner")
# Aqui você arrasta o .tscn da Máscara ou do Boost
@export var item_scene: PackedScene 
@export var respawn_time: float = 5.0

var current_item = null
var spawn_timer: Timer

func _ready():
	# Criamos um timer via código para não poluir a árvore de nós
	spawn_timer = Timer.new()
	spawn_timer.wait_time = respawn_time
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_spawn_item)
	add_child(spawn_timer)
	
	# Spawna o primeiro item
	_spawn_item()

func _spawn_item():
	if item_scene:
		current_item = item_scene.instantiate()
		add_child(current_item)
		
		# Conectamos ao sinal 'tree_exited' do item. 
		# Assim, quando o item der 'queue_free()' (for coletado), o timer inicia.
		current_item.tree_exited.connect(_on_item_collected)

func _on_item_collected():
	# Começa a contagem para o respawn
	spawn_timer.start()
