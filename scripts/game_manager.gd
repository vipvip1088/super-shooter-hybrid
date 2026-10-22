## game_manager.gd — central state container and orchestrator
## NO typed class references (var x: SomeClass) to avoid cascade parse failures.
## All Balance.CONSTANT references moved to _ready() to be safe on Godot 4.2.
extends Node2D

# ── Player state ───────────────────────────────────────────────────────────
var p_pos:            Vector2 = Vector2(1500.0, 1500.0)
var p_hp:             float   = 100.0
var p_max_hp:         float   = 100.0
var p_money:          int     = 800
var p_wood:           int     = 0
var p_metal:          int     = 0
var p_chips:          int     = 0
var p_weapon:         String  = "pistol"
var p_ammo:           int     = 12
var p_max_ammo:       int     = 12
var p_facing:         Vector2 = Vector2.RIGHT
var p_is_dashing:     bool    = false
var p_dash_cooldown:  float   = 0.0
var p_invincible:     float   = 0.0
var p_is_reloading:   bool    = false
var p_reload_timer:   float   = 0.0
var p_perks:          Array   = []
var p_owned_weapons:  Array   = ["pistol"]
var p_loot_mult:      float   = 1.0
var p_reload_mult:    float   = 1.0
var p_zone_resist:    float   = 0.0
var p_kill_bonus:     float   = 0.0
var p_hit_stop_dur:   float   = 0.07
var p_last_stand:     float   = 0.0
var p_xp:             int     = 0
var p_level:          int     = 1
var p_xp_to_next:     int     = 100
var p_hero:           String  = "assault"
var p_speed_mult:     float   = 1.0
var p_dmg_mult:       float   = 1.0
var p_vampire:        float   = 0.0
var p_double_shot:    bool    = false
var p_shield:         float   = 0.0
var p_explosive_rds:  bool    = false
var p_magnet_mult:    float   = 1.0
var p_ultimate_cd:    float   = 0.0
var p_ultimate_max:   float   = 30.0
var p_kill_count:     int     = 0
var p_is_ultimate:    bool    = false
var p_ultimate_timer: float   = 0.0
var p_crystals:       int     = 0

# ── Dash ──────────────────────────────────────────────────────────────────
var _dash_timer:   float   = 0.0
var _dash_dir:     Vector2 = Vector2.ZERO
var _dash_charges: int     = 1
var _dash_charges_max: int = 1

# ── Zone ──────────────────────────────────────────────────────────────────
var zone_center:        Vector2 = Vector2(1500.0, 1500.0)
var zone_radius:        float   = 1200.0
var zone_target_radius: float   = 840.0
var zone_timer:         float   = 120.0
var zone_phase:         int     = 0

# ── World arrays ──────────────────────────────────────────────────────────
var enemies:     Array = []
var projectiles: Array = []
var loot_items:  Array = []
var barricades:  Array = []
var turrets:     Array = []

# ── Round ─────────────────────────────────────────────────────────────────
var current_round: int = 1

# ── Modules (untyped to prevent cascade compile failure) ──────────────────
var combat_manager  # CombatManager
var enemy_spawner   # EnemySpawner
var round_manager   # RoundManager
var loot_manager    # LootManager
var world_renderer  # WorldRenderer
var fx_manager      # FxManager
var sound_manager   # SoundManager
var save_manager    # SaveManager
var hud             # HUD

# ── Input ─────────────────────────────────────────────────────────────────
var _move_dir: Vector2 = Vector2.ZERO
var _aim_dir:  Vector2 = Vector2.ZERO

# ── Camera ────────────────────────────────────────────────────────────────
var _camera: Camera2D

# ── Hero select ────────────────────────────────────────────────────────────
var _hero_selected: bool = false

# ── Level-up ──────────────────────────────────────────────────────────────
var _level_up_choices: Array = []


