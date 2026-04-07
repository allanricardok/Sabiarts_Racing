# SpeedLines.gd
extends ColorRect
class_name SpeedLines

@export_group("Gatilhos de Velocidade")
## Velocidade (km/h) onde as linhas COMEÇAM a aparecer
@export var min_speed_kmh : float = 80.0
## Velocidade (km/h) onde as linhas chegam na força máxima
@export var max_speed_kmh : float = 160.0
## Opacidade máxima do efeito (0.0 a 1.0)
@export var max_opacity : float = 1.0

var car : BaseVehicle = null

func _ready():
	# --- CORREÇÃO DO MULTIPLAYER (MATERIAL ÚNICO) ---
	# Duplica o material para que a HUD do P1 não altere a HUD do P2!
	if material is ShaderMaterial:
		material = material.duplicate()
		material.set_shader_parameter("intensity", 0.0)

func _process(_delta):
	# --- CONEXÃO BLINDADA COM A HUD ---
	# Em vez de olhar a Viewport, subimos a árvore de nós até achar 
	# o script principal da HUD e pegamos o carro exato que pertence a ela!
	if not is_instance_valid(car):
		var hud_node = get_parent()
		while hud_node != null:
			if "my_car" in hud_node and is_instance_valid(hud_node.my_car):
				car = hud_node.my_car
				break
			hud_node = hud_node.get_parent()
			
	# Se ainda não encontrou o carro (ex: HUD carregando), sai do process
	if not is_instance_valid(car): 
		return
		
	# Calcula a velocidade APENAS do carro dono desta HUD
	var kmh = car.linear_velocity.length() * 2.3
	
	# Mapeia a velocidade para a intensidade do shader
	var current_intensity = 0.0
	
	if kmh >= min_speed_kmh:
		# Remapeia: Ex (80-160 km/h -> 0.0-1.0 de intensidade)
		current_intensity = clamp(remap(kmh, min_speed_kmh, max_speed_kmh, 0.0, max_opacity), 0.0, max_opacity)
	
	# Envia a intensidade final para o Shader desenhar na tela
	if material is ShaderMaterial:
		material.set_shader_parameter("intensity", current_intensity)
