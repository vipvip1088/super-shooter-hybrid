class_name EnemyAI3D
extends CharacterBody3D

signal died(enemy: Node3D, reward: int, xp: int, pos: Vector3)
signal damaged_player(amount: float)

enum State { IDLE, CHASE, ATTACK, RETREAT, EXPLODING, DEAD }

# ── Config ─────────────────────────────────────────────────────────────────────
var type: String = "rusher"
var hp: float = 80.0
var max_hp: float = 80.0
var speed: float = 7.5
var dmg: float = 15.0
var atk_range: float = 1.8
var shoot_dmg: float = 0.0
var shoot_range: float = 0.0
var reward: int = 50
var xp_reward: int = 10
var wave_scale: float = 1.0

# ── State ──────────────────────────────────────────────────────────────────────
var state: State = State.IDLE
var flash_timer: float = 0.0
var attack_cd: float = 0.0
var shoot_cd: float = 0.0
var explode_timer: float = 1.6
var death_timer: float = 0.0
var boss_phase: int = 0
var boss_shoot_pattern: float = 0.0

# ── Nodes ──────────────────────────────────────────────────────────────────────
var nav_agent: NavigationAgent3D
var _body_mat: StandardMaterial3D
var _body_mi: MeshInstance3D
var _hp_bar_root: Node3D
var _hp_bar_mi: MeshInstance3D
var _hp_bar_fill_mi: MeshInstance3D
var _hp_fill_mat: StandardMaterial3D
var _laser_mi: MeshInstance3D  # sniper laser pointer
var _orbit_lights: Array = []   # boss orbiting lights

# ── Refs ───────────────────────────────────────────────────────────────────────
var player: Node3D
var _gm: Node


func setup(enemy_type: String, game_manager: Node, player_node: Node3D, hp_mult: float) -> void:
	type = enemy_type
	_gm = game_manager
	player = player_node
	var dat: Dictionary = Balance.ENEMIES3D[type]
	max_hp = dat["hp"] * hp_mult
	hp = max_hp
	speed = dat["speed"]
	dmg = dat["dmg"]
	atk_range = dat["atk_range"]
	shoot_dmg = dat["shoot_dmg"]
	shoot_range = dat["shoot_range"]
	reward = dat["reward"]
	xp_reward = int(dat["reward"] / 5)
	_build_mesh(dat)
	_setup_nav()
	_setup_collision()
	_setup_hp_bar()
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 1  # world geometry only


func _setup_collision() -> void:
	var col = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.8
	add_child(col)


func _setup_nav() -> void:
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 1.5
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.5
	nav_agent.neighbor_distance = 8.0
	nav_agent.max_neighbors = 10
	add_child(nav_agent)


# ── Mesh Building ──────────────────────────────────────────────────────────────
func _build_mesh(dat: Dictionary) -> void:
	var base_col: Color = dat["color"]
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = base_col
	_body_mat.roughness = 0.6
	_body_mat.metallic = 0.1

	match type:
		"rusher":    _build_rusher(base_col)
		"sniper_e":  _build_sniper_enemy(base_col)
		"tank":      _build_tank(base_col)
		"kamikaze":  _build_kamikaze(base_col)
		"boss":      _build_boss(base_col)
		_:           _build_rusher(base_col)

	_apply_scale(dat["scale"])


func _build_rusher(col: Color) -> void:
	_body_mi = _add_capsule(self, Vector3(0, 0.8, 0), 0.36, 1.4, _body_mat)
	# Horns
	var horn_mat = StandardMaterial3D.new()
	horn_mat.albedo_color = col.darkened(0.35)
	horn_mat.roughness = 0.5
	_add_box_mi(self, Vector3(-0.22, 1.62, 0), Vector3(0.09, 0.30, 0.09), horn_mat)
	_add_box_mi(self, Vector3( 0.22, 1.62, 0), Vector3(0.09, 0.30, 0.09), horn_mat)
	# Eyes
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1, 0.9, 0.1)
	eye_mat.emission_enabled = true; eye_mat.emission = Color(1, 0.8, 0)
	eye_mat.emission_energy_multiplier = 1.5
	_add_sphere_mi(self, Vector3(-0.12, 1.45, 0.32), 0.06, eye_mat)
	_add_sphere_mi(self, Vector3( 0.12, 1.45, 0.32), 0.06, eye_mat)


