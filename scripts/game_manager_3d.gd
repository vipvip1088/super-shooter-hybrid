## game_manager_3d.gd — 3D game orchestrator.
## NO typed user-class references (no cascade parse failures → no gray screen).
extends Node3D

# ── Untyped module refs ────────────────────────────────────────────────────────
var world_gen
var player
var fx_manager
var audio_gen
var hud
var save_mgr
var dmg_numbers   # DamageNumbers3D

# ── Containers ─────────────────────────────────────────────────────────────────
var enemies_node: Node3D
var proj_node: Node3D
var loot_node: Node3D

# ── Live arrays ────────────────────────────────────────────────────────────────
var enemies: Array = []
var projectiles: Array = []
var loot_items: Array = []

# ── Economy / meta ─────────────────────────────────────────────────────────────
var p_money: int = 800
var p_xp: int = 0
var p_xp_to_next: int = 100
var p_level: int = 1
var p_kill_count: int = 0
var p_score: int = 0
var p_loot_mult: float = 1.0
var p_zone_resist: float = 0.0
var p_kill_bonus: int = 0
var _combo: int = 0
var _combo_timer: float = 0.0
const COMBO_WINDOW := 4.0

# ── Wave state ─────────────────────────────────────────────────────────────────
var wave: int = 0
var between_waves: bool = false
var between_timer: float = 0.0
const BETWEEN_WAVE_TIME := 4.0
var _spawn_queue: Array = []
var _spawn_timer: float = 0.0
const SPAWN_INTERVAL := 0.7

# ── Zone ───────────────────────────────────────────────────────────────────────
var zone_center: Vector3 = Vector3.ZERO
var zone_radius: float = Balance.ZONE3D_START_R
var zone_target_radius: float = Balance.ZONE3D_START_R
var zone_phase_idx: int = 0
var zone_phase_timer: float = 0.0
var _zone_cylinder: MeshInstance3D
var _zone_mat: StandardMaterial3D
var _zone_warn_light: OmniLight3D

# ── Fire state ─────────────────────────────────────────────────────────────────
var _fire_active: bool = false

# ── Flow ───────────────────────────────────────────────────────────────────────
var running: bool = false
var game_over: bool = false


func _ready() -> void:
	_safe_build()


# ── Construction ───────────────────────────────────────────────────────────────
func _safe_build() -> void:
	# World first
	var WG = load("res://scripts/world/world_generator_3d.gd")
	world_gen = WG.new(); world_gen.name = "WorldGen"
	add_child(world_gen)
	world_gen.setup(self)
	world_gen.generate()

	# Containers
	enemies_node = Node3D.new(); enemies_node.name = "Enemies"; add_child(enemies_node)
	proj_node    = Node3D.new(); proj_node.name    = "Projs";   add_child(proj_node)
	loot_node    = Node3D.new(); loot_node.name    = "Loot";    add_child(loot_node)

	# Player
	var PC = load("res://scripts/player/player_controller_3d.gd")
	player = PC.new(); player.name = "Player"
	player.position = Vector3(0, 0, 2)
	player.collision_layer = 4; player.collision_mask = 1
	add_child(player)
	player.setup(self)
	player.took_damage.connect(_on_player_took_damage)
	player.died.connect(_on_player_died)

	# FX
	var FX = load("res://scripts/fx/fx_manager_3d.gd")
	fx_manager = FX.new(); fx_manager.name = "FX"; add_child(fx_manager)
	fx_manager.setup(self)

	# Audio
	var AG = load("res://scripts/audio/audio_generator_3d.gd")
	audio_gen = AG.new(); audio_gen.name = "Audio"; add_child(audio_gen)
	audio_gen.setup(self)

	# Damage numbers
	var DN = load("res://scripts/core/damage_numbers.gd")
	dmg_numbers = DN.new(); dmg_numbers.name = "DmgNumbers"; add_child(dmg_numbers)

	# HUD
	var HUD = load("res://scripts/ui/hud_3d.gd")
	hud = HUD.new(); hud.name = "HUD3D"; add_child(hud)
	hud.setup(self)
	_connect_hud()

	# Save
	var SM = load("res://scripts/core/save_manager.gd")
	save_mgr = SM.new(); save_mgr.name = "SaveMgr"; add_child(save_mgr)

	# Zone cylinder
	_build_zone_cylinder()

	# Wait one physics frame for NavigationServer3D to register the nav region
	await get_tree().physics_frame

	running = true
	_start_wave()


