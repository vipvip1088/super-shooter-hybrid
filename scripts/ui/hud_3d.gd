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
signal perk_chosen(perk_key: String)
signal shop_buy(weapon_id: String)

# ── Touch state ────────────────────────────────────────────────────────────────
var _left_id:   int = -1
var _right_id:  int = -1
var _left_orig: Vector2
var _left_cur:  Vector2
var _right_orig: Vector2
var _right_cur:  Vector2
const STICK_RADIUS := 90.0
const DEAD_ZONE    := 12.0
var _fire_held: bool = false

# ── Game state (updated by GM) ─────────────────────────────────────────────────
var hp: float = 100.0
var max_hp: float = 100.0
var shield: float = 0.0
var max_shield: float = 50.0
var ammo: int = 30
var max_ammo: int = 30
var is_reloading: bool = false
var reload_progress: float = 0.0
var wave: int = 0
var score: int = 0
var enemy_count: int = 0
var dash_cd: float = 0.0
var ult_cd: float = 0.0
var ult_max_cd: float = 30.0
var xp: int = 0
var xp_to_next: int = 100
var level: int = 1
var money: int = 0
var current_weapon: String = "ar"
var zone_warning: bool = false
var kill_feed: Array = []  # strings, max 4
var kill_feed_timers: Array = []

# ── Overlay state ──────────────────────────────────────────────────────────────
var _show_perk: bool = false
var _perk_options: Array = []
var _show_shop: bool = false
var _shop_hover: int = -1

# ── Drawing node ───────────────────────────────────────────────────────────────
var _draw_node: Control

var _vp_size: Vector2


func setup(_gm: Node) -> void:
	layer = 10
	_vp_size = Vector2(1080, 1920)
	_draw_node = Control.new()
	_draw_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	_draw_node.set_process(true)


func _process(_delta: float) -> void:
	_draw_node.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var vp := get_viewport().get_visible_rect().size
	var pos := event.position

	if event.pressed:
		# Left stick zone: bottom-left quarter
		if pos.x < vp.x * 0.42 and pos.y > vp.y * 0.55:
			if _left_id == -1:
				_left_id = event.index
				_left_orig = pos
				_left_cur = pos
			return

		# Button zones (right side)
		if _check_buttons(pos, event.pressed):
			return

		# Right look zone
		if pos.x > vp.x * 0.42 and pos.y > vp.y * 0.35:
			if _right_id == -1:
				_right_id = event.index
				_right_orig = pos
				_right_cur = pos
			return

	else:  # released
		if event.index == _left_id:
			_left_id = -1
			emit_signal("move_input", Vector2.ZERO)
		if event.index == _right_id:
			_right_id = -1
			_fire_held = false
			emit_signal("fire_held", false)
		_check_buttons(pos, false)


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _left_id:
		_left_cur = event.position
		var delta := _left_cur - _left_orig
		if delta.length() > DEAD_ZONE:
			var dir := delta / STICK_RADIUS
			if dir.length() > 1.0:
				dir = dir.normalized()
			emit_signal("move_input", Vector2(dir.x, -dir.y))
		else:
			emit_signal("move_input", Vector2.ZERO)

	elif event.index == _right_id:
		var drag_delta := event.relative
		emit_signal("look_input", drag_delta)
		_right_cur = event.position


func _check_buttons(pos: Vector2, pressed: bool) -> bool:
	var vp := get_viewport().get_visible_rect().size
	var buttons := _get_button_rects(vp)
	for btn_name in buttons:
		var r: Rect2 = buttons[btn_name]
		if r.has_point(pos):
			if pressed:
				_on_button(btn_name)
			return true
	return false


func _on_button(name: String) -> void:
	match name:
		"fire":
			_fire_held = true
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


func _get_button_rects(vp: Vector2) -> Dictionary:
	var s := vp.y / 1920.0  # scale factor
	return {
		"fire":     Rect2(vp.x - 220*s, vp.y - 260*s, 180*s, 180*s),
		"reload":   Rect2(vp.x - 230*s, vp.y - 480*s, 140*s, 110*s),
		"dash":     Rect2(250*s, vp.y - 420*s, 130*s, 100*s),
		"ult":      Rect2(vp.x - 390*s, vp.y - 270*s, 130*s, 130*s),
		"wpn_next": Rect2(vp.x - 180*s, vp.y - 620*s, 100*s,  80*s),
		"wpn_prev": Rect2(vp.x - 300*s, vp.y - 620*s, 100*s,  80*s),
	}


