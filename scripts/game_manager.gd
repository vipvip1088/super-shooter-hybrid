extends Node2D

# ── Constants ──────────────────────────────────────────────────────────────
const MAP_W       := 3000.0
const MAP_H       := 3000.0
const GRID_STEP   := 150.0
const PLAYER_R    := 22.0
const BARRICADE_W := 70.0
const BARRICADE_H := 70.0
const PLAYER_SPEED:= 500.0
const ZONE_PHASES := [
	{"duration": 120.0, "damage": 2.0,  "ratio": 0.70},
	{"duration":  90.0, "damage": 5.0,  "ratio": 0.45},
	{"duration":  60.0, "damage": 10.0, "ratio": 0.25},
	{"duration":  30.0, "damage": 20.0, "ratio": 0.10},
	{"duration":  15.0, "damage": 40.0, "ratio": 0.00},
]

# ── Player state ───────────────────────────────────────────────────────────
var player_pos  := Vector2(MAP_W * 0.5, MAP_H * 0.5)
var player_hp   := 100.0
var player_money:= 1000
var wood        := 10
var metal       := 10
var weapon      := "pistol"
var ammo        := 30
var barricades  : Array[Vector2] = []

# ── Zone state ─────────────────────────────────────────────────────────────
var zone_center         := Vector2(MAP_W * 0.5, MAP_H * 0.5)
var zone_radius         := 1200.0
var zone_target_radius  := 840.0
var zone_shrink_speed   := 0.0
var zone_phase          := 0
var zone_phase_timer    := 120.0
var zone_damage_ps      := 2.0

# ── Movement ───────────────────────────────────────────────────────────────
var move_dir    := Vector2.ZERO
var auto_move   := false
var auto_angle  := 0.0

# ── Feedback text ──────────────────────────────────────────────────────────
var feedback_text  := ""
var feedback_timer := 0.0

# ── Node refs ──────────────────────────────────────────────────────────────
var camera    : Camera2D
var hud_node  : Control

func _ready() -> void:
	zone_target_radius = zone_radius * ZONE_PHASES[0]["ratio"]
	zone_shrink_speed  = (zone_radius - zone_target_radius) / ZONE_PHASES[0]["duration"]

	camera = Camera2D.new()
	camera.position = player_pos
	add_child(camera)

	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)

	var hud_script := load("res://scripts/hud.gd") as GDScript
	hud_node = hud_script.new() as Control
	hud_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(hud_node)

	hud_node.joystick_moved.connect(_on_joystick_moved)
	hud_node.shop_pressed.connect(_on_shop_pressed)
	hud_node.craft_pressed.connect(_on_craft_pressed)
	hud_node.test_pressed.connect(_on_test_pressed)

func _process(delta: float) -> void:
	_move_player(delta)
	_update_zone(delta)
	_apply_zone_damage(delta)
	_tick_feedback(delta)
	_sync_hud()
	queue_redraw()

# ── Movement ───────────────────────────────────────────────────────────────
func _move_player(delta: float) -> void:
	var dir := move_dir
	if auto_move:
		auto_angle += delta * 0.7
		dir = Vector2(cos(auto_angle), sin(auto_angle))
	player_pos += dir * PLAYER_SPEED * delta
	player_pos.x = clampf(player_pos.x, 0.0, MAP_W)
	player_pos.y = clampf(player_pos.y, 0.0, MAP_H)
	camera.position = player_pos

# ── Zone ───────────────────────────────────────────────────────────────────
func _update_zone(delta: float) -> void:
	zone_phase_timer -= delta
	if zone_radius > zone_target_radius:
		zone_radius = maxf(zone_target_radius, zone_radius - zone_shrink_speed * delta)
	if zone_phase_timer <= 0.0 and zone_phase < ZONE_PHASES.size() - 1:
		zone_phase      += 1
		zone_phase_timer = ZONE_PHASES[zone_phase]["duration"]
		zone_target_radius = zone_radius * ZONE_PHASES[zone_phase]["ratio"]
		zone_shrink_speed  = (zone_radius - zone_target_radius) / maxf(zone_phase_timer, 0.01)
		zone_damage_ps     = ZONE_PHASES[zone_phase]["damage"]

func _apply_zone_damage(delta: float) -> void:
	if player_pos.distance_to(zone_center) > zone_radius:
		player_hp = maxf(0.0, player_hp - zone_damage_ps * delta)

# ── Feedback ───────────────────────────────────────────────────────────────
func _tick_feedback(delta: float) -> void:
	if feedback_timer > 0.0:
		feedback_timer -= delta
		if feedback_timer <= 0.0:
			feedback_text = ""

func _show_feedback(text: String) -> void:
	feedback_text  = text
	feedback_timer = 2.5

# ── HUD sync ───────────────────────────────────────────────────────────────
func _sync_hud() -> void:
	var in_zone := player_pos.distance_to(zone_center) <= zone_radius
	hud_node.set_meta("hp",          player_hp)
	hud_node.set_meta("money",       player_money)
	hud_node.set_meta("wood",        wood)
	hud_node.set_meta("metal",       metal)
	hud_node.set_meta("weapon",      weapon)
	hud_node.set_meta("ammo",        ammo)
	hud_node.set_meta("in_zone",     in_zone)
	hud_node.set_meta("zone_phase",  zone_phase)
	hud_node.set_meta("zone_timer",  zone_phase_timer)
	hud_node.set_meta("feedback",    feedback_text)
	hud_node.set_meta("auto_move",   auto_move)
	hud_node.queue_redraw()

# ── Drawing ────────────────────────────────────────────────────────────────
func _draw() -> void:
	_draw_grid()
	_draw_zone()
	_draw_barricades()
	_draw_player()

