extends Control

# ── Signals ────────────────────────────────────────────────────────────────
signal joystick_moved(direction: Vector2)
signal shop_pressed()
signal craft_pressed()
signal test_pressed()

# ── Joystick ───────────────────────────────────────────────────────────────
var _js_center   := Vector2.ZERO
var _js_radius   := 100.0
var _js_knob     := Vector2.ZERO
var _js_touch_id := -1

# ── Button rects (recalculated on resize) ─────────────────────────────────
var _btn_shop  := Rect2()
var _btn_craft := Rect2()
var _btn_test  := Rect2()

# ── Touch state ────────────────────────────────────────────────────────────
var _btn_active: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_recalc(size if size != Vector2.ZERO else Vector2(1080, 1920))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recalc(size)
		queue_redraw()

func _recalc(s: Vector2) -> void:
	_js_center = Vector2(s.x * 0.17, s.y * 0.86)
	_js_radius = s.x * 0.095

	var bw := s.x * 0.22
	var bh := s.y * 0.063
	var bx := s.x * 0.75
	_btn_shop  = Rect2(bx, s.y * 0.725, bw, bh)
	_btn_craft = Rect2(bx, s.y * 0.805, bw, bh)
	_btn_test  = Rect2(bx, s.y * 0.885, bw, bh)

func _draw() -> void:
	var s := size
	if s.x < 10.0:
		return
	_recalc(s)

	# ── Read state from metadata ──────────────────────────────────────────
	var hp        := float(get_meta("hp",         100.0))
	var money     := int(get_meta("money",        1000))
	var wd        := int(get_meta("wood",         10))
	var mt        := int(get_meta("metal",        10))
	var wpn       := str(get_meta("weapon",       "pistol"))
	var ammo      := int(get_meta("ammo",         30))
	var in_zone   := bool(get_meta("in_zone",     true))
	var zphase    := int(get_meta("zone_phase",   0))
	var ztimer    := float(get_meta("zone_timer", 120.0))
	var feedback  := str(get_meta("feedback",     ""))
	var auto_on   := bool(get_meta("auto_move",   false))

	# ── Stats panel top ───────────────────────────────────────────────────
	var fs  := int(s.y * 0.022)
	var fs2 := int(s.y * 0.018)
	var pad := 16.0

	draw_rect(Rect2(0, 0, s.x, s.y * 0.135), Color(0.0, 0.0, 0.0, 0.55))
	draw_line(Vector2(0, s.y * 0.135), Vector2(s.x, s.y * 0.135), Color(1,1,1,0.12), 2.0)

	var lx := pad
	var ly := pad
	var row := float(fs) + 10.0

	_text("HP  %.0f / 100" % hp, Vector2(lx, ly), fs,
		Color(0.25, 1.0, 0.4) if hp > 40.0 else Color(1.0, 0.3, 0.3))
	_text("$  %d" % money, Vector2(lx, ly + row), fs, Color(1.0, 0.88, 0.0))
	_text("%s  [ %d rnds ]" % [wpn.to_upper(), ammo], Vector2(lx, ly + row * 2), fs2, Color(0.8, 0.8, 1.0))
	_text("Wood: %d   Metal: %d" % [wd, mt], Vector2(lx, ly + row * 3), fs2, Color(0.88, 0.65, 0.32))

	var zc := Color(0.25, 0.9, 1.0) if in_zone else Color(1.0, 0.25, 0.25)
	var zt := "SAFE" if in_zone else "DANGER  -%.0f HP/s" % [float(2 * (zphase + 1))]
	_text("ZONE  Phase %d  |  %s" % [zphase, zt], Vector2(s.x * 0.52, ly), fs2, zc)
	_text("Timer: %.0f s" % ztimer, Vector2(s.x * 0.52, ly + row), fs2, Color(0.75, 0.75, 0.75))

	# HP bar (full width under panel)
	var bary := s.y * 0.135
	draw_rect(Rect2(0, bary, s.x, 6.0), Color(0.25, 0.0, 0.0))
	draw_rect(Rect2(0, bary, s.x * hp / 100.0, 6.0),
		Color(0.1, 0.85, 0.2) if hp > 40.0 else Color(0.95, 0.45, 0.1))

	# ── Joystick ──────────────────────────────────────────────────────────
	draw_circle(_js_center, _js_radius, Color(1.0, 1.0, 1.0, 0.08))
	draw_arc(_js_center, _js_radius, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.35), 3.0)
	# Cross guides
	var cr := _js_radius * 0.45
	draw_line(_js_center - Vector2(cr, 0), _js_center + Vector2(cr, 0), Color(1,1,1,0.18), 2.0)
	draw_line(_js_center - Vector2(0, cr), _js_center + Vector2(0, cr), Color(1,1,1,0.18), 2.0)
	# Knob
	var knob_pos := _js_center + _js_knob
	draw_circle(knob_pos, _js_radius * 0.36, Color(1.0, 1.0, 1.0, 0.40))
	draw_arc(knob_pos, _js_radius * 0.36, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.85), 2.5)

	# ── Buttons ───────────────────────────────────────────────────────────
	_draw_btn(_btn_shop,  "ЗАКУПКА",       Color(0.15, 0.42, 0.88))
	_draw_btn(_btn_craft, "КРАФТ  стену",  Color(0.52, 0.32, 0.08))
	_draw_btn(_btn_test,  "СТОП" if auto_on else "АВТО-ТЕСТ",
		Color(0.65, 0.12, 0.08) if auto_on else Color(0.08, 0.52, 0.18))

	# ── Feedback banner ───────────────────────────────────────────────────
	if feedback != "":
		var fw := s.x * 0.78
		var fh := s.y * 0.055
		var fx := (s.x - fw) * 0.5
		var fy := s.y * 0.52
		draw_rect(Rect2(fx - 4, fy - 4, fw + 8, fh + 8), Color(0.0, 0.0, 0.0, 0.85))
		draw_rect(Rect2(fx, fy, fw, fh), Color(0.12, 0.12, 0.18, 0.92))
		draw_rect(Rect2(fx, fy, fw, fh), Color(0.5, 0.7, 1.0, 0.6), false, 2.0)
		_text(feedback, Vector2(fx + 12.0, fy + fh * 0.22), int(fh * 0.45), Color(1.0, 0.95, 0.75))

