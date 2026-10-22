class_name WorldRenderer
extends Node2D

var _gm: Node

func setup(game_manager: Node) -> void:
	_gm = game_manager

func _draw() -> void:
	if not _gm:
		return
	_draw_map()
	_draw_zone()
	_draw_barricades()
	_draw_turrets()
	_draw_loot()
	_draw_enemies()
	_draw_projectiles()
	_draw_player()

# ── Map ────────────────────────────────────────────────────────────────────
func _draw_map() -> void:
	draw_rect(Rect2(0.0, 0.0, 3000.0, 3000.0), Color(0.10, 0.13, 0.10))
	var gc := Color(0.20, 0.25, 0.20, 1.0)
	var x := 0.0
	while x <= 3000.0:
		draw_line(Vector2(x, 0.0), Vector2(x, 3000.0), gc, 1.5)
		x += 150.0
	var y := 0.0
	while y <= 3000.0:
		draw_line(Vector2(0.0, y), Vector2(3000.0, y), gc, 1.5)
		y += 150.0
	var zc: Vector2 = _gm.zone_center
	draw_circle(zc, 10.0, Color(1.0, 1.0, 0.3, 0.8))
	draw_line(zc - Vector2(20, 0), zc + Vector2(20, 0), Color(1.0, 1.0, 0.3, 0.5), 2.0)
	draw_line(zc - Vector2(0, 20), zc + Vector2(0, 20), Color(1.0, 1.0, 0.3, 0.5), 2.0)

# ── Zone ───────────────────────────────────────────────────────────────────
func _draw_zone() -> void:
	var zc: Vector2 = _gm.zone_center
	var zr: float   = _gm.zone_radius
	var pp: Vector2 = _gm.p_pos
	draw_arc(zc, zr + 20.0, 0.0, TAU, 128, Color(0.2, 0.85, 1.0, 0.12), 40.0)
	draw_arc(zc, zr,         0.0, TAU, 128, Color(0.25, 0.9, 1.0, 1.0),   6.0)
	draw_arc(zc, zr - 14.0, 0.0, TAU, 128, Color(0.25, 0.9, 1.0, 0.20),  28.0)
	if pp.distance_to(zc) > zr:
		var pulse := fmod(Time.get_ticks_msec() * 0.003, TAU)
		draw_arc(pp, 30.0, 0.0, TAU, 32,
			Color(1.0, 0.15, 0.15, sin(pulse) * 0.4 + 0.6), 5.0)

# ── Turrets ────────────────────────────────────────────────────────────────
func _draw_turrets() -> void:
	var turrets = _gm.get("turrets")
	if turrets == null:
		return
	for t in turrets:
		var p: Vector2 = t["pos"]
		draw_circle(p, 18.0, Color(0.8, 0.7, 0.2, 0.9))
		draw_arc(p, 18.0, 0.0, TAU, 16, Color(1.0, 0.9, 0.3), 3.0)
		draw_rect(Rect2(p.x - 4.0, p.y - 20.0, 8.0, 16.0), Color(0.6, 0.6, 0.6))

# ── Barricades ─────────────────────────────────────────────────────────────
func _draw_barricades() -> void:
	for b in _gm.barricades:
		var r := Rect2(b.x - 35.0, b.y - 35.0, 70.0, 70.0)
		draw_rect(r, Color(0.52, 0.36, 0.14))
		draw_rect(r, Color(0.72, 0.52, 0.22), false, 3.5)
		draw_line(Vector2(r.position.x + 5, b.y - 10),
			Vector2(r.end.x - 5, b.y - 10), Color(0.62, 0.44, 0.18), 2.0)
		draw_line(Vector2(r.position.x + 5, b.y + 10),
			Vector2(r.end.x - 5, b.y + 10), Color(0.62, 0.44, 0.18), 2.0)