func _ready() -> void:
	# All Balance refs are here (not at class level) — safe on Godot 4.2
	p_hp          = Balance.PLAYER_MAX_HP
	p_max_hp      = Balance.PLAYER_MAX_HP
	p_money       = Balance.STARTING_MONEY
	p_hit_stop_dur= Balance.HIT_STOP_DUR
	zone_radius   = Balance.ZONE_INITIAL_RADIUS
	zone_target_radius = Balance.ZONE_INITIAL_RADIUS * float(Balance.ZONE_PHASES[0]["ratio"])
	zone_timer    = float(Balance.ZONE_PHASES[0]["duration"])

	_build_scene()
	_connect_signals()

	round_manager.setup(self)
	combat_manager.setup(self)
	enemy_spawner.setup(self)
	loot_manager.setup(self)
	world_renderer.setup(self)
	fx_manager.setup(self, _camera)
	sound_manager.setup(self)
	hud.setup(self)

	# Load saved crystals
	if save_manager:
		var sd = save_manager.load_data()
		p_crystals = int(sd.get("crystals", 0))

	# Show hero select
	hud.show_hero_select()


func _build_scene() -> void:
	_camera = Camera2D.new()
	_camera.position = p_pos
	add_child(_camera)

	world_renderer = _safe_load("res://scripts/rendering/world_renderer.gd")
	add_child(world_renderer)

	fx_manager = _safe_load("res://scripts/rendering/fx_manager.gd")
	add_child(fx_manager)

	hud = _safe_load("res://scripts/ui/hud.gd")
	hud.z_index = 10
	add_child(hud)

	combat_manager = _safe_load("res://scripts/core/combat_manager.gd")
	add_child(combat_manager)

	enemy_spawner = _safe_load("res://scripts/core/enemy_spawner.gd")
	add_child(enemy_spawner)

	round_manager = _safe_load("res://scripts/core/round_manager.gd")
	add_child(round_manager)

	loot_manager = _safe_load("res://scripts/core/loot_manager.gd")
	add_child(loot_manager)

	var sm_script = load("res://scripts/audio/sound_manager.gd")
	if sm_script:
		sound_manager = sm_script.new()
	else:
		sound_manager = Node.new()
		sound_manager.set_script(null)
	add_child(sound_manager)

	var sv_script = load("res://scripts/core/save_manager.gd")
	if sv_script:
		save_manager = sv_script.new()
		add_child(save_manager)


func _safe_load(path: String) -> Node:
	var s = load(path)
	if s:
		return s.new()
	push_error("GameManager: failed to load " + path)
	return Node.new()


func _connect_signals() -> void:
	combat_manager.hit_enemy.connect(_on_hit_enemy)
	combat_manager.hit_player.connect(_on_hit_player)
	combat_manager.projectile_explosion.connect(_on_explosion)
	combat_manager.weapon_empty.connect(_on_weapon_empty)
	combat_manager.reload_complete.connect(_on_reload_complete)

	enemy_spawner.enemy_died.connect(_on_enemy_died)
	enemy_spawner.wave_cleared.connect(_on_wave_cleared)
	enemy_spawner.enemy_hit_player.connect(_on_hit_player)

	round_manager.state_changed.connect(_on_state_changed)
	round_manager.buy_phase_started.connect(_on_buy_phase_started)
	round_manager.upgrade_choices.connect(_on_upgrade_choices)
	round_manager.game_over.connect(_on_game_over)
	round_manager.victory.connect(_on_victory)

	loot_manager.loot_collected.connect(_on_loot_collected)

	hud.move_input.connect(func(d: Vector2) -> void: _move_dir = d)
	hud.aim_input.connect(func(d: Vector2) -> void:  _aim_dir  = d)
	hud.shoot_pressed.connect(_on_shoot_pressed)
	hud.reload_pressed.connect(func() -> void: combat_manager.start_reload())
	hud.dash_pressed.connect(_on_dash_pressed)
	hud.ultimate_pressed.connect(_on_ultimate_pressed)
	hud.shop_buy.connect(_on_shop_buy)
	hud.craft_action.connect(_on_craft_action)
	hud.perk_chosen.connect(func(k: String) -> void: round_manager.apply_perk(k))
	hud.hero_chosen.connect(_on_hero_chosen)
	hud.level_perk_chosen.connect(_on_level_perk_chosen)


