class_name HUD3D
extends CanvasLayer

# ── Signals ────────────────────────────────────────────────────────────────────
signal move_input(dir: Vector2)
signal look_input(delta: Vector2)
signal fire_held(state: bool)
signal reload_pressed
signal dash_pressed
signal ult_pressed
signal weapon_next
signal weapon_prev
signal perk_chosen(key: String)
signal shop_buy(weapon_id: String)
signal empty_clicked

# ── Touch IDs ──────────────────────────────────────────────────────────────────
var _left_id:  int = -1
var _right_id: int = -1
var _left_orig:  Vector2
var _left_cur:   Vector2
var _right_prev: Vector2
var _button_touches: Dictionary = {}  # touch_index → button_name
const STICK_RADIUS := 88.0

# ── Game state (set by GM each frame) ─────────────────────────────────────────
var hp: float       = 100.0
var max_hp: float   = 100.0
var shield: float   = 0.0
var max_shield: float = 50.0
var ammo: int       = 30
var max_ammo: int   = 30
var is_reloading: bool  = false
var reload_progress: float = 0.0
var wave: int   = 1
var score: int  = 0
var combo: int  = 0
var enemy_count: int = 0
var dash_cd: float  = 0.0
var ult_cd: float   = 0.0
var ult_max_cd: float = 30.0
var p_xp: int       = 0
var p_xp_next: int  = 100
var p_level: int    = 1
var money: int      = 0
var current_weapon: String = "ar"
var zone_warning: bool = false

# ── Kill feed ──────────────────────────────────────────────────────────────────
var _feed: Array = []       # {text, timer}
const FEED_MAX := 5
const FEED_DURATION := 3.5

# ── Screen-edge hit ────────────────────────────────────────────────────────────
var _hit_flash: float = 0.0
var _hit_dir: Vector2 = Vector2.ZERO

# ── Overlays ───────────────────────────────────────────────────────────────────
var _perk_opts: Array = []
var _show_perk: bool  = false
var _show_shop: bool  = false
var _fire_vis: bool   = false
var _show_game_over: bool = false
var _go_wave: int = 0; var _go_kills: int = 0; var _go_score: int = 0

# ── Draw node ──────────────────────────────────────────────────────────────────
var _draw: Control
var _vp: Vector2 = Vector2(1080, 1920)


func setup(_gm: Node) -> void:
	layer = 10
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_draw)
	_draw.draw.connect(_on_draw)


func _process(_d: float) -> void:
	_vp = get_viewport().get_visible_rect().size
	_draw.queue_redraw()
	# Tick kill feed
	for i in range(_feed.size() - 1, -1, -1):
		_feed[i]["timer"] -= _d
		if _feed[i]["timer"] <= 0.0:
			_feed.remove_at(i)
	_hit_flash = maxf(0.0, _hit_flash - _d * 4.0)


# ── Input ──────────────────────────────────────────────────────────────────────
func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		_handle_touch(ev)
	elif ev is InputEventScreenDrag:
		_handle_drag(ev)


func _handle_touch(ev: InputEventScreenTouch) -> void:
	var pos := ev.position
	var s   := _vp.y / 1920.0

	if ev.pressed:
		# ── Overlays intercept ALL touches ─────────────────────────────────
		if _show_game_over:
			get_tree().reload_current_scene(); return
		if _show_perk:
			_try_perk_tap(pos, s); return
		if _show_shop:
			_try_shop_tap(pos, s); return

		# ── Left joystick zone ──────────────────────────────────────────────
		if pos.x < _vp.x * 0.44 and pos.y > _vp.y * 0.52:
			if _left_id == -1:
				_left_id = ev.index; _left_orig = pos; _left_cur = pos
			return

		# ── Button zones ────────────────────────────────────────────────────
		var btns := _btn_rects(s)
		for bname in btns:
			if btns[bname].has_point(pos):
				_button_touches[ev.index] = bname
				_on_press(bname)
				return

		# ── Right aim zone ──────────────────────────────────────────────────
		if pos.x >= _vp.x * 0.44:
			if _right_id == -1:
				_right_id = ev.index; _right_prev = pos
	else:
		# ── Releases ─────────────────────────────────────────────────────────
		if ev.index == _left_id:
			_left_id = -1
			emit_signal("move_input", Vector2.ZERO)
		if ev.index == _right_id:
			_right_id = -1
		if _button_touches.has(ev.index):
			_on_release(_button_touches[ev.index])
			_button_touches.erase(ev.index)