func _connect_hud() -> void:
	hud.move_input.connect(   func(d):    if player: player.set_move_input(d))
	hud.look_input.connect(   func(d):    if player: player.add_look_delta(d))
	hud.fire_held.connect(    _on_fire_held)
	hud.reload_pressed.connect(_on_reload_pressed)
	hud.dash_pressed.connect( _on_dash_pressed)
	hud.ult_pressed.connect(  _on_ult_pressed)
	hud.weapon_next.connect(  func(): if player: player.weapon_system.cycle_weapon(1))
	hud.weapon_prev.connect(  func(): if player: player.weapon_system.cycle_weapon(-1))
	hud.perk_chosen.connect(  _on_perk_chosen)
	hud.shop_buy.connect(     _on_shop_buy)
	# Weapon signals → audio + FX
	player.weapon_system.ammo_changed.connect(func(c,m): hud.update_ammo(c, m))
	player.weapon_system.fired.connect(_on_weapon_fired)
	player.weapon_system.hit_enemy.connect(_on_hit_enemy_fx)
	player.weapon_system.empty_clicked.connect(func(): audio_gen.play_empty())


# ── Zone cylinder ──────────────────────────────────────────────────────────────
func _build_zone_cylinder() -> void:
	_zone_mat = StandardMaterial3D.new()
	_zone_mat.albedo_color        = Color(0.2, 0.85, 1.0, 0.13)
	_zone_mat.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_mat.emission_enabled    = true
	_zone_mat.emission            = Color(0.2, 0.85, 1.0)
	_zone_mat.emission_energy_multiplier = 0.9
	_zone_mat.cull_mode           = BaseMaterial3D.CULL_DISABLED
	_zone_mat.roughness           = 0.0

	_zone_cylinder = MeshInstance3D.new()
	_zone_cylinder.name = "ZoneWall"
	var cyl := CylinderMesh.new()
	cyl.top_radius    = zone_radius
	cyl.bottom_radius = zone_radius
	cyl.height        = Balance.ARENA_WALL_H * 1.6
	cyl.radial_segments = 48; cyl.rings = 1
	_zone_cylinder.mesh = cyl
	_zone_cylinder.material_override = _zone_mat
	_zone_cylinder.position = Vector3(0, Balance.ARENA_WALL_H * 0.8, 0)
	_zone_cylinder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_zone_cylinder)

	_zone_warn_light = OmniLight3D.new()
	_zone_warn_light.light_color = Color(1.0, 0.2, 0.1)
	_zone_warn_light.light_energy = 0.0
	_zone_warn_light.omni_range = 8.0
	_zone_warn_light.shadow_enabled = false
	add_child(_zone_warn_light)

	if Balance.ZONE3D_PHASES.size() > 0:
		var ph: Dictionary = Balance.ZONE3D_PHASES[0]
		zone_target_radius = Balance.ZONE3D_START_R * float(ph["end_ratio"])
		zone_phase_timer   = float(ph["duration"])


# ── Wave management ────────────────────────────────────────────────────────────
func _start_wave() -> void:
	wave += 1
	between_waves = false
	var types := _get_wave_enemy_types()
	_spawn_queue = types.duplicate()
	_spawn_timer = 0.0
	hud.update_wave(wave, _spawn_queue.size() + enemies.size())
	hud.add_kill_feed("── Wave %d ──" % wave)
	audio_gen.play_levelup()

	# Spawn 3 enemies immediately at wave start
	for _i in range(mini(3, _spawn_queue.size())):
		_spawn_next_enemy()