func _process(delta: float) -> void:
	if not _hero_selected:
		return

	if not round_manager.is_playing():
		round_manager.update(delta)
		hud.set_freeze_timer(round_manager._timer)
		hud.queue_redraw()
		return

	_update_player(delta)
	_update_zone(delta)
	_update_ultimate(delta)
	_update_turrets(delta)

	combat_manager.update(delta, p_pos, enemies, projectiles)
	enemy_spawner.update(delta, p_pos, zone_center, zone_radius, enemies, projectiles)
	loot_manager.update(delta, p_pos)
	fx_manager.update(delta)

	_camera.position = p_pos
	world_renderer.queue_redraw()
	hud.queue_redraw()


func _update_player(delta: float) -> void:
	var spd := Balance.PLAYER_SPEED * p_speed_mult

	if p_last_stand > 0.0 and p_hp / p_max_hp < 0.2:
		spd *= p_last_stand

	if p_is_ultimate and p_hero == "phantom":
		spd *= 2.0

	if p_is_dashing:
		_dash_timer -= delta
		p_invincible = maxf(_dash_timer, 0.0)
		p_pos += _dash_dir * Balance.DASH_SPEED * delta
		if _dash_timer <= 0.0:
			p_is_dashing = false
			p_invincible = 0.0
	else:
		p_pos += _move_dir * spd * delta
		if p_invincible > 0.0:
			p_invincible -= delta

	if _aim_dir.length_squared() > 0.01:
		p_facing = _aim_dir.normalized()
	elif _move_dir.length_squared() > 0.01:
		p_facing = _move_dir.normalized()

	p_pos.x = clampf(p_pos.x, 0.0, Balance.MAP_W)
	p_pos.y = clampf(p_pos.y, 0.0, Balance.MAP_H)

	if p_dash_cooldown > 0.0:
		p_dash_cooldown -= delta

	if p_ultimate_cd > 0.0:
		p_ultimate_cd -= delta


func _update_zone(delta: float) -> void:
	if zone_phase >= Balance.ZONE_PHASES.size():
		return
	zone_timer -= delta
	if zone_timer <= 0.0:
		zone_phase = mini(zone_phase + 1, Balance.ZONE_PHASES.size() - 1)
		var ph: Dictionary = Balance.ZONE_PHASES[zone_phase]
		zone_timer = float(ph["duration"])
		zone_target_radius = Balance.ZONE_INITIAL_RADIUS * float(ph["ratio"])

	zone_radius = lerpf(zone_radius, zone_target_radius, delta * 0.15)

	var dist: float = p_pos.distance_to(zone_center)
	if dist > zone_radius:
		var ph: Dictionary = Balance.ZONE_PHASES[zone_phase]
		var dmg: float = float(ph["damage"]) * delta * (1.0 - p_zone_resist)
		_damage_player(dmg)


func _update_ultimate(delta: float) -> void:
	if not p_is_ultimate:
		return
	p_ultimate_timer -= delta
	if p_ultimate_timer <= 0.0:
		p_is_ultimate = false
		if p_hero == "berserker":
			p_dmg_mult /= 3.0


func _update_turrets(delta: float) -> void:
	for turret in turrets:
		turret["shoot_cd"] -= delta
		if turret["shoot_cd"] <= 0.0 and not enemies.is_empty():
			turret["shoot_cd"] = 0.8
			var best_e = null
			var best_d := 300.0
			for e in enemies:
				var d: float = (turret["pos"] as Vector2).distance_to(e["pos"])
				if d < best_d:
					best_d = d
					best_e = e
			if best_e != null:
				var dir: Vector2 = ((best_e["pos"] as Vector2) - turret["pos"]).normalized()
				projectiles.append({
					"pos": Vector2(turret["pos"]),
					"vel": dir * 700.0,
					"damage": 20.0,
					"owner": "player",
					"weapon": "pistol",
					"ttl": 0.8,
					"radius": 5.0,
					"aoe": 0.0,
					"color": Color(1.0, 0.9, 0.2, 1.0),
					"trail": [],
					"dist": 0.0,
				})


