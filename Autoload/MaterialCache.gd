extends Node
# Autoload Nome: MaterialCache

var _mats: Dictionary = {}

func _ready():
	_construir_materiais()

func _construir_materiais():
	# ====================================================================
	# 1. MATERIAL DE GELO (VehicleEffects)
	# ====================================================================
	var ice = StandardMaterial3D.new()
	ice.albedo_color = Color(0.2, 0.6, 1.0, 0.7) 
	ice.roughness = 0.1 
	ice.metallic = 0.3
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats["VehicleIce"] = ice

# ====================================================================
	# 2. MATERIAL DO TURBO COMET (TurboCometFX)
	# ====================================================================
	var turbo_comet = StandardMaterial3D.new()
	turbo_comet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	turbo_comet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	turbo_comet.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	turbo_comet.cull_mode = BaseMaterial3D.CULL_DISABLED
	turbo_comet.vertex_color_use_as_albedo = true
	_mats["TurboComet"] = turbo_comet
	
	# ====================================================================
	# 3. MATERIAL DO SHOCKWAVE (TrickShockwaveBurstFX)
	# ====================================================================
	var shockwave = StandardMaterial3D.new()
	shockwave.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shockwave.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shockwave.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shockwave.cull_mode = BaseMaterial3D.CULL_DISABLED
	shockwave.vertex_color_use_as_albedo = true
	_mats["ShockwaveBurst"] = shockwave
	
	# ====================================================================
	# 4. MATERIAL DOS ANÉIS DE ENERGIA (TrickEnergyRingsFX)
	# ====================================================================
	var energy_rings = StandardMaterial3D.new()
	energy_rings.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	energy_rings.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	energy_rings.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	energy_rings.cull_mode = BaseMaterial3D.CULL_DISABLED
	energy_rings.vertex_color_use_as_albedo = true
	_mats["EnergyRings"] = energy_rings
	
	# ====================================================================
	# 5. MATERIAL DA CAUDA DO COMETA (TrickCometTailFX)
	# ====================================================================
	var fireball_tail = StandardMaterial3D.new()
	fireball_tail.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fireball_tail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fireball_tail.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fireball_tail.cull_mode = BaseMaterial3D.CULL_DISABLED
	fireball_tail.vertex_color_use_as_albedo = true
	_mats["FireballTail"] = fireball_tail
	
	# ====================================================================
	# 6. MATERIAL BASE NEON (TaillightTrailManager)
	# ====================================================================
	var base_neon = StandardMaterial3D.new()
	base_neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base_neon.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	base_neon.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base_neon.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["BaseNeon"] = base_neon
	
	# ====================================================================
	# 7. MATERIAL DE PICKUP DE STATUS (StatusChangerPickup)
	# ====================================================================
	var status_pickup = StandardMaterial3D.new()
	status_pickup.emission_enabled = true
	status_pickup.emission_energy_multiplier = 0.5
	_mats["StatusPickupBase"] = status_pickup
	
	# ====================================================================
	# 8. MATERIAL DE DESTAQUE DAS ARMAS (WeaponManager)
	# ====================================================================
	var weapon_highlight = StandardMaterial3D.new()
	weapon_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	weapon_highlight.albedo_color = Color(1.0, 0.8, 0.0, 0.4)
	weapon_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	weapon_highlight.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mats["WeaponHighlight"] = weapon_highlight
	
	# ====================================================================
	# 9. MATERIAL UNIVERSAL DE PICKUP (UniversalPickup)
	# ====================================================================
	var universal_pickup = StandardMaterial3D.new()
	universal_pickup.emission_enabled = true
	universal_pickup.emission_energy_multiplier = 0.5
	_mats["UniversalPickupBase"] = universal_pickup
	
	# ====================================================================
	# 10. MATERIAL DE PICKUP DE ARMA ANTIGO (PickupItem)
	# ====================================================================
	var weapon_pickup = StandardMaterial3D.new()
	weapon_pickup.emission_enabled = true
	weapon_pickup.emission_energy_multiplier = 0.5
	_mats["WeaponPickupBase"] = weapon_pickup
	
	# ====================================================================
	# 11. MATERIAL DE SANGUE DOS PEDESTRES (Pedestrian)
	# ====================================================================
	var pedestrian_gore = StandardMaterial3D.new()
	pedestrian_gore.albedo_color = Color(0.65, 0.0, 0.0)
	pedestrian_gore.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats["PedestrianGore"] = pedestrian_gore
	
	# ====================================================================
	# 12. MATERIAL DOS TRACERS DE TIRO (HitscanMachineGun)
	# ====================================================================
	var tracer_base = StandardMaterial3D.new()
	tracer_base.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_base.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_base.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["WeaponTracerBase"] = tracer_base
	
	# ====================================================================
	# 13. MATERIAL DO CABO DO GANCHO (Grappling)
	# ====================================================================
	var grappling_cable = StandardMaterial3D.new()
	grappling_cable.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats["GrapplingCableBase"] = grappling_cable
	
	# ====================================================================
	# 14. MATERIAL DE FUMAÇA DA EXPLOSÃO (ExplosionSmokePuff)
	# ====================================================================
	var explosion_smoke = StandardMaterial3D.new()
	explosion_smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	explosion_smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion_smoke.blend_mode = BaseMaterial3D.BLEND_MODE_MIX 
	explosion_smoke.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	explosion_smoke.billboard_keep_scale = true 
	explosion_smoke.cull_mode = BaseMaterial3D.CULL_DISABLED
	explosion_smoke.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mats["ExplosionSmokeBase"] = explosion_smoke
	
	# ====================================================================
	# 15. MATERIAL DO CLARÃO DA EXPLOSÃO (ExplosionFlash)
	# ====================================================================
	var explosion_flash = StandardMaterial3D.new()
	explosion_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	explosion_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion_flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD 
	explosion_flash.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	explosion_flash.billboard_keep_scale = true 
	explosion_flash.cull_mode = BaseMaterial3D.CULL_DISABLED
	explosion_flash.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mats["ExplosionFlashBase"] = explosion_flash
	
	# ====================================================================
	# 16. MATERIAL DE TELEPORTE DOS CARROS (BaseVehicle)
	# ====================================================================
	var teleport_mat = StandardMaterial3D.new()
	teleport_mat.albedo_color = Color(0.05, 0.05, 0.05)
	teleport_mat.metallic = 0.0
	teleport_mat.roughness = 1.0
	teleport_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats["CarTeleportEffect"] = teleport_mat
	
	# ====================================================================
	# 17. MATERIAL BASE DA LUZ DE FREIO (BrakeLightManager)
	# ====================================================================
	var brake_light = StandardMaterial3D.new()
	brake_light.emission_enabled = true
	_mats["BrakeLightBase"] = brake_light
	
	# ====================================================================
	# 18. MATERIAL DO ESCUDO DE INVULNERABILIDADE (AbilityComponent)
	# ====================================================================
	var car_shield = StandardMaterial3D.new()
	car_shield.albedo_color = Color(0.42, 0.45, 0.45)
	car_shield.metallic = 0.8
	car_shield.roughness = 0.1
	_mats["CarShieldEffect"] = car_shield

# Função universal para os scripts buscarem os materiais prontos
func get_mat(id: String) -> Material:
	if _mats.has(id):
		return _mats[id]
	push_error("[MaterialCache] AVISO: Material não encontrado no cache: " + id)
	return null