func _get_wave_enemy_types() -> Array:
	var count := Balance.WAVE3D_BASE + (wave - 1) * Balance.WAVE3D_STEP
	var result: Array = []
	if wave >= Balance.BOSS3D_WAVE and wave % Balance.BOSS3D_WAVE == 0:
		result.append("boss")
		count = maxi(count - 3, 1)
	var pool := ["rusher","rusher","rusher","sniper_e","tank","kamikaze","rusher","sniper_e"]
	for i in range(count):
		result.append(pool[i % pool.size()])
	result.shuffle()
	return result


func _spawn_next_enemy() -> void:
	if _spawn_queue.is_empty() or not world_gen:
		return
	var etype: String = _spawn_queue.pop_front()
	var spawn_pos: Vector3 = world_gen.get_random_spawn()
	var hp_mult := 1.0 + wave * Balance.HP3D_SCALE

	var EA = load("res://scripts/enemies/enemy_ai_3d.gd")
	var enemy = EA.new()
	enemy.name = "E_%s_%d_%d" % [etype, wave, enemies.size()]
	enemy.position = spawn_pos
	enemies_node.add_child(enemy)
	enemy.setup(etype, self, player, hp_mult)
	enemy.died.connect(_on_enemy_died)
	enemies.append(enemy)
	hud.update_wave(wave, enemies.size() + _spawn_queue.size())


# ── Main loop ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not running:
		return

	# ── Continuous fire ──────────────────────────────────────────────────────
	if _fire_active and player and is_instance_valid(player) and not game_over:
		player.weapon_system.try_fire()

	if game_over:
		return

	_update_combo(delta)
	_update_spawn_queue(delta)
	_update_projectiles(delta)
	_update_loot(delta)
	_update_zone(delta)
	_update_between_waves(delta)
	_update_hud()


func _update_combo(delta: float) -> void:
	if _combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0


func _update_spawn_queue(delta: float) -> void:
	if _spawn_queue.is_empty() or between_waves:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_spawn_next_enemy()


func _update_between_waves(delta: float) -> void:
	if not between_waves:
		return
	between_timer -= delta
	if between_timer <= 0.0:
		between_waves = false
		_start_wave()


func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		var nd: Node3D = p.get("node")
		if not is_instance_valid(nd):
			projectiles.remove_at(i); continue

		p["traveled"] += p["speed"] * delta
		nd.position += p["dir"] * p["speed"] * delta

		# Rotate projectile
		nd.rotate_object_local(Vector3.UP, delta * 8.0)

		var hit := false
		if p.get("from_enemy", false):
			if player and is_instance_valid(player):
				if nd.global_position.distance_to(player.global_position) < 1.1:
					player.apply_damage(p["damage"])
					hit = true
		else:
			for enemy in enemies.duplicate():
				if not is_instance_valid(enemy): continue
				if nd.global_position.distance_to(enemy.global_position) < 1.6:
					if p["aoe"] > 0.0:
						create_explosion_3d(nd.global_position, p["aoe"], p["damage"])
						hit = true; break
					else:
						enemy.take_damage(p["damage"])
						if dmg_numbers:
							dmg_numbers.spawn(nd.global_position + Vector3(0,1.5,0),
								int(p["damage"]))
						hit = true; break

		if hit or p["traveled"] >= p["max_range"]:
			if p["aoe"] > 0.0 and not p.get("from_enemy", false) and not hit:
				create_explosion_3d(nd.global_position, p["aoe"], p["damage"])
			nd.queue_free()
			projectiles.remove_at(i)


