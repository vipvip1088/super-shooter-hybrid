class_name HUD
extends Node2D

signal move_input(direction: Vector2)
signal aim_input(direction: Vector2)
signal shoot_pressed()
signal reload_pressed()
signal dash_pressed()
signal shop_buy(weapon_id: String)
signal craft_pressed(item: String)
signal perk_chosen(perk_key: String)

const JOYSTICK_RADIUS   := 70.0
const JOYSTICK_DEAD     := 0.12
const VIEWPORT_W        := 1080.0
const VIEWPORT_H        := 1920.0

var _gm: Node

# ── Joystick state ──────────────────────────────────────────────────────────
var _lj_touch:   int     = -1
var _lj_origin:  Vector2 = Vector2.ZERO
var _lj_current: Vector2 = Vector2.ZERO

var _rj_touch:   int     = -1
var _rj_origin:  Vector2 = Vector2.ZERO
var _rj_current: Vector2 = Vector2.ZERO

# ── Shop / Upgrade overlay ──────────────────────────────────────────────────
var _shop_visible:    bool  = false
var _upgrade_visible: bool  = false
var _upgrade_perks:   Array = []

# ── Cached state for drawing ────────────────────────────────────────────────
var _state:      String = "FREEZE"
var _round:      int    = 1
var _freeze_t:   float  = 0.0


func setup(game_manager: Node) -> void:
	_gm = game_manager
	set_process_input(true)


func show_shop() -> void:
	_shop_visible    = true
	_upgrade_visible = false
	queue_redraw()


func hide_shop() -> void:
	_shop_visible = false
	queue_redraw()


func show_upgrade(perks: Array) -> void:
	_upgrade_perks   = perks
	_upgrade_visible = true
	_shop_visible    = false
	queue_redraw()


func hide_upgrade() -> void:
	_upgrade_visible = false
	queue_redraw()


func set_state(s: String) -> void:
	_state = s
	queue_redraw()


func set_freeze_timer(t: float) -> void:
	_freeze_t = t
	queue_redraw()


# ── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var pos: Vector2 = event.position

	if event.pressed:
		# Overlays consume taps first
		if _upgrade_visible:
			_tap_upgrade(pos)
			return
		if _shop_visible:
			_tap_shop(pos)
			return

		# Button zones (top area)
		if _in_reload_btn(pos):
			emit_signal("reload_pressed")
			return
		if _in_dash_btn(pos):
			emit_signal("dash_pressed")
			return
		if _in_shop_btn(pos):
			show_shop()
			return

		# Left half → move joystick
		if pos.x < VIEWPORT_W * 0.5:
			_lj_touch   = event.index
			_lj_origin  = pos
			_lj_current = pos
		else:
			_rj_touch   = event.index
			_rj_origin  = pos
			_rj_current = pos
	else:
		if event.index == _lj_touch:
			_lj_touch = -1
			emit_signal("move_input", Vector2.ZERO)
		elif event.index == _rj_touch:
			_rj_touch = -1
			emit_signal("aim_input", Vector2.ZERO)
	queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _lj_touch:
		_lj_current = event.position
		var dir := _joystick_dir(_lj_origin, _lj_current)
		emit_signal("move_input", dir)
		queue_redraw()
	elif event.index == _rj_touch:
		_rj_current = event.position
		var dir := _joystick_dir(_rj_origin, _rj_current)
		if dir.length() > JOYSTICK_DEAD:
			emit_signal("aim_input", dir)
			emit_signal("shoot_pressed")
		queue_redraw()


func _joystick_dir(origin: Vector2, current: Vector2) -> Vector2:
	var raw := current - origin
	if raw.length() > JOYSTICK_RADIUS:
		raw = raw.normalized() * JOYSTICK_RADIUS
	var normalized := raw / JOYSTICK_RADIUS
	if normalized.length() < JOYSTICK_DEAD:
		return Vector2.ZERO
	return normalized


# ── Button hit-tests ─────────────────────────────────────────────────────────

func _in_reload_btn(pos: Vector2) -> bool:
	return _circle_hit(pos, Vector2(VIEWPORT_W - 130.0, 280.0), 50.0)


func _in_dash_btn(pos: Vector2) -> bool:
	return _circle_hit(pos, Vector2(VIEWPORT_W - 240.0, 340.0), 50.0)


func _in_shop_btn(pos: Vector2) -> bool:
	return _circle_hit(pos, Vector2(VIEWPORT_W - 60.0, 400.0), 40.0)


func _circle_hit(pos: Vector2, center: Vector2, r: float) -> bool:
	return pos.distance_to(center) <= r


# ── Overlay tap handlers ──────────────────────────────────────────────────────

func _tap_upgrade(pos: Vector2) -> void:
	for i in range(_upgrade_perks.size()):
		var cy := VIEWPORT_H * 0.35 + i * 180.0
		if abs(pos.y - cy) < 80.0:
			emit_signal("perk_chosen", _upgrade_perks[i])
			hide_upgrade()
			return
	emit_signal("perk_chosen", "")
	hide_upgrade()


