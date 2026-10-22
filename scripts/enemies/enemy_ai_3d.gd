class_name EnemyAI3D
extends CharacterBody3D

signal died(enemy: Node3D, reward: int, xp: int, pos: Vector3)

enum State { IDLE, CHASE, ATTACK, EXPLODING, DEAD }

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

# ── Runtime state ──────────────────────────────────────────────────────────────
var state: State = State.IDLE
var _flash: float = 0.0
var _atk_cd: float = 0.0
var _shoot_cd: float = 0.0
var _explode_timer: float = 1.6
var _death_timer: float = 0.55
var _boss_phase: int = 0
var _boss_spiral_t: float = 0.0
var _alive: bool = true

# ── Nodes ──────────────────────────────────────────────────────────────────────
var nav_agent: NavigationAgent3D
var _body_mat: StandardMaterial3D
var _base_color: Color
var _orbit_lights: Array = []
var _hp_root: Node3D
var _hp_fill_mat: StandardMaterial3D
var _hp_fill_mi: MeshInstance3D
var _laser_dot: MeshInstance3D

# ── Refs ───────────────────────────────────────────────────────────────────────
var player: Node3D
var _gm: Node


func setup(etype: String, gm: Node, pl: Node3D, hp_mult: float) -> void:
	type = etype; _gm = gm; player = pl
	var dat: Dictionary = Balance.ENEMIES3D[type]
	max_hp    = dat["hp"] * hp_mult; hp = max_hp
	speed     = dat["speed"]
	dmg       = dat["dmg"]
	atk_range = dat["atk_range"]
	shoot_dmg = dat["shoot_dmg"]
	shoot_range = dat["shoot_range"]
	reward    = dat["reward"]
	xp_reward = maxi(1, int(dat["reward"] / 5))
	_base_color = dat["color"]

	_build_collision()
	_build_mesh(dat)
	_build_nav()
	_build_hp_bar()
	add_to_group("enemies")
	collision_layer = 2
	collision_mask  = 1   # world geometry
	scale           = dat["scale"]


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42; cap.height = 1.6
	col.shape = cap; col.position.y = 0.8
	add_child(col)


func _build_nav() -> void:
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "Nav"
	nav_agent.path_desired_distance   = 0.8
	nav_agent.target_desired_distance = 1.2
	nav_agent.avoidance_enabled       = true
	nav_agent.radius                  = 0.5
	nav_agent.height                  = 1.8
	nav_agent.neighbor_distance       = 10.0
	nav_agent.max_neighbors           = 8
	add_child(nav_agent)


# ── Mesh Building ──────────────────────────────────────────────────────────────
func _build_mesh(dat: Dictionary) -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = _base_color
	_body_mat.roughness = 0.55; _body_mat.metallic = 0.12
	match type:
		"rusher":   _mesh_rusher()
		"sniper_e": _mesh_sniper_e()
		"tank":     _mesh_tank()
		"kamikaze": _mesh_kamikaze()
		"boss":     _mesh_boss()
		_:          _mesh_rusher()


func _mesh_rusher() -> void:
	_add_capsule(self, Vector3(0,0.8,0), 0.36, 1.4, _body_mat)
	# Armour shoulder pads
	var pad_mat := _mat(_base_color.darkened(0.3), 0.4, 0.2)
	_add_box(self, Vector3(-0.42,1.05,0), Vector3(0.16,0.22,0.30), pad_mat)
	_add_box(self, Vector3( 0.42,1.05,0), Vector3(0.16,0.22,0.30), pad_mat)
	# Horns
	var horn_mat := _mat(_base_color.lightened(0.15), 0.5, 0.0)
	_add_box(self, Vector3(-0.20,1.65,0), Vector3(0.08,0.28,0.08), horn_mat)
	_add_box(self, Vector3( 0.20,1.65,0), Vector3(0.08,0.28,0.08), horn_mat)
	# Glowing eyes
	var eye_mat := _mat_emit(Color(1,0.85,0.1), Color(1,0.7,0), 2.0)
	_add_sphere(self, Vector3(-0.12,1.46,0.32), 0.065, eye_mat)
	_add_sphere(self, Vector3( 0.12,1.46,0.32), 0.065, eye_mat)


func _mesh_sniper_e() -> void:
	_add_capsule(self, Vector3(0,0.9,0), 0.30, 1.6, _body_mat)
	# Translucent cloak
	var cloak := _mat_alpha(_base_color, 0.45)
	_add_capsule(self, Vector3(0,0.9,0), 0.34, 1.65, cloak)
	# Scope/eye glow
	var scope_mat := _mat_emit(Color(0.9,0.05,0.05), Color(1,0,0), 3.0)
	_add_sphere(self, Vector3(0,1.52,0.33), 0.055, scope_mat)
	# Laser dot (shown when aiming)
	_laser_dot = _add_sphere(self, Vector3(0,1.52,0.35), 0.05, scope_mat)
	_laser_dot.visible = false