func _build_sniper_enemy(col: Color) -> void:
	_body_mi = _add_capsule(self, Vector3(0, 0.9, 0), 0.30, 1.6, _body_mat)
	# Cloak (semi-transparent)
	var cloak_mat = StandardMaterial3D.new()
	cloak_mat.albedo_color = Color(col.r, col.g, col.b, 0.55)
	cloak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloak_mat.roughness = 0.1; cloak_mat.metallic = 0.5
	_add_capsule(self, Vector3(0, 0.9, 0), 0.33, 1.65, cloak_mat)
	# Scope glow
	var scope_mat = StandardMaterial3D.new()
	scope_mat.albedo_color = Color(0.8, 0.1, 0.1)
	scope_mat.emission_enabled = true; scope_mat.emission = Color(1, 0, 0)
	scope_mat.emission_energy_multiplier = 2.0
	_add_sphere_mi(self, Vector3(0, 1.5, 0.32), 0.05, scope_mat)
	# Laser line (initially hidden, shown when aiming)
	_laser_mi = MeshInstance3D.new()
	var lm = CylinderMesh.new(); lm.top_radius = 0.012; lm.bottom_radius = 0.012; lm.height = 1.0
	_laser_mi.mesh = lm
	_laser_mi.material_override = scope_mat
	_laser_mi.visible = false
	_laser_mi.rotation_degrees.x = 90.0
	_laser_mi.position = Vector3(0, 1.5, -0.5)
	add_child(_laser_mi)


func _build_tank(col: Color) -> void:
	# Large boxy body
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = col; body_mat.roughness = 0.8; body_mat.metallic = 0.4
	_body_mi = _add_box_mi(self, Vector3(0, 0.7, 0), Vector3(1.0, 1.1, 0.9), body_mat)
	_add_box_mi(self, Vector3(0, 1.55, 0), Vector3(0.7, 0.7, 0.65), body_mat)  # head
	# Shield dome
	var shield_mat = StandardMaterial3D.new()
	shield_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.25)
	shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mat.emission_enabled = true; shield_mat.emission = Color(0.2, 0.5, 1.0, 0.3)
	shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_sphere_mi(self, Vector3(0, 0.95, 0), 1.05, shield_mat)
	# Armor plates
	var plate_mat = StandardMaterial3D.new()
	plate_mat.albedo_color = col.darkened(0.2); plate_mat.metallic = 0.7; plate_mat.roughness = 0.3
	_add_box_mi(self, Vector3(0.55, 0.7, 0), Vector3(0.14, 0.8, 0.7), plate_mat)
	_add_box_mi(self, Vector3(-0.55, 0.7, 0), Vector3(0.14, 0.8, 0.7), plate_mat)


func _build_kamikaze(col: Color) -> void:
	_body_mat.roughness = 0.3
	_body_mat.emission_enabled = true; _body_mat.emission = col; _body_mat.emission_energy_multiplier = 0.4
	_body_mi = _add_sphere_mi(self, Vector3(0, 0.7, 0), 0.45, _body_mat)
	# Spikes
	var spike_mat = StandardMaterial3D.new()
	spike_mat.albedo_color = col.lightened(0.3); spike_mat.roughness = 0.2
	for i in range(8):
		var a := (TAU / 8.0) * i
		var sp_pos := Vector3(cos(a) * 0.52, 0.7 + sin(a) * 0.1, sin(a) * 0.52)
		_add_box_mi(self, sp_pos, Vector3(0.07, 0.07, 0.22), spike_mat)
	# Inner glow
	var glow_mat = StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1, 1, 1, 0.5)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.emission_enabled = true; glow_mat.emission = Color(1, 0.4, 0)
	glow_mat.emission_energy_multiplier = 2.0
	_add_sphere_mi(self, Vector3(0, 0.7, 0), 0.30, glow_mat)


func _build_boss(col: Color) -> void:
	# Large sphere body
	_body_mat.emission_enabled = true; _body_mat.emission = col; _body_mat.emission_energy_multiplier = 0.3
	_body_mi = _add_sphere_mi(self, Vector3(0, 1.2, 0), 1.0, _body_mat)
	# Rings
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = col; ring_mat.metallic = 0.9; ring_mat.roughness = 0.1
	ring_mat.emission_enabled = true; ring_mat.emission = col; ring_mat.emission_energy_multiplier = 1.5
	for i in range(3):
		var rm = MeshInstance3D.new()
		var tor = TorusMesh.new()
		tor.inner_radius = 0.9 + i * 0.3; tor.outer_radius = 1.1 + i * 0.3
		tor.rings = 24; tor.ring_segments = 8
		rm.mesh = tor; rm.material_override = ring_mat
		rm.position = Vector3(0, 1.2, 0)
		rm.rotation_degrees = Vector3(i * 30, 0, i * 45)
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rm)
	# Orbit lights
	for i in range(4):
		var ol = OmniLight3D.new()
		ol.light_color = col; ol.light_energy = 3.0; ol.omni_range = 8.0; ol.shadow_enabled = false
		add_child(ol)
		_orbit_lights.append(ol)