func _tap_shop(pos: Vector2) -> void:
	if pos.y > VIEWPORT_H * 0.85:
		hide_shop()
		return
	var weapons := Balance.WEAPON_ORDER
	for i in range(weapons.size()):
		var cy := VIEWPORT_H * 0.25 + i * 140.0
		if abs(pos.y - cy) < 60.0:
			emit_signal("shop_buy", weapons[i])
			return
	hide_shop()


# ── Draw ─────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not _gm:
		return
	_draw_joysticks()
	_draw_buttons()
	_draw_stats()
	if _upgrade_visible:
		_draw_upgrade_overlay()
	elif _shop_visible:
		_draw_shop_overlay()
	elif _state == "FREEZE":
		_draw_freeze_overlay()
	elif _state == "GAME_OVER":
		_draw_game_over_overlay()
	elif _state == "VICTORY":
		_draw_victory_overlay()


func _draw_joysticks() -> void:
	# Left joystick
	if _lj_touch >= 0:
		draw_arc(_lj_origin, JOYSTICK_RADIUS, 0.0, TAU, 32, Color(1.0,1.0,1.0,0.25), 3.0)
		var knob := _lj_origin + clampf((_lj_current - _lj_origin).length(), 0.0, JOYSTICK_RADIUS) * (_lj_current - _lj_origin).normalized()
		draw_circle(knob, 30.0, Color(1.0,1.0,1.0,0.45))
	else:
		draw_arc(Vector2(180.0, VIEWPORT_H - 200.0), JOYSTICK_RADIUS, 0.0, TAU, 32, Color(1.0,1.0,1.0,0.12), 2.0)

	# Right joystick
	if _rj_touch >= 0:
		draw_arc(_rj_origin, JOYSTICK_RADIUS, 0.0, TAU, 32, Color(1.0,0.3,0.3,0.25), 3.0)
		var knob := _rj_origin + clampf((_rj_current - _rj_origin).length(), 0.0, JOYSTICK_RADIUS) * (_rj_current - _rj_origin).normalized()
		draw_circle(knob, 30.0, Color(1.0,0.3,0.3,0.45))
	else:
		draw_arc(Vector2(VIEWPORT_W - 180.0, VIEWPORT_H - 200.0), JOYSTICK_RADIUS, 0.0, TAU, 32, Color(1.0,0.3,0.3,0.12), 2.0)


func _draw_buttons() -> void:
	var font := ThemeDB.fallback_font

	# Reload button
	var reload_cd_ratio := 1.0
	if _gm.p_is_reloading:
		reload_cd_ratio = 1.0 - _gm.p_reload_timer / maxf(0.01, _gm.get("_reload_total") if _gm.get("_reload_total") else 0.01)
	var rc := Color(0.2, 0.8, 0.2, 0.85) if not _gm.p_is_reloading else Color(0.8, 0.8, 0.2, 0.85)
	draw_circle(Vector2(VIEWPORT_W - 130.0, 280.0), 50.0, Color(rc.r, rc.g, rc.b, 0.30))
	draw_arc(Vector2(VIEWPORT_W - 130.0, 280.0), 50.0, 0.0, TAU, 32, rc, 3.0)
	draw_string(font, Vector2(VIEWPORT_W - 160.0, 288.0), "RELOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, rc)

	# Dash button
	var dash_rdy := _gm.get("p_dash_cooldown") == null or _gm.p_dash_cooldown <= 0.0
	var dc := Color(0.4, 0.7, 1.0, 0.85) if dash_rdy else Color(0.4, 0.4, 0.5, 0.85)
	draw_circle(Vector2(VIEWPORT_W - 240.0, 340.0), 50.0, Color(dc.r, dc.g, dc.b, 0.30))
	draw_arc(Vector2(VIEWPORT_W - 240.0, 340.0), 50.0, 0.0, TAU, 32, dc, 3.0)
	draw_string(font, Vector2(VIEWPORT_W - 265.0, 348.0), "DASH", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, dc)

	# Shop button
	draw_circle(Vector2(VIEWPORT_W - 60.0, 400.0), 40.0, Color(1.0,0.85,0.0,0.25))
	draw_arc(Vector2(VIEWPORT_W - 60.0, 400.0), 40.0, 0.0, TAU, 24, Color(1.0,0.85,0.0,0.85), 3.0)
	draw_string(font, Vector2(VIEWPORT_W - 80.0, 408.0), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0,0.85,0.0))


