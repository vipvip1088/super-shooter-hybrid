## game_manager_3d.gd — 3D game orchestrator.
## NO typed class references (prevents cascade parse failures → gray screen).
extends Node3D

# ── Untyped module refs ────────────────────────────────────────────────────────
var world_gen        # WorldGenerator3D
var player           # PlayerController3D
var fx_manager       # FXManager3D
var audio_gen        # AudioGenerator3D
var hud              # HUD3D
var save_mgr         # SaveManager

# ── Enemy / projectile containers ─────────────────────────────────────────────
var enemies_node: Node3D
var proj_node: Node3D
var loot_node: Node3D

# ── Live data ─────────────────────────────────────────────────────────────────
var enemies: Array = []      # Array[EnemyAI3D]
var projectiles: Array = []  # Array[Dictionary]
var loot_items: Array = []   # Array[Dictionary]

# ── Player stats ───────────────────────────────────────────────────────────────
var p_money: int = 800
var p_xp: int = 0
var p_xp_to_next: int = 100
var p_level: int = 1
var p_kill_count: int = 0

# ── Perk flags (mirrors PlayerController3D for GM logic) ──────────────────────
var p_loot_mult: float = 1.0
var p_zone_resist: float = 0.0
var p_kill_bonus: int = 0

# ── Wave state ─────────────────────────────────────────────────────────────────
var wave: int = 0
var wave_timer: float = 0.0
var between_waves: bool = false
var buy_phase: bool = false
var buy_timer: float = 0.0
var enemies_this_wave: int = 0
var enemies_killed_wave: int = 0
var _spawn_queue: Array = []
var _spawn_timer: float = 0.0

# ── Zone state ─────────────────────────────────────────────────────────────────
var zone_center: Vector3 = Vector3.ZERO
var zone_radius: float = Balance.ZONE3D_START_R
var zone_target_radius: float = Balance.ZONE3D_START_R
var zone_phase_idx: int = 0
var zone_phase_timer: float = 0.0
var zone_cylinder: MeshInstance3D
var zone_mat: StandardMaterial3D
var zone_inner_mat: StandardMaterial3D

# ── Game flow ──────────────────────────────────────────────────────────────────
var running: bool = false
var game_over: bool = false


func _ready() -> void:
	_safe_build()


func _safe_build() -> void:
	# World
	var WG = load("res://scripts/world/world_generator_3d.gd")
	world_gen = WG.new()
	world_gen.name = "WorldGen"
	add_child(world_gen)
	world_gen.setup(self)
	world_gen.generate()

	# Containers
	enemies_node = Node3D.new(); enemies_node.name = "Enemies"; add_child(enemies_node)
	proj_node    = Node3D.new(); proj_node.name = "Projectiles"; add_child(proj_node)
	loot_node    = Node3D.new(); loot_node.name = "Loot"; add_child(loot_node)

	# Player
	var PC = load("res://scripts/player/player_controller_3d.gd")
	player = PC.new()
	player.name = "Player"
	player.position = Vector3(0, 0, 0)
	player.collision_layer = 4
	player.collision_mask = 1
	add_child(player)
	player.setup(self)
	player.took_damage.connect(_on_player_took_damage)
	player.died.connect(_on_player_died)

	# FX
	var FX = load("res://scripts/fx/fx_manager_3d.gd")
	fx_manager = FX.new()
	fx_manager.name = "FXManager"
	add_child(fx_manager)
	fx_manager.setup(self)

	# Audio
	var AG = load("res://scripts/audio/audio_generator_3d.gd")
	audio_gen = AG.new()
	audio_gen.name = "AudioGen"
	add_child(audio_gen)
	audio_gen.setup(self)

	# HUD
	var HUD = load("res://scripts/ui/hud_3d.gd")
	hud = HUD.new()
	hud.name = "HUD3D"
	add_child(hud)
	hud.setup(self)
	hud.move_input.connect(func(d): player.set_move_input(d) if player else null)
	hud.look_input.connect(func(d): player.add_look_delta(d) if player else null)
	hud.fire_held.connect(_on_fire_held)
	hud.reload_pressed.connect(_on_reload_pressed)
	hud.dash_pressed.connect(_on_dash_pressed)
	hud.ult_pressed.connect(_on_ult_pressed)
	hud.weapon_next.connect(func(): player.weapon_system.cycle_weapon(1) if player else null)
	hud.weapon_prev.connect(func(): player.weapon_system.cycle_weapon(-1) if player else null)
	hud.perk_chosen.connect(_on_perk_chosen)

	# Weapon system signals
	player.weapon_system.ammo_changed.connect(func(c, m): hud.update_ammo(c, m))
	player.weapon_system.fired.connect(_on_weapon_fired)
	player.weapon_system.hit_enemy.connect(_on_hit_enemy_fx)

	# Save manager
	var SM = load("res://scripts/core/save_manager.gd")
	save_mgr = SM.new()
	save_mgr.name = "SaveMgr"
	add_child(save_mgr)

	# Zone
	_build_zone()

	# Start
	_start_wave()
	running = true