# ── Loot ───────────────────────────────────────────────────────────────────
func _draw_loot() -> void:
	for item in _gm.loot_items:
		var p: Vector2 = item["pos"]
		draw_circle(p, 14.0, Color(1.0, 1.0, 1.0, 0.10))
		match item["type"]:
			"money":
				draw_circle(p, 8.0, Color(1.0, 0.9, 0.0))
				draw_arc(p, 8.0, 0.0, TAU, 16, Color(0.8, 0.6, 0.0), 2.0)
			"health":
				draw_rect(Rect2(p.x - 3, p.y - 9, 6, 18), Color(0.2, 0.9, 0.3))
				draw_rect(Rect2(p.x - 9, p.y - 3, 18, 6), Color(0.2, 0.9, 0.3))
			"ammo":
				draw_rect(Rect2(p.x - 3, p.y - 6, 6, 12), Color(0.9, 0.85, 0.2))
			"wood":
				var pts := PackedVector2Array([
					p + Vector2(0, -10), p + Vector2(9, 8), p + Vector2(-9, 8)
				])
				draw_polygon(pts, PackedColorArray([
					Color(0.6,0.4,0.1), Color(0.6,0.4,0.1), Color(0.6,0.4,0.1)
				]))
			"metal":
				var pts := PackedVector2Array([
					p + Vector2(0, -10), p + Vector2(10, 0),
					p + Vector2(0, 10),  p + Vector2(-10, 0)
				])
				draw_polygon(pts, PackedColorArray([
					Color(0.6,0.6,0.8), Color(0.6,0.6,0.8),
					Color(0.6,0.6,0.8), Color(0.6,0.6,0.8)
				]))
			"chips":
				draw_rect(Rect2(p.x - 8.0, p.y - 8.0, 16.0, 16.0), Color(0.2, 0.8, 1.0))
				draw_rect(Rect2(p.x - 4.0, p.y - 4.0, 8.0, 8.0), Color(0.0, 0.4, 0.8))

# ── Enemies ────────────────────────────────────────────────────────────────
func _draw_enemies() -> void:
	for e in _gm.enemies:
		if e.get("hp", 0.0) <= 0.0:
			continue
		var p:       Vector2 = e["pos"]
		var t:       String  = e["type"]
		var r:       float   = e["radius"]
		var flash:   float   = e.get("flash", 0.0)
		var base_c:  Color   = _enemy_color(t)
		var draw_c:  Color   = base_c.lerp(Color.WHITE, minf(1.0, flash / 0.15) * 0.8)
		var facing:  Vector2 = e.get("facing", Vector2.RIGHT)

		match t:
			"rusher":
				var tip := p + facing * r
				var perp := Vector2(-facing.y, facing.x)
				var pts := PackedVector2Array([
					tip,
					p - facing * r * 0.6 + perp * r * 0.85,
					p - facing * r * 0.6 - perp * r * 0.85
				])
				draw_polygon(pts, PackedColorArray([draw_c, draw_c, draw_c]))
				draw_arc(p, r, 0.0, TAU, 24, draw_c.darkened(0.3), 2.0)

			"shooter":
				var pts: PackedVector2Array
				pts.resize(6)
				for k in range(6):
					var a := (TAU / 6.0) * k
					pts[k] = p + Vector2(cos(a), sin(a)) * r
				draw_polygon(pts, PackedColorArray([
					draw_c, draw_c, draw_c, draw_c, draw_c, draw_c
				]))
				draw_rect(
					Rect2(p + facing * r, Vector2(r * 0.9, 5.0)),
					draw_c.lightened(0.25)
				)

			"tank":
				draw_circle(p, r, draw_c)
				draw_circle(p + Vector2(-8, -6), r * 0.55, draw_c.lightened(0.15))
				draw_circle(p + Vector2(7, -4),  r * 0.45, draw_c.lightened(0.10))
				draw_arc(p, r, 0.0, TAU, 24, draw_c.darkened(0.4), 5.0)
				if e["hp"] / e["max_hp"] < 0.30:
					draw_arc(p, r + 6.0, 0.0, TAU, 16, Color(1.0, 1.0, 0.0, 0.75), 3.0)

			"bomber":
				draw_circle(p, r, draw_c)
				draw_arc(p, r * 0.55, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.75), 2.0)
				if e.get("state", "") == "exploding":
					var et: float = e.get("explode_timer", 1.5)
					var pct: float = 1.0 - et / 1.5
					draw_circle(p, lerp(5.0, r * 0.88, pct), Color(1.0, 1.0, 1.0, pct * 0.85))

			"boss":
				var bphase: int = e.get("phase", 0)
				var ring_c := Color(1.0, 0.82, 0.0)
				if bphase == 1: ring_c = Color(1.0, 0.50, 0.0)
				elif bphase == 2: ring_c = Color(1.0, 0.15, 0.0)
				draw_circle(p, r, draw_c)
				draw_arc(p, r, 0.0, TAU, 64, ring_c, 6.0)
				var rot := Time.get_ticks_msec() * 0.001
				for k in range(8):
					var a := rot + (TAU / 8.0) * k
					draw_circle(p + Vector2(cos(a), sin(a)) * (r + 16.0), 5.0, ring_c)
				draw_arc(p, r + 24.0, 0.0, TAU, 32, ring_c.darkened(0.3), 2.5)

			"elite":
				draw_circle(p, r, draw_c)
				draw_arc(p, r, 0.0, TAU, 32, draw_c.lightened(0.3), 3.0)
				var rot2 := Time.get_ticks_msec() * 0.002
				for k in range(6):
					var a2 := rot2 + (TAU / 6.0) * k
					draw_circle(p + Vector2(cos(a2), sin(a2)) * (r + 10.0), 3.5, draw_c.lightened(0.4))

		# HP bar
		var bw := r * 3.5
		var bp := p + Vector2(-bw * 0.5, -r - 18.0)
		draw_rect(Rect2(bp, Vector2(bw, 6.0)), Color(0.25, 0.0, 0.0))
		var hf: float = maxf(0.0, e["hp"] / e["max_hp"])
		draw_rect(Rect2(bp, Vector2(bw * hf, 6.0)),
			Color(0.1, 0.85, 0.2) if hf > 0.4 else Color(0.9, 0.4, 0.1))