func _handle_drag(ev: InputEventScreenDrag) -> void:
	if ev.index == _left_id:
		_left_cur = ev.position
		var delta := (_left_cur - _left_orig) / (STICK_RADIUS * _vp.y / 1920.0)
		if delta.length() > 1.0: delta = delta.normalized()
		emit_signal("move_input", Vector2(delta.x, -delta.y))
	elif ev.index == _right_id:
		emit_signal("look_input", ev.relative)


# ── Button press/release ───────────────────────────────────────────────────────
func _on_press(name: String) -> void:
	match name:
		"fire":
			_fire_vis = true
			emit_signal("fire_held", true)
		"reload":
			emit_signal("reload_pressed")
		"dash":
			emit_signal("dash_pressed")
		"ult":
			emit_signal("ult_pressed")
		"wpn_next":
			emit_signal("weapon_next")
		"wpn_prev":
			emit_signal("weapon_prev")


func _on_release(name: String) -> void:
	match name:
		"fire":
			_fire_vis = false
			emit_signal("fire_held", false)


# ── Overlay tap handlers ───────────────────────────────────────────────────────
func _try_perk_tap(pos: Vector2, s: float) -> void:
	if _perk_opts.is_empty(): return
	var card_w := 260.0 * s; var card_h := 340.0 * s
	var n := _perk_opts.size()
	var total_w := card_w * n + 28.0 * s * (n - 1)
	var sx := (_vp.x - total_w) * 0.5
	for i in range(n):
		var r := Rect2(sx + i * (card_w + 28.0*s), 280.0*s, card_w, card_h)
		if r.has_point(pos):
			emit_signal("perk_chosen", _perk_opts[i])
			_show_perk = false
			return
	# Tap X (close only if desired — perk screen forces choice, so no auto-close)


func _try_shop_tap(pos: Vector2, s: float) -> void:
	# Close button
	if Rect2(_vp.x - 110*s, 70*s, 90*s, 90*s).has_point(pos):
		_show_shop = false; return
	var weapons := Balance.WEAPON3D_ORDER
	var cw := 200.0*s; var ch := 260.0*s; var pad := 22.0*s; var cols := 3
	for i in range(weapons.size()):
		var wid: String = weapons[i]
		var cx := 40.0*s + (i % cols) * (cw + pad)
		var cy := 250.0*s + (i / cols) * (ch + pad)
		if Rect2(cx, cy, cw, ch).has_point(pos):
			emit_signal("shop_buy", wid)
			return
	_show_shop = false  # tap outside = close


# ── Public API ─────────────────────────────────────────────────────────────────
func update_hp(cur: float, mx: float) -> void:   hp = cur; max_hp = mx
func update_ammo(cur: int, mx: int) -> void:      ammo = cur; max_ammo = mx
func update_wave(w: int, ec: int) -> void:        wave = w; enemy_count = ec
func update_xp(xp: int, nxt: int, lv: int) -> void: p_xp = xp; p_xp_next = nxt; p_level = lv
func update_money(m: int) -> void:               money = m
func update_reload(r: bool, p: float) -> void:   is_reloading = r; reload_progress = p
func update_dash_cd(cd: float) -> void:          dash_cd = cd
func update_ult(cd: float, mx: float) -> void:   ult_cd = cd; ult_max_cd = mx
func update_weapon(wid: String) -> void:         current_weapon = wid
func set_zone_warning(w: bool) -> void:          zone_warning = w