# ── Zone ───────────────────────────────────────────────────────────────────────
func _build_zone() -> void:
	# Outer warning wall (large cylinder, inside-visible)
	zone_mat = StandardMaterial3D.new()
	zone_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.12)
	zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone_mat.emission_enabled = true
	zone_mat.emission = Color(0.2, 0.8, 1.0, 0.5)
	zone_mat.emission_energy_multiplier = 0.8
	zone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	zone_mat.roughness = 0.0

	var seg = 40
	zone_cylinder = MeshInstance3D.new()
	zone_cylinder.name = "ZoneCylinder"
	var cyl = CylinderMesh.new()
	cyl.top_radius = zone_radius
	cyl.bottom_radius = zone_radius
	cyl.height = Balance.ARENA_WALL_H * 1.5
	cyl.radial_segments = seg
	cyl.rings = 1
	zone_cylinder.mesh = cyl
	zone_cylinder.material_override = zone_mat
	zone_cylinder.position = Vector3(zone_center.x, Balance.ARENA_WALL_H * 0.75, zone_center.z)
	zone_cylinder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(zone_cylinder)

	if Balance.ZONE3D_PHASES.size() > 0:
		var ph: Dictionary = Balance.ZONE3D_PHASES[0]
		zone_target_radius = Balance.ZONE3D_START_R * ph["end_ratio"]
		zone_phase_timer = ph["duration"]


# ── Wave management ────────────────────────────────────────────────────────────
func _start_wave() -> void:
	wave += 1
	between_waves = false
	buy_phase = false
	enemies_killed_wave = 0

	var hp_scale := 1.0 + wave * Balance.HP3D_SCALE
	var types := _get_wave_enemy_types()
	enemies_this_wave = types.size()

	_spawn_queue = types.duplicate()
	_spawn_timer = 0.0

	hud.update_wave(wave, enemies_this_wave)
	hud.add_kill_feed("Wave %d starts!" % wave)


func _get_wave_enemy_types() -> Array:
	var count := Balance.WAVE3D_BASE + (wave - 1) * Balance.WAVE3D_STEP
	var result: Array = []
	var pool := ["rusher", "rusher", "rusher", "sniper_e", "tank", "kamikaze"]
	if wave >= Balance.BOSS3D_WAVE and wave % Balance.BOSS3D_WAVE == 0:
		result.append("boss")
		count = maxi(count - 2, 1)
	for i in range(count):
		result.append(pool[i % pool.size()])
	return result