func _damage_player(amount: float) -> void:
	if p_invincible > 0.0:
		return
	if p_is_ultimate and p_hero == "phantom":
		return
	if p_shield > 0.0:
		var absorbed := minf(p_shield, amount)
		p_shield -= absorbed
		amount -= absorbed
		if amount <= 0.0:
			return
	p_hp -= amount
	if p_hp <= 0.0:
		p_hp = 0.0
		round_manager.trigger_game_over()


func _add_xp(amount: int) -> void:
	p_xp += amount
	var xp_table: Array = Balance.XP_PER_LEVEL
	while p_level <= xp_table.size() and p_xp >= p_xp_to_next:
		p_xp -= p_xp_to_next
		p_level += 1
		if p_level - 1 < xp_table.size():
			p_xp_to_next = int(xp_table[p_level - 1])
		else:
			p_xp_to_next = 9999
		_on_level_up()


func _on_level_up() -> void:
	var choices := _pick_level_perks(3)
	_level_up_choices = choices
	hud.show_level_up(choices, p_level)
	fx_manager.spawn_floater(p_pos + Vector2(0, -80), "LEVEL UP! " + str(p_level), Color(1.0, 0.85, 0.0))
	if sound_manager.has_method("play_levelup"):
		sound_manager.play_levelup()


func _pick_level_perks(count: int) -> Array:
	var available: Array = []
	for k in Balance.PERK_KEYS:
		if k not in p_perks:
			available.append(k)
	available.shuffle()
	var result: Array = []
	for i in range(mini(count, available.size())):
		result.append(available[i])
	return result


func _apply_perk_effect(perk_key: String) -> void:
	var perk: Dictionary = Balance.PERKS.get(perk_key, {})
	if perk.is_empty():
		return
	var effect: String = perk["effect"]
	var value: float   = float(perk["value"])
	match effect:
		"max_hp":        p_max_hp += value; p_hp = minf(p_hp + value, p_max_hp)
		"loot_mult":     p_loot_mult  = maxf(p_loot_mult,  value)
		"reload_mult":   p_reload_mult = maxf(p_reload_mult, value); combat_manager.set_reload_multiplier(p_reload_mult)
		"zone_resist":   p_zone_resist = maxf(p_zone_resist, value)
		"kill_bonus":    p_kill_bonus  += value
		"ammo_mult":
			var wd: Dictionary = combat_manager.get_weapon(p_weapon)
			if not wd.is_empty():
				p_max_ammo = int(int(wd["ammo"]) * value)
				p_ammo = p_max_ammo
		"hit_stop":      p_hit_stop_dur = value
		"last_stand":    p_last_stand   = value
		"vampire":       p_vampire      += value
		"double_shot":   p_double_shot  = true
		"shield":        p_shield       += value
		"explosive":     p_explosive_rds = true
		"speed_mult":    p_speed_mult   *= value
		"berserker":     p_dmg_mult     = maxf(p_dmg_mult, value)
		"magnet":        p_magnet_mult  = maxf(p_magnet_mult, value)
	p_perks.append(perk_key)


# ── Signal handlers ────────────────────────────────────────────────────────