func add_kill_feed(text: String) -> void:
	_feed.append({"text": text, "timer": FEED_DURATION})
	if _feed.size() > FEED_MAX: _feed.pop_front()

func trigger_hit_flash() -> void:
	_hit_flash = 1.0

func show_perk_choice(opts: Array) -> void:
	_perk_opts = opts; _show_perk = true

func show_shop_between_waves() -> void:
	_show_shop = true

func show_game_over(w: int, kills: int, sc: int) -> void:
	_go_wave = w; _go_kills = kills; _go_score = sc; _show_game_over = true


# ── Button rect dictionary ─────────────────────────────────────────────────────
func _btn_rects(s: float) -> Dictionary:
	return {
		"fire":     Rect2(_vp.x-220*s, _vp.y-265*s, 185*s, 185*s),
		"reload":   Rect2(_vp.x-240*s, _vp.y-490*s, 145*s, 115*s),
		"dash":     Rect2(250*s,        _vp.y-425*s, 130*s, 105*s),
		"ult":      Rect2(_vp.x-405*s, _vp.y-275*s, 135*s, 135*s),
		"wpn_next": Rect2(_vp.x-185*s, _vp.y-640*s, 105*s,  82*s),
		"wpn_prev": Rect2(_vp.x-310*s, _vp.y-640*s, 105*s,  82*s),
	}


# ── Drawing ────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	var s := _vp.y / 1920.0
	var font := ThemeDB.fallback_font

	if _show_game_over:
		_draw_game_over(s, font); return
	if _show_perk:
		_draw_perk_overlay(s, font); return
	if _show_shop:
		_draw_shop_overlay(s, font); return

	_draw_crosshair(s)
	_draw_hp_shield(s, font)
	_draw_ammo_panel(s, font)
	_draw_wave_hud(s, font)
	_draw_xp_bar(s, font)
	_draw_buttons(s, font)
	_draw_left_stick(s)
	_draw_kill_feed(s, font)
	_draw_minimap(s, font)
	_draw_hit_flash()


# ── Crosshair ──────────────────────────────────────────────────────────────────
func _draw_crosshair(s: float) -> void:
	var cx := _vp.x * 0.5
	var cy := _vp.y * 0.5 - 75.0 * s
	var gap := 24.0 * s
	var len := 18.0 * s
	var col := Color(1.0, 1.0, 1.0, 0.88)
	var dot_col := Color(1.0, 0.3, 0.3, 0.9)
	if current_weapon == "sniper":
		_draw.draw_arc(Vector2(cx,cy), 30.0*s, 0, TAU, 32, Color(0.3,0.9,1.0,0.9), 1.5)
	else:
		# Spread indicator
		var spread_gap := gap
		if _fire_vis: spread_gap *= 1.35
		_draw.draw_line(Vector2(cx - spread_gap - len, cy), Vector2(cx - spread_gap, cy), col, 2.0)
		_draw.draw_line(Vector2(cx + spread_gap, cy), Vector2(cx + spread_gap + len, cy), col, 2.0)
		_draw.draw_line(Vector2(cx, cy - spread_gap - len), Vector2(cx, cy - spread_gap), col, 2.0)
		_draw.draw_line(Vector2(cx, cy + spread_gap), Vector2(cx, cy + spread_gap + len), col, 2.0)
	_draw.draw_circle(Vector2(cx, cy), 2.8*s, dot_col)