func _spawn_enemy_from_queue() -> void:
	if _spawn_queue.is_empty():
		return
	var etype: String = _spawn_queue.pop_front()
	var spawn_pos: Vector3 = world_gen.get_random_spawn()
	var hp_mult := 1.0 + wave * Balance.HP3D_SCALE

	var EA = load("res://scripts/enemies/enemy_ai_3d.gd")
	var enemy = EA.new()
	enemy.name = "Enemy_%s_%d" % [etype, wave]
	enemy.position = spawn_pos
	enemies_node.add_child(enemy)
	enemy.setup(etype, self, player, hp_mult)
	enemy.died.connect(_on_enemy_died)
	enemies.append(enemy)


# ── Process ────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not running or game_over:
		return
	_update_spawn_queue(delta)
	_update_projectiles(delta)
	_update_loot(delta)
	_update_zone(delta)
	_update_hud()
	_check_wave_clear()


func _update_spawn_queue(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 0.8
		_spawn_enemy_from_queue()


func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		var node: Node3D = p.get("node")
		if not is_instance_valid(node):
			projectiles.remove_at(i)
			continue

		p["traveled"] += p["speed"] * delta
		var move := p["dir"] * p["speed"] * delta
		node.position += move

		# Check collision with enemies
		var hit := false
		if p.get("from_enemy", false):
			# Enemy projectile hits player
			if player and is_instance_valid(player):
				var d := node.global_position.distance_to(player.global_position)
				if d < 1.0:
					player.apply_damage(p["damage"])
					audio_gen.play_hurt()
					hit = true
		else:
			# Player projectile hits enemies
			for enemy in enemies:
				if not is_instance_valid(enemy):
					continue
				var d := node.global_position.distance_to(enemy.global_position)
				if d < 1.5:
					if p["aoe"] > 0.0:
						create_explosion_3d(node.global_position, p["aoe"], p["damage"])
					else:
						enemy.take_damage(p["damage"])
					hit = true
					break

		if hit or p["traveled"] >= p["max_range"]:
			if p["aoe"] > 0.0 and not p.get("from_enemy", false):
				create_explosion_3d(node.global_position, p["aoe"], p["damage"])
			node.queue_free()
			projectiles.remove_at(i)


func _update_loot(delta: float) -> void:
	for i in range(loot_items.size() - 1, -1, -1):
		var item: Dictionary = loot_items[i]
		var node: Node3D = item.get("node")
		if not is_instance_valid(node):
			loot_items.remove_at(i)
			continue
		item["timer"] -= delta
		# Float animation
		var bob := sin(Time.get_ticks_msec() * 0.003 + item["phase"]) * 0.12
		node.position.y = 0.5 + bob

		# Magnet pull
		if player and is_instance_valid(player):
			var d := node.global_position.distance_to(player.global_position)
			var mm: float = player.p_magnet_mult
			var magnet_r := 5.0 * mm
			if d < magnet_r:
				var dir := (player.global_position - node.global_position).normalized()
				var pull := lerpf(5.0, 18.0, 1.0 - d / maxf(magnet_r, 0.1))
				node.position += dir * pull * delta

			if d < 1.0:
				_collect_loot(item)
				node.queue_free()
				loot_items.remove_at(i)
				continue

		if item["timer"] <= 0.0:
			node.queue_free()
			loot_items.remove_at(i)


func _update_zone(delta: float) -> void:
	if zone_phase_idx >= Balance.ZONE3D_PHASES.size():
		return
	zone_phase_timer -= delta
	var ph: Dictionary = Balance.ZONE3D_PHASES[zone_phase_idx]

	# Shrink zone
	zone_radius = lerpf(zone_radius, zone_target_radius, delta * 0.4)
	_update_zone_cylinder()

	# Damage player outside zone
	if player and is_instance_valid(player):
		var d2d := Vector2(player.global_position.x, player.global_position.z)
		var zc2d := Vector2(zone_center.x, zone_center.z)
		var in_zone := d2d.distance_to(zc2d) <= zone_radius
		hud.set_zone_warning(not in_zone)
		if not in_zone:
			player.apply_damage(ph["damage"] * delta)

	if zone_phase_timer <= 0.0:
		zone_phase_idx += 1
		if zone_phase_idx < Balance.ZONE3D_PHASES.size():
			var next_ph: Dictionary = Balance.ZONE3D_PHASES[zone_phase_idx]
			zone_target_radius = Balance.ZONE3D_START_R * next_ph["end_ratio"]
			zone_phase_timer = next_ph["duration"]


func _update_zone_cylinder() -> void:
	if not zone_cylinder:
		return
	var mesh: CylinderMesh = zone_cylinder.mesh
	mesh.top_radius = zone_radius
	mesh.bottom_radius = zone_radius
	# Pulse glow
	var pulse := sin(Time.get_ticks_msec() * 0.003) * 0.15 + 0.8
	zone_mat.emission_energy_multiplier = pulse


func _update_hud() -> void:
	if not hud:
		return
	hud.update_hp(player.hp, player.max_hp)
	hud.shield = player.p_shield
	hud.update_xp(p_xp, p_xp_to_next, p_level)
	hud.update_money(p_money)
	hud.update_weapon(player.weapon_system.current_weapon)
	hud.update_reload(player.weapon_system.is_reloading, player.weapon_system.reload_progress)
	hud.update_dash_cd(player.dash_cd)
	hud.enemy_count = enemies.size()


func _check_wave_clear() -> void:
	if _spawn_queue.is_empty() and enemies.is_empty():
		if not between_waves:
			between_waves = true
			_on_wave_clear()


func _on_wave_clear() -> void:
	p_money += Balance.ROUND_SURVIVAL_BONUS
	hud.add_kill_feed("Wave %d cleared! +$%d" % [wave, Balance.ROUND_SURVIVAL_BONUS])
	audio_gen.play_levelup()
	# Brief pause then next wave
	var t = get_tree().create_timer(3.5)
	t.timeout.connect(_start_wave)


# ── Callbacks ──────────────────────────────────────────────────────────────────
func _on_enemy_died(enemy: Node3D, reward: int, xp: int, pos: Vector3) -> void:
	enemies.erase(enemy)
	p_money += int(reward * p_loot_mult)
	p_money += p_kill_bonus
	p_kill_count += 1
	if player and is_instance_valid(player) and player.p_vampire > 0.0:
		player.hp = minf(player.hp + player.p_vampire, player.max_hp)
	_add_xp(xp)
	_spawn_loot(pos)
	audio_gen.play_kill()
	hud.add_kill_feed("+$%d" % reward)
	hud.update_wave(wave, enemies.size())


func _on_player_took_damage(amount: float) -> void:
	audio_gen.play_hurt()
	if hud:
		hud.update_hp(player.hp, player.max_hp)


func _on_player_died() -> void:
	running = false
	game_over = true
	if save_mgr:
		save_mgr.save_run_result(wave, p_kill_count, 0)
	_show_game_over()


func _on_fire_held(state: bool) -> void:
	if not player or not is_instance_valid(player):
		return
	if state:
		player.weapon_system.try_fire()
		audio_gen.play_shoot(player.weapon_system.current_weapon)


func _on_reload_pressed() -> void:
	if player and is_instance_valid(player):
		player.weapon_system.start_reload()
		audio_gen.play_reload()


func _on_dash_pressed() -> void:
	if player and is_instance_valid(player):
		player.do_dash()
		audio_gen.play_dash()


func _on_ult_pressed() -> void:
	pass  # TODO: hero ultimates in next iteration


func _on_perk_chosen(perk_key: String) -> void:
	if not hud:
		return
	hud._show_perk = false
	var perk: Dictionary = Balance.PERKS.get(perk_key, {})
	var effect: String = perk.get("effect", "")
	var value: float = perk.get("value", 0.0)
	if not player or not is_instance_valid(player):
		return
	match effect:
		"max_hp":      player.max_hp += value; player.hp = minf(player.hp + value, player.max_hp)
		"speed_mult":  player.p_speed_mult *= value
		"loot_mult":   p_loot_mult *= value
		"zone_resist": p_zone_resist += value
		"kill_bonus":  p_kill_bonus += int(value)
		"vampire":     player.p_vampire += value
		"double_shot": player.p_double_shot = true
		"shield":      player.p_shield += value
		"explosive":   player.p_explosive_rds = true
		"magnet":      player.p_magnet_mult *= value
		"berserker":   player.p_last_stand = true
	hud.add_kill_feed("Perk: " + perk.get("name", perk_key))


func _on_hit_enemy_fx(enemy: Node3D, damage: float, pos: Vector3) -> void:
	if fx_manager:
		var col: Color = Balance.ENEMIES3D.get(
			enemy.get("type") if enemy.has_method("get") else "rusher", {}
		).get("color", Color(1.0, 0.3, 0.1))
		fx_manager.spawn_blood_hit(pos, col)
	audio_gen.play_hit_enemy()


func _on_weapon_fired(weapon_id: String, from: Vector3, dir: Vector3) -> void:
	if fx_manager:
		fx_manager.spawn_muzzle_flash(from, Balance.WEAPONS3D[weapon_id]["color"])
	# Hit scan: bullet decal
	if Balance.WEAPONS3D[weapon_id]["hitscan"] and fx_manager:
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 80.0, 1)
		var result := space.intersect_ray(q)
		if not result.is_empty():
			fx_manager.spawn_bullet_hole(result["position"], result["normal"])