func _on_hit_enemy(idx: int, damage: float, _is_aoe: bool) -> void:
	if idx >= enemies.size():
		return
	var e = enemies[idx]
	e["flash"] = 0.15
	var actual_dmg := damage * p_dmg_mult
	if p_hp / p_max_hp < 0.5 and "berserker_perk" in p_perks:
		actual_dmg *= Balance.PERKS["berserker_perk"]["value"]
	enemy_spawner.apply_damage_to_enemy(enemies, idx, actual_dmg)
	if idx < enemies.size() and e["hp"] > 0.0:
		fx_manager.spawn_hit_fx(e["pos"], e["type"])
		fx_manager.spawn_floater(e["pos"] + Vector2(0, -30), "-%d" % int(actual_dmg), Color(1.0, 0.3, 0.3))
	fx_manager.hit_stop(p_hit_stop_dur)
	if sound_manager.has_method("play_hit"):
		sound_manager.play_hit()


func _on_hit_player(damage: float) -> void:
	_damage_player(damage)
	fx_manager.shake(Balance.SHAKE_HIT)
	fx_manager.spawn_floater(p_pos + Vector2(0, -40), "-%d" % int(damage), Color(1.0, 0.2, 0.2))
	if sound_manager.has_method("play_hurt"):
		sound_manager.play_hurt()


func _on_explosion(pos: Vector2, radius: float, _damage: float) -> void:
	fx_manager.spawn_explosion_fx(pos, radius)
	if sound_manager.has_method("play_explosion"):
		sound_manager.play_explosion()


func _on_weapon_empty(_wid: String) -> void:
	combat_manager.start_reload()
	if sound_manager.has_method("play_empty"):
		sound_manager.play_empty()


func _on_reload_complete(_wid: String, _new_ammo: int) -> void:
	fx_manager.spawn_floater(p_pos + Vector2(0, -50), "RELOADED", Color(0.4, 1.0, 0.4))
	if sound_manager.has_method("play_reload"):
		sound_manager.play_reload()


func _on_enemy_died(pos: Vector2, type: String, reward: int, xp: int) -> void:
	var total_reward := int(float(reward) * p_loot_mult) + int(p_kill_bonus)
	p_money    += total_reward
	p_kill_count += 1
	loot_manager.spawn_loot(pos, p_loot_mult)
	fx_manager.spawn_death_fx(pos, type)
	fx_manager.spawn_floater(pos + Vector2(0, -40), "+$%d" % total_reward, Color(1.0, 0.85, 0.0))
	if sound_manager.has_method("play_kill"):
		sound_manager.play_kill()
	if p_vampire > 0.0:
		p_hp = minf(p_hp + p_vampire, p_max_hp)
		fx_manager.spawn_floater(pos + Vector2(0, -70), "+%.0f HP" % p_vampire, Color(0.5, 1.0, 0.5))
	_add_xp(xp)


func _on_wave_cleared() -> void:
	round_manager.trigger_upgrade()
	# Award crystals for completing a round
	var crystal_gain := current_round
	p_crystals += crystal_gain
	fx_manager.spawn_floater(p_pos + Vector2(0, -100), "+%d 💎" % crystal_gain, Color(0.5, 0.8, 1.0))
	if save_manager:
		save_manager.save_crystals(p_crystals)


func _on_loot_collected(type: String, amount: int) -> void:
	var text: String
	match type:
		"money":  text = "+$%d" % amount
		"health": text = "+%d HP" % amount
		"ammo":   text = "AMMO"
		"wood":   text = "+%d Wood" % amount
		"metal":  text = "+%d Metal" % amount
		"chips":  text = "+%d Chips" % amount
		_:        text = "+"
	fx_manager.spawn_floater(p_pos + Vector2(randf_range(-20, 20), -40), text, Color(0.6, 1.0, 0.6))
	if sound_manager.has_method("play_pickup"):
		sound_manager.play_pickup()


func _on_state_changed(new_state: String) -> void:
	hud.set_state(new_state)
	if new_state == "PLAYING":
		enemy_spawner.start_wave(current_round, zone_center, zone_radius)
	elif new_state == "FREEZE":
		hud.hide_upgrade()
		hud.hide_shop()
		hud.hide_craft()
		hud.hide_level_up()