func _mesh_tank() -> void:
	var bmat := _mat(_base_color, 0.75, 0.45)
	_add_box(self, Vector3(0,0.65,0), Vector3(1.1,1.15,0.95), bmat)
	_add_box(self, Vector3(0,1.60,0), Vector3(0.75,0.72,0.68), bmat)
	# Armour plates
	var plate := _mat(_base_color.darkened(0.2), 0.3, 0.7)
	_add_box(self, Vector3( 0.60,0.65,0), Vector3(0.14,0.9,0.75), plate)
	_add_box(self, Vector3(-0.60,0.65,0), Vector3(0.14,0.9,0.75), plate)
	# Shield dome (semi-transparent blue)
	var shield_mat := StandardMaterial3D.new()
	shield_mat.albedo_color = Color(0.3,0.6,1.0,0.22)
	shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mat.emission_enabled = true; shield_mat.emission = Color(0.2,0.5,1.0,0.3)
	shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_mat.roughness = 0.0
	_add_sphere(self, Vector3(0,0.9,0), 1.12, shield_mat)
	# Red eye
	_add_sphere(self, Vector3(0,1.65,0.35), 0.09, _mat_emit(Color(1,0,0), Color(1,0,0), 3.0))


func _mesh_kamikaze() -> void:
	var km := _body_mat
	km.emission_enabled = true; km.emission = _base_color; km.emission_energy_multiplier = 0.5
	_add_sphere(self, Vector3(0,0.72,0), 0.46, km)
	# Spikes around body
	var spike_mat := _mat(_base_color.lightened(0.25), 0.25, 0.0)
	for i in range(8):
		var a := (TAU/8.0)*i
		var sp_p := Vector3(cos(a)*0.55, 0.72+sin(a)*0.12, sin(a)*0.55)
		var sp_mi := _add_box(self, sp_p, Vector3(0.07,0.07,0.25), spike_mat)
		sp_mi.rotation.y = a
	# Inner glow
	var glow := _mat_emit(Color(1,0.4,0), Color(1,0.2,0), 2.5)
	var igm := StandardMaterial3D.new()
	igm.albedo_color = Color(1,0.5,0,0.4)
	igm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	igm.emission_enabled = true; igm.emission = Color(1,0.3,0); igm.emission_energy_multiplier = 2.0
	_add_sphere(self, Vector3(0,0.72,0), 0.30, igm)


func _mesh_boss() -> void:
	var bmat := _body_mat
	bmat.emission_enabled = true; bmat.emission = _base_color; bmat.emission_energy_multiplier = 0.4
	_add_sphere(self, Vector3(0,1.2,0), 1.0, bmat)
	# Eye cluster
	var eye_mat := _mat_emit(Color(1,0,0), Color(1,0,0), 4.0)
	_add_sphere(self, Vector3(0,1.35,0.95), 0.14, eye_mat)
	_add_sphere(self, Vector3(-0.22,1.25,0.88), 0.09, eye_mat)
	_add_sphere(self, Vector3( 0.22,1.25,0.88), 0.09, eye_mat)
	# Rings
	var ring_mat := _mat_emit(_base_color, _base_color.lightened(0.3), 1.8)
	for i in range(3):
		var rm := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.88 + i*0.28; tor.outer_radius = 1.08 + i*0.28
		tor.rings = 20; tor.ring_segments = 8
		rm.mesh = tor; rm.material_override = ring_mat
		rm.position = Vector3(0,1.2,0)
		rm.rotation_degrees = Vector3(i*35, 0, i*50)
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rm)
	# Orbit lights
	for i in range(4):
		var ol := OmniLight3D.new()
		ol.light_color = _base_color; ol.light_energy = 2.5
		ol.omni_range = 7.0; ol.shadow_enabled = false
		add_child(ol); _orbit_lights.append(ol)