# ── Player damaged by enemy direct call ───────────────────────────────────────
func on_player_damaged(amount: float) -> void:
	audio_gen.play_hurt()
	if hud:
		hud.update_hp(player.hp, player.max_hp)


# ── Surface hit (world) ────────────────────────────────────────────────────────
func on_hit_surface(pos: Vector3, normal: Vector3, _collider: Object) -> void:
	if fx_manager:
		fx_manager.spawn_hit(pos, normal)
		fx_manager.spawn_bullet_hole(pos, normal)


# ── Projectiles ────────────────────────────────────────────────────────────────
func spawn_projectile_3d(origin: Vector3, dir: Vector3, speed: float, max_range: float,
		damage: float, aoe: float, col: Color, weapon_id: String) -> void:
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 0.18; sm.height = 0.36
	mi.mesh = sm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = origin
	proj_node.add_child(mi)
	projectiles.append({
		"node": mi, "dir": dir, "speed": speed,
		"max_range": max_range, "traveled": 0.0,
		"damage": damage, "aoe": aoe,
		"from_enemy": false, "weapon": weapon_id,
	})


func spawn_enemy_projectile(origin: Vector3, dir: Vector3, damage: float, _type: String) -> void:
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new(); sm.radius = 0.14; sm.height = 0.28
	mi.mesh = sm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.1)
	mat.emission_enabled = true; mat.emission = Color(1.0, 0.2, 0.0)
	mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = origin
	proj_node.add_child(mi)
	projectiles.append({
		"node": mi, "dir": dir, "speed": 16.0,
		"max_range": 35.0, "traveled": 0.0,
		"damage": damage, "aoe": 0.0, "from_enemy": true,
	})