func _apply_scale(s: Vector3) -> void:
	scale = s


# ── HP Bar ─────────────────────────────────────────────────────────────────────
func _setup_hp_bar() -> void:
	_hp_bar_root = Node3D.new()
	_hp_bar_root.name = "HPBar"
	add_child(_hp_bar_root)

	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.0, 0.0); bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var bg_mi = MeshInstance3D.new()
	var bgm = QuadMesh.new(); bgm.size = Vector2(0.9, 0.08)
	bg_mi.mesh = bgm; bg_mi.material_override = bg_mat
	bg_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar_root.add_child(bg_mi)

	_hp_fill_mat = StandardMaterial3D.new()
	_hp_fill_mat.albedo_color = Color(0.1, 0.85, 0.2)
	_hp_fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_fill_mi = MeshInstance3D.new()
	var fillm = QuadMesh.new(); fillm.size = Vector2(0.9, 0.07)
	_hp_bar_fill_mi.mesh = fillm; _hp_bar_fill_mi.material_override = _hp_fill_mat
	_hp_bar_fill_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar_root.add_child(_hp_bar_fill_mi)

	_hp_bar_root.position.y = _get_bar_height()


func _get_bar_height() -> float:
	match type:
		"tank": return 2.5
		"boss": return 3.2
		"kamikaze": return 1.4
		_: return 2.1


# ── Physics Process ────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_do_death_anim(delta)
		return

	_update_timers(delta)
	_update_hp_bar()
	_update_boss_effects(delta)

	if not player or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)

	match state:
		State.IDLE:
			if dist < 50.0:
				state = State.CHASE
		State.CHASE:
			_do_chase(delta, dist)
		State.ATTACK:
			_do_melee(delta, dist)
		State.EXPLODING:
			_do_exploding(delta, dist)


func _update_timers(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
	if attack_cd > 0.0:
		attack_cd -= delta
	if shoot_cd > 0.0:
		shoot_cd -= delta


func _update_hp_bar() -> void:
	if not _hp_bar_root:
		return
	var frac := maxf(0.0, hp / max_hp)
	_hp_bar_fill_mi.scale.x = frac
	_hp_bar_fill_mi.position.x = (frac - 1.0) * 0.45
	_hp_fill_mat.albedo_color = Color(0.1, 0.85, 0.2) if frac > 0.4 else Color(0.9, 0.4, 0.1)

	# Flash
	if flash_timer > 0.0:
		var fl := flash_timer / 0.18
		_body_mat.albedo_color = _body_mat.albedo_color.lerp(Color.WHITE, fl * 0.85)
	else:
		_body_mat.albedo_color = _body_mat.albedo_color.lerp(Balance.ENEMIES3D[type]["color"], 0.15)


func _update_boss_effects(delta: float) -> void:
	if type != "boss":
		return
	boss_shoot_pattern += delta
	var rot := Time.get_ticks_msec() * 0.001
	for i in range(_orbit_lights.size()):
		var a := rot + (TAU / _orbit_lights.size()) * i
		_orbit_lights[i].position = Vector3(cos(a) * 2.5, 1.2, sin(a) * 2.5)
	# Phase transitions
	var frac := hp / max_hp
	if frac < 0.33 and boss_phase < 2:
		boss_phase = 2
		_body_mat.emission_energy_multiplier = 1.5
		for ol: OmniLight3D in _orbit_lights:
			ol.light_color = Color(1, 0.2, 0.1)
	elif frac < 0.66 and boss_phase < 1:
		boss_phase = 1
		_body_mat.emission_energy_multiplier = 0.8
		for ol: OmniLight3D in _orbit_lights:
			ol.light_color = Color(1, 0.55, 0.1)


func _do_chase(delta: float, dist: float) -> void:
	# Switch to attack if in range
	var engage_range := atk_range if shoot_range <= 0.1 else shoot_range
	if dist <= engage_range:
		if type == "kamikaze":
			state = State.EXPLODING
		else:
			state = State.ATTACK
		return

	# Navigate toward player
	nav_agent.target_position = player.global_position
	if nav_agent.is_navigation_finished():
		return
	var next := nav_agent.get_next_path_position()
	var dir := (next - global_position)
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 8.0)
	else:
		velocity.x = lerpf(velocity.x, 0.0, delta * 8.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 8.0)

	if not is_on_floor():
		velocity.y -= Balance.P3D_GRAVITY * delta
	else:
		velocity.y = -0.5

	# Ranged attack while chasing (sniper_e, boss)
	if shoot_range > 0.1 and dist <= shoot_range:
		_try_shoot()

	move_and_slide()


