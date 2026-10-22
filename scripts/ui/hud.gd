class_name HUD
extends Node2D

signal move_input(direction: Vector2)
signal aim_input(direction: Vector2)
signal shoot_pressed()
signal reload_pressed()
signal dash_pressed()
signal ultimate_pressed()
signal shop_buy(weapon_id: String)
signal craft_action(recipe_id: String)
signal perk_chosen(perk_key: String)
signal hero_chosen(hero_id: String)
signal level_perk_chosen(perk_key: String)

const JOYSTICK_RADIUS := 70.0
const JOYSTICK_DEAD   := 0.12
const VW              := 1080.0
const VH              := 1920.0

var _gm: Node

var _lj_touch:   int     = -1
var _lj_origin:  Vector2 = Vector2.ZERO
var _lj_current: Vector2 = Vector2.ZERO
var _rj_touch:   int     = -1
var _rj_origin:  Vector2 = Vector2.ZERO
var _rj_current: Vector2 = Vector2.ZERO

var _state:             String = "FREEZE"
var _freeze_t:          float  = 0.0
var _shop_visible:      bool   = false
var _upgrade_visible:   bool   = false
var _craft_visible:     bool   = false
var _hero_select_vis:   bool   = true
var _level_up_vis:      bool   = false
var _upgrade_perks:     Array  = []
var _level_up_perks:    Array  = []
var _level_up_level:    int    = 1
var _shop_tab:          int    = 0   # 0=weapons, 1=shop items


func setup(game_manager: Node) -> void:
	_gm = game_manager
	set_process_input(true)


func show_shop() -> void:
	_shop_visible    = true
	_upgrade_visible = false
	_craft_visible   = false
	queue_redraw()


func hide_shop() -> void:
	_shop_visible = false
	queue_redraw()


func show_craft() -> void:
	_craft_visible   = true
	_shop_visible    = false
	_upgrade_visible = false
	queue_redraw()


func hide_craft() -> void:
	_craft_visible = false
	queue_redraw()


func show_upgrade(perks: Array) -> void:
	_upgrade_perks   = perks
	_upgrade_visible = true
	_shop_visible    = false
	_craft_visible   = false
	queue_redraw()


func hide_upgrade() -> void:
	_upgrade_visible = false
	queue_redraw()


func show_hero_select() -> void:
	_hero_select_vis = true
	queue_redraw()


func hide_hero_select() -> void:
	_hero_select_vis = false
	queue_redraw()


func show_level_up(perks: Array, level: int) -> void:
	_level_up_perks  = perks
	_level_up_level  = level
	_level_up_vis    = true
	queue_redraw()


func hide_level_up() -> void:
	_level_up_vis = false
	queue_redraw()


func set_state(s: String) -> void:
	_state = s
	queue_redraw()


func set_freeze_timer(t: float) -> void:
	_freeze_t = t
	queue_redraw()


# ── Input ──────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var pos: Vector2 = event.position

	if event.pressed:
		if _hero_select_vis:
			_tap_hero_select(pos)
			return
		if _level_up_vis:
			_tap_level_up(pos)
			return
		if _upgrade_visible:
			_tap_upgrade(pos)
			return
		if _craft_visible:
			_tap_craft(pos)
			return
		if _shop_visible:
			_tap_shop(pos)
			return

		if _in_btn(pos, _btn_reload()):
			emit_signal("reload_pressed"); return
		if _in_btn(pos, _btn_dash()):
			emit_signal("dash_pressed");   return
		if _in_btn(pos, _btn_ult()):
			emit_signal("ultimate_pressed"); return
		if _in_btn(pos, _btn_shop()):
			show_shop(); return
		if _in_btn(pos, _btn_craft()):
			show_craft(); return

		if pos.x < VW * 0.5:
			_lj_touch = event.index; _lj_origin = pos; _lj_current = pos
		else:
			_rj_touch = event.index; _rj_origin = pos; _rj_current = pos
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
		emit_signal("move_input", _joystick_dir(_lj_origin, _lj_current))
		queue_redraw()
	elif event.index == _rj_touch:
		_rj_current = event.position
		var dir := _joystick_dir(_rj_origin, _rj_current)
		if dir.length() > JOYSTICK_DEAD:
			emit_signal("aim_input",   dir)
			emit_signal("shoot_pressed")
		queue_redraw()