func _update_loot(delta: float) -> void:
	for i in range(loot_items.size() - 1, -1, -1):
		var item: Dictionary = loot_items[i]
		var nd: Node3D = item.get("node")
		if not is_instance_valid(nd):
			loot_items.remove_at(i); continue
		item["timer"] -= delta
		# Bob animation
		nd.position.y = 0.55 + sin(Time.get_ticks_msec() * 0.003 + item["phase"]) * 0.14
		nd.rotate_y(delta * 1.5)

		if player and is_instance_valid(player):
			var d := nd.global_position.distance_to(player.global_position)
			var magnet_r := 5.5 * float(player.p_magnet_mult)
			if d < magnet_r:
				var pull_dir := (player.global_position - nd.global_position).normalized()
				var pull_speed := lerpf(6.0, 22.0, 1.0 - d / maxf(magnet_r, 0.1))
				nd.position += pull_dir * pull_speed * delta
			if d < 1.2:
				_collect_loot(item)
				nd.queue_free()
				loot_items.remove_at(i)
				continue

		if item["timer"] <= 0.0:
			nd.queue_free(); loot_items.remove_at(i)


func _update_zone(delta: float) -> void:
	if zone_phase_idx >= Balance.ZONE3D_PHASES.size():
		return
	zone_phase_timer -= delta
	var ph: Dictionary = Balance.ZONE3D_PHASES[zone_phase_idx]

	zone_radius = lerpf(zone_radius, zone_target_radius, delta * 0.35)
	_update_zone_visual()

	if player and is_instance_valid(player):
		var pp := Vector2(player.global_position.x, player.global_position.z)
		var zc := Vector2(zone_center.x, zone_center.z)
		var in_zone := pp.distance_to(zc) <= zone_radius
		hud.set_zone_warning(not in_zone)
		if not in_zone:
			var resist_mult := 1.0 - p_zone_resist
			player.apply_damage(ph["damage"] * delta * resist_mult)
			_zone_warn_light.global_position = player.global_position
			_zone_warn_light.light_energy = lerpf(_zone_warn_light.light_energy, 3.0, delta * 5.0)
		else:
			_zone_warn_light.light_energy = lerpf(_zone_warn_light.light_energy, 0.0, delta * 5.0)

	if zone_phase_timer <= 0.0:
		zone_phase_idx += 1
		if zone_phase_idx < Balance.ZONE3D_PHASES.size():
			var nph: Dictionary = Balance.ZONE3D_PHASES[zone_phase_idx]
			zone_target_radius = Balance.ZONE3D_START_R * float(nph["end_ratio"])
			zone_phase_timer   = float(nph["duration"])


func _update_zone_visual() -> void:
	if not _zone_cylinder: return
	var mesh: CylinderMesh = _zone_cylinder.mesh
	mesh.top_radius    = zone_radius
	mesh.bottom_radius = zone_radius
	var pulse := sin(Time.get_ticks_msec() * 0.003) * 0.15 + 0.85
	_zone_mat.emission_energy_multiplier = pulse


func _update_hud() -> void:
	if not hud: return
	if player and is_instance_valid(player):
		hud.update_hp(player.hp, player.max_hp)
		hud.shield  = player.p_shield
		hud.update_weapon(player.weapon_system.current_weapon)
		hud.update_reload(player.weapon_system.is_reloading,
			player.weapon_system.reload_progress)
		hud.update_dash_cd(player.dash_cd)
	hud.update_xp(p_xp, p_xp_to_next, p_level)
	hud.update_money(p_money)
	hud.score  = p_score
	hud.combo  = _combo
	hud.enemy_count = enemies.size() + _spawn_queue.size()


func _check_wave_clear() -> void:
	if _spawn_queue.is_empty() and enemies.is_empty() and not between_waves:
		between_waves = true
		between_timer = BETWEEN_WAVE_TIME
		p_money += Balance.ROUND_SURVIVAL_BONUS
		hud.add_kill_feed("Wave %d clear!  +$%d" % [wave, Balance.ROUND_SURVIVAL_BONUS])
		audio_gen.play_levelup()
		hud.show_shop_between_waves()