# ── Public updaters ────────────────────────────────────────────────────────────
func update_hp(cur: float, mx: float) -> void:
	hp = cur; max_hp = mx


func update_ammo(cur: int, mx: int) -> void:
	ammo = cur; max_ammo = mx


func update_wave(w: int, enemies: int) -> void:
	wave = w; enemy_count = enemies


func update_xp(cur: int, to_next: int, lv: int) -> void:
	xp = cur; xp_to_next = to_next; level = lv


func update_money(m: int) -> void:
	money = m


func update_reload(reloading: bool, progress: float) -> void:
	is_reloading = reloading; reload_progress = progress


func update_dash_cd(cd: float) -> void:
	dash_cd = cd


func update_ult(cd: float, mx: float) -> void:
	ult_cd = cd; ult_max_cd = mx


func update_weapon(wid: String) -> void:
	current_weapon = wid


func set_zone_warning(w: bool) -> void:
	zone_warning = w


func add_kill_feed(text: String) -> void:
	kill_feed.append(text)
	kill_feed_timers.append(3.5)
	if kill_feed.size() > 4:
		kill_feed.pop_front()
		kill_feed_timers.pop_front()


func show_perk_choice(options: Array) -> void:
	_perk_options = options
	_show_perk = true


func show_shop() -> void:
	_show_shop = true


func hide_shop() -> void:
	_show_shop = false


# ── Drawing ────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	var vp := get_viewport().get_visible_rect().size
	_vp_size = vp
	var s := vp.y / 1920.0
	var font := ThemeDB.fallback_font

	_draw_crosshair(vp, s, font)
	_draw_hp_bar(vp, s, font)
	_draw_ammo(vp, s, font)
	_draw_wave_info(vp, s, font)
	_draw_xp_bar(vp, s, font)
	_draw_buttons(vp, s, font)
	_draw_left_stick(vp, s)
	_draw_right_stick(vp, s)
	_draw_kill_feed(vp, s, font)
	_draw_minimap_zone(vp, s)

	if zone_warning:
		_draw_zone_warning(vp, s, font)

	if _show_perk:
		_draw_perk_overlay(vp, s, font)
	elif _show_shop:
		_draw_shop_overlay(vp, s, font)


func _draw_crosshair(vp: Vector2, s: float, font: Font) -> void:
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5 - 80.0 * s
	var gap := 22.0 * s
	var len := 16.0 * s
	var col := Color(1.0, 1.0, 1.0, 0.85)
	if current_weapon == "sniper":
		# Circle reticle for sniper
		_draw_node.draw_arc(Vector2(cx, cy), 28.0 * s, 0, TAU, 32, Color(0.3, 0.9, 1.0, 0.9), 1.5)
		_draw_node.draw_line(Vector2(cx - 38*s, cy), Vector2(cx - gap, cy), col, 1.5)
		_draw_node.draw_line(Vector2(cx + gap, cy), Vector2(cx + 38*s, cy), col, 1.5)
		_draw_node.draw_line(Vector2(cx, cy - 38*s), Vector2(cx, cy - gap), col, 1.5)
		_draw_node.draw_line(Vector2(cx, cy + gap), Vector2(cx, cy + 38*s), col, 1.5)
	else:
		_draw_node.draw_line(Vector2(cx - gap - len, cy), Vector2(cx - gap, cy), col, 2.0)
		_draw_node.draw_line(Vector2(cx + gap, cy), Vector2(cx + gap + len, cy), col, 2.0)
		_draw_node.draw_line(Vector2(cx, cy - gap - len), Vector2(cx, cy - gap), col, 2.0)
		_draw_node.draw_line(Vector2(cx, cy + gap), Vector2(cx, cy + gap + len), col, 2.0)
		_draw_node.draw_circle(Vector2(cx, cy), 3.0 * s, Color(1,1,1,0.7))


