class_name WeaponSystem3D
extends Node3D

signal fired(weapon_id: String, from: Vector3, direction: Vector3)
signal reloaded
signal ammo_changed(current: int, max_ammo: int)
signal hit_enemy(enemy: Node3D, damage: float, pos: Vector3)

# ── State ──────────────────────────────────────────────────────────────────────
var current_weapon: String = "ar"
var ammo: int = 0
var max_ammo: int = 0
var fire_timer: float = 0.0
var reload_timer: float = 0.0
var is_reloading: bool = false
var reload_progress: float = 0.0

# ── Nodes ──────────────────────────────────────────────────────────────────────
var _raycast: RayCast3D
var _muzzle_light: OmniLight3D
var _muzzle_timer: float = 0.0
var _weapon_mesh: Node3D
var _weapon_models: Dictionary = {}

# ── Refs ───────────────────────────────────────────────────────────────────────
var _gm: Node
var _player  # PlayerController3D


func setup(game_manager: Node, player: Node) -> void:
	_gm = game_manager
	_player = player
	_setup_raycast()
	_setup_muzzle_light()
	_build_all_weapon_models()
	equip("ar")


func _setup_raycast() -> void:
	_raycast = RayCast3D.new()
	_raycast.name = "WeaponRay"
	_raycast.collision_mask = 0b00000111  # layer 1 (world), 2 (enemies), 3 (barrels)
	_raycast.target_position = Vector3(0, 0, -120.0)
	_raycast.enabled = true
	add_child(_raycast)


func _setup_muzzle_light() -> void:
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.name = "MuzzleFlash"
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 4.0
	_muzzle_light.shadow_enabled = false
	_muzzle_light.position = Vector3(0, 0, -0.5)
	add_child(_muzzle_light)


# ── Weapon model construction ──────────────────────────────────────────────────
func _build_all_weapon_models() -> void:
	for wid in Balance.WEAPONS3D.keys():
		var model = _build_weapon_model(wid)
		model.visible = false
		_weapon_models[wid] = model
		add_child(model)


func _build_weapon_model(wid: String) -> Node3D:
	var root = Node3D.new()
	root.name = "Model_" + wid
	var wdat: Dictionary = Balance.WEAPONS3D[wid]
	var col: Color = wdat["color"]

	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.35
	mat.metallic = 0.7

	var glow_mat = StandardMaterial3D.new()
	glow_mat.albedo_color = col
	glow_mat.emission_enabled = true
	glow_mat.emission = col
	glow_mat.emission_energy_multiplier = 1.2
	glow_mat.roughness = 0.2

	match wid:
		"ar":
			_add_part(root, Vector3(0, 0, -0.32), Vector3(0.08, 0.08, 0.55), mat)  # barrel
			_add_part(root, Vector3(0, -0.04, -0.05), Vector3(0.12, 0.10, 0.28), mat)  # body
			_add_part(root, Vector3(0, -0.05, 0.18), Vector3(0.06, 0.12, 0.18), mat)  # stock
			_add_part(root, Vector3(0, -0.10, 0.02), Vector3(0.04, 0.08, 0.10), mat)  # grip
			_add_cylinder(root, Vector3(0, 0, -0.35), 0.025, 0.025, 0.12, glow_mat)   # barrel tip

		"shotgun":
			_add_part(root, Vector3(0, 0, -0.30), Vector3(0.10, 0.10, 0.50), mat)
			_add_part(root, Vector3(0, -0.06, 0.0), Vector3(0.14, 0.12, 0.28), mat)
			_add_part(root, Vector3(0.0, 0, -0.28), Vector3(0.05, 0.05, 0.44), glow_mat)  # pump

		"sniper":
			_add_part(root, Vector3(0, 0.0, -0.50), Vector3(0.055, 0.055, 0.80), mat)
			_add_part(root, Vector3(0, 0.06, -0.25), Vector3(0.07, 0.05, 0.24), glow_mat) # scope
			_add_part(root, Vector3(0, -0.04, -0.1), Vector3(0.10, 0.08, 0.22), mat)
			_add_part(root, Vector3(0, -0.04, 0.18), Vector3(0.06, 0.16, 0.20), mat)

		"plasma":
			_add_cylinder(root, Vector3(0, 0, -0.20), 0.12, 0.10, 0.42, mat)
			_add_sphere(root, Vector3(0, 0, -0.38), 0.10, glow_mat)
			_add_cylinder(root, Vector3(0, 0, -0.02), 0.06, 0.08, 0.18, mat)  # handle

		"grenade":
			_add_cylinder(root, Vector3(0, 0, -0.22), 0.13, 0.11, 0.38, mat)
			_add_cylinder(root, Vector3(0, 0, -0.38), 0.065, 0.065, 0.08, glow_mat)
			_add_part(root, Vector3(0, -0.08, 0.02), Vector3(0.10, 0.12, 0.16), mat)

	return root