func _draw_btn(r: Rect2, label: String, c: Color) -> void:
	# Outer shadow
	draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.4))
	# Fill
	draw_rect(r, Color(c.r, c.g, c.b, 0.82))
	# Border
	draw_rect(r, Color(minf(c.r + 0.25, 1.0), minf(c.g + 0.25, 1.0), minf(c.b + 0.25, 1.0), 0.95),
		false, 2.5)
	# Label
	var fs := int(r.size.y * 0.40)
	_text(label, Vector2(r.position.x + 12.0, r.position.y + r.size.y * 0.27), fs, Color.WHITE)

func _text(t: String, pos: Vector2, fs: int, c: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, t,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

# ── Input ──────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)
	# Desktop mouse support for testing
	elif event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		_on_touch(0, me.position, me.pressed)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _js_touch_id == 0:
			_on_drag(0, (event as InputEventMouseMotion).position)

func _on_touch(id: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if pos.distance_to(_js_center) < _js_radius * 1.6:
			_js_touch_id = id
			_update_js(pos)
			return
		if _btn_shop.has_point(pos):
			_btn_active[id] = "shop"
			shop_pressed.emit()
			return
		if _btn_craft.has_point(pos):
			_btn_active[id] = "craft"
			craft_pressed.emit()
			return
		if _btn_test.has_point(pos):
			_btn_active[id] = "test"
			test_pressed.emit()
			return
	else:
		if id == _js_touch_id:
			_js_touch_id = -1
			_js_knob     = Vector2.ZERO
			joystick_moved.emit(Vector2.ZERO)
			queue_redraw()
		_btn_active.erase(id)

func _on_drag(id: int, pos: Vector2) -> void:
	if id == _js_touch_id:
		_update_js(pos)

func _update_js(touch_pos: Vector2) -> void:
	var delta := touch_pos - _js_center
	if delta.length() > _js_radius:
		delta = delta.normalized() * _js_radius
	_js_knob = delta
	var dir := delta / _js_radius if _js_radius > 0.0 else Vector2.ZERO
	joystick_moved.emit(dir)
	queue_redraw()