# ── HP + Shield ────────────────────────────────────────────────────────────────
func _draw_hp_shield(s: float, font: Font) -> void:
	var bw := 330.0*s; var bh := 24.0*s
	var bx := 36.0*s;  var by := _vp.y - 168.0*s

	# HP shadow
	_draw.draw_rect(Rect2(bx-2, by-2, bw+4, bh+4), Color(0,0,0,0.5))
	_draw.draw_rect(Rect2(bx, by, bw, bh), Color(0.1,0.0,0.0,0.9))
	var hf := maxf(0.0, hp / maxf(max_hp,1.0))
	var hcol := Color(0.15,0.85,0.25) if hf > 0.4 else (Color(0.9,0.65,0.1) if hf > 0.2 else Color(1.0,0.1,0.1))
	if hf > 0.0:
		_draw.draw_rect(Rect2(bx, by, bw*hf, bh), hcol)
	_draw.draw_rect(Rect2(bx, by, bw, bh), Color(1,1,1,0.4), false, 1.5)
	_draw.draw_string(font, Vector2(bx+8, by+bh-5), "HP  %d / %d" % [int(hp), int(max_hp)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(14*s), Color.WHITE)

	# Shield bar (above HP)
	if shield > 0.0:
		var sy := by - 30.0*s; var sf := maxf(0.0, shield/maxf(max_shield,1.0))
		_draw.draw_rect(Rect2(bx, sy, bw, bh*0.6), Color(0,0.08,0.2,0.85))
		_draw.draw_rect(Rect2(bx, sy, bw*sf, bh*0.6), Color(0.35,0.65,1.0,0.92))
		_draw.draw_rect(Rect2(bx, sy, bw, bh*0.6), Color(0.5,0.8,1.0,0.5), false, 1.2)
		_draw.draw_string(font, Vector2(bx+8, sy+bh*0.55), "SHIELD  %d" % int(shield),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(13*s), Color(0.7,0.9,1.0))


# ── Ammo panel ─────────────────────────────────────────────────────────────────
func _draw_ammo_panel(s: float, font: Font) -> void:
	var ax := _vp.x - 36.0*s; var ay := _vp.y - 210.0*s
	var big := int(58.0*s)
	var acol := Color.WHITE if not is_reloading else Color(0.9,0.6,0.1)
	# Ammo count
	_draw.draw_string(font, Vector2(ax, ay), str(ammo),
		HORIZONTAL_ALIGNMENT_RIGHT, -1, big, acol)
	_draw.draw_string(font, Vector2(ax, ay + big*0.72), "/%d" % max_ammo,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, int(big*0.52), Color(0.7,0.7,0.7))
	# Weapon name
	_draw.draw_string(font, Vector2(ax, ay - 44.0*s), current_weapon.to_upper(),
		HORIZONTAL_ALIGNMENT_RIGHT, -1, int(21.0*s), Balance.WEAPONS3D.get(current_weapon,{}).get("color",Color.WHITE))
	# Reload arc
	if is_reloading:
		var rc := Vector2(ax - 56.0*s, ay - 28.0*s)
		_draw.draw_arc(rc, 30.0*s, -PI*0.5, -PI*0.5 + reload_progress*TAU, 32,
			Color(1.0,0.7,0.1), 4.5)
		_draw.draw_string(font, Vector2(rc.x, rc.y + 10.0*s), "RELOAD",
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(14*s), Color(1.0,0.8,0.2))


# ── Wave / score info ──────────────────────────────────────────────────────────
func _draw_wave_hud(s: float, font: Font) -> void:
	var cx := _vp.x * 0.5
	_draw.draw_string(font, Vector2(cx, 56.0*s),
		"Wave  %d" % wave, HORIZONTAL_ALIGNMENT_CENTER, -1, int(32*s), Color(1,1,1,0.9))
	if enemy_count > 0:
		_draw.draw_string(font, Vector2(cx, 96.0*s),
			"%d left" % enemy_count, HORIZONTAL_ALIGNMENT_CENTER, -1, int(21*s),
			Color(1.0,0.42,0.28,0.88))
	_draw.draw_string(font, Vector2(cx, 130.0*s),
		"$%d" % money, HORIZONTAL_ALIGNMENT_CENTER, -1, int(22*s),
		Color(1.0,0.9,0.3,0.88))
	if combo >= 2:
		var pulse := sin(Time.get_ticks_msec()*0.012)*0.4+0.8
		_draw.draw_string(font, Vector2(cx, 168.0*s),
			"x%d COMBO" % combo, HORIZONTAL_ALIGNMENT_CENTER, -1, int(28*s),
			Color(1.0, 0.55, 0.0, pulse))


# ── XP bar ─────────────────────────────────────────────────────────────────────
func _draw_xp_bar(s: float, font: Font) -> void:
	var bw := _vp.x - 80.0*s; var bh := 11.0*s
	var bx := 40.0*s;          var by := _vp.y - 16.0*s
	_draw.draw_rect(Rect2(bx, by, bw, bh), Color(0.08,0.0,0.18,0.85))
	var xf := float(p_xp) / float(maxi(p_xp_next, 1))
	_draw.draw_rect(Rect2(bx, by, bw*xf, bh), Color(0.75,0.25,1.0,0.92))
	_draw.draw_rect(Rect2(bx, by, bw, bh), Color(0.6,0.3,0.9,0.4), false, 1.2)
	_draw.draw_string(font, Vector2(bx+7, by-2.0*s),
		"Lv%d" % p_level, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12*s), Color(0.85,0.65,1.0))