func _draw_hp_bar(vp: Vector2, s: float, font: Font) -> void:
	var bw := 320.0 * s
	var bh := 22.0 * s
	var bx := 40.0 * s
	var by := vp.y - 160.0 * s

	# HP
	_draw_node.draw_rect(Rect2(bx, by, bw, bh), Color(0.15, 0.0, 0.0, 0.8))
	var hf := maxf(0.0, hp / max_hp)
	var hcol := Color(0.15, 0.85, 0.25) if hf > 0.4 else Color(0.9, 0.35, 0.1)
	_draw_node.draw_rect(Rect2(bx, by, bw * hf, bh), hcol)
	_draw_node.draw_rect(Rect2(bx, by, bw, bh), Color(1,1,1,0.5), false, 1.5)
	_draw_node.draw_string(font, Vector2(bx + 6, by + bh - 4), "HP  %d/%d" % [int(hp), int(max_hp)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), Color.WHITE)

	# Shield
	if shield > 0.0:
		var sy := by - 28.0 * s
		var sf := maxf(0.0, shield / max_shield)
		_draw_node.draw_rect(Rect2(bx, sy, bw, bh * 0.65), Color(0.0, 0.1, 0.25, 0.8))
		_draw_node.draw_rect(Rect2(bx, sy, bw * sf, bh * 0.65), Color(0.3, 0.6, 1.0, 0.9))
		_draw_node.draw_rect(Rect2(bx, sy, bw, bh * 0.65), Color(0.5, 0.8, 1.0, 0.5), false, 1.2)


func _draw_ammo(vp: Vector2, s: float, font: Font) -> void:
	var ax := vp.x - 40.0 * s
	var ay := vp.y - 200.0 * s
	var fs := int(52.0 * s)
	var ammo_col := Color.WHITE if not is_reloading else Color(0.9, 0.6, 0.1)
	_draw_node.draw_string(font, Vector2(ax, ay), str(ammo),
		HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, ammo_col)
	_draw_node.draw_string(font, Vector2(ax, ay + fs * 0.75), "/" + str(max_ammo),
		HORIZONTAL_ALIGNMENT_RIGHT, -1, int(fs * 0.55), Color(0.7, 0.7, 0.7))

	# Reload arc
	if is_reloading:
		var cx := ax - 50.0 * s
		var cy := ay - 20.0 * s
		_draw_node.draw_arc(Vector2(cx, cy), 28.0 * s, -PI * 0.5,
			-PI * 0.5 + reload_progress * TAU, 32, Color(1.0, 0.7, 0.1), 4.0)
		_draw_node.draw_string(font, Vector2(cx, cy + 8.0 * s), "RELOAD",
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(13.0 * s), Color(1.0, 0.8, 0.2))

	# Weapon name
	var wdat: Dictionary = Balance.WEAPONS3D.get(current_weapon, {})
	var wname := current_weapon.to_upper()
	_draw_node.draw_string(font, Vector2(ax, ay - 42.0 * s), wname,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, int(20.0 * s), Color(0.8, 0.8, 0.8))


func _draw_wave_info(vp: Vector2, s: float, font: Font) -> void:
	_draw_node.draw_string(font, Vector2(vp.x * 0.5, 60.0 * s),
		"Wave %d" % wave, HORIZONTAL_ALIGNMENT_CENTER, -1, int(30.0 * s), Color(1, 1, 1, 0.9))
	if enemy_count > 0:
		_draw_node.draw_string(font, Vector2(vp.x * 0.5, 100.0 * s),
			"%d enemies" % enemy_count, HORIZONTAL_ALIGNMENT_CENTER, -1, int(20.0 * s), Color(1, 0.4, 0.3, 0.85))
	_draw_node.draw_string(font, Vector2(vp.x * 0.5, 136.0 * s),
		"$%d" % money, HORIZONTAL_ALIGNMENT_CENTER, -1, int(22.0 * s), Color(1.0, 0.9, 0.3, 0.85))