func _draw_grid() -> void:
	draw_rect(Rect2(0.0, 0.0, MAP_W, MAP_H), Color(0.11, 0.14, 0.11))
	var gc := Color(0.21, 0.26, 0.21, 1.0)
	var x := 0.0
	while x <= MAP_W:
		draw_line(Vector2(x, 0.0), Vector2(x, MAP_H), gc, 1.5)
		x += GRID_STEP
	var y := 0.0
	while y <= MAP_H:
		draw_line(Vector2(0.0, y), Vector2(MAP_W, y), gc, 1.5)
		y += GRID_STEP
	# Center cross
	draw_circle(zone_center, 10.0, Color(1.0, 1.0, 0.3, 0.7))
	draw_line(zone_center - Vector2(20, 0), zone_center + Vector2(20, 0), Color(1.0, 1.0, 0.3, 0.5), 2.0)
	draw_line(zone_center - Vector2(0, 20), zone_center + Vector2(0, 20), Color(1.0, 1.0, 0.3, 0.5), 2.0)

func _draw_zone() -> void:
	# Outer glow
	draw_arc(zone_center, zone_radius + 18.0, 0.0, TAU, 128, Color(0.2, 0.8, 1.0, 0.15), 36.0)
	# Main border
	draw_arc(zone_center, zone_radius, 0.0, TAU, 128, Color(0.25, 0.85, 1.0, 1.0), 7.0)
	# Inner soft edge
	draw_arc(zone_center, zone_radius - 12.0, 0.0, TAU, 128, Color(0.25, 0.85, 1.0, 0.25), 24.0)
	# Danger pulse ring around player when outside
	if player_pos.distance_to(zone_center) > zone_radius:
		var pulse := fmod(Time.get_ticks_msec() * 0.003, TAU)
		var alpha := (sin(pulse) * 0.5 + 0.5) * 0.8 + 0.2
		draw_arc(player_pos, PLAYER_R + 14.0, 0.0, TAU, 32, Color(1.0, 0.2, 0.2, alpha), 5.0)

func _draw_barricades() -> void:
	for b in barricades:
		var r := Rect2(b.x - BARRICADE_W * 0.5, b.y - BARRICADE_H * 0.5, BARRICADE_W, BARRICADE_H)
		draw_rect(r, Color(0.52, 0.36, 0.14))
		draw_rect(r, Color(0.72, 0.52, 0.22), false, 3.5)
		# Wood plank lines
		draw_line(Vector2(r.position.x + 5, b.y - 12), Vector2(r.end.x - 5, b.y - 12), Color(0.62, 0.44, 0.18), 2.0)
		draw_line(Vector2(r.position.x + 5, b.y + 12), Vector2(r.end.x - 5, b.y + 12), Color(0.62, 0.44, 0.18), 2.0)

func _draw_player() -> void:
	var in_zone := player_pos.distance_to(zone_center) <= zone_radius
	# Drop shadow
	draw_circle(player_pos + Vector2(5, 5), PLAYER_R, Color(0.0, 0.0, 0.0, 0.28))
	# Body
	var body_color := Color(0.2, 0.55, 1.0) if in_zone else Color(1.0, 0.32, 0.18)
	draw_circle(player_pos, PLAYER_R, body_color)
	draw_arc(player_pos, PLAYER_R, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.85), 2.5)
	# Direction indicator
	var dir := move_dir if move_dir.length_squared() > 0.01 else Vector2.RIGHT
	if auto_move:
		dir = Vector2(cos(auto_angle), sin(auto_angle))
	draw_circle(player_pos + dir.normalized() * (PLAYER_R - 5.0), 6.0, Color.WHITE)
	# HP bar
	var bw := 72.0
	var bh := 9.0
	var bp := player_pos + Vector2(-bw * 0.5, -PLAYER_R - 22.0)
	draw_rect(Rect2(bp, Vector2(bw, bh)), Color(0.22, 0.0, 0.0))
	draw_rect(Rect2(bp, Vector2(bw * player_hp / 100.0, bh)),
		Color(0.1, 0.85, 0.2) if player_hp > 40.0 else Color(0.9, 0.5, 0.1))
	draw_rect(Rect2(bp, Vector2(bw, bh)), Color(1.0, 1.0, 1.0, 0.6), false, 1.0)

# ── Button callbacks ───────────────────────────────────────────────────────
func _on_joystick_moved(dir: Vector2) -> void:
	if not auto_move:
		move_dir = dir

func _on_shop_pressed() -> void:
	if player_money >= 900:
		player_money -= 900
		weapon = "rifle"
		ammo += 90
		_show_feedback("Куплена Винтовка! -$900  |  патроны +90")
	elif player_money >= 500:
		player_money -= 500
		weapon = "smg"
		ammo += 60
		_show_feedback("Куплен SMG! -$500  |  патроны +60")
	elif player_money >= 200:
		player_money -= 200
		weapon = "pistol"
		ammo += 30
		_show_feedback("Куплен Пистолет! -$200  |  патроны +30")
	else:
		_show_feedback("Нет денег! Нужно минимум $200")

func _on_craft_pressed() -> void:
	if wood >= 5:
		wood -= 5
		barricades.append(player_pos + Vector2(90.0, 0.0))
		_show_feedback("Деревянная стена построена! (дерево -5)")
	elif metal >= 3:
		metal -= 3
		barricades.append(player_pos + Vector2(90.0, 0.0))
		_show_feedback("Металлическая стена построена! (металл -3)")
	else:
		_show_feedback("Недостаточно ресурсов! Нужно: дерево 5 или металл 3")

func _on_test_pressed() -> void:
	auto_move = !auto_move
	move_dir = Vector2.ZERO
	_show_feedback("Авто-тест ВКЛ — игрок идёт по кругу" if auto_move else "Авто-тест ВЫКЛ")
