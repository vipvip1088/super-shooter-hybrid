class_name FXManager3D
extends Node3D

# Pools for reusable effects
var _hit_pool: Array = []
var _explosion_pool: Array = []
const POOL_SIZE := 12
var _decal_count: int = 0
const MAX_DECALS := 40
var _decals: Array = []


func setup(_gm: Node) -> void:
	_prewarm_pools()


func _prewarm_pools() -> void:
	for _i in range(POOL_SIZE):
		_hit_pool.append(_make_hit_burst())
		_explosion_pool.append(_make_explosion_burst())


# ── Hit sparks ─────────────────────────────────────────────────────────────────
func spawn_hit(pos: Vector3, normal: Vector3, col: Color = Color(1.0, 0.8, 0.3)) -> void:
	var fx = _get_from_pool(_hit_pool)
	if not fx:
		return
	fx.global_position = pos
	# Orient emitter along normal
	if normal.length_squared() > 0.1:
		fx.global_rotation = Vector3.UP.signed_angle_to(normal, Vector3.FORWARD) * Vector3.UP
	var pm: ParticleProcessMaterial = fx.process_material
	pm.color = col
	fx.restart()
	fx.emitting = true
	# Auto-hide after particle lifetime
	var t = get_tree().create_timer(0.5)
	t.timeout.connect(func(): _return_to_pool(_hit_pool, fx))


func _make_hit_burst() -> GPUParticles3D:
	var gp = GPUParticles3D.new()
	gp.amount = 18
	gp.lifetime = 0.45
	gp.one_shot = true
	gp.explosiveness = 0.95
	gp.emitting = false
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 65.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.04; pm.scale_max = 0.10
	pm.color = Color(1.0, 0.7, 0.2)
	pm.color_ramp = _make_fade_gradient(Color(1.0, 0.8, 0.3), Color(1.0, 0.3, 0.0, 0.0))
	gp.process_material = pm
	var mesh = SphereMesh.new(); mesh.radius = 0.05; mesh.height = 0.10
	gp.draw_pass_1 = mesh
	add_child(gp)
	return gp


# ── Explosion ──────────────────────────────────────────────────────────────────
func spawn_explosion(pos: Vector3, radius: float = 6.0) -> void:
	var fx = _get_from_pool(_explosion_pool)
	if not fx:
		return
	fx.global_position = pos
	var pm: ParticleProcessMaterial = fx.process_material
	pm.emission_sphere_radius = radius * 0.3
	fx.restart(); fx.emitting = true
	# Flash light
	_spawn_explosion_light(pos, radius)
	var t = get_tree().create_timer(1.5)
	t.timeout.connect(func(): _return_to_pool(_explosion_pool, fx))


func _make_explosion_burst() -> GPUParticles3D:
	var gp = GPUParticles3D.new()
	gp.amount = 40
	gp.lifetime = 1.2
	gp.one_shot = true
	gp.explosiveness = 0.90
	gp.emitting = false
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 120.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -6.0, 0)
	pm.scale_min = 0.15; pm.scale_max = 0.50
	pm.color = Color(1.0, 0.55, 0.05)
	pm.color_ramp = _make_fade_gradient(Color(1.0, 0.9, 0.3), Color(0.6, 0.1, 0.0, 0.0))
	gp.process_material = pm
	var mesh = SphereMesh.new(); mesh.radius = 0.18; mesh.height = 0.36
	gp.draw_pass_1 = mesh
	add_child(gp)
	return gp


func _spawn_explosion_light(pos: Vector3, radius: float) -> void:
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.15)
	light.light_energy = 8.0
	light.omni_range = radius * 3.5
	light.shadow_enabled = false
	light.global_position = pos
	get_parent().add_child(light)
	# Fade out
	var t = 0.0
	while t < 0.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		light.light_energy = lerpf(8.0, 0.0, t / 0.5)
	light.queue_free()