func _on_buy_phase_started(_duration: float, _money: int) -> void:
	hud.show_shop()


func _on_upgrade_choices(perks: Array) -> void:
	hud.show_upgrade(perks)


func _on_game_over() -> void:
	hud.set_state("GAME_OVER")
	hud.queue_redraw()
	if save_manager:
		save_manager.save_crystals(p_crystals)


func _on_victory() -> void:
	hud.set_state("VICTORY")
	hud.queue_redraw()
	if save_manager:
		save_manager.save_crystals(p_crystals)


func _on_shoot_pressed() -> void:
	if _aim_dir.length_squared() < 0.01:
		return
	var dir := _aim_dir.normalized()
	var fired := combat_manager.try_shoot(p_pos, dir, projectiles)
	if fired:
		if p_double_shot:
			combat_manager.try_shoot(p_pos, dir.rotated(0.08), projectiles)
		if p_explosive_rds:
			# patch last projectile to have small AOE
			if not projectiles.is_empty():
				var last = projectiles[projectiles.size() - 1]
				if float(last.get("aoe", 0.0)) < 1.0:
					last["aoe"] = 30.0
		if sound_manager.has_method("play_shoot"):
			sound_manager.play_shoot(p_weapon)


func _on_dash_pressed() -> void:
	if p_is_dashing:
		return
	if p_dash_cooldown > 0.0 and _dash_charges <= 0:
		return
	var dir := _move_dir if _move_dir.length_squared() > 0.01 else p_facing
	_dash_dir     = dir.normalized()
	_dash_timer   = Balance.DASH_DURATION
	p_is_dashing  = true
	p_dash_cooldown   = Balance.DASH_COOLDOWN
	p_invincible      = Balance.DASH_DURATION
	if sound_manager.has_method("play_dash"):
		sound_manager.play_dash()


func _on_ultimate_pressed() -> void:
	if p_ultimate_cd > 0.0:
		return
	p_ultimate_cd  = p_ultimate_max
	p_is_ultimate  = true
	match p_hero:
		"assault":
			p_ultimate_timer = 2.0
			p_dmg_mult *= 2.0
			fx_manager.spawn_floater(p_pos + Vector2(0, -60), "STEEL STORM!", Color(0.3, 0.7, 1.0))
		"engineer":
			p_is_ultimate = false
			turrets.append({
				"pos": Vector2(p_pos),
				"shoot_cd": 0.0,
				"life": 10.0,
			})
			fx_manager.spawn_floater(p_pos + Vector2(0, -60), "TURRET DEPLOYED!", Color(0.9, 0.7, 0.2))
		"berserker":
			p_ultimate_timer = 4.0
			p_dmg_mult *= 3.0
			fx_manager.spawn_floater(p_pos + Vector2(0, -60), "RAGE!", Color(1.0, 0.2, 0.0))
		"phantom":
			p_ultimate_timer = 3.0
			p_invincible     = 3.0
			fx_manager.spawn_floater(p_pos + Vector2(0, -60), "GHOST MODE!", Color(0.6, 0.0, 1.0))
	if sound_manager.has_method("play_ultimate"):
		sound_manager.play_ultimate()


func _on_shop_buy(weapon_id: String) -> void:
	if weapon_id not in Balance.WEAPONS:
		return
	var wd: Dictionary = Balance.WEAPONS[weapon_id]
	var weapon_price: int = int(wd["price"])
	if p_owned_weapons.has(weapon_id):
		_equip_weapon(weapon_id)
		hud.hide_shop()
		return
	if p_money < weapon_price:
		fx_manager.spawn_floater(p_pos + Vector2(0, -60), "NOT ENOUGH $", Color(1.0, 0.3, 0.3))
		return
	p_money -= weapon_price
	p_owned_weapons.append(weapon_id)
	_equip_weapon(weapon_id)
	hud.hide_shop()
	fx_manager.spawn_floater(p_pos + Vector2(0, -60), "GOT " + weapon_id.to_upper(), Color(1.0, 0.85, 0.0))
	if sound_manager.has_method("play_buy"):
		sound_manager.play_buy()