func _joystick_dir(origin: Vector2, current: Vector2) -> Vector2:
	var raw := current - origin
	if raw.length() > JOYSTICK_RADIUS:
		raw = raw.normalized() * JOYSTICK_RADIUS
	var norm := raw / JOYSTICK_RADIUS
	if norm.length() < JOYSTICK_DEAD:
		return Vector2.ZERO
	return norm


# ── Button definitions ──────────────────────────────────────────────────────

func _btn_reload() -> Rect2:
	return Rect2(VW - 180.0, 220.0, 120.0, 80.0)

func _btn_dash() -> Rect2:
	return Rect2(VW - 300.0, 320.0, 110.0, 70.0)

func _btn_ult() -> Rect2:
	return Rect2(VW - 180.0, 320.0, 120.0, 80.0)

func _btn_shop() -> Rect2:
	return Rect2(VW - 90.0, 420.0, 80.0, 60.0)

func _btn_craft() -> Rect2:
	return Rect2(VW - 90.0, 490.0, 80.0, 60.0)

func _in_btn(pos: Vector2, rect: Rect2) -> bool:
	return rect.has_point(pos)


# ── Overlay tap handlers ────────────────────────────────────────────────────

func _tap_hero_select(pos: Vector2) -> void:
	var heroes := Balance.HERO_ORDER
	for i in range(heroes.size()):
		var cy := VH * 0.25 + i * 200.0
		if abs(pos.y - cy) < 85.0:
			emit_signal("hero_chosen", heroes[i])
			return


func _tap_upgrade(pos: Vector2) -> void:
	for i in range(_upgrade_perks.size()):
		var cy := VH * 0.35 + i * 190.0
		if abs(pos.y - cy) < 80.0:
			emit_signal("perk_chosen", _upgrade_perks[i])
			hide_upgrade()
			return
	emit_signal("perk_chosen", "")
	hide_upgrade()


func _tap_level_up(pos: Vector2) -> void:
	for i in range(_level_up_perks.size()):
		var cy := VH * 0.35 + i * 190.0
		if abs(pos.y - cy) < 80.0:
			emit_signal("level_perk_chosen", _level_up_perks[i])
			return
	emit_signal("level_perk_chosen", "")
	hide_level_up()


func _tap_shop(pos: Vector2) -> void:
	if pos.y > VH * 0.88:
		hide_shop(); return
	# Tab switching
	if pos.y < VH * 0.23:
		if pos.x < VW * 0.5:
			_shop_tab = 0
		else:
			_shop_tab = 1
		queue_redraw(); return

	if _shop_tab == 0:
		var weapons := Balance.WEAPON_ORDER
		for i in range(weapons.size()):
			var cy := VH * 0.27 + i * 130.0
			if abs(pos.y - cy) < 55.0:
				emit_signal("shop_buy", weapons[i])
				return
	hide_shop()


func _tap_craft(pos: Vector2) -> void:
	if pos.y > VH * 0.88:
		hide_craft(); return
	var recipes := Balance.CRAFTING.keys()
	for i in range(recipes.size()):
		var cy := VH * 0.22 + i * 130.0
		if abs(pos.y - cy) < 55.0:
			emit_signal("craft_action", recipes[i])
			return
	hide_craft()


# ── Draw ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if not _gm:
		return
	if _hero_select_vis:
		_draw_hero_select()
		return

	_draw_joysticks()
	_draw_buttons()
	_draw_stats()

	if _level_up_vis:
		_draw_level_up_overlay()
	elif _upgrade_visible:
		_draw_upgrade_overlay()
	elif _craft_visible:
		_draw_craft_overlay()
	elif _shop_visible:
		_draw_shop_overlay()
	elif _state == "FREEZE":
		_draw_freeze_overlay()
	elif _state == "GAME_OVER":
		_draw_game_over_overlay()
	elif _state == "VICTORY":
		_draw_victory_overlay()


