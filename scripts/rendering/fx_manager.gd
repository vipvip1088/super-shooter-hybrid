class_name FxManager
extends Node2D

const MAX_PARTICLES := 200
const MAX_FLOATERS  := 40

var _gm: Node

var _shake_trauma:    float = 0.0
var _shake_max_x:     float = 0.0
var _shake_max_y:     float = 0.0
var _hit_stop:        float = 0.0

var _particles: Array = []
var _floaters:  Array = []

var _camera: Camera2D


func setup(game_manager: Node, camera: Camera2D) -> void:
	_gm     = game_manager
	_camera = camera


# ── Public API ─────────────────────────────────────────────────────────────

func shake(amplitude: Vector2, duration: float = 0.18) -> void:
	_shake_trauma  = maxf(_shake_trauma, duration)
	_shake_max_x   = maxf(_shake_max_x,  amplitude.x)
	_shake_max_y   = maxf(_shake_max_y,  amplitude.y)


func hit_stop(duration: float) -> void:
	_hit_stop = maxf(_hit_stop, duration)


func spawn_particles(pos: Vector2, count: int, color: Color,
		speed: float = Balance.PARTICLE_SPEED,
		life: float  = Balance.PARTICLE_LIFE) -> void:
	for _i in range(count):
		if _particles.size() >= MAX_PARTICLES:
			break
		var angle := randf() * TAU
		var spd   := randf_range(speed * 0.5, speed)
		_particles.append({
			"pos":   Vector2(pos),
			"vel":   Vector2(cos(angle), sin(angle)) * spd,
			"life":  life,
			"max":   life,
			"color": color,
			"r":     randf_range(2.0, 5.0)
		})


func spawn_floater(pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	if _floaters.size() >= MAX_FLOATERS:
		return
	_floaters.append({
		"pos":   Vector2(pos),
		"text":  text,
		"color": color,
		"life":  Balance.FLOAT_LIFE,
		"max":   Balance.FLOAT_LIFE
	})


func spawn_explosion_fx(pos: Vector2, radius: float) -> void:
	shake(Balance.SHAKE_EXPLOSION)
	spawn_particles(pos, 20, Color(1.0, 0.6, 0.1), Balance.PARTICLE_SPEED * 1.3, Balance.PARTICLE_LIFE)
	spawn_particles(pos, 10, Color(1.0, 1.0, 0.4), Balance.PARTICLE_SPEED * 0.7, Balance.PARTICLE_LIFE * 0.6)


func spawn_hit_fx(pos: Vector2, enemy_type: String) -> void:
	var c: Color
	match enemy_type:
		"rusher":  c = Color(1.0, 0.5, 0.1)
		"shooter": c = Color(0.7, 0.2, 1.0)
		"tank":    c = Color(0.5, 0.5, 0.5)
		"bomber":  c = Color(1.0, 0.2, 0.2)
		"boss":    c = Color(1.0, 0.8, 0.0)
		_:         c = Color(1.0, 0.5, 0.5)
	shake(Balance.SHAKE_HIT)
	spawn_particles(pos, 6, c, Balance.PARTICLE_SPEED * 0.8)


func spawn_death_fx(pos: Vector2, enemy_type: String) -> void:
	var c: Color
	match enemy_type:
		"rusher":  c = Color(1.0, 0.5, 0.1)
		"shooter": c = Color(0.7, 0.2, 1.0)
		"tank":    c = Color(0.5, 0.5, 0.5)
		"bomber":  c = Color(1.0, 0.2, 0.2)
		"boss":    c = Color(1.0, 0.8, 0.0)
		_:         c = Color(1.0, 0.5, 0.5)
	shake(Balance.SHAKE_DEATH)
	spawn_particles(pos, 18, c)
	spawn_particles(pos, 8, Color.WHITE, Balance.PARTICLE_SPEED * 0.5)


# ── Update ──────────────────────────────────────────────────────────────────

func update(delta: float) -> void:
	if _hit_stop > 0.0:
		_hit_stop -= delta
		return

	_update_shake(delta)

	for i in range(_particles.size() - 1, -1, -1):
		var pt = _particles[i]
		pt["pos"] += pt["vel"] * delta
		pt["vel"] *= 0.92
		pt["life"] -= delta
		if pt["life"] <= 0.0:
			_particles.remove_at(i)

	for i in range(_floaters.size() - 1, -1, -1):
		var fl = _floaters[i]
		fl["pos"].y -= Balance.FLOAT_SPEED * delta
		fl["life"]  -= delta
		if fl["life"] <= 0.0:
			_floaters.remove_at(i)

	queue_redraw()


func _update_shake(delta: float) -> void:
	if not _camera:
		return
	if _shake_trauma > 0.0:
		var t := _shake_trauma / 0.18
		var ox := randf_range(-_shake_max_x, _shake_max_x) * t
		var oy := randf_range(-_shake_max_y, _shake_max_y) * t
		_camera.offset = Vector2(ox * 40.0, oy * 40.0)
		_shake_trauma -= delta
		if _shake_trauma <= 0.0:
			_shake_trauma = 0.0
			_shake_max_x  = 0.0
			_shake_max_y  = 0.0
			_camera.offset = Vector2.ZERO
	else:
		_camera.offset = Vector2.ZERO


# ── Draw ────────────────────────────────────────────────────────────────────

func _draw() -> void:
	for pt in _particles:
		var alpha := pt["life"] / pt["max"]
		var c: Color = pt["color"]
		draw_circle(pt["pos"], pt["r"], Color(c.r, c.g, c.b, alpha))

	for fl in _floaters:
		var alpha := fl["life"] / fl["max"]
		var c: Color = fl["color"]
		draw_string(
			ThemeDB.fallback_font,
			fl["pos"],
			fl["text"],
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			22,
			Color(c.r, c.g, c.b, alpha)
		)