func _draw_xp_bar(vp: Vector2, s: float, font: Font) -> void:
	var bw := vp.x - 80.0 * s
	var bh := 10.0 * s
	var bx := 40.0 * s
	var by := vp.y - 15.0 * s
	_draw_node.draw_rect(Rect2(bx, by, bw, bh), Color(0.1, 0.0, 0.2, 0.8))
	var xf := float(xp) / float(maxi(xp_to_next, 1))
	_draw_node.draw_rect(Rect2(bx, by, bw * xf, bh), Color(0.7, 0.2, 1.0, 0.9))
	_draw_node.draw_string(font, Vector2(bx + 6.0 * s, by - 2.0 * s),
		"LVL %d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11.0 * s), Color(0.8, 0.6, 1.0))


func _draw_buttons(vp: Vector2, s: float, font: Font) -> void:
	var btns := _get_button_rects(vp)

	var fire_col := Color(0.9, 0.2, 0.15, 0.85) if _fire_held else Color(0.8, 0.15, 0.1, 0.65)
	_draw_btn(btns["fire"], fire_col, "FIRE", font, s)

	var reload_col := Color(0.9, 0.6, 0.1, 0.7) if is_reloading else Color(0.5, 0.5, 0.2, 0.60)
	_draw_btn(btns["reload"], reload_col, "R", font, s)

	var dash_ready := dash_cd <= 0.0
	var dash_col := Color(0.1, 0.6, 1.0, 0.75) if dash_ready else Color(0.2, 0.3, 0.5, 0.5)
	_draw_btn(btns["dash"], dash_col, "DASH", font, s)
	if not dash_ready:
		_draw_node.draw_string(font, Vector2(btns["dash"].position.x + btns["dash"].size.x * 0.5,
			btns["dash"].end.y + 22.0 * s), "%.1fs" % dash_cd,
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(16.0 * s), Color(0.6, 0.8, 1.0))

	var ult_f := 1.0 - ult_cd / maxf(ult_max_cd, 0.01)
	var ult_col := Color(0.8, 0.5, 0.0, 0.8) if ult_cd <= 0.0 else Color(0.35, 0.25, 0.05, 0.55)
	_draw_btn(btns["ult"], ult_col, "ULT", font, s)
	if ult_cd > 0.0:
		_draw_node.draw_arc(btns["ult"].get_center(),
			btns["ult"].size.x * 0.52, -PI * 0.5, -PI * 0.5 + ult_f * TAU,
			24, Color(1.0, 0.8, 0.2, 0.8), 3.5 * s)

	_draw_btn(btns["wpn_next"], Color(0.3, 0.3, 0.3, 0.55), ">", font, s)
	_draw_btn(btns["wpn_prev"], Color(0.3, 0.3, 0.3, 0.55), "<", font, s)


func _draw_btn(r: Rect2, col: Color, label: String, font: Font, s: float) -> void:
	_draw_node.draw_rect(r, col)
	_draw_node.draw_rect(r, Color(1,1,1,0.35), false, 2.0)
	_draw_node.draw_string(font, Vector2(r.position.x + r.size.x * 0.5,
		r.position.y + r.size.y * 0.58), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, int(minf(r.size.x, r.size.y) * 0.38), Color.WHITE)


func _draw_left_stick(vp: Vector2, s: float) -> void:
	if _left_id == -1:
		return
	var center := _left_orig
	_draw_node.draw_arc(center, STICK_RADIUS * s, 0, TAU, 32, Color(1,1,1,0.18), 2.0)
	var raw := (_left_cur - _left_orig)
	var clamped := raw.limit_length(STICK_RADIUS * s)
	_draw_node.draw_circle(center + clamped, 30.0 * s, Color(1,1,1,0.35))


func _draw_right_stick(vp: Vector2, s: float) -> void:
	pass  # Right side is free-drag; no visual indicator needed


func _draw_kill_feed(vp: Vector2, s: float, font: Font) -> void:
	var y := 180.0 * s
	for i in range(kill_feed.size()):
		_draw_node.draw_string(font, Vector2(vp.x - 40.0 * s, y),
			kill_feed[i], HORIZONTAL_ALIGNMENT_RIGHT, -1, int(19.0 * s),
			Color(1.0, 0.9, 0.3, 0.9))
		y += 26.0 * s


func _draw_minimap_zone(vp: Vector2, s: float) -> void:
	# Tiny zone indicator (top-right corner)
	var cx := vp.x - 90.0 * s
	var cy := 220.0 * s
	var r := 60.0 * s
	_draw_node.draw_arc(Vector2(cx, cy), r, 0, TAU, 32, Color(0.2, 0.7, 1.0, 0.5), 2.0 * s)


func _draw_zone_warning(vp: Vector2, s: float, font: Font) -> void:
	var pulse := sin(Time.get_ticks_msec() * 0.006) * 0.5 + 0.5
	_draw_node.draw_rect(Rect2(0, 0, vp.x, 8.0 * s), Color(1.0, 0.1, 0.1, 0.5 + pulse * 0.4))
	_draw_node.draw_rect(Rect2(0, vp.y - 8.0 * s, vp.x, 8.0 * s), Color(1.0, 0.1, 0.1, 0.5 + pulse * 0.4))
	_draw_node.draw_string(font, Vector2(vp.x * 0.5, vp.y * 0.15),
		"OUT OF ZONE", HORIZONTAL_ALIGNMENT_CENTER, -1, int(36.0 * s),
		Color(1.0, 0.2, 0.2, 0.7 + pulse * 0.3))


func _draw_perk_overlay(vp: Vector2, s: float, font: Font) -> void:
	_draw_node.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.72))
	_draw_node.draw_string(font, Vector2(vp.x * 0.5, 200.0 * s),
		"LEVEL UP!  Choose a Perk", HORIZONTAL_ALIGNMENT_CENTER, -1, int(42.0 * s),
		Color(0.8, 0.4, 1.0))

	var card_w := 260.0 * s
	var card_h := 340.0 * s
	var total_w := card_w * _perk_options.size() + 30.0 * s * (_perk_options.size() - 1)
	var start_x := (vp.x - total_w) * 0.5

	for i in range(_perk_options.size()):
		var key: String = _perk_options[i]
		var perk: Dictionary = Balance.PERKS.get(key, {"name": key, "desc": ""})
		var cx := start_x + i * (card_w + 30.0 * s)
		var r := Rect2(cx, 300.0 * s, card_w, card_h)
		_draw_node.draw_rect(r, Color(0.22, 0.10, 0.35, 0.95))
		_draw_node.draw_rect(r, Color(0.7, 0.3, 1.0, 0.8), false, 2.5)
		_draw_node.draw_string(font, Vector2(r.position.x + r.size.x * 0.5,
			r.position.y + 60.0 * s), perk.get("name", key),
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(26.0 * s), Color(1.0, 0.8, 1.0))
		_draw_node.draw_string(font, Vector2(r.position.x + 20.0 * s,
			r.position.y + 110.0 * s), perk.get("desc", ""),
			HORIZONTAL_ALIGNMENT_LEFT, int(card_w - 40.0 * s), int(20.0 * s), Color(0.85, 0.85, 0.85))

	_draw_node.draw_string(font, Vector2(vp.x * 0.5, vp.y - 120.0 * s),
		"Tap a card to choose", HORIZONTAL_ALIGNMENT_CENTER, -1, int(22.0 * s), Color(0.7, 0.7, 0.7))