# ── Buttons ────────────────────────────────────────────────────────────────────
func _draw_buttons(s: float, font: Font) -> void:
	var btns := _btn_rects(s)

	# FIRE
	var fire_c := Color(0.95,0.18,0.12,0.9) if _fire_vis else Color(0.72,0.12,0.08,0.72)
	_draw_btn(btns["fire"], fire_c, "FIRE", font, s, true)

	# RELOAD
	var rl_c := Color(0.88,0.58,0.08,0.78) if is_reloading else Color(0.4,0.4,0.18,0.65)
	_draw_btn(btns["reload"], rl_c, "R", font, s, false)

	# DASH
	var dash_ready := dash_cd <= 0.0
	_draw_btn(btns["dash"], Color(0.1,0.6,1.0,0.78) if dash_ready else Color(0.15,0.3,0.55,0.52),
		"DASH", font, s, false)
	if not dash_ready:
		_draw.draw_arc(btns["dash"].get_center(), btns["dash"].size.x*0.52,
			-PI*0.5, -PI*0.5 + (1.0-dash_cd/Balance.P3D_DASH_CD)*TAU,
			24, Color(0.4,0.8,1.0,0.65), 3.5*s)

	# ULT
	var ult_r := 1.0 - ult_cd/maxf(ult_max_cd,0.01)
	_draw_btn(btns["ult"], Color(0.85,0.5,0.0,0.82) if ult_cd<=0 else Color(0.3,0.2,0.05,0.55),
		"ULT", font, s, false)
	if ult_cd > 0.0:
		_draw.draw_arc(btns["ult"].get_center(), btns["ult"].size.x*0.52,
			-PI*0.5, -PI*0.5 + ult_r*TAU, 24, Color(1.0,0.8,0.2,0.75), 4.0*s)

	_draw_btn(btns["wpn_next"], Color(0.28,0.28,0.28,0.6), ">", font, s, false)
	_draw_btn(btns["wpn_prev"], Color(0.28,0.28,0.28,0.6), "<", font, s, false)


func _draw_btn(r: Rect2, col: Color, lbl: String, font: Font, s: float, circle: bool) -> void:
	if circle:
		_draw.draw_arc(r.get_center(), r.size.x*0.5, 0, TAU, 32, col, r.size.x*0.5)
		_draw.draw_arc(r.get_center(), r.size.x*0.5, 0, TAU, 32, Color(1,1,1,0.4), 2.5)
	else:
		_draw.draw_rect(r, col)
		_draw.draw_rect(r, Color(1,1,1,0.32), false, 2.0)
	var fs := int(minf(r.size.x, r.size.y) * (0.38 if not circle else 0.30))
	_draw.draw_string(font, r.get_center() + Vector2(0, fs*0.38),
		lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color.WHITE)


