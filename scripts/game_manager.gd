class_name GameManager
extends Node2D

# ── Player state ────────────────────────────────────────────────────────────
var p_pos:          Vector2 = Vector2(1500.0, 1500.0)
var p_hp:           float   = Balance.PLAYER_MAX_HP
var p_max_hp:       float   = Balance.PLAYER_MAX_HP
var p_money:        int     = Balance.STARTING_MONEY
var p_wood:         int     = 0
var p_metal:        int     = 0
var p_weapon:       String  = "pistol"
var p_ammo:         int     = 12
var p_max_ammo:     int     = 12
var p_facing:       Vector2 = Vector2.RIGHT
var p_is_dashing:   bool    = false
var p_dash_cooldown:float   = 0.0
var p_invincible:   float   = 0.0
var p_is_reloading: bool    = false
var p_reload_timer: float   = 0.0
var p_perks:        Array   = []
var p_owned_weapons:Array   = ["pistol"]
var p_loot_mult:    float   = 1.0
var p_reload_mult:  float   = 1.0
var p_zone_resist:  float   = 0.0
var p_kill_bonus:   float   = 0.0
var p_hit_stop_dur: float   = Balance.HIT_STOP_DUR
var p_last_stand:   float   = 0.0
var p_xp:           int     = 0

# ── Dash internals ─────────────────────────────────────────────────────────
var _dash_timer: float  = 0.0
var _dash_dir:   Vector2 = Vector2.ZERO

# ── Zone ───────────────────────────────────────────────────────────────────
var zone_center:        Vector2 = Vector2(1500.0, 1500.0)
var zone_radius:        float   = Balance.ZONE_INITIAL_RADIUS
var zone_target_radius: float   = Balance.ZONE_INITIAL_RADIUS * Balance.ZONE_PHASES[0]["ratio"]
var zone_timer:         float   = Balance.ZONE_PHASES[0]["duration"]
var zone_phase:         int     = 0

# ── World arrays ────────────────────────────────────────────────────────────
var enemies:    Array = []
var projectiles:Array = []
var loot_items: Array = []
var barricades: Array = []

# ── Round ──────────────────────────────────────────────────────────────────
var current_round: int = 1

# ── Module references ───────────────────────────────────────────────────────
var combat_manager: CombatManager
var enemy_spawner:  EnemySpawner
var round_manager:  RoundManager
var loot_manager:   LootManager
var world_renderer: WorldRenderer
var fx_manager:     FxManager
var hud:            HUD

# ── Input state ─────────────────────────────────────────────────────────────
var _move_dir: Vector2 = Vector2.ZERO
var _aim_dir:  Vector2 = Vector2.ZERO

# ── Camera ──────────────────────────────────────────────────────────────────
var _camera: Camera2D


func _ready() -> void:
	_build_scene()
	_connect_signals()
	round_manager.setup(self)
	combat_manager.setup(self)
	enemy_spawner.setup(self)
	loot_manager.setup(self)
	world_renderer.setup(self)
	fx_manager.setup(self, _camera)
	hud.setup(self)


func _build_scene() -> void:
	_camera = Camera2D.new()
	_camera.position = p_pos
	add_child(_camera)

	world_renderer = WorldRenderer.new()
	add_child(world_renderer)

	fx_manager = FxManager.new()
	add_child(fx_manager)

	hud = HUD.new()
	hud.z_index = 10
	add_child(hud)

	combat_manager = CombatManager.new()
	add_child(combat_manager)

	enemy_spawner = EnemySpawner.new()
	add_child(enemy_spawner)

	round_manager = RoundManager.new()
	add_child(round_manager)

	loot_manager = LootManager.new()
	add_child(loot_manager)


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

	hud.move_input.connect(func(d): _move_dir = d)
	hud.aim_input.connect(func(d): _aim_dir = d)
	hud.shoot_pressed.connect(_on_shoot_pressed)
	hud.reload_pressed.connect(func(): combat_manager.start_reload())
	hud.dash_pressed.connect(_on_dash_pressed)
	hud.shop_buy.connect(_on_shop_buy)
	hud.perk_chosen.connect(func(k): round_manager.apply_perk(k))


func _process(delta: float) -> void:
	if not round_manager.is_playing():
		round_manager.update(delta)
		hud.set_freeze_timer(round_manager._timer)
		hud.queue_redraw()
		return

	_update_player(delta)
	_update_zone(delta)
	combat_manager.update(delta, p_pos, enemies, projectiles)
	enemy_spawner.update(delta, p_pos, zone_center, zone_radius, enemies, projectiles)
	loot_manager.update(delta, p_pos)
	fx_manager.update(delta)

	_camera.position = p_pos
	world_renderer.queue_redraw()
	hud.queue_redraw()


func _update_player(delta: float) -> void:
	var spd := Balance.PLAYER_SPEED

	# Last stand perk
	if p_last_stand > 0.0 and p_hp / p_max_hp < 0.2:
		spd *= p_last_stand

	if p_is_dashing:
		_dash_timer -= delta
		p_invincible = _dash_timer
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