func _draw_shop_overlay(vp: Vector2, s: float, font: Font) -> void:
	_draw_node.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.78))
	_draw_node.draw_string(font, Vector2(vp.x * 0.5, 180.0 * s),
		"SHOP  —  $%d" % money, HORIZONTAL_ALIGNMENT_CENTER, -1, int(38.0 * s), Color(1.0, 0.9, 0.3))

	var weapons := Balance.WEAPON3D_ORDER
	var card_w := 200.0 * s
	var card_h := 260.0 * s
	var cols := 3
	var pad := 24.0 * s

	for i in range(weapons.size()):
		var wid: String = weapons[i]
		var wdat: Dictionary = Balance.WEAPONS3D[wid]
		var col_idx := i % cols
		var row_idx := i / cols
		var cx := 40.0 * s + col_idx * (card_w + pad)
		var cy := 260.0 * s + row_idx * (card_h + pad)
		var r := Rect2(cx, cy, card_w, card_h)
		var can_buy := money >= wdat["price"] and wdat["price"] > 0
		var bg_col := Color(0.15, 0.22, 0.15, 0.92) if can_buy else Color(0.10, 0.10, 0.10, 0.8)
		_draw_node.draw_rect(r, bg_col)
		_draw_node.draw_rect(r, wdat["color"].lightened(0.2), false, 2.0)
		_draw_node.draw_string(font, Vector2(cx + card_w * 0.5, cy + 45.0 * s),
			wid.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, -1, int(22.0 * s), wdat["color"])
		var price_str := "FREE" if wdat["price"] == 0 else "$%d" % wdat["price"]
		_draw_node.draw_string(font, Vector2(cx + card_w * 0.5, cy + card_h - 28.0 * s),
			price_str, HORIZONTAL_ALIGNMENT_CENTER, -1, int(20.0 * s),
			Color(1.0, 0.9, 0.3) if can_buy else Color(0.5, 0.5, 0.5))

	_draw_node.draw_string(font, Vector2(vp.x * 0.5, vp.y - 80.0 * s),
		"Tap weapon to buy  |  Tap outside to close", HORIZONTAL_ALIGNMENT_CENTER,
		-1, int(20.0 * s), Color(0.7, 0.7, 0.7))