func _draw_hero_select() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.04, 0.04, 0.08))
	var font := ThemeDB.fallback_font

	draw_string(font, Vector2(VW * 0.5 - 170.0, 100.0), "ВЫБЕРИТЕ ГЕРОЯ",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color(1.0, 0.85, 0.0))

	var heroes := Balance.HERO_ORDER
	for i in range(heroes.size()):
		var hid: String  = heroes[i]
		var hd: Dictionary = Balance.HEROES[hid]
		var cy := VH * 0.25 + i * 200.0

		var hc := Color(float(hd["color_r"]), float(hd["color_g"]), float(hd["color_b"]))
		draw_rect(Rect2(60.0, cy - 80.0, VW - 120.0, 155.0), Color(0.1, 0.1, 0.15))
		draw_rect(Rect2(60.0, cy - 80.0, VW - 120.0, 155.0), hc, false, 3.0)

		draw_circle(Vector2(130.0, cy - 5.0), 45.0, hc.darkened(0.3))
		draw_arc(Vector2(130.0, cy - 5.0), 45.0, 0.0, TAU, 32, hc, 3.0)

		draw_string(font, Vector2(200.0, cy - 30.0), hd["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 36, hc)
		draw_string(font, Vector2(200.0, cy + 15.0), hd["desc"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85, 0.85, 0.85))
		draw_string(font, Vector2(200.0, cy + 55.0),
			hd["ult_name"] + ": " + hd["ult_desc"],
			HORIZONTAL_ALIGNMENT_LEFT, int(VW - 230.0), 20, Color(0.6, 0.9, 0.6))

	draw_string(font, Vector2(VW * 0.5 - 100.0, VH * 0.94),
		"Коснитесь героя для выбора", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.6, 0.6))


func _draw_joysticks() -> void:
	var font := ThemeDB.fallback_font
	if _lj_touch >= 0:
		draw_arc(_lj_origin, JOYSTICK_RADIUS, 0.0, TAU, 32, Color(1,1,1,0.25), 3.0)
		var delta_raw := _lj_current - _lj_origin
		var knob := _lj_origin + delta_raw.normalized() * minf(delta_raw.length(), JOYSTICK_RADIUS)
		draw_circle(knob, 28.0, Color(1,1,1,0.45))
	else:
		draw_arc(Vector2(180.0, VH - 200.0), JOYSTICK_RADIUS, 0.0, TAU, 32,
			Color(1,1,1,0.12), 2.0)
		draw_string(font, Vector2(155.0, VH - 195.0), "MOVE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1,1,1,0.3))

	if _rj_touch >= 0:
		draw_arc(_rj_origin, JOYSTICK_RADIUS, 0.0, TAU, 32, Color(1,0.3,0.3,0.25), 3.0)
		var delta_raw2 := _rj_current - _rj_origin
		var knob2 := _rj_origin + delta_raw2.normalized() * minf(delta_raw2.length(), JOYSTICK_RADIUS)
		draw_circle(knob2, 28.0, Color(1,0.3,0.3,0.45))
	else:
		draw_arc(Vector2(VW - 180.0, VH - 200.0), JOYSTICK_RADIUS, 0.0, TAU, 32,
			Color(1,0.3,0.3,0.12), 2.0)
		draw_string(font, Vector2(VW - 208.0, VH - 195.0), "AIM/FIRE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1,0.3,0.3,0.3))


func _draw_buttons() -> void:
	var font := ThemeDB.fallback_font

	# Reload
	var rc := Color(0.2,0.85,0.2) if not _gm.p_is_reloading else Color(0.9,0.9,0.2)
	_draw_btn(_btn_reload(), "RELOAD", rc, font)

	# Dash
	var dash_rdy: bool = float(_gm.p_dash_cooldown) <= 0.0
	_draw_btn(_btn_dash(), "DASH", Color(0.4,0.7,1.0) if dash_rdy else Color(0.3,0.3,0.5), font)

	# Ultimate
	var ult_rdy: bool = float(_gm.p_ultimate_cd) <= 0.0
	var ult_c := Color(1.0,0.6,0.0) if ult_rdy else Color(0.4,0.3,0.1)
	var h_data: Dictionary = Balance.HEROES.get(_gm.p_hero, {})
	var ult_label: String = h_data.get("ult_name", "ULT") if not h_data.is_empty() else "ULT"
	if not ult_rdy:
		ult_label += " %.0fs" % float(_gm.p_ultimate_cd)
	_draw_btn(_btn_ult(), ult_label, ult_c, font)

	# Shop
	_draw_btn(_btn_shop(), "SHOP", Color(1.0,0.85,0.0), font)

	# Craft
	_draw_btn(_btn_craft(), "CRAFT", Color(0.7,0.55,0.3), font)

	# Reload progress arc
	if _gm.p_is_reloading:
		var wd: Dictionary = Balance.WEAPONS.get(_gm.p_weapon, {})
		var reload_total: float = (float(wd.get("reload_time", 1.0)) / float(_gm.p_reload_mult)) if not wd.is_empty() else 1.0
		var pct := 1.0 - _gm.p_reload_timer / maxf(reload_total, 0.01)
		var r2 := _btn_reload()
		var c2 := r2.get_center()
		draw_arc(c2, 30.0, -PI * 0.5, -PI * 0.5 + TAU * pct, 24, Color(0.3,1.0,0.3,0.9), 4.0)


func _draw_btn(rect: Rect2, label: String, color: Color, font: Font) -> void:
	draw_rect(rect, Color(color.r, color.g, color.b, 0.25))
	draw_rect(rect, color, false, 2.0)
	var cx := rect.position.x + rect.size.x * 0.5 - 30.0
	var cy := rect.position.y + rect.size.y * 0.5 + 8.0
	draw_string(font, Vector2(cx, cy), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)


func _draw_stats() -> void:
	if not _gm:
		return
	var font := ThemeDB.fallback_font
	var x := 20.0
	var y := 55.0

	# HP bar
	var hp_w := 240.0
	draw_rect(Rect2(x, y, hp_w, 14.0), Color(0.2, 0.0, 0.0))
	var hf: float = maxf(0.0, float(_gm.p_hp) / float(_gm.p_max_hp))
	draw_rect(Rect2(x, y, hp_w * hf, 14.0),
		Color(0.1, 0.9, 0.2) if hf > 0.4 else Color(0.9, 0.3, 0.1))
	draw_rect(Rect2(x, y, hp_w, 14.0), Color(1,1,1,0.4), false, 1.0)
	draw_string(font, Vector2(x + 5.0, y + 11.0),
		"%.0f / %.0f" % [float(_gm.p_hp), float(_gm.p_max_hp)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	y += 22.0

	# Shield bar
	if float(_gm.p_shield) > 0.0:
		draw_rect(Rect2(x, y, hp_w * minf(float(_gm.p_shield) / 50.0, 1.0), 8.0),
			Color(0.3, 0.6, 1.0))
		y += 14.0

	# XP bar
	var xp_w := 200.0
	var xp_pct := float(_gm.p_xp) / float(maxi(_gm.p_xp_to_next, 1))
	draw_rect(Rect2(x, y, xp_w, 7.0), Color(0.1, 0.1, 0.2))
	draw_rect(Rect2(x, y, xp_w * xp_pct, 7.0), Color(0.5, 0.3, 1.0))
	draw_string(font, Vector2(x + xp_w + 5.0, y + 6.0),
		"Lv.%d" % _gm.p_level, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.5, 1.0))
	y += 16.0

	# Round
	draw_string(font, Vector2(x, y), "Round %d" % _gm.current_round,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1,1,1,0.9))
	y += 32.0

	# Weapon + ammo
	var wc := Color(1.0, 0.9, 0.2)
	if _gm.p_weapon in Balance.WEAPONS:
		var wd: Dictionary = Balance.WEAPONS[_gm.p_weapon]
		var rarity: String = wd.get("rarity", "common")
		wc = Balance.RARITY_COLORS.get(rarity, wc)
	draw_string(font, Vector2(x, y),
		_gm.p_weapon.to_upper() + "  %d/%d" % [_gm.p_ammo, _gm.p_max_ammo],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, wc)
	y += 28.0

	# Money + resources
	draw_string(font, Vector2(x, y), "$%d" % _gm.p_money,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.0, 0.9))
	y += 24.0
	draw_string(font, Vector2(x, y),
		"W:%d M:%d C:%d 💎%d" % [_gm.p_wood, _gm.p_metal, _gm.p_chips, _gm.p_crystals],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.6, 0.4, 0.85))

	# Zone timer — top center
	if float(_gm.zone_timer) > 0.0:
		draw_string(font, Vector2(VW * 0.5 - 70.0, 48.0),
			"Zone %.0fs" % float(_gm.zone_timer),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.25, 0.9, 1.0, 0.9))