func _add_part(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _add_cylinder(parent: Node3D, pos: Vector3, r_top: float, r_bot: float, h: float, mat: Material) -> void:
	var mi = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = r_top; cm.bottom_radius = r_bot; cm.height = h
	mi.mesh = cm; mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = 90.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _add_sphere(parent: Node3D, pos: Vector3, r: float, mat: Material) -> void:
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new(); sm.radius = r; sm.height = r * 2.0
	mi.mesh = sm; mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ── Equip ──────────────────────────────────────────────────────────────────────
func equip(weapon_id: String) -> void:
	if not Balance.WEAPONS3D.has(weapon_id):
		return
	if _weapon_models.has(current_weapon):
		_weapon_models[current_weapon].visible = false
	current_weapon = weapon_id
	var wdat: Dictionary = Balance.WEAPONS3D[weapon_id]
	ammo = wdat["ammo"]
	max_ammo = wdat["ammo"]
	is_reloading = false
	reload_timer = 0.0
	fire_timer = 0.0
	if _weapon_models.has(weapon_id):
		_weapon_models[weapon_id].visible = true
	emit_signal("ammo_changed", ammo, max_ammo)


func cycle_weapon(dir: int) -> void:
	var order: Array = Balance.WEAPON3D_ORDER
	var idx := order.find(current_weapon)
	idx = (idx + dir + order.size()) % order.size()
	equip(order[idx])


# ── Process ────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	_muzzle_timer = maxf(0.0, _muzzle_timer - delta)
	if _muzzle_timer <= 0.0:
		_muzzle_light.light_energy = lerpf(_muzzle_light.light_energy, 0.0, delta * 20.0)

	if is_reloading:
		reload_timer -= delta
		reload_progress = 1.0 - reload_timer / Balance.WEAPONS3D[current_weapon]["reload"]
		if reload_timer <= 0.0:
			ammo = max_ammo
			is_reloading = false
			reload_progress = 0.0
			emit_signal("ammo_changed", ammo, max_ammo)
			emit_signal("reloaded")

	# Sync raycast to camera direction
	if _player and is_instance_valid(_player):
		var cam_origin: Vector3 = _player.get_camera_origin()
		var cam_dir: Vector3 = _player.get_aim_direction()
		_raycast.global_position = cam_origin
		_raycast.target_position = cam_dir * Balance.WEAPONS3D[current_weapon]["range"]

	# Position weapon model at anchor
	if _player and is_instance_valid(_player) and _weapon_models.has(current_weapon):
		_weapon_models[current_weapon].global_transform = _player._weapon_anchor.global_transform


# ── Fire ───────────────────────────────────────────────────────────────────────
func try_fire() -> void:
	if is_reloading or fire_timer > 0.0:
		return
	if ammo <= 0:
		start_reload()
		return
	var wdat: Dictionary = Balance.WEAPONS3D[current_weapon]
	fire_timer = wdat["fire_rate"]
	ammo -= 1
	emit_signal("ammo_changed", ammo, max_ammo)

	if wdat["hitscan"]:
		_fire_hitscan(wdat)
	else:
		_fire_projectile(wdat)

	_do_muzzle_flash(wdat["color"])
	emit_signal("fired", current_weapon, _player.get_camera_origin(), _player.get_aim_direction())

	if ammo <= 0:
		start_reload()


func _fire_hitscan(wdat: Dictionary) -> void:
	var cam_origin := _player.get_camera_origin()
	var cam_dir := _player.get_aim_direction()
	var pellets: int = wdat["pellets"]
	var spread: float = wdat["spread"]
	var dmg: float = wdat["damage"] * _player.p_dmg_mult

	for _p in range(pellets):
		var shot_dir := cam_dir
		if spread > 0.0:
			shot_dir += Vector3(
				randf_range(-spread, spread),
				randf_range(-spread, spread),
				randf_range(-spread, spread)
			)
			shot_dir = shot_dir.normalized()
		_cast_ray(cam_origin, shot_dir, wdat["range"], dmg)

	# Double-shot perk
	if _player.p_double_shot:
		for _p in range(pellets):
			var shot_dir2 := cam_dir + Vector3(randf_range(-0.06,0.06),randf_range(-0.06,0.06),0)
			_cast_ray(cam_origin, shot_dir2.normalized(), wdat["range"], dmg * 0.75)


func _cast_ray(origin: Vector3, direction: Vector3, range_m: float, damage: float) -> void:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * range_m,
		0b00000110  # enemy layer (2) + barrel layer (3)
	)
	query.exclude = [_player]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return
	var hit_pos: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var collider = result["collider"]

	# Notify FX
	if _gm.has_method("on_hit_surface"):
		_gm.on_hit_surface(hit_pos, hit_normal, collider)

	# Enemy damage
	if collider.has_method("take_damage"):
		var real_dmg := damage
		# Explosive rounds
		if _player.p_explosive_rds and _gm.has_method("create_explosion_3d"):
			_gm.create_explosion_3d(hit_pos, 2.5, damage * 0.8)
		collider.take_damage(real_dmg, _player)
		emit_signal("hit_enemy", collider, real_dmg, hit_pos)

	# Explosive barrel
	if collider.is_in_group("explosive_barrel") and _gm.has_method("explode_barrel"):
		_gm.explode_barrel(collider)


func _fire_projectile(wdat: Dictionary) -> void:
	if not _gm.has_method("spawn_projectile_3d"):
		return
	var dmg := wdat["damage"] * _player.p_dmg_mult
	_gm.spawn_projectile_3d(
		_player.get_camera_origin(),
		_player.get_aim_direction(),
		wdat["proj_speed"],
		wdat["range"],
		dmg,
		wdat["aoe"],
		wdat["color"],
		current_weapon
	)


func _do_muzzle_flash(col: Color) -> void:
	_muzzle_light.light_color = col.lightened(0.3)
	_muzzle_light.light_energy = 4.0
	_muzzle_timer = 0.06
	# Camera shake
	_player.add_camera_shake(0.12)


# ── Reload ─────────────────────────────────────────────────────────────────────
func start_reload() -> void:
	if is_reloading or ammo >= max_ammo:
		return
	is_reloading = true
	var wdat: Dictionary = Balance.WEAPONS3D[current_weapon]
	reload_timer = wdat["reload"]
	reload_progress = 0.0