func _update_zone(delta: float) -> void:
	if zone_phase >= Balance.ZONE_PHASES.size():
		return
	zone_timer -= delta
	if zone_timer <= 0.0:
		zone_phase = mini(zone_phase + 1, Balance.ZONE_PHASES.size() - 1)
		var ph: Dictionary = Balance.ZONE_PHASES[zone_phase]
		zone_timer = ph["duration"]
		zone_target_radius = Balance.ZONE_INITIAL_RADIUS * ph["ratio"]

	zone_radius = lerpf(zone_radius, zone_target_radius, delta * 0.15)

	var dist: float = p_pos.distance_to(zone_center)
	if dist > zone_radius:
		var ph: Dictionary = Balance.ZONE_PHASES[zone_phase]
		var dmg: float = ph["damage"] * delta * (1.0 - p_zone_resist)
		_damage_player(dmg)


func _damage_player(amount: float) -> void:
	if p_invincible > 0.0:
		return
	p_hp -= amount
	if p_hp <= 0.0:
		p_hp = 0.0
		round_manager.trigger_game_over()


# ── Signal handlers ──────────────────────────────────────────────────────────

func _on_hit_enemy(idx: int, damage: float, is_aoe: bool) -> void:
	if idx >= enemies.size():
		return
	var e = enemies[idx]
	e["flash"] = 0.15
	enemy_spawner.apply_damage_to_enemy(enemies, idx, damage)
	if e["hp"] > 0.0:
		fx_manager.spawn_hit_fx(e["pos"], e["type"])
		var dmg_str := "-%d" % int(damage)
		fx_manager.spawn_floater(e["pos"] + Vector2(0, -30), dmg_str, Color(1.0, 0.3, 0.3))
	fx_manager.hit_stop(p_hit_stop_dur)


func _on_hit_player(damage: float) -> void:
	_damage_player(damage)
	fx_manager.shake(Balance.SHAKE_HIT)
	fx_manager.spawn_floater(p_pos + Vector2(0, -40), "-%d" % int(damage), Color(1.0, 0.2, 0.2))


func _on_explosion(pos: Vector2, radius: float, damage: float) -> void:
	fx_manager.spawn_explosion_fx(pos, radius)


func _on_weapon_empty(_wid: String) -> void:
	combat_manager.start_reload()


func _on_reload_complete(_wid: String, _new_ammo: int) -> void:
	fx_manager.spawn_floater(p_pos + Vector2(0, -50), "RELOADED", Color(0.4, 1.0, 0.4))


func _on_enemy_died(pos: Vector2, type: String, reward: int, xp: int) -> void:
	var total_reward := int(reward * p_loot_mult) + int(p_kill_bonus)
	p_money += total_reward
	p_xp    += xp
	loot_manager.spawn_loot(pos, p_loot_mult)
	fx_manager.spawn_death_fx(pos, type)
	fx_manager.spawn_floater(pos + Vector2(0, -40), "+$%d" % total_reward, Color(1.0, 0.85, 0.0))


func _on_wave_cleared() -> void:
	round_manager.trigger_upgrade()


func _on_loot_collected(type: String, amount: int) -> void:
	var text: String
	match type:
		"money":  text = "+$%d" % amount
		"health": text = "+%d HP" % amount
		"ammo":   text = "AMMO"
		"wood":   text = "+%d Wood" % amount
		"metal":  text = "+%d Metal" % amount
		_:        text = "+"
	fx_manager.spawn_floater(p_pos + Vector2(randf_range(-20, 20), -40), text, Color(0.6, 1.0, 0.6))


func _on_state_changed(new_state: String) -> void:
	hud.set_state(new_state)
	if new_state == "PLAYING":
		enemy_spawner.start_wave(current_round, zone_center, zone_radius)
	elif new_state == "FREEZE":
		hud.hide_upgrade()
		hud.hide_shop()


func _on_buy_phase_started(_duration: float, _money: int) -> void:
	hud.show_shop()


func _on_upgrade_choices(perks: Array) -> void:
	hud.show_upgrade(perks)


func _on_game_over() -> void:
	hud.set_state("GAME_OVER")
	hud.queue_redraw()


func _on_victory() -> void:
	hud.set_state("VICTORY")
	hud.queue_redraw()


func _on_shoot_pressed() -> void:
	if _aim_dir.length_squared() < 0.01:
		return
	combat_manager.try_shoot(p_pos, _aim_dir.normalized(), projectiles)


func _on_dash_pressed() -> void:
	if p_is_dashing or p_dash_cooldown > 0.0:
		return
	var dir := _move_dir if _move_dir.length_squared() > 0.01 else p_facing
	_dash_dir    = dir.normalized()
	_dash_timer  = Balance.DASH_DURATION
	p_is_dashing = true
	p_dash_cooldown = Balance.DASH_COOLDOWN
	p_invincible    = Balance.DASH_DURATION


func _on_shop_buy(weapon_id: String) -> void:
	if weapon_id not in Balance.WEAPONS:
		return
	var wd: Dictionary = Balance.WEAPONS[weapon_id]
	if p_owned_weapons.has(weapon_id):
		p_weapon   = weapon_id
		p_ammo     = wd["ammo"]
		p_max_ammo = wd["max_ammo"]
		hud.hide_shop()
		return
	if p_money < wd["price"]:
		return
	p_money -= wd["price"]
	p_owned_weapons.append(weapon_id)
	p_weapon   = weapon_id
	p_ammo     = wd["ammo"]
	p_max_ammo = wd["max_ammo"]
	combat_manager.set_reload_multiplier(p_reload_mult)
	hud.hide_shop()
	fx_manager.spawn_floater(p_pos + Vector2(0, -60), "GOT " + weapon_id.to_upper(), Color(1.0, 0.85, 0.0))