# ── HP Bar ─────────────────────────────────────────────────────────────────────
func _build_hp_bar() -> void:
	_hp_root = Node3D.new(); _hp_root.name = "HPBar"; add_child(_hp_root)
	_hp_root.position.y = _bar_height()

	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15,0.0,0.0)
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var bg_mi := MeshInstance3D.new()
	var bgm := QuadMesh.new(); bgm.size = Vector2(0.95,0.09)
	bg_mi.mesh = bgm; bg_mi.material_override = bg_mat
	bg_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_root.add_child(bg_mi)

	_hp_fill_mat = StandardMaterial3D.new()
	_hp_fill_mat.albedo_color = Color(0.1,0.85,0.2)
	_hp_fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_fill_mi = MeshInstance3D.new()
	var fm := QuadMesh.new(); fm.size = Vector2(0.94,0.075)
	_hp_fill_mi.mesh = fm; _hp_fill_mi.material_override = _hp_fill_mat
	_hp_fill_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_root.add_child(_hp_fill_mi)


func _bar_height() -> float:
	match type:
		"tank": return 2.55
		"boss": return 3.3
		_: return 2.15




# ── Physics Process ────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_do_death_anim(delta); return

	_tick_timers(delta)
	_update_hp_bar()
	_update_boss_orbit(delta)

	if not player or not is_instance_valid(player): return
	var dist := global_position.distance_to(player.global_position)

	if state == State.IDLE and dist < 52.0:
		state = State.CHASE

	match state:
		State.CHASE:     _do_chase(delta, dist)
		State.ATTACK:    _do_melee(delta, dist)
		State.EXPLODING: _do_exploding(delta, dist)


func _tick_timers(delta: float) -> void:
	if _flash > 0.0: _flash -= delta
	if _atk_cd > 0.0: _atk_cd -= delta
	if _shoot_cd > 0.0: _shoot_cd -= delta


func _update_hp_bar() -> void:
	if not _hp_root: return
	var frac := maxf(0.0, hp / max_hp)
	_hp_fill_mi.scale.x = frac
	_hp_fill_mi.position.x = (frac - 1.0) * 0.475
	_hp_fill_mat.albedo_color = Color(0.12,0.85,0.22) if frac > 0.4 else Color(0.9,0.38,0.1)
	# Flash white on hit
	if _flash > 0.0:
		var fl := clampf(_flash / 0.18, 0.0, 1.0)
		_body_mat.albedo_color = _base_color.lerp(Color.WHITE, fl * 0.88)
	else:
		_body_mat.albedo_color = _body_mat.albedo_color.lerp(_base_color, 0.20)


func _update_boss_orbit(delta: float) -> void:
	if type != "boss": return
	_boss_spiral_t += delta
	var rot := _boss_spiral_t
	for i in range(_orbit_lights.size()):
		var a := rot * 1.2 + (TAU / _orbit_lights.size()) * i
		_orbit_lights[i].position = Vector3(cos(a)*2.8, 1.2, sin(a)*2.8)
	# Phase transitions
	var frac := hp / max_hp
	if frac < 0.33 and _boss_phase < 2:
		_boss_phase = 2
		for ol: OmniLight3D in _orbit_lights: ol.light_color = Color(1.0,0.12,0.05)
		_body_mat.emission = Color(1.0,0.1,0.0); _body_mat.emission_energy_multiplier = 1.6
	elif frac < 0.66 and _boss_phase < 1:
		_boss_phase = 1
		for ol: OmniLight3D in _orbit_lights: ol.light_color = Color(1.0,0.5,0.1)
		_body_mat.emission = Color(1.0,0.5,0.0); _body_mat.emission_energy_multiplier = 0.9


# ── AI Behaviours ──────────────────────────────────────────────────────────────
func _do_chase(delta: float, dist: float) -> void:
	var engage := atk_range if shoot_range < 0.1 else shoot_range
	if dist <= atk_range:
		state = State.EXPLODING if type == "kamikaze" else State.ATTACK
		return
	if type == "kamikaze" and dist < 6.0:
		state = State.EXPLODING; return

	# Navigate — try NavigationAgent first, fall back to direct
	nav_agent.target_position = player.global_position
	var move_dir: Vector3
	if not nav_agent.is_navigation_finished():
		var next := nav_agent.get_next_path_position()
		move_dir = (next - global_position)
	else:
		# Direct movement fallback (always works)
		move_dir = (player.global_position - global_position)
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(move_dir.x, move_dir.z), delta * 9.0)
	else:
		velocity.x = lerpf(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 10.0)

	if not is_on_floor():
		velocity.y -= Balance.P3D_GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()

	# Ranged attack while chasing
	if shoot_range > 0.1 and dist <= shoot_range:
		_try_shoot(dist)


