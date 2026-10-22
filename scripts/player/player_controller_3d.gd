class_name PlayerController3D
extends CharacterBody3D

signal took_damage(amount: float)
signal died
signal dash_used

# ── State ──────────────────────────────────────────────────────────────────────
var hp: float
var max_hp: float
var speed: float
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_dir: Vector3 = Vector3.ZERO
var dash_cd: float = 0.0
var invincible: float = 0.0
var p_shield: float = 0.0

# ── Perks ──────────────────────────────────────────────────────────────────────
var p_dmg_mult: float = 1.0
var p_speed_mult: float = 1.0
var p_vampire: float = 0.0
var p_double_shot: bool = false
var p_explosive_rds: bool = false
var p_magnet_mult: float = 1.0
var p_last_stand: bool = false

# ── Input (set by HUD) ─────────────────────────────────────────────────────────
var move_dir: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO
var fire_held: bool = false
var is_sniping: bool = false

# ── Camera ─────────────────────────────────────────────────────────────────────
var cam_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var cam_yaw: float = 0.0
var cam_pitch: float = Balance.CAM_PITCH_DEF
var cam_shake: float = 0.0
var _target_fov: float = Balance.CAM_FOV_DEF
var _cur_fov: float = Balance.CAM_FOV_DEF

# ── Visuals ────────────────────────────────────────────────────────────────────
var _body_mesh: MeshInstance3D
var _body_mat: StandardMaterial3D
var _weapon_anchor: Node3D
var _dash_trail: Array = []

# ── Refs ───────────────────────────────────────────────────────────────────────
var weapon_system  # WeaponSystem3D
var _gm: Node


func setup(game_manager: Node) -> void:
	_gm = game_manager
	hp = Balance.P3D_MAX_HP
	max_hp = Balance.P3D_MAX_HP
	speed = Balance.P3D_SPEED
	_build_mesh()
	_setup_camera()
	var WS = load("res://scripts/player/weapon_system_3d.gd")
	weapon_system = WS.new()
	weapon_system.name = "WeaponSystem3D"
	add_child(weapon_system)
	weapon_system.setup(game_manager, self)


# ── Mesh assembly ──────────────────────────────────────────────────────────────
func _build_mesh() -> void:
	# Collision
	var col = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = Balance.P3D_RADIUS
	cap.height = Balance.P3D_HEIGHT
	col.shape = cap
	col.position.y = Balance.P3D_HEIGHT * 0.5
	add_child(col)

	# Body (capsule)
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	var body_cap = CapsuleMesh.new()
	body_cap.radius = 0.36
	body_cap.height = 1.5
	_body_mesh.mesh = body_cap
	_body_mesh.position.y = 0.92
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.20, 0.55, 1.0)
	_body_mat.roughness = 0.55
	_body_mat.metallic = 0.1
	_body_mesh.material_override = _body_mat
	_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_body_mesh)

	# Head
	var head_mi = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.20; sphere.height = 0.40
	sphere.radial_segments = 10; sphere.rings = 6
	head_mi.mesh = sphere
	head_mi.position.y = 1.82
	var head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.92, 0.78, 0.62)
	head_mi.material_override = head_mat
	head_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head_mi)

	# Helmet
	var helm_mi = MeshInstance3D.new()
	var helm_sphere = SphereMesh.new()
	helm_sphere.radius = 0.225; helm_sphere.height = 0.28
	helm_sphere.radial_segments = 10; helm_sphere.rings = 5
	helm_mi.mesh = helm_sphere
	helm_mi.position = Vector3(0, 1.92, 0)
	var helm_mat = StandardMaterial3D.new()
	helm_mat.albedo_color = Color(0.15, 0.20, 0.30)
	helm_mat.roughness = 0.4; helm_mat.metallic = 0.3
	helm_mi.material_override = helm_mat
	helm_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(helm_mi)

	# Weapon anchor (in front of camera, camera-relative)
	_weapon_anchor = Node3D.new()
	_weapon_anchor.name = "WeaponAnchor"
	add_child(_weapon_anchor)


# ── Camera setup ───────────────────────────────────────────────────────────────
func _setup_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	cam_pivot.position.y = 1.45
	add_child(cam_pivot)

	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.spring_length = Balance.CAM_SPRING
	spring_arm.collision_mask = 1
	spring_arm.rotation_degrees.x = cam_pitch
	cam_pivot.add_child(spring_arm)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = _cur_fov
	camera.near = 0.1
	camera.far = 200.0
	spring_arm.add_child(camera)


# ── Physics ────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_update_camera(delta)
	_move(delta)
	_update_weapon_anchor()
	_update_visuals(delta)
	move_and_slide()


func _update_timers(delta: float) -> void:
	if invincible > 0.0:
		invincible -= delta
	if dash_cd > 0.0:
		dash_cd -= delta
	if cam_shake > 0.0:
		cam_shake = maxf(0.0, cam_shake - delta * Balance.CAM_SHAKE_DECAY)