func _equip_weapon(weapon_id: String) -> void:
	if weapon_id not in Balance.WEAPONS:
		return
	var wd: Dictionary = Balance.WEAPONS[weapon_id]
	p_weapon   = weapon_id
	p_ammo     = int(wd["ammo"])
	p_max_ammo = int(wd["max_ammo"])
	p_is_reloading = false
	combat_manager.set_reload_multiplier(p_reload_mult)


func _on_craft_action(recipe_id: String) -> void:
	if recipe_id not in Balance.CRAFTING:
		return
	var recipe: Dictionary = Balance.CRAFTING[recipe_id]
	var cost_wood:  int = int(recipe.get("wood",  0))
	var cost_metal: int = int(recipe.get("metal", 0))
	var cost_chips: int = int(recipe.get("chips", 0))
	if p_wood < cost_wood or p_metal < cost_metal or p_chips < cost_chips:
		fx_manager.spawn_floater(p_pos + Vector2(0, -60), "NEED MORE RESOURCES", Color(1.0, 0.4, 0.1))
		return
	p_wood  -= cost_wood
	p_metal -= cost_metal
	p_chips -= cost_chips

	var result: String = recipe["result"]
	match result:
		"barricade", "metal_wall":
			var place_pos := p_pos + p_facing * 80.0
			barricades.append(place_pos)
			fx_manager.spawn_floater(p_pos + Vector2(0, -60), "BUILT!", Color(0.7, 0.55, 0.3))
		"heal_50":
			p_hp = minf(p_hp + 50.0, p_max_hp)
			fx_manager.spawn_floater(p_pos + Vector2(0, -60), "+50 HP", Color(0.3, 1.0, 0.4))
		"full_ammo":
			p_ammo = p_max_ammo
			fx_manager.spawn_floater(p_pos + Vector2(0, -60), "AMMO FULL", Color(1.0, 0.9, 0.3))
		"grenade":
			var gpos := p_pos + _aim_dir.normalized() * 200.0
			combat_manager.create_explosion(gpos, 100.0, 60.0, enemies, projectiles)
		"turret":
			if p_hero == "engineer":
				turrets.append({"pos": Vector2(p_pos + p_facing * 80.0), "shoot_cd": 0.0, "life": 20.0})
				fx_manager.spawn_floater(p_pos + Vector2(0, -60), "TURRET!", Color(0.9, 0.7, 0.2))


func _on_hero_chosen(hero_id: String) -> void:
	p_hero = hero_id
	_apply_hero_stats()
	_hero_selected = true
	hud.hide_hero_select()


func _on_level_perk_chosen(perk_key: String) -> void:
	if perk_key != "":
		_apply_perk_effect(perk_key)
	hud.hide_level_up()


func _apply_hero_stats() -> void:
	if p_hero not in Balance.HEROES:
		return
	var h: Dictionary = Balance.HEROES[p_hero]
	p_max_hp     = Balance.PLAYER_MAX_HP * float(h["hp_mult"])
	p_hp         = p_max_hp
	p_speed_mult = float(h["speed_mult"])
	p_ultimate_max = float(h["ult_cd"])

	var start_weapon: String = h["start_weapon"]
	p_weapon     = start_weapon
	p_owned_weapons = ["pistol"]
	if start_weapon != "pistol":
		p_owned_weapons.append(start_weapon)

	if start_weapon in Balance.WEAPONS:
		var wd: Dictionary = Balance.WEAPONS[start_weapon]
		p_ammo     = int(wd["ammo"])
		p_max_ammo = int(wd["max_ammo"])
	else:
		p_ammo     = 12
		p_max_ammo = 12

	match p_hero:
		"engineer":
			p_wood  = 20
			p_metal = 10
		"phantom":
			_dash_charges_max = 2
			_dash_charges     = 2