func _do_melee(delta: float, dist: float) -> void:
	if dist > atk_range * 2.0:
		state = State.CHASE; return
	_face_player(delta)
	if _atk_cd <= 0.0:
		_atk_cd = 1.5
		if player.has_method("apply_damage"):
			player.apply_damage(dmg)
		if _gm and _gm.has_method("on_player_damaged"):
			_gm.on_player_damaged(dmg)
	velocity.y = -0.5 if is_on_floor() else velocity.y - Balance.P3D_GRAVITY * delta
	velocity.x = lerpf(velocity.x, 0.0, delta * 10.0)
	velocity.z = lerpf(velocity.z, 0.0, delta * 10.0)
	move_and_slide()


func _do_exploding(delta: float, dist: float) -> void:
	_explode_timer -= delta
	# Pulse and rush player
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.18
	scale = Balance.ENEMIES3D[type]["scale"] * pulse
	_body_mat.emission_energy_multiplier = (1.6 - _explode_timer / 1.6) * 4.0

	var dir := (player.global_position - global_position)
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		velocity.x = dir.normalized().x * speed * 1.5
		velocity.z = dir.normalized().z * speed * 1.5
	velocity.y = -0.5 if is_on_floor() else velocity.y - Balance.P3D_GRAVITY * delta
	move_and_slide()

	if _explode_timer <= 0.0 or dist < atk_range:
		if _gm and _gm.has_method("create_explosion_3d"):
			_gm.create_explosion_3d(global_position, 5.0, dmg)
		_die()


func _try_shoot(dist: float) -> void:
	if _shoot_cd > 0.0: return
	_shoot_cd = 2.2 + randf() * 1.8
	if _laser_dot: _laser_dot.visible = true
	# Show laser dot briefly then fire
	if _gm and _gm.has_method("spawn_enemy_projectile"):
		var dir := (player.global_position - global_position + Vector3(0,0.8,0)).normalized()
		_gm.spawn_enemy_projectile(global_position + Vector3(0,1.3,0), dir, shoot_dmg, type)
	if type == "boss":
		_fire_boss_burst()
	var t := get_tree().create_timer(0.35)
	t.timeout.connect(func(): if is_instance_valid(self) and _laser_dot: _laser_dot.visible = false)


func _fire_boss_burst() -> void:
	if not _gm or not _gm.has_method("spawn_enemy_projectile"): return
	var count := 8 + _boss_phase * 4
	for i in range(count):
		var a := (TAU / count) * i + _boss_spiral_t * 0.6
		var dir := Vector3(cos(a), 0.0, sin(a)).normalized()
		_gm.spawn_enemy_projectile(
			global_position + Vector3(0,1.5,0), dir, shoot_dmg * 0.65, "boss_spiral"
		)


func _face_player(delta: float) -> void:
	var dir := player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 9.0)


func State_KAMIKAZE_CHECK() -> State:
	return State.EXPLODING if type == "kamikaze" else State.ATTACK


# ── Damage ─────────────────────────────────────────────────────────────────────
func take_damage(amount: float, _src: Node = null) -> void:
	if state == State.DEAD: return
	hp -= amount; _flash = 0.18
	if hp <= 0.0: hp = 0.0; _die()


func get_body_color() -> Color:
	return _base_color


func _die() -> void:
	if state == State.DEAD: return
	state = State.DEAD; _alive = false
	nav_agent.avoidance_enabled = false
	collision_layer = 0; collision_mask = 0
	velocity = Vector3.ZERO
	if _hp_root: _hp_root.visible = false
	emit_signal("died", self, reward, xp_reward, global_position)


func _do_death_anim(delta: float) -> void:
	_death_timer -= delta
	var t := clampf(1.0 - _death_timer / 0.55, 0.0, 1.0)
	scale = Balance.ENEMIES3D[type]["scale"] * (1.0 - t * 0.96)
	position.y = -t * 0.75
	if _death_timer <= 0.0: queue_free()


# ── Mesh helpers ───────────────────────────────────────────────────────────────
func _add_capsule(p: Node3D, pos: Vector3, r: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var cm := CapsuleMesh.new()
	cm.radius = r; cm.height = h; cm.radial_segments = 10; cm.rings = 4
	mi.mesh = cm; mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON; p.add_child(mi); return mi

func _add_box(p: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; p.add_child(mi); return mi

func _add_sphere(p: Node3D, pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var sm := SphereMesh.new()
	sm.radius = r; sm.height = r*2.0; sm.radial_segments = 8; sm.rings = 4
	mi.mesh = sm; mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; p.add_child(mi); return mi

func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col; m.roughness = rough; m.metallic = metal; return m

func _mat_emit(col: Color, emit: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col; m.emission_enabled = true
	m.emission = emit; m.emission_energy_multiplier = energy; m.roughness = 0.2; return m

func _mat_alpha(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1; m.metallic = 0.4; m.cull_mode = BaseMaterial3D.CULL_DISABLED; return m