# ── Left joystick visual ───────────────────────────────────────────────────────
func _draw_left_stick(s: float) -> void:
	if _left_id == -1: return
	var sc := s
	_draw.draw_arc(_left_orig, STICK_RADIUS*sc, 0, TAU, 32, Color(1,1,1,0.15), 2.0)
	var raw := (_left_cur - _left_orig).limit_length(STICK_RADIUS*sc)
	_draw.draw_circle(_left_orig + raw, 34.0*sc, Color(1,1,1,0.32))
	_draw.draw_arc(_left_orig + raw, 34.0*sc, 0, TAU, 24, Color(1,1,1,0.55), 2.0)


# ── Kill feed ──────────────────────────────────────────────────────────────────
func _draw_kill_feed(s: float, font: Font) -> void:
	var y := 200.0*s
	for item in _feed:
		var a := clampf(item["timer"] / FEED_DURATION * 2.0, 0.0, 1.0)
		var x := _vp.x - 40.0*s
		# Highlight combo lines
		var col := Color(1.0, 0.9, 0.3, a)
		if "Combo" in item["text"] or "kill" in item["text"].to_lower():
			col = Color(1.0, 0.55, 0.0, a)
		elif "Wave" in item["text"]:
			col = Color(0.5, 1.0, 0.5, a)
		elif "+" in item["text"] and "$" in item["text"]:
			col = Color(0.8, 0.95, 0.3, a)
		_draw.draw_string(font, Vector2(x, y), item["text"],
			HORIZONTAL_ALIGNMENT_RIGHT, -1, int(20*s), col)
		y += 27.0*s


# ── Minimap ────────────────────────────────────────────────────────────────────
func _draw_minimap(s: float, font: Font) -> void:
	var cx := _vp.x - 95.0*s; var cy := 240.0*s; var r := 68.0*s
	_draw.draw_circle(Vector2(cx,cy), r, Color(0,0,0,0.48))
	_draw.draw_arc(Vector2(cx,cy), r, 0, TAU, 36, Color(0.3,0.9,0.35,0.55), 1.8)
	# Zone ring
	var zfrac := clampf(r * 0.85, 0, r)
	_draw.draw_arc(Vector2(cx,cy), zfrac, 0, TAU, 28,
		Color(0.2,0.8,1.0,0.4), 1.5)
	# Player dot (center)
	_draw.draw_circle(Vector2(cx,cy), 5.0*s, Color(0.3,0.6,1.0,0.9))
	# Enemy blips — positioned from gm
	if Engine.get_main_loop():
		var gm := _find_gm()
		if gm:
			var arena := Balance.ARENA_HALF
			for e in gm.enemies:
				if not is_instance_valid(e): continue
				var ep: Vector3 = e.global_position
				var pp: Vector3 = gm.player.global_position if gm.player else Vector3.ZERO
				var rel_x := (ep.x - pp.x) / (arena * 2.0) * r * 2.0
				var rel_z := (ep.z - pp.z) / (arena * 2.0) * r * 2.0
				var bpos := Vector2(cx + rel_x, cy + rel_z)
				if (bpos - Vector2(cx,cy)).length() < r:
					var bcol := Color(1.0,0.25,0.1,0.88) if e.get("type","") != "boss" else Color(1.0,0.8,0.0,0.88)
					_draw.draw_circle(bpos, 4.5*s, bcol)
	_draw.draw_string(font, Vector2(cx, cy + r + 16.0*s),
		"MAP", HORIZONTAL_ALIGNMENT_CENTER, -1, int(11*s), Color(0.7,0.7,0.7,0.6))


func _find_gm() -> Node:
	# Walk up to root, find GameManager3D
	var node: Node = self
	while node:
		node = node.get_parent()
		if node and node.get_script() and node.name == "GameManager3D":
			return node
	return null


# ── Screen-edge hit flash ──────────────────────────────────────────────────────
func _draw_hit_flash() -> void:
	if _hit_flash <= 0.0: return
	var a := _hit_flash * 0.38
	_draw.draw_rect(Rect2(0, 0, _vp.x, _vp.y), Color(1.0, 0.05, 0.05, a))