# ── Explosions ─────────────────────────────────────────────────────────────────
func create_explosion_3d(pos: Vector3, radius: float, damage: float) -> void:
	if fx_manager:
		fx_manager.spawn_explosion(pos, radius)
	audio_gen.play_explosion()
	if player and is_instance_valid(player):
		var d := pos.distance_to(player.global_position)
		if d < radius:
			var falloff := 1.0 - clampf(d / radius, 0.0, 1.0) * 0.5
			player.apply_damage(damage * falloff)
			player.add_camera_shake(1.2)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var d := pos.distance_to(enemy.global_position)
		if d < radius:
			var falloff := 1.0 - clampf(d / radius, 0.0, 1.0) * 0.5
			enemy.take_damage(damage * falloff)


func explode_barrel(barrel: Node3D) -> void:
	if not is_instance_valid(barrel):
		return
	var r: float = barrel.get_meta("explode_radius", 6.0)
	var d: float = barrel.get_meta("explode_damage", 80.0)
	create_explosion_3d(barrel.global_position, r, d)
	barrel.queue_free()


# ── Loot ───────────────────────────────────────────────────────────────────────
func _spawn_loot(pos: Vector3) -> void:
	var loot_types := [
		{"type": "money", "chance": 1.0,  "value": randi_range(40, 140)},
		{"type": "health","chance": 0.20, "value": 25},
		{"type": "ammo",  "chance": 0.35, "value": 1},
	]
	for lt in loot_types:
		if randf() < lt["chance"] * p_loot_mult:
			_spawn_loot_item(pos + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)),
				lt["type"], lt["value"])