# ── Callbacks ──────────────────────────────────────────────────────────────────
func _on_enemy_died(enemy: Node3D, reward: int, xp: int, pos: Vector3) -> void:
	enemies.erase(enemy)
	_check_wave_clear()

	_combo += 1
	_combo_timer = COMBO_WINDOW
	var mult := 1.0 + (_combo - 1) * 0.1
	var actual_reward := int(reward * p_loot_mult * mult)
	p_money += actual_reward + p_kill_bonus
	p_score += actual_reward * 10
	p_kill_count += 1

	if player and is_instance_valid(player) and player.p_vampire > 0.0:
		player.hp = minf(player.hp + player.p_vampire, player.max_hp)

	_add_xp(xp)
	_spawn_loot(pos)
	audio_gen.play_kill()
	if _combo >= 3:
		hud.add_kill_feed("%dx Combo! +$%d" % [_combo, actual_reward])
	elif _combo >= 2:
		hud.add_kill_feed("Double kill  +$%d" % actual_reward)
	else:
		hud.add_kill_feed("+$%d" % actual_reward)
	hud.update_wave(wave, enemies.size() + _spawn_queue.size())


func _on_player_took_damage(amount: float) -> void:
	audio_gen.play_hurt()
	if hud:
		hud.update_hp(player.hp, player.max_hp)
		hud.trigger_hit_flash()


func _on_player_died() -> void:
	running = false; game_over = true
	_fire_active = false
	if save_mgr:
		save_mgr.save_run_result(wave, p_kill_count, 0)
	if hud:
		hud.show_game_over(wave, p_kill_count, p_score)
	audio_gen.play_hurt()
	var t := get_tree().create_timer(5.0)
	t.timeout.connect(func(): get_tree().reload_current_scene())


func _on_fire_held(state: bool) -> void:
	_fire_active = state
	if state and player and is_instance_valid(player):
		# Immediate first shot on press
		player.weapon_system.try_fire()


func _on_reload_pressed() -> void:
	if player and is_instance_valid(player):
		player.weapon_system.start_reload()
		audio_gen.play_reload()


func _on_dash_pressed() -> void:
	if player and is_instance_valid(player):
		player.do_dash()
		audio_gen.play_dash()


func _on_ult_pressed() -> void:
	pass  # TODO: hero ultimates


func _on_weapon_fired(weapon_id: String, from: Vector3, dir: Vector3) -> void:
	audio_gen.play_shoot(weapon_id)
	if fx_manager:
		fx_manager.spawn_muzzle_flash(from, Balance.WEAPONS3D[weapon_id]["color"])
	# Bullet decal for hitscan
	if Balance.WEAPONS3D[weapon_id]["hitscan"]:
		_cast_decal_ray(from, dir, Balance.WEAPONS3D[weapon_id]["range"])


func _cast_decal_ray(from: Vector3, dir: Vector3, range_m: float) -> void:
	if not fx_manager: return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * range_m, 1)
	if player: q.exclude = [player]
	var result := space.intersect_ray(q)
	if not result.is_empty():
		fx_manager.spawn_hit(result["position"], result["normal"])
		fx_manager.spawn_bullet_hole(result["position"], result["normal"])


func _on_hit_enemy_fx(enemy: Node3D, damage: float, pos: Vector3) -> void:
	if fx_manager:
		var ecol := Color(1.0, 0.3, 0.1)
		if enemy.has_method("get_body_color"):
			ecol = enemy.get_body_color()
		fx_manager.spawn_blood_hit(pos, ecol)
	audio_gen.play_hit_enemy()
	if dmg_numbers:
		dmg_numbers.spawn(pos + Vector3(0, 1.0, 0), int(damage))


# ── Player damaged by enemy ────────────────────────────────────────────────────
func on_player_damaged(amount: float) -> void:
	audio_gen.play_hurt()
	if hud: hud.update_hp(player.hp, player.max_hp)


func on_hit_surface(pos: Vector3, normal: Vector3, _col: Object) -> void:
	if fx_manager:
		fx_manager.spawn_hit(pos, normal)
		fx_manager.spawn_bullet_hole(pos, normal)