# ── Muzzle flash ───────────────────────────────────────────────────────────────
func spawn_muzzle_flash(pos: Vector3, col: Color) -> void:
	var gp = GPUParticles3D.new()
	gp.amount = 8
	gp.lifetime = 0.06
	gp.one_shot = true
	gp.explosiveness = 1.0
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 20.0
	pm.initial_velocity_min = 1.0; pm.initial_velocity_max = 3.0
	pm.scale_min = 0.03; pm.scale_max = 0.08
	pm.color = col.lightened(0.4)
	gp.process_material = pm
	var mesh = SphereMesh.new(); mesh.radius = 0.04; mesh.height = 0.08
	gp.draw_pass_1 = mesh
	gp.global_position = pos
	get_parent().add_child(gp)
	gp.emitting = true
	var t = get_tree().create_timer(0.2)
	t.timeout.connect(func(): gp.queue_free())


# ── Bullet decals ──────────────────────────────────────────────────────────────
func spawn_bullet_hole(pos: Vector3, normal: Vector3) -> void:
	if _decal_count >= MAX_DECALS:
		# Remove oldest
		if _decals.size() > 0:
			var old = _decals.pop_front()
			if is_instance_valid(old):
				old.queue_free()
			_decal_count -= 1

	var decal = Decal.new()
	decal.global_position = pos + normal * 0.02
	if normal.length_squared() > 0.1:
		decal.look_at(pos + normal * 0.5)
		decal.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	decal.size = Vector3(0.18, 0.04, 0.18)
	decal.albedo_mix = 0.9
	# Procedural texture via material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	decal.material_override = mat
	get_parent().add_child(decal)
	_decals.append(decal)
	_decal_count += 1
	# Fade after 12s
	var timer = get_tree().create_timer(12.0)
	timer.timeout.connect(func():
		if is_instance_valid(decal):
			decal.queue_free()
			_decal_count -= 1
	)


# ── Blood/enemy hit ────────────────────────────────────────────────────────────
func spawn_blood_hit(pos: Vector3, col: Color) -> void:
	var gp = GPUParticles3D.new()
	gp.amount = 10
	gp.lifetime = 0.35
	gp.one_shot = true
	gp.explosiveness = 0.9
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 90.0
	pm.initial_velocity_min = 1.5; pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -12.0, 0)
	pm.scale_min = 0.04; pm.scale_max = 0.10
	pm.color = col
	gp.process_material = pm
	var mesh = SphereMesh.new(); mesh.radius = 0.05; mesh.height = 0.10
	gp.draw_pass_1 = mesh
	gp.global_position = pos
	get_parent().add_child(gp)
	gp.emitting = true
	var t = get_tree().create_timer(0.5)
	t.timeout.connect(func(): gp.queue_free())


# ── Loot pickup ────────────────────────────────────────────────────────────────
func spawn_pickup_sparkle(pos: Vector3) -> void:
	var gp = GPUParticles3D.new()
	gp.amount = 12
	gp.lifetime = 0.4
	gp.one_shot = true
	gp.explosiveness = 0.95
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0); pm.spread = 80.0
	pm.initial_velocity_min = 2.0; pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -4.0, 0)
	pm.scale_min = 0.05; pm.scale_max = 0.12
	pm.color = Color(1.0, 0.95, 0.3)
	gp.process_material = pm
	var mesh = SphereMesh.new(); mesh.radius = 0.06; mesh.height = 0.12
	gp.draw_pass_1 = mesh
	gp.global_position = pos + Vector3(0, 0.5, 0)
	get_parent().add_child(gp)
	gp.emitting = true
	var t = get_tree().create_timer(0.6)
	t.timeout.connect(func(): gp.queue_free())


# ── Pool helpers ───────────────────────────────────────────────────────────────
func _get_from_pool(pool: Array) -> GPUParticles3D:
	for fx in pool:
		if is_instance_valid(fx) and not fx.emitting:
			return fx
	return null


func _return_to_pool(pool: Array, fx: GPUParticles3D) -> void:
	if is_instance_valid(fx):
		fx.emitting = false


# ── Gradient helper ────────────────────────────────────────────────────────────
func _make_fade_gradient(c_start: Color, c_end: Color) -> Gradient:
	var g = Gradient.new()
	g.colors = PackedColorArray([c_start, c_end])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	return g