func _spawn_loot_item(pos: Vector3, type: String, value: int) -> void:
	var mi = MeshInstance3D.new()
	var mesh: Mesh
	var col: Color
	match type:
		"money":
			mesh = SphereMesh.new()
			(mesh as SphereMesh).radius = 0.18; (mesh as SphereMesh).height = 0.36
			col = Color(1.0, 0.9, 0.0)
		"health":
			mesh = BoxMesh.new(); (mesh as BoxMesh).size = Vector3(0.28, 0.28, 0.28)
			col = Color(0.1, 0.9, 0.2)
		"ammo":
			mesh = CylinderMesh.new()
			(mesh as CylinderMesh).top_radius = 0.08; (mesh as CylinderMesh).bottom_radius = 0.10
			(mesh as CylinderMesh).height = 0.22
			col = Color(0.9, 0.85, 0.2)
		_:
			mesh = SphereMesh.new(); col = Color(0.7, 0.7, 0.7)
	mi.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.5, 0)
	loot_node.add_child(mi)
	loot_items.append({
		"node": mi, "type": type, "value": value,
		"timer": Balance.LOOT_DESPAWN_TIME,
		"phase": randf_range(0, TAU),
	})


func _collect_loot(item: Dictionary) -> void:
	if not player or not is_instance_valid(player):
		return
	match item["type"]:
		"money":  p_money += item["value"]
		"health": player.hp = minf(player.hp + item["value"], player.max_hp)
		"ammo":
			player.weapon_system.ammo = mini(
				player.weapon_system.ammo + player.weapon_system.max_ammo,
				player.weapon_system.max_ammo
			)
	audio_gen.play_pickup(item["type"])
	if fx_manager:
		fx_manager.spawn_pickup_sparkle(item["node"].global_position)


# ── XP / Level up ──────────────────────────────────────────────────────────────
func _add_xp(amount: int) -> void:
	p_xp += amount
	while p_xp >= p_xp_to_next and p_level < Balance.XP_PER_LEVEL.size():
		p_xp -= p_xp_to_next
		p_level += 1
		var next_idx := mini(p_level - 1, Balance.XP_PER_LEVEL.size() - 1)
		p_xp_to_next = Balance.XP_PER_LEVEL[next_idx]
		_trigger_level_up()


func _trigger_level_up() -> void:
	audio_gen.play_levelup()
	var keys: Array = Balance.PERK_KEYS.duplicate()
	keys.shuffle()
	var options := keys.slice(0, 3)
	if hud:
		hud.show_perk_choice(options)


# ── Game Over ──────────────────────────────────────────────────────────────────
func _show_game_over() -> void:
	if not hud:
		return
	hud.add_kill_feed("GAME OVER — Wave %d  Kills: %d" % [wave, p_kill_count])
	# Restart after delay
	var t = get_tree().create_timer(4.0)
	t.timeout.connect(func(): get_tree().reload_current_scene())


# ── Continuous fire in _process ────────────────────────────────────────────────
var _fire_active: bool = false

func _on_fire_held_state(state: bool) -> void:
	_fire_active = state