# ── Perk chosen ────────────────────────────────────────────────────────────────
func _on_perk_chosen(perk_key: String) -> void:
	var perk: Dictionary = Balance.PERKS.get(perk_key, {})
	var effect: String  = perk.get("effect", "")
	var value: float    = perk.get("value",  0.0)
	if not player or not is_instance_valid(player): return
	match effect:
		"max_hp":    player.max_hp += value; player.hp = minf(player.hp + value, player.max_hp)
		"speed_mult":player.p_speed_mult = maxf(0.5, player.p_speed_mult * value)
		"loot_mult": p_loot_mult *= value
		"zone_resist":p_zone_resist = minf(p_zone_resist + value, 0.9)
		"kill_bonus":p_kill_bonus += int(value)
		"vampire":   player.p_vampire += value
		"double_shot":player.p_double_shot = true
		"shield":    player.p_shield += value
		"explosive": player.p_explosive_rds = true
		"magnet":    player.p_magnet_mult *= value
		"berserker": player.p_last_stand = true
		"ammo_mult":
			var ws := player.weapon_system
			ws.max_ammo = int(ws.max_ammo * value)
			ws.ammo = ws.max_ammo
			hud.update_ammo(ws.ammo, ws.max_ammo)
		"reload_mult":
			pass  # handled at fire time
	hud.add_kill_feed("+ " + perk.get("name", perk_key))
	audio_gen.play_buy()


# ── Shop buy ───────────────────────────────────────────────────────────────────
func _on_shop_buy(weapon_id: String) -> void:
	if not Balance.WEAPONS3D.has(weapon_id): return
	if not player or not is_instance_valid(player): return
	var price: int = Balance.WEAPONS3D[weapon_id]["price"]
	if p_money < price:
		hud.add_kill_feed("Not enough money!")
		return
	p_money -= price
	player.weapon_system.equip(weapon_id)
	hud.add_kill_feed("Equipped: " + weapon_id.to_upper())
	audio_gen.play_buy()


# ── Projectile spawning ────────────────────────────────────────────────────────
func spawn_projectile_3d(origin: Vector3, dir: Vector3, speed: float,
		max_range: float, damage: float, aoe: float, col: Color, wid: String) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.20; sm.height = 0.40
	sm.radial_segments = 6; sm.rings = 3
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = origin
	proj_node.add_child(mi)

	# Trail light
	var trail_l := OmniLight3D.new()
	trail_l.light_color = col; trail_l.light_energy = 2.0
	trail_l.omni_range = 3.0; trail_l.shadow_enabled = false
	mi.add_child(trail_l)

	projectiles.append({
		"node": mi, "dir": dir.normalized(), "speed": speed,
		"max_range": max_range, "traveled": 0.0,
		"damage": damage, "aoe": aoe, "from_enemy": false, "weapon": wid,
	})


func spawn_enemy_projectile(origin: Vector3, dir: Vector3, dmg: float, _etype: String) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.13; sm.height = 0.26
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.05)
	mat.emission_enabled = true; mat.emission = Color(1.0, 0.15, 0.0)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = origin
	proj_node.add_child(mi)
	projectiles.append({
		"node": mi, "dir": dir.normalized(), "speed": 15.0,
		"max_range": 38.0, "traveled": 0.0,
		"damage": dmg, "aoe": 0.0, "from_enemy": true,
	})


# ── Explosions ─────────────────────────────────────────────────────────────────
func create_explosion_3d(pos: Vector3, radius: float, damage: float) -> void:
	if fx_manager: fx_manager.spawn_explosion(pos, radius)
	audio_gen.play_explosion()
	if player and is_instance_valid(player):
		var d := pos.distance_to(player.global_position)
		if d < radius:
			player.apply_damage(damage * (1.0 - clampf(d/radius,0.0,1.0)*0.5))
			player.add_camera_shake(1.4)
	for e in enemies.duplicate():
		if not is_instance_valid(e): continue
		var d := pos.distance_to(e.global_position)
		if d < radius:
			e.take_damage(damage * (1.0 - clampf(d/radius,0.0,1.0)*0.5))
	# Chain-react nearby barrels
	for barrel in get_tree().get_nodes_in_group("explosive_barrel"):
		if not is_instance_valid(barrel): continue
		if pos.distance_to(barrel.global_position) < radius * 1.2:
			explode_barrel(barrel)


