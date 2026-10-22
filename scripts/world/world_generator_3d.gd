class_name WorldGenerator3D
extends Node3D

signal generation_complete

var nav_region: NavigationRegion3D
var spawn_points: Array = []
var cover_positions: Array = []
var _gm: Node


func setup(game_manager: Node) -> void:
	_gm = game_manager


func generate() -> void:
	_build_environment()
	_build_ground()
	_build_walls()
	_build_cover()
	_build_nav_mesh()
	_build_spawn_points()
	_build_lighting()
	emit_signal("generation_complete")


# ── Environment ────────────────────────────────────────────────────────────────
func _build_environment() -> void:
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_color = Color(0.18, 0.20, 0.25)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_light_color = Color(0.10, 0.12, 0.18)
	env_node.environment = env
	add_child(env_node)


# ── Ground ─────────────────────────────────────────────────────────────────────
func _build_ground() -> void:
	var body = StaticBody3D.new()
	body.name = "Ground"
	add_child(body)

	var mesh_inst = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(Balance.ARENA_SIZE, Balance.ARENA_SIZE)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	mesh_inst.mesh = plane
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.15, 0.12)
	mat.roughness = 0.95
	mat.metallic = 0.0
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(Balance.ARENA_SIZE, 0.2, Balance.ARENA_SIZE)
	col.shape = box
	col.position.y = -0.1
	body.add_child(col)

	# Grid lines baked as thin boxes
	var grid_mat = StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.22, 0.28, 0.22, 0.4)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mat.roughness = 1.0
	var step := 8.0
	var half := Balance.ARENA_HALF
	var x := -half
	while x <= half:
		_add_grid_line(body, Vector3(x, 0.01, 0), Vector3(0.04, 0.01, Balance.ARENA_SIZE), grid_mat)
		x += step
	var z := -half
	while z <= half:
		_add_grid_line(body, Vector3(0, 0.01, z), Vector3(Balance.ARENA_SIZE, 0.01, 0.04), grid_mat)
		z += step


func _add_grid_line(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ── Perimeter walls ────────────────────────────────────────────────────────────
func _build_walls() -> void:
	var h := Balance.ARENA_HALF
	var wh := Balance.ARENA_WALL_H
	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.20, 0.24, 0.20)
	wall_mat.roughness = 0.9
	var edge_mat = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.28, 0.90, 0.35)
	edge_mat.emission_enabled = true
	edge_mat.emission = Color(0.10, 0.60, 0.15)
	edge_mat.emission_energy_multiplier = 0.8
	edge_mat.roughness = 0.3
	var thickness := 1.0
	var walls := [
		{"pos": Vector3(0, wh*0.5, -h), "size": Vector3(Balance.ARENA_SIZE + thickness*2, wh, thickness)},
		{"pos": Vector3(0, wh*0.5,  h), "size": Vector3(Balance.ARENA_SIZE + thickness*2, wh, thickness)},
		{"pos": Vector3(-h, wh*0.5, 0), "size": Vector3(thickness, wh, Balance.ARENA_SIZE)},
		{"pos": Vector3( h, wh*0.5, 0), "size": Vector3(thickness, wh, Balance.ARENA_SIZE)},
	]
	for w in walls:
		var body = StaticBody3D.new()
		body.name = "Wall"
		add_child(body)
		_add_box_mesh(body, w["pos"], w["size"], wall_mat)
		# Glowing top edge strip
		var edge_size: Vector3 = w["size"]
		edge_size.y = 0.15
		_add_box_mesh_no_collider(body,
			Vector3(w["pos"].x, wh + 0.07, w["pos"].z), edge_size, edge_mat)