func _draw_shop_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, 0.82))
	var font := ThemeDB.fallback_font

	# Header
	draw_string(font, Vector2(VW * 0.5 - 60.0, 80.0), "SHOP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color.WHITE)
	draw_string(font, Vector2(VW * 0.5 - 60.0, 130.0), "$%d" % _gm.p_money,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1.0, 0.85, 0.0))

	# Tab buttons
	var tab0_c := Color(0.3,0.7,1.0) if _shop_tab == 0 else Color(0.3,0.3,0.4)
	var tab1_c := Color(0.7,0.55,0.3) if _shop_tab == 1 else Color(0.3,0.3,0.4)
	draw_rect(Rect2(60.0, 155.0, VW * 0.5 - 70.0, 46.0), Color(tab0_c.r,tab0_c.g,tab0_c.b,0.3))
	draw_rect(Rect2(60.0, 155.0, VW * 0.5 - 70.0, 46.0), tab0_c, false, 2.0)
	draw_string(font, Vector2(120.0, 184.0), "WEAPONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tab0_c)
	draw_rect(Rect2(VW * 0.5 + 10.0, 155.0, VW * 0.5 - 70.0, 46.0), Color(tab1_c.r,tab1_c.g,tab1_c.b,0.3))
	draw_rect(Rect2(VW * 0.5 + 10.0, 155.0, VW * 0.5 - 70.0, 46.0), tab1_c, false, 2.0)
	draw_string(font, Vector2(VW * 0.5 + 50.0, 184.0), "ITEMS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tab1_c)

	if _shop_tab == 0:
		var weapons := Balance.WEAPON_ORDER
		for i in range(weapons.size()):
			var wid: String = weapons[i]
			var wd: Dictionary = Balance.WEAPONS[wid]
			var cy := VH * 0.145 + (i + 1) * 130.0
			var owned: bool = _gm.p_owned_weapons.has(wid)
			var can_buy: bool = int(_gm.p_money) >= int(wd["price"]) and not owned
			var rarity: String = wd.get("rarity", "common")
			var rar_c: Color = Balance.RARITY_COLORS.get(rarity, Color.WHITE)
			var bc := rar_c if can_buy else (Color(0.6,0.8,0.6) if owned else Color(0.4,0.4,0.4))
			draw_rect(Rect2(60.0, cy - 48.0, VW - 120.0, 94.0), Color(0.1,0.1,0.14,0.95))
			draw_rect(Rect2(60.0, cy - 48.0, VW - 120.0, 94.0), bc, false, 2.0)
			var label := "%s [%s]  DMG:%.0f  AOE:%.0f  $%d%s" % [
				wid.to_upper(), rarity.to_upper(), float(wd["damage"]),
				float(wd["aoe"]), int(wd["price"]),
				" ✓" if owned else ""
			]
			draw_string(font, Vector2(90.0, cy + 8.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, int(VW - 120.0), 22, bc)
	else:
		draw_string(font, Vector2(100.0, VH * 0.28), "(Items shop - coming soon)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.6,0.6,0.6))

	draw_rect(Rect2(60.0, VH * 0.885, VW - 120.0, 68.0), Color(0.7,0.1,0.1,0.9))
	draw_string(font, Vector2(VW * 0.5 - 60.0, VH * 0.885 + 44.0), "CLOSE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)


func _draw_craft_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, 0.82))
	var font := ThemeDB.fallback_font

	draw_string(font, Vector2(VW * 0.5 - 80.0, 80.0), "CRAFTING",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(0.8, 0.6, 0.2))
	draw_string(font, Vector2(60.0, 130.0),
		"Wood:%d  Metal:%d  Chips:%d" % [_gm.p_wood, _gm.p_metal, _gm.p_chips],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.7, 0.5))

	var recipes := Balance.CRAFTING.keys()
	for i in range(recipes.size()):
		var rid: String = recipes[i]
		var rd: Dictionary = Balance.CRAFTING[rid]
		var cy := VH * 0.115 + (i + 1) * 130.0

		var cost_w := int(rd.get("wood",  0))
		var cost_m := int(rd.get("metal", 0))
		var cost_c := int(rd.get("chips", 0))
		var can_craft: bool = _gm.p_wood >= cost_w and _gm.p_metal >= cost_m and _gm.p_chips >= cost_c

		var bc := Color(0.7, 0.55, 0.3) if can_craft else Color(0.35, 0.28, 0.15)
		draw_rect(Rect2(60.0, cy - 48.0, VW - 120.0, 94.0), Color(0.12,0.1,0.06,0.95))
		draw_rect(Rect2(60.0, cy - 48.0, VW - 120.0, 94.0), bc, false, 2.0)

		draw_string(font, Vector2(90.0, cy - 12.0), rd.get("desc", rid),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, bc)
		var cost_str := "Wood:%d Metal:%d Chips:%d" % [cost_w, cost_m, cost_c]
		draw_string(font, Vector2(90.0, cy + 28.0), cost_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(bc.r, bc.g, bc.b, 0.75))

	draw_rect(Rect2(60.0, VH * 0.885, VW - 120.0, 68.0), Color(0.7,0.1,0.1,0.9))
	draw_string(font, Vector2(VW * 0.5 - 60.0, VH * 0.885 + 44.0), "CLOSE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)


func _draw_upgrade_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, 0.88))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(VW * 0.5 - 140.0, 120.0), "ROUND UPGRADE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1.0, 0.85, 0.0))
	_draw_perk_cards(_upgrade_perks, font, false)
	draw_string(font, Vector2(VW * 0.5 - 110.0, VH * 0.90),
		"Tap a card to choose", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.55, 0.55, 0.55))