func explode_barrel(barrel: Node3D) -> void:
	if not is_instance_valid(barrel): return
	barrel.remove_from_group("explosive_barrel")  # prevent infinite loop
	create_explosion_3d(barrel.global_position,
		barrel.get_meta("explode_radius", 6.0),
		barrel.get_meta("explode_damage", 80.0))
	barrel.queue_free()


# ── Loot spawning ──────────────────────────────────────────────────────────────
func _spawn_loot(pos: Vector3) -> void:
	var drops := [
		{"type":"money",  "chance":1.0,  "val":randi_range(40,140)},
		{"type":"health", "chance":0.22, "val":25},
		{"type":"ammo",   "chance":0.38, "val":1},
	]
	for d in drops:
		if randf() < float(d["chance"]) * p_loot_mult:
			var offset := Vector3(randf_range(-1.2,1.2), 0, randf_range(-1.2,1.2))
			_spawn_loot_node(pos + offset, d["type"], d["val"])


func _spawn_loot_node(pos: Vector3, ltype: String, val: int) -> void:
	var mi := MeshInstance3D.new()
	var col: Color
	match ltype:
		"money":
			var sm := SphereMesh.new(); sm.radius = 0.18; sm.height = 0.36
			sm.radial_segments = 8; sm.rings = 4; mi.mesh = sm
			col = Color(1.0, 0.9, 0.0)
		"health":
			var bm := BoxMesh.new(); bm.size = Vector3(0.28, 0.28, 0.28); mi.mesh = bm
			col = Color(0.1, 0.92, 0.2)
		"ammo":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.08; cm.bottom_radius = 0.10; cm.height = 0.24
			cm.radial_segments = 8; mi.mesh = cm
			col = Color(0.95, 0.85, 0.2)
		_:
			var sm2 := SphereMesh.new(); sm2.radius = 0.16; mi.mesh = sm2
			col = Color(0.7, 0.7, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true; mat.emission = col; mat.emission_energy_multiplier = 0.55
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.55, 0)
	# Spin rings for money
	if ltype == "money":
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(0.8, 0.65, 0.0)
		ring_mat.emission_enabled = true; ring_mat.emission = Color(0.8,0.65,0.0)
		ring_mat.emission_energy_multiplier = 0.4
		var rm := MeshInstance3D.new()
		var tor := TorusMesh.new(); tor.inner_radius = 0.16; tor.outer_radius = 0.22
		tor.rings = 16; tor.ring_segments = 6
		rm.mesh = tor; rm.material_override = ring_mat
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(rm)
	loot_node.add_child(mi)
	loot_items.append({
		"node": mi, "type": ltype, "value": val,
		"timer": Balance.LOOT_DESPAWN_TIME,
		"phase": randf_range(0, TAU),
	})


func _collect_loot(item: Dictionary) -> void:
	if not player or not is_instance_valid(player): return
	match item["type"]:
		"money":  p_money += item["value"]
		"health": player.hp = minf(player.hp + float(item["value"]), player.max_hp)
		"ammo":
			var ws := player.weapon_system
			ws.ammo = mini(ws.ammo + ws.max_ammo, ws.max_ammo)
			hud.update_ammo(ws.ammo, ws.max_ammo)
	audio_gen.play_pickup(item["type"])
	if fx_manager:
		fx_manager.spawn_pickup_sparkle(item["node"].global_position)


# ── XP / level ─────────────────────────────────────────────────────────────────
func _add_xp(amount: int) -> void:
	p_xp += amount
	while p_level < Balance.XP_PER_LEVEL.size() and p_xp >= p_xp_to_next:
		p_xp -= p_xp_to_next
		p_level += 1
		p_xp_to_next = Balance.XP_PER_LEVEL[mini(p_level - 1, Balance.XP_PER_LEVEL.size()-1)]
		_trigger_level_up()


func _trigger_level_up() -> void:
	audio_gen.play_levelup()
	var keys: Array = Balance.PERK_KEYS.duplicate()
	keys.shuffle()
	hud.show_perk_choice(keys.slice(0, 3))