# ── Perk overlay ───────────────────────────────────────────────────────────────
func _draw_perk_overlay(s: float, font: Font) -> void:
	_draw.draw_rect(Rect2(0,0,_vp.x,_vp.y), Color(0,0,0,0.80))
	# Header glow
	_draw.draw_rect(Rect2(0, 0, _vp.x, 260.0*s), Color(0.18,0.0,0.28,0.9))
	_draw.draw_string(font, Vector2(_vp.x*0.5, 96.0*s),
		"LEVEL  %d" % p_level,
		HORIZONTAL_ALIGNMENT_CENTER, -1, int(38*s), Color(0.9,0.5,1.0))
	_draw.draw_string(font, Vector2(_vp.x*0.5, 150.0*s),
		"Choose a Perk", HORIZONTAL_ALIGNMENT_CENTER, -1, int(28*s), Color(0.75,0.75,0.75))

	var n := _perk_opts.size()
	var cw := 260.0*s; var ch := 340.0*s
	var total_w := cw * n + 28.0*s * (n-1)
	var sx := (_vp.x - total_w) * 0.5
	for i in range(n):
		var key: String = _perk_opts[i]
		var perk: Dictionary = Balance.PERKS.get(key, {"name":key,"desc":""})
		var r := Rect2(sx + i*(cw+28.0*s), 280.0*s, cw, ch)
		# Card bg gradient-ish
		_draw.draw_rect(r, Color(0.20,0.08,0.32,0.95))
		_draw.draw_rect(r, Color(0.72,0.32,1.0,0.85), false, 2.5)
		# Perk icon background circle
		_draw.draw_circle(r.get_center() + Vector2(0, -80*s), 40.0*s, Color(0.35,0.15,0.5,0.8))
		_draw.draw_arc(r.get_center() + Vector2(0, -80*s), 40.0*s, 0, TAU, 24,
			Color(0.8,0.4,1.0), 2.5)
		# Perk number icon
		_draw.draw_string(font, r.get_center() + Vector2(0, -80*s + int(18*s)),
			str(i+1), HORIZONTAL_ALIGNMENT_CENTER, -1, int(32*s), Color(1.0,0.9,1.0))
		# Name
		_draw.draw_string(font, Vector2(r.get_center().x, r.position.y + 150*s),
			perk.get("name", key), HORIZONTAL_ALIGNMENT_CENTER, -1, int(24*s), Color(1.0,0.82,1.0))
		# Desc (wrapped)
		var desc: String = perk.get("desc", "")
		_draw.draw_string(font, Vector2(r.position.x + 18*s, r.position.y + 195*s),
			desc, HORIZONTAL_ALIGNMENT_LEFT, int(cw-36*s), int(19*s), Color(0.82,0.82,0.82))
		# Tap hint
		_draw.draw_string(font, Vector2(r.get_center().x, r.end.y - 26*s),
			"Tap to choose", HORIZONTAL_ALIGNMENT_CENTER, -1, int(16*s), Color(0.6,0.6,0.6))