func _add_box_mesh(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var body: StaticBody3D
	if parent is StaticBody3D:
		body = parent
	else:
		body = parent as StaticBody3D

	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(mi)

	var col = CollisionShape3D.new()
	var bs = BoxShape3D.new()
	bs.size = size
	col.shape = bs
	col.position = pos
	parent.add_child(col)


func _add_box_mesh_no_collider(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ── Cover objects ──────────────────────────────────────────────────────────────
func _build_cover() -> void:
	cover_positions.clear()
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	var count := rng.randi_range(Balance.COVER_MIN, Balance.COVER_MAX)
	var half := Balance.ARENA_HALF - 5.0
	var min_dist_sq := 25.0   # 5m minimum between covers
	var min_player_sq := 64.0 # 8m from center (player spawn)

	for _i in range(count * 8):
		if cover_positions.size() >= count:
			break
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var pos := Vector3(x, 0.0, z)
		if pos.length_squared() < min_player_sq:
			continue
		var too_close := false
		for existing in cover_positions:
			if pos.distance_squared_to(existing) < min_dist_sq:
				too_close = true; break
		if too_close:
			continue
		cover_positions.append(pos)
		_spawn_cover_at(pos, rng)


func _spawn_cover_at(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var kind := rng.randi_range(0, 4)
	match kind:
		0: _make_crate(pos, rng)
		1: _make_column(pos, rng)
		2: _make_l_wall(pos, rng)
		3: _make_barrel(pos, rng)
		4: _make_rubble(pos, rng)


func _make_crate(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var size_v := rng.randf_range(1.2, 2.4)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.36, 0.18)
	mat.roughness = 0.85
	var body = StaticBody3D.new()
	body.name = "CoverCrate"
	body.add_to_group("nav_obstacle")
	add_child(body)
	var s := Vector3(size_v, size_v, size_v)
	_add_box_mesh(body, pos + Vector3(0, size_v * 0.5, 0), s, mat)
	# Metal edge
	var edge_mat = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.55, 0.55, 0.55)
	edge_mat.metallic = 0.8
	edge_mat.roughness = 0.4
	for corner in [Vector3(1,1,1),Vector3(-1,1,1),Vector3(1,1,-1),Vector3(-1,1,-1)]:
		var cm = MeshInstance3D.new()
		var bm2 = BoxMesh.new()
		bm2.size = Vector3(0.08, size_v + 0.05, 0.08)
		cm.mesh = bm2
		cm.material_override = edge_mat
		cm.position = pos + Vector3(corner.x * size_v * 0.5, size_v * 0.5, corner.z * size_v * 0.5)
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(cm)


func _make_column(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(0.4, 0.8)
	var h := rng.randf_range(2.5, 5.0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.32, 0.30)
	mat.roughness = 0.8
	var body = StaticBody3D.new()
	body.name = "CoverColumn"
	body.add_to_group("nav_obstacle")
	add_child(body)
	var mi = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = r; cyl.bottom_radius = r; cyl.height = h
	mi.mesh = cyl; mi.material_override = mat
	mi.position = pos + Vector3(0, h * 0.5, 0)
	body.add_child(mi)
	var col = CollisionShape3D.new()
	var cs = CylinderShape3D.new()
	cs.radius = r; cs.height = h
	col.shape = cs; col.position = pos + Vector3(0, h * 0.5, 0)
	body.add_child(col)


func _make_l_wall(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.30, 0.28)
	mat.roughness = 0.9
	var body = StaticBody3D.new()
	body.name = "CoverLWall"
	body.add_to_group("nav_obstacle")
	add_child(body)
	var rot_y := rng.randf_range(0, TAU)
	body.rotation.y = rot_y
	var h := 2.2
	# Two wall segments forming an L
	_add_box_mesh(body, pos + Vector3(0, h*0.5, 0),       Vector3(4.0, h, 0.4), mat)
	_add_box_mesh(body, pos + Vector3(-1.8, h*0.5, -1.8), Vector3(0.4, h, 3.6), mat)


func _make_barrel(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.2, 0.1)
	mat.roughness = 0.5
	mat.metallic = 0.4
	var body = StaticBody3D.new()
	body.name = "ExplosiveBarrel"
	body.add_to_group("explosive_barrel")
	body.add_to_group("nav_obstacle")
	add_child(body)
	var mi = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.32; cyl.bottom_radius = 0.35; cyl.height = 0.9
	mi.mesh = cyl; mi.material_override = mat
	mi.position = pos + Vector3(0, 0.45, 0)
	body.add_child(mi)
	# Danger stripe
	var stripe_mat = StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(1.0, 0.9, 0.0)
	stripe_mat.emission_enabled = true
	stripe_mat.emission = Color(0.6, 0.5, 0.0)
	var sm = MeshInstance3D.new()
	var cm2 = CylinderMesh.new()
	cm2.top_radius = 0.33; cm2.bottom_radius = 0.36; cm2.height = 0.12
	sm.mesh = cm2; sm.material_override = stripe_mat
	sm.position = pos + Vector3(0, 0.45, 0)
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(sm)
	var col = CollisionShape3D.new()
	var cs = CylinderShape3D.new()
	cs.radius = 0.36; cs.height = 0.9
	col.shape = cs; col.position = pos + Vector3(0, 0.45, 0)
	body.add_child(col)
	# Store HP
	body.set_meta("hp", 60.0)
	body.set_meta("explode_radius", 6.0)
	body.set_meta("explode_damage", 80.0)


func _make_rubble(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.30, 0.25)
	mat.roughness = 1.0
	var body = StaticBody3D.new()
	body.name = "CoverRubble"
	body.add_to_group("nav_obstacle")
	add_child(body)
	for i in range(rng.randi_range(3, 6)):
		var offset := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
		var sz := Vector3(
			rng.randf_range(0.4, 1.0),
			rng.randf_range(0.3, 0.8),
			rng.randf_range(0.4, 1.0)
		)
		_add_box_mesh(body, pos + offset + Vector3(0, sz.y * 0.5, 0), sz, mat)


# ── Navigation mesh (flat arena + NavigationObstacle3D per cover) ──────────────
func _build_nav_mesh() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)

	var nm = NavigationMesh.new()
	nm.cell_size = Balance.NAV_CELL_SIZE
	nm.cell_height = 0.25
	nm.agent_height = 1.8
	nm.agent_radius = 0.5
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 45.0
	nm.filter_walkable_low_height_spans = true

	# Flat arena vertices (two triangles = one quad)
	var h := Balance.ARENA_HALF - 1.0
	nm.vertices = PackedVector3Array([
		Vector3(-h, 0.0, -h), Vector3( h, 0.0, -h),
		Vector3( h, 0.0,  h), Vector3(-h, 0.0,  h),
	])
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	nm.add_polygon(PackedInt32Array([0, 2, 3]))
	nav_region.navigation_mesh = nm

	# Dynamic obstacles around cover objects
	for cp in cover_positions:
		var obs = NavigationObstacle3D.new()
		obs.radius = 1.8
		obs.height = 3.0
		obs.avoidance_enabled = true
		obs.position = cp
		nav_region.add_child(obs)


# ── Spawn points (ring around arena edge) ─────────────────────────────────────
func _build_spawn_points() -> void:
	spawn_points.clear()
	var count := 16
	var r := Balance.ARENA_HALF - 3.0
	for i in range(count):
		var angle := (TAU / count) * i
		spawn_points.append(Vector3(cos(angle) * r, 0.0, sin(angle) * r))


# ── Directional lighting ───────────────────────────────────────────────────────
func _build_lighting() -> void:
	var sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, 30.0, 0.0)
	sun.light_color = Color(0.95, 0.92, 0.85)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

	# Ambient fill from below
	var fill = OmniLight3D.new()
	fill.name = "AmbientFill"
	fill.position = Vector3(0, 0.5, 0)
	fill.light_color = Color(0.15, 0.25, 0.35)
	fill.light_energy = 0.6
	fill.omni_range = Balance.ARENA_SIZE
	fill.shadow_enabled = false
	add_child(fill)


func get_random_spawn() -> Vector3:
	if spawn_points.is_empty():
		return Vector3(Balance.ARENA_HALF - 5.0, 0.0, 0.0)
	return spawn_points[randi() % spawn_points.size()]