func _draw_level_up_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, 0.88))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(VW * 0.5 - 140.0, 90.0),
		"LEVEL UP!  Lv.%d" % _level_up_level,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(0.6, 0.3, 1.0))
	_draw_perk_cards(_level_up_perks, font, true)
	draw_string(font, Vector2(VW * 0.5 - 110.0, VH * 0.90),
		"Choose a mutation", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.55, 0.55, 0.55))


func _draw_perk_cards(perks: Array, font: Font, purple: bool) -> void:
	var header_c := Color(0.6, 0.3, 1.0) if purple else Color(1.0, 0.85, 0.0)
	for i in range(perks.size()):
		var key: String = perks[i]
		var perk: Dictionary = Balance.PERKS.get(key, {})
		if perk.is_empty():
			continue
		var cy := VH * 0.33 + i * 190.0
		draw_rect(Rect2(60.0, cy - 76.0, VW - 120.0, 150.0), Color(0.1, 0.1, 0.18, 0.95))
		draw_rect(Rect2(60.0, cy - 76.0, VW - 120.0, 150.0), header_c, false, 2.5)
		draw_string(font, Vector2(100.0, cy - 22.0), perk["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, header_c)
		draw_string(font, Vector2(100.0, cy + 28.0), perk["desc"],
			HORIZONTAL_ALIGNMENT_LEFT, int(VW - 140.0), 24, Color(0.88, 0.88, 0.88))


func _draw_freeze_overlay() -> void:
	var font := ThemeDB.fallback_font
	var n := int(_freeze_t) + 1
	draw_string(font, Vector2(VW * 0.5 - 40.0, VH * 0.44), str(n),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 100, Color(1,1,1,0.88))
	draw_string(font, Vector2(VW * 0.5 - 120.0, VH * 0.56),
		"Round %d" % _gm.current_round,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(1.0, 0.85, 0.0))


func _draw_game_over_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, 0.78))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(VW * 0.5 - 150.0, VH * 0.38), "GAME OVER",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color(1.0, 0.18, 0.18))
	draw_string(font, Vector2(VW * 0.5 - 160.0, VH * 0.50),
		"Round: %d   Kills: %d" % [_gm.current_round, _gm.p_kill_count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
	draw_string(font, Vector2(VW * 0.5 - 160.0, VH * 0.58),
		"Money: $%d   Level: %d" % [_gm.p_money, _gm.p_level],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1.0, 0.85, 0.0))
	draw_string(font, Vector2(VW * 0.5 - 100.0, VH * 0.68),
		"Crystals: %d 💎" % _gm.p_crystals,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.5, 0.8, 1.0))


func _draw_victory_overlay() -> void:
	draw_rect(Rect2(0.0, 0.0, VW, VH), Color(0.0, 0.0, 0.0, 0.72))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(VW * 0.5 - 150.0, VH * 0.36), "VICTORY!",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 66, Color(1.0, 0.85, 0.0))
	draw_string(font, Vector2(VW * 0.5 - 180.0, VH * 0.50),
		"All 10 rounds survived!", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
	draw_string(font, Vector2(VW * 0.5 - 150.0, VH * 0.60),
		"Crystals: %d 💎" % _gm.p_crystals, HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
		Color(0.5, 0.8, 1.0))