# ── Shop overlay ───────────────────────────────────────────────────────────────
func _draw_shop_overlay(s: float, font: Font) -> void:
	_draw.draw_rect(Rect2(0,0,_vp.x,_vp.y), Color(0,0,0,0.82))
	# Header
	_draw.draw_rect(Rect2(0, 0, _vp.x, 230.0*s), Color(0.05,0.12,0.05,0.95))
	_draw.draw_string(font, Vector2(_vp.x*0.5, 90.0*s),
		"SHOP", HORIZONTAL_ALIGNMENT_CENTER, -1, int(42*s), Color(1.0,0.9,0.3))
	_draw.draw_string(font, Vector2(_vp.x*0.5, 145.0*s),
		"$%d" % money, HORIZONTAL_ALIGNMENT_CENTER, -1, int(30*s), Color(0.8,0.8,0.3))

	# Close button (X)
	var close_r := Rect2(_vp.x - 110*s, 70*s, 90*s, 90*s)
	_draw.draw_rect(close_r, Color(0.7,0.1,0.1,0.8))
	_draw.draw_rect(close_r, Color(1,0.4,0.4,0.7), false, 2.0)
	_draw.draw_string(font, close_r.get_center() + Vector2(0, int(14*s)),
		"✕", HORIZONTAL_ALIGNMENT_CENTER, -1, int(30*s), Color.WHITE)

	# Weapon cards
	var wl := Balance.WEAPON3D_ORDER
	var cw := 200.0*s; var ch := 260.0*s; var pad := 22.0*s; var cols := 3
	for i in range(wl.size()):
		var wid: String = wl[i]
		var wd: Dictionary = Balance.WEAPONS3D[wid]
		var col_idx := i % cols; var row_idx := i / cols
		var cx2 := 40.0*s + col_idx * (cw + pad)
		var cy2 := 250.0*s + row_idx * (ch + pad)
		var r := Rect2(cx2, cy2, cw, ch)
		var can_buy := money >= wd["price"] or wd["price"] == 0
		var bg := Color(0.12,0.20,0.12,0.94) if can_buy else Color(0.08,0.08,0.08,0.82)
		_draw.draw_rect(r, bg)
		_draw.draw_rect(r, wd["color"].lightened(0.2), false, 2.2)
		_draw.draw_string(font, Vector2(r.get_center().x, r.position.y + 48*s),
			wid.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, -1, int(22*s), wd["color"])
		# Stats
		_draw.draw_string(font, Vector2(r.position.x+12*s, r.position.y + 90*s),
			"DMG: %.0f" % wd["damage"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(15*s), Color(0.9,0.5,0.3))
		_draw.draw_string(font, Vector2(r.position.x+12*s, r.position.y + 114*s),
			"AMM: %d" % wd["ammo"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(15*s), Color(0.5,0.7,0.9))
		_draw.draw_string(font, Vector2(r.position.x+12*s, r.position.y + 138*s),
			"TYPE: " + ("HITSCAN" if wd["hitscan"] else "PROJ"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15*s), Color(0.7,0.7,0.7))
		var price_str := "FREE" if wd["price"] == 0 else "$%d" % wd["price"]
		_draw.draw_string(font, Vector2(r.get_center().x, r.end.y - 26*s),
			price_str, HORIZONTAL_ALIGNMENT_CENTER, -1, int(20*s),
			Color(1.0,0.9,0.3) if can_buy else Color(0.45,0.45,0.45))


# ── Game over ──────────────────────────────────────────────────────────────────
func _draw_game_over(s: float, font: Font) -> void:
	_draw.draw_rect(Rect2(0,0,_vp.x,_vp.y), Color(0,0,0,0.92))
	_draw.draw_string(font, Vector2(_vp.x*0.5, _vp.y*0.25),
		"GAME  OVER", HORIZONTAL_ALIGNMENT_CENTER, -1, int(62*s), Color(1.0,0.15,0.15))
	var stats := [
		"Wave reached:  %d" % _go_wave,
		"Enemies killed:  %d" % _go_kills,
		"Score:  %d" % _go_score,
	]
	var sy := _vp.y * 0.42
	for line in stats:
		_draw.draw_string(font, Vector2(_vp.x*0.5, sy),
			line, HORIZONTAL_ALIGNMENT_CENTER, -1, int(32*s), Color(0.9,0.9,0.9))
		sy += 55.0*s
	# Tap to restart hint
	var pulse := sin(Time.get_ticks_msec()*0.005)*0.4+0.6
	_draw.draw_string(font, Vector2(_vp.x*0.5, _vp.y*0.78),
		"Tap to Restart", HORIZONTAL_ALIGNMENT_CENTER, -1, int(28*s),
		Color(0.8,0.8,0.8,pulse))