func _enemy_color(type: String) -> Color:
	match type:
		"rusher":  return Color(1.0, 0.50, 0.10)
		"shooter": return Color(0.70, 0.20, 1.00)
		"tank":    return Color(0.50, 0.52, 0.52)
		"bomber":  return Color(1.00, 0.15, 0.15)
		"boss":    return Color(1.00, 0.82, 0.00)
	return Color(1.0, 0.5, 0.5)

# ── Projectiles ────────────────────────────────────────────────────────────
func _draw_projectiles() -> void:
	for proj in _gm.projectiles:
		var p:     Vector2 = proj["pos"]
		var col:   Color   = proj["color"]
		var rad:   float   = proj["radius"]
		var trail: Array   = proj.get("trail", [])

		var trail_sz := trail.size()
		for ti in range(trail_sz):
			var alpha := float(ti + 1) / float(trail_sz + 1) * 0.5
			draw_circle(trail[ti], rad * 0.5, Color(col.r, col.g, col.b, alpha))

		if proj.get("weapon", "") == "plasma":
			draw_arc(p, rad + 7.0, 0.0, TAU, 24,
				Color(col.r, col.g, col.b, 0.35), 14.0)
		draw_circle(p, rad, col)

# ── Player ─────────────────────────────────────────────────────────────────
func _draw_player() -> void:
	var p:   Vector2 = _gm.p_pos
	var inv: float   = _gm.p_invincible
	var in_zone: bool = p.distance_to(_gm.zone_center) <= _gm.zone_radius

	draw_circle(p + Vector2(5, 5), 22.0, Color(0.0, 0.0, 0.0, 0.25))

	var body_c: Color
	if inv > 0.0:
		var fl := sin(Time.get_ticks_msec() * 0.025) * 0.5 + 0.5
		body_c = Color(1.0, 1.0, 1.0, 0.6 + fl * 0.4)
	elif in_zone:
		body_c = Color(0.2, 0.55, 1.0)
	else:
		body_c = Color(1.0, 0.3, 0.15)

	if _gm.p_is_dashing:
		var fd: Vector2 = _gm.p_facing
		for sl in range(3):
			draw_circle(p - fd * (18.0 + sl * 12.0), 22.0 * (0.7 - sl * 0.15),
				Color(body_c.r, body_c.g, body_c.b, 0.30 - sl * 0.08))

	draw_circle(p, 22.0, body_c)
	draw_arc(p, 22.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.85), 2.5)

	var fd2: Vector2 = _gm.p_facing
	if fd2.length_squared() > 0.01:
		draw_circle(p + fd2 * 16.0, 6.0, Color.WHITE)

	var bw := 72.0
	var bp := p + Vector2(-bw * 0.5, -44.0)
	draw_rect(Rect2(bp, Vector2(bw, 9.0)), Color(0.22, 0.0, 0.0))
	var hf: float = maxf(0.0, _gm.p_hp / _gm.p_max_hp)
	draw_rect(Rect2(bp, Vector2(bw * hf, 9.0)),
		Color(0.1, 0.85, 0.2) if hf > 0.4 else Color(0.9, 0.5, 0.1))
	draw_rect(Rect2(bp, Vector2(bw, 9.0)), Color(1.0, 1.0, 1.0, 0.6), false, 1.0)