func _do_melee(delta: float, dist: float) -> void:
	# Back to chase if out of range
	if dist > atk_range * 1.8:
		state = State.CHASE
		return
	_face_player(delta)
	if attack_cd <= 0.0:
		attack_cd = 1.4
		if player.has_method("apply_damage"):
			player.apply_damage(dmg)
		emit_signal("damaged_player", dmg)
		if _gm.has_method("on_player_damaged"):
			_gm.on_player_damaged(dmg)

	if not is_on_floor():
		velocity.y -= Balance.P3D_GRAVITY * delta
	else:
		velocity.y = -0.5
		velocity.x = lerpf(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 10.0)
	move_and_slide()


func _do_exploding(delta: float, dist: float) -> void:
	explode_timer -= delta
	# Pulse scale
	var pulse := sin(Time.get_ticks_msec() * 0.01) * 0.1 + 1.0
	scale = Balance.ENEMIES3D[type]["scale"] * pulse
	_body_mat.emission_energy_multiplier = (1.6 - explode_timer / 1.6) * 3.0

	# Keep moving toward player
	if dist > 0.5:
		var dir := (player.global_position - global_position)
		dir.y = 0.0; dir = dir.normalized()
		velocity.x = dir.x * speed * 1.3
		velocity.z = dir.z * speed * 1.3

	if not is_on_floor():
		velocity.y -= Balance.P3D_GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()

	if explode_timer <= 0.0 or dist < atk_range:
		# Explode
		if _gm.has_method("create_explosion_3d"):
			_gm.create_explosion_3d(global_position, 4.5, dmg)
		_die()


func _try_shoot() -> void:
	if shoot_cd > 0.0:
		return
	shoot_cd = 2.0 + randf() * 1.5
	var dist := global_position.distance_to(player.global_position)
	if dist > shoot_range:
		return
	# Sniper laser pointer
	if _laser_mi:
		_laser_mi.visible = true
		_laser_mi.scale.z = dist * 0.5

	# Spawn enemy projectile via game manager
	if _gm.has_method("spawn_enemy_projectile"):
		var dir := (player.global_position - global_position).normalized()
		_gm.spawn_enemy_projectile(global_position + Vector3(0, 1.2, 0), dir, shoot_dmg, type)
	# Direct damage for boss (in addition to projectile)
	if type == "boss":
		_fire_boss_spiral()


func _fire_boss_spiral() -> void:
	if not _gm.has_method("spawn_enemy_projectile"):
		return
	var count := 8 if boss_phase < 1 else (12 if boss_phase < 2 else 16)
	for i in range(count):
		var a := (TAU / count) * i + boss_shoot_pattern * 0.5
		var dir := Vector3(cos(a), 0.0, sin(a)).normalized()
		_gm.spawn_enemy_projectile(
			global_position + Vector3(0, 1.5, 0), dir, shoot_dmg * 0.7, "boss_spiral"
		)


func _face_player(delta: float) -> void:
	var dir := player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 8.0)


# ── Damage ─────────────────────────────────────────────────────────────────────
func take_damage(amount: float, _source: Node = null) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	flash_timer = 0.18
	if _laser_mi:
		_laser_mi.visible = false
	if hp <= 0.0:
		hp = 0.0
		if type == "kamikaze" and state == State.EXPLODING:
			if _gm.has_method("create_explosion_3d"):
				_gm.create_explosion_3d(global_position, 4.5, dmg)
		_die()


func _die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	death_timer = 0.55
	nav_agent.avoidance_enabled = false
	collision_layer = 0; collision_mask = 0
	velocity = Vector3.ZERO
	if _hp_bar_root:
		_hp_bar_root.visible = false
	emit_signal("died", self, reward, xp_reward, global_position)


func _do_death_anim(delta: float) -> void:
	death_timer -= delta
	var t := 1.0 - maxf(0.0, death_timer / 0.55)
	scale = Balance.ENEMIES3D[type]["scale"] * (1.0 - t * 0.95)
	position.y = -t * 0.8
	if death_timer <= 0.0:
		queue_free()


# ── Mesh Helpers ───────────────────────────────────────────────────────────────
func _add_capsule(parent: Node3D, pos: Vector3, r: float, h: float, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var cm = CapsuleMesh.new(); cm.radius = r; cm.height = h
	cm.radial_segments = 10; cm.rings = 4
	mi.mesh = cm; mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _add_box_mi(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_sphere_mi(parent: Node3D, pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new(); sm.radius = r; sm.height = r * 2.0
	sm.radial_segments = 8; sm.rings = 4
	mi.mesh = sm; mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
