extends Area3D

@export var destination_marker : Marker3D

var original_color : Color

func _ready():
	body_entered.connect(_on_body_entered)
	
	# Prepara o material para poder piscar a cor individualmente
	if has_node("MeshInstance3D"):
		var mesh = $MeshInstance3D
		var mat = mesh.get_active_material(0)
		if mat and mat is StandardMaterial3D:
			# Duplica para que um teleporter piscando não pisque todos os outros do mapa
			mesh.material_override = mat.duplicate()
			original_color = mesh.material_override.albedo_color

func _on_body_entered(body):
	if not body.has_method("teleport_to") or not destination_marker:
		return

	# --- SISTEMA DE TRANCAS ---
	if is_in_group("LockableTeleporters"):
		var tem_chave = false
		if "has_teleportkey" in body and body.has_teleportkey:
			tem_chave = true
		else:
			var stats = body.get_node_or_null("%StatsComponent")
			if stats and "has_teleportkey" in stats and stats.has_teleportkey:
				tem_chave = true

		if not tem_chave:
			var input = body.get_node_or_null("%InputComponent")
			if input and not input.is_bot:
				# Tenta achar a HUD com sufixo, se falhar, tenta a HUD genérica
				var hud = get_tree().get_first_node_in_group("HUD" + input.suffix)
				if not hud: hud = get_tree().get_first_node_in_group("HUD")
				
				if hud and hud.has_method("criar_toast"): 
					print("[Teleporter] Enviando erro para HUD: ", hud.name)
					hud.criar_toast("You don't have the Teleporter Key", Color.DARK_RED)
				else:
					print("[Teleporter] ERRO: Nenhuma HUD encontrada na cena!")
			
			_piscar_vermelho() 
			return # BLOQUEIA O TELEPORTE

	# Se não estiver no grupo (ou se estiver e tiver a chave), teleporta!
	body.teleport_to(destination_marker.global_transform)

func _piscar_vermelho():
	if not has_node("MeshInstance3D"): return
	
	var mat = $MeshInstance3D.material_override as StandardMaterial3D
	if not mat: return
	
	# Fica vermelho vivo instantaneamente
	mat.albedo_color = Color(1.0, 0.0, 0.0, 0.8) 
	
	# Anima a cor voltando para a cor original ao longo de 0.6 segundos
	var tween = create_tween()
	tween.tween_property(mat, "albedo_color", original_color, 0.6).set_trans(Tween.TRANS_SINE)