func _draw_stats() -> void:
	if not _gm:
		return
	var font := ThemeDB.fallback_font
	var x    := 20.0
	var y    := 60.0

	# Round + state
	draw_string(font, Vector2(x, y), "Round %d" % _gm.current_round, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0,1.0,1.0,0.9))
	y += 36.0

	# Weapon + ammo
	var ammo_str := "%d / %d" % [_gm.p_ammo, _gm.p_max_ammo]
	var wc := Color(1.0,0.9,0.2)
	draw_string(font, Vector2(x, y), _gm.p_weapon.to_upper() + "  " + ammo_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, wc)
	y += 32.0

	# Money
	draw_string(font, Vector2(x, y), "$%d" % _gm.p_money, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0,0.85,0.0,0.9))
	y += 30.0

	# Wood / Metal
	draw_string(font, Vector2(x, y), "Wood:%d  Metal:%d" % [_gm.p_wood, _gm.p_metal], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7,0.55,0.3,0.85))

	# Zone timer top center
	if _gm.zone_timer > 0.0:
		var zt_str := "Zone: %.0fs" % _gm.zone_timer
		draw_string(font, Vector2(VIEWPORT_W * 0.5 - 60.0, 50.0), zt_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.25, 0.9, 1.0, 0.9))


func _draw_shop_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VIEWPORT_W, VIEWPORT_H), Color(0.0, 0.0, 0.0, 0.78))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 80.0, VIEWPORT_H * 0.12), "SHOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color.WHITE)
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 80.0, VIEWPORT_H * 0.17), "$%d" % _gm.p_money, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1.0,0.85,0.0))

	var weapons := Balance.WEAPON_ORDER
	for i in range(weapons.size()):
		var wid: String = weapons[i]
		var wd: Dictionary = Balance.WEAPONS[wid]
		var cy := VIEWPORT_H * 0.25 + i * 140.0
		var owned: bool = _gm.p_weapon == wid or _gm.p_owned_weapons.has(wid)
		var affordable: bool = _gm.p_money >= wd["price"] and not owned
		var bc := Color(0.2, 0.6, 0.2, 0.9) if affordable else Color(0.5, 0.5, 0.5, 0.6)
		draw_rect(Rect2(80.0, cy - 50.0, VIEWPORT_W - 160.0, 100.0), Color(0.1,0.1,0.15,0.9))
		draw_rect(Rect2(80.0, cy - 50.0, VIEWPORT_W - 160.0, 100.0), bc, false, 2.0)
		var label := "%s  DMG:%d  $%d%s" % [wid.to_upper(), int(wd["damage"]), wd["price"], " (owned)" if owned else ""]
		draw_string(font, Vector2(110.0, cy + 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, bc)

	draw_rect(Rect2(80.0, VIEWPORT_H * 0.85, VIEWPORT_W - 160.0, 70.0), Color(0.8,0.2,0.2,0.85))
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 60.0, VIEWPORT_H * 0.85 + 44.0), "CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)


func _draw_upgrade_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VIEWPORT_W, VIEWPORT_H), Color(0.0,0.0,0.0,0.85))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 120.0, VIEWPORT_H * 0.15), "CHOOSE PERK", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1.0,0.85,0.0))

	for i in range(_upgrade_perks.size()):
		var key: String = _upgrade_perks[i]
		var perk: Dictionary = Balance.PERKS.get(key, {})
		if perk.is_empty():
			continue
		var cy := VIEWPORT_H * 0.35 + i * 180.0
		draw_rect(Rect2(80.0, cy - 70.0, VIEWPORT_W - 160.0, 140.0), Color(0.12,0.12,0.18,0.95))
		draw_rect(Rect2(80.0, cy - 70.0, VIEWPORT_W - 160.0, 140.0), Color(1.0,0.85,0.0,0.9), false, 2.5)
		draw_string(font, Vector2(110.0, cy - 10.0), perk["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1.0,0.85,0.0))
		draw_string(font, Vector2(110.0, cy + 35.0), perk["desc"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85,0.85,0.85))

	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 100.0, VIEWPORT_H * 0.88), "Tap anywhere to skip", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6,0.6,0.6))


func _draw_freeze_overlay() -> void:
	var font := ThemeDB.fallback_font
	var r := int(_freeze_t) + 1
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 30.0, VIEWPORT_H * 0.45), str(r), HORIZONTAL_ALIGNMENT_LEFT, -1, 96, Color(1.0,1.0,1.0,0.85))
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 100.0, VIEWPORT_H * 0.55), "Round %d" % _gm.current_round, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1.0,0.85,0.0))


func _draw_game_over_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VIEWPORT_W, VIEWPORT_H), Color(0.0,0.0,0.0,0.75))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 130.0, VIEWPORT_H * 0.40), "GAME OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color(1.0,0.2,0.2))
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 150.0, VIEWPORT_H * 0.52), "Round: %d" % _gm.current_round, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color.WHITE)
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 150.0, VIEWPORT_H * 0.60), "Money: $%d" % _gm.p_money, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1.0,0.85,0.0))


func _draw_victory_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VIEWPORT_W, VIEWPORT_H), Color(0.0,0.0,0.0,0.70))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 130.0, VIEWPORT_H * 0.38), "VICTORY!", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1.0,0.85,0.0))
	draw_string(font, Vector2(VIEWPORT_W * 0.5 - 160.0, VIEWPORT_H * 0.52), "All 10 rounds cleared!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