func _move(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= Balance.P3D_GRAVITY * delta
	else:
		velocity.y = -0.5

	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_dir.x * (Balance.P3D_DASH_DIST / Balance.P3D_DASH_DUR)
		velocity.z = dash_dir.z * (Balance.P3D_DASH_DIST / Balance.P3D_DASH_DUR)
		if dash_timer <= 0.0:
			is_dashing = false
		return

	var cur_speed := speed * p_speed_mult
	if p_last_stand and hp < max_hp * 0.20:
		cur_speed *= 1.30

	# Camera-relative movement
	var fwd := -cam_pivot.global_transform.basis.z
	var rgt :=  cam_pivot.global_transform.basis.x
	fwd.y = 0.0; if fwd.length_squared() > 0.001: fwd = fwd.normalized()
	rgt.y = 0.0; if rgt.length_squared() > 0.001: rgt = rgt.normalized()
	var wish := fwd * move_dir.y + rgt * move_dir.x
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	velocity.x = wish.x * cur_speed
	velocity.z = wish.z * cur_speed

	# Face movement direction smoothly
	if wish.length_squared() > 0.04:
		var target_y := atan2(wish.x, wish.z)
		rotation.y = lerp_angle(rotation.y, target_y, delta * 12.0)


func _update_camera(delta: float) -> void:
	# Horizontal
	cam_yaw -= look_delta.x * 0.0025
	cam_pivot.rotation.y = cam_yaw
	# Vertical
	cam_pitch = clampf(cam_pitch - look_delta.y * 0.0025 * (180.0 / PI), -75.0, -5.0)
	spring_arm.rotation_degrees.x = cam_pitch
	look_delta = Vector2.ZERO

	# Sniper zoom smooth
	if is_sniping:
		_target_fov = Balance.CAM_FOV_SNIPE
		spring_arm.spring_length = lerpf(spring_arm.spring_length, 1.5, delta * 8.0)
	else:
		_target_fov = Balance.CAM_FOV_DEF
		spring_arm.spring_length = lerpf(spring_arm.spring_length, Balance.CAM_SPRING, delta * 6.0)
	_cur_fov = lerpf(_cur_fov, _target_fov, delta * 8.0)
	camera.fov = _cur_fov

	# Camera shake offset
	if cam_shake > 0.0:
		camera.position = Vector3(
			randf_range(-1.0, 1.0) * cam_shake * 0.06,
			randf_range(-1.0, 1.0) * cam_shake * 0.06,
			0.0
		)
	else:
		camera.position = Vector3.ZERO


func _update_weapon_anchor() -> void:
	# Weapon floats right of camera in world space
	var cam_basis := camera.global_transform.basis
	_weapon_anchor.global_position = (
		camera.global_position
		+ cam_basis.x * 0.25
		- cam_basis.y * 0.18
		+ cam_basis.z * (-0.5)
	)
	_weapon_anchor.global_rotation = camera.global_rotation


func _update_visuals(delta: float) -> void:
	# Body color flash on damage
	var target_c := Color(0.20, 0.55, 1.0)
	if invincible > 0.0:
		var fl := sin(Time.get_ticks_msec() * 0.04) * 0.5 + 0.5
		target_c = target_c.lerp(Color.WHITE, fl * 0.6)
	_body_mat.albedo_color = _body_mat.albedo_color.lerp(target_c, delta * 10.0)

	# Dash trail spheres
	_manage_dash_trail(delta)


func _manage_dash_trail(delta: float) -> void:
	if is_dashing:
		var trail_mi = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.3; sm.height = 0.6
		trail_mi.mesh = sm
		var tmat = StandardMaterial3D.new()
		tmat.albedo_color = Color(0.3, 0.6, 1.0, 0.5)
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.emission_enabled = true
		tmat.emission = Color(0.2, 0.4, 1.0)
		tmat.emission_energy_multiplier = 0.5
		trail_mi.material_override = tmat
		trail_mi.position = global_position + Vector3(0, 0.9, 0)
		trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(trail_mi)
		_dash_trail.append({"node": trail_mi, "life": 0.25})

	for i in range(_dash_trail.size() - 1, -1, -1):
		var entry = _dash_trail[i]
		entry["life"] -= delta
		if entry["life"] <= 0.0:
			entry["node"].queue_free()
			_dash_trail.remove_at(i)
		else:
			var a := entry["life"] / 0.25
			var m: StandardMaterial3D = entry["node"].material_override
			if m:
				m.albedo_color.a = a * 0.5


# ── Public API ─────────────────────────────────────────────────────────────────
func apply_damage(amount: float) -> void:
	if invincible > 0.0:
		return
	var real_dmg := amount
	if p_shield > 0.0:
		var absorbed := minf(p_shield, real_dmg)
		p_shield -= absorbed
		real_dmg -= absorbed
	if real_dmg <= 0.0:
		return
	hp -= real_dmg
	invincible = 0.25
	add_camera_shake(0.5)
	emit_signal("took_damage", real_dmg)
	if hp <= 0.0:
		hp = 0.0
		emit_signal("died")


func add_camera_shake(intensity: float) -> void:
	cam_shake = maxf(cam_shake, intensity)


func do_dash() -> void:
	if is_dashing or dash_cd > 0.0:
		return
	is_dashing = true
	dash_timer = Balance.P3D_DASH_DUR
	dash_cd = Balance.P3D_DASH_CD
	# Dash in move direction or forward
	var fwd := -cam_pivot.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001: fwd = fwd.normalized()
	if move_dir.length_squared() > 0.04:
		var rgt := cam_pivot.global_transform.basis.x
		rgt.y = 0.0; if rgt.length_squared() > 0.001: rgt = rgt.normalized()
		dash_dir = (fwd * move_dir.y + rgt * move_dir.x).normalized()
	else:
		dash_dir = fwd
	invincible = Balance.P3D_DASH_DUR + 0.15
	emit_signal("dash_used")


func get_aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func get_camera_origin() -> Vector3:
	return camera.global_position
