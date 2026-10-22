class_name EnemySpawner
extends Node

signal enemy_died(pos: Vector2, type: String, reward: int, xp: int)
signal wave_cleared()
signal boss_died(pos: Vector2)
signal enemy_hit_player(damage: float)

var _gm: Node
var _next_id: int = 0
var _current_round: int = 0
var _enemies_to_spawn: int = 0
var _spawn_timer: float = 0.0
var _spawn_queue: Array = []
var _wave_active: bool = false
var _zone_center: Vector2 = Vector2.ZERO
var _zone_radius: float = 0.0
var _pending_enemy: Dictionary = {}
var _enemy_list_ref: Array = []

# ─── Base stats ───────────────────────────────────────────────────────────────
const STATS: Dictionary = {
	"rusher":  {"max_hp": 60.0,   "speed": 320.0, "contact_dmg": 15.0, "shoot_dmg": 0.0,  "shoot_range": 0.0,   "agro": 600.0,  "radius": 18.0, "reward": 150,  "xp": 10},
	"shooter": {"max_hp": 45.0,   "speed": 150.0, "contact_dmg": 0.0,  "shoot_dmg": 12.0, "shoot_range": 420.0, "agro": 500.0,  "radius": 16.0, "reward": 200,  "xp": 15},
	"tank":    {"max_hp": 250.0,  "speed": 80.0,  "contact_dmg": 30.0, "shoot_dmg": 0.0,  "shoot_range": 0.0,   "agro": 400.0,  "radius": 30.0, "reward": 350,  "xp": 25},
	"bomber":  {"max_hp": 50.0,   "speed": 280.0, "contact_dmg": 60.0, "shoot_dmg": 0.0,  "shoot_range": 0.0,   "agro": 500.0,  "radius": 20.0, "reward": 200,  "xp": 20},
	"boss":    {"max_hp": 1000.0, "speed": 120.0, "contact_dmg": 25.0, "shoot_dmg": 20.0, "shoot_range": 600.0, "agro": 2000.0, "radius": 50.0, "reward": 2000, "xp": 200},
}

# ─── Setup ────────────────────────────────────────────────────────────────────
func setup(game_manager: Node) -> void:
	_gm = game_manager
	_next_id = 0
	_current_round = 0
	_enemies_to_spawn = 0
	_spawn_timer = 0.0
	_spawn_queue = []
	_wave_active = false

# ─── Wave logic ───────────────────────────────────────────────────────────────
func start_wave(round_num: int, zone_center: Vector2, zone_radius: float) -> void:
	_current_round = round_num
	_zone_center = zone_center
	_zone_radius = zone_radius
	_spawn_queue.clear()

	var count: int = max(5, 3 + round_num * 2 + int(round_num / 3))
	_enemies_to_spawn = count

	# Extra tanks every 3 rounds after round 3
	var extra_tanks: int = 0
	if round_num > 3:
		extra_tanks = int((round_num - 3) / 3)

	# Fill queue with weighted random types
	for i in range(count):
		var r: int = randi_range(0, 9)
		var t: String
		if r < 5:
			t = "rusher"
		elif r < 8:
			t = "shooter"
		elif r < 9:
			t = "tank"
		else:
			t = "bomber"
		_spawn_queue.append(t)

	# Add extra tanks for later rounds
	for _t in range(extra_tanks):
		_spawn_queue.append("tank")

	# Add boss every 5 rounds starting at round 5
	if round_num >= 5 and (round_num % 5) == 0:
		_spawn_queue.append("boss")

	_spawn_timer = 1.5
	_wave_active = true

func _get_spawn_pos(zone_center: Vector2, zone_radius: float) -> Vector2:
	var angle: float = randf() * TAU
	var dist: float = zone_radius * randf_range(0.3, 0.85)
	return zone_center + Vector2(cos(angle), sin(angle)) * dist

# ─── Spawn enemy ──────────────────────────────────────────────────────────────
func spawn_enemy(type: String, pos: Vector2, round_num: int) -> void:
	var s: Dictionary = STATS[type]
	var round_scale_hp: float = 1.0 + (round_num - 1) * 0.15
	var round_scale_sp: float = minf(2.0, 1.0 + (round_num - 1) * 0.05)

	var scaled_hp: float = s["max_hp"] * round_scale_hp
	var scaled_speed: float = s["speed"] * round_scale_sp

	_pending_enemy = {
		"id": _next_id,
		"type": type,
		"pos": pos,
		"hp": scaled_hp,
		"max_hp": scaled_hp,
		"vel": Vector2.ZERO,
		"state": "idle",
		"state_timer": 0.0,
		"shoot_cd": 0.0,
		"flash": 0.0,
		"phase": 0,
		"pattern_timer": 0.0,
		"explode_timer": 1.5,
		"facing": Vector2.RIGHT,
		"reward": s["reward"],
		"xp": s["xp"],
		"radius": s["radius"],
		"speed": scaled_speed,
		"agro": s["agro"],
		"shoot_range": s["shoot_range"],
		"contact_dmg": s["contact_dmg"],
		"shoot_dmg": s["shoot_dmg"],
	}
	_next_id += 1

# ─── Main update ──────────────────────────────────────────────────────────────
func update(delta: float, player_pos: Vector2, zone_center: Vector2, zone_radius: float, enemy_list: Array, proj_list: Array) -> void:
	# Tick spawn queue
	if _wave_active and _spawn_queue.size() > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			var t: String = _spawn_queue.pop_front()
			spawn_enemy(t, _get_spawn_pos(zone_center, zone_radius), _current_round)
			enemy_list.append(_pending_enemy)
			_spawn_timer = randf_range(0.8, 2.0)

	# Update each enemy AI (backwards for safe removal)
	for i in range(enemy_list.size() - 1, -1, -1):
		var e: Dictionary = enemy_list[i]
		if e["state"] == "dead":
			continue

		# Tick flash
		if e["flash"] > 0.0:
			e["flash"] = maxf(0.0, e["flash"] - delta)

		# Tick state timer
		e["state_timer"] += delta

		# AI dispatch
		match e["type"]:
			"rusher":
				_ai_rusher(e, delta, player_pos, enemy_list, proj_list)
			"shooter":
				_ai_shooter(e, delta, player_pos, enemy_list, proj_list)
			"tank":
				_ai_tank(e, delta, player_pos, enemy_list, proj_list)
			"bomber":
				_ai_bomber(e, delta, player_pos, enemy_list, proj_list)
			"boss":
				_ai_boss(e, delta, player_pos, enemy_list, proj_list)

		# Death check
		if e["hp"] <= 0.0 and e["state"] != "dead":
			kill_enemy(enemy_list, i)

	# Wave cleared check
	if _wave_active and enemy_list.is_empty() and _spawn_queue.is_empty():
		_wave_active = false
		emit_signal("wave_cleared")

# ─── AI: Rusher ───────────────────────────────────────────────────────────────
func _ai_rusher(e: Dictionary, delta: float, player_pos: Vector2, _enemy_list: Array, _proj_list: Array) -> void:
	e["state"] = "chase"
	var dir: Vector2 = (player_pos - e["pos"])
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	else:
		dir = Vector2.RIGHT

	# Zigzag: every 0.5–1.0s interval change perpendicular offset
	var zigzag_offset: Vector2 = Vector2.ZERO
	if e["state_timer"] > randf_range(0.5, 1.0):
		e["state_timer"] = 0.0
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var side: float = 1.0 if randi_range(0, 1) == 0 else -1.0
		zigzag_offset = perp * side * 0.4

	var move_dir: Vector2 = (dir + zigzag_offset)
	if move_dir.length_squared() > 0.0001:
		move_dir = move_dir.normalized()

	e["vel"] = move_dir * e["speed"]
	e["pos"] += e["vel"] * delta
	e["facing"] = move_dir

	# Contact damage
	if e["pos"].distance_to(player_pos) < e["radius"] + 22.0 and _gm.p_invincible <= 0.0:
		emit_signal("enemy_hit_player", e["contact_dmg"])
		_gm.p_invincible = 0.5

# ─── AI: Shooter ──────────────────────────────────────────────────────────────
func _ai_shooter(e: Dictionary, delta: float, player_pos: Vector2, _enemy_list: Array, proj_list: Array) -> void:
	var dist: float = e["pos"].distance_to(player_pos)
	var dir: Vector2 = (player_pos - e["pos"])
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()

	if dist > e["agro"]:
		e["state"] = "idle"
		e["vel"] = Vector2.ZERO
	elif dist > e["shoot_range"]:
		e["state"] = "chase"
		e["vel"] = dir * e["speed"]
		e["pos"] += e["vel"] * delta
		e["facing"] = dir
	elif dist < e["shoot_range"] * 0.5:
		# Flee backwards to maintain distance
		e["state"] = "chase"
		e["vel"] = -dir * e["speed"]
		e["pos"] += e["vel"] * delta
		e["facing"] = dir
	else:
		e["state"] = "attack"
		e["vel"] = Vector2.ZERO
		e["facing"] = dir

		# Shoot every 1.5s
		e["shoot_cd"] -= delta
		if e["shoot_cd"] <= 0.0:
			e["shoot_cd"] = 1.5
			var spread: float = randf_range(-0.08, 0.08)
			var shoot_dir: Vector2 = dir.rotated(spread)
			var bullet: Dictionary = {
				"pos": e["pos"] + shoot_dir * (e["radius"] + 8.0),
				"vel": shoot_dir * 380.0,
				"damage": e["shoot_dmg"],
				"owner": "enemy",
				"weapon": "enemy_bullet",
				"ttl": 2.0,
				"radius": 6.0,
				"aoe": 0.0,
				"color": Color(1.0, 0.3, 0.3, 1.0),
				"trail": [],
				"dist": 0.0,
			}
			proj_list.append(bullet)

# ─── AI: Tank ─────────────────────────────────────────────────────────────────
func _ai_tank(e: Dictionary, delta: float, player_pos: Vector2, _enemy_list: Array, _proj_list: Array) -> void:
	var dir: Vector2 = (player_pos - e["pos"])
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	else:
		dir = Vector2.RIGHT

	e["state"] = "chase"
	e["vel"] = dir * e["speed"]
	e["pos"] += e["vel"] * delta
	e["facing"] = dir

	# Contact damage with cooldown (0.8s)
	if e["pos"].distance_to(player_pos) < e["radius"] + 60.0:
		e["shoot_cd"] -= delta
		if e["shoot_cd"] <= 0.0 and _gm.p_invincible <= 0.0:
			e["shoot_cd"] = 0.8
			emit_signal("enemy_hit_player", e["contact_dmg"])
			_gm.p_invincible = 0.5

# ─── AI: Bomber ───────────────────────────────────────────────────────────────
func _ai_bomber(e: Dictionary, delta: float, player_pos: Vector2, _enemy_list: Array, proj_list: Array) -> void:
	var dist: float = e["pos"].distance_to(player_pos)
	var dir: Vector2 = (player_pos - e["pos"])
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	else:
		dir = Vector2.RIGHT

	if e["state"] == "exploding":
		# Countdown to explosion
		e["explode_timer"] -= delta
		e["flash"] = 0.15  # keep flashing

		if e["explode_timer"] <= 0.0:
			# Explode: hit player if in range
			if dist < 100.0 and _gm.p_invincible <= 0.0:
				emit_signal("enemy_hit_player", e["contact_dmg"])
				_gm.p_invincible = 0.5

			# Emit without reward (suicide)
			emit_signal("enemy_died", e["pos"], e["type"], 0, 0)
			e["hp"] = 0.0
			e["state"] = "dead"
		return

	# Normal chase
	e["state"] = "chase"
	e["vel"] = dir * e["speed"]
	e["pos"] += e["vel"] * delta
	e["facing"] = dir

	# Begin explode sequence when in range
	if dist < 80.0:
		e["state"] = "exploding"
		e["explode_timer"] = 1.5

# ─── AI: Boss ─────────────────────────────────────────────────────────────────
func _ai_boss(e: Dictionary, delta: float, player_pos: Vector2, _enemy_list: Array, proj_list: Array) -> void:
	var hp_pct: float = e["hp"] / e["max_hp"]
	var old_phase: int = e["phase"]

	# Phase transitions
	if hp_pct > 0.66:
		e["phase"] = 0
	elif hp_pct > 0.33:
		e["phase"] = 1
	else:
		e["phase"] = 2

	# Flash on phase transition
	if e["phase"] != old_phase:
		e["flash"] = 0.3
		# Speed boost per phase
		var base_s: float = STATS["boss"]["speed"]
		var round_scale: float = minf(2.0, 1.0 + (_current_round - 1) * 0.05)
		e["speed"] = base_s * round_scale * (1.0 + e["phase"] * 0.25)

	var dir: Vector2 = (player_pos - e["pos"])
	var dist: float = dir.length()
	if dist > 0.0001:
		dir = dir.normalized()
	else:
		dir = Vector2.RIGHT

	# Movement: slow chase
	e["vel"] = dir * e["speed"]
	e["pos"] += e["vel"] * delta
	e["facing"] = dir

	# Contact damage
	if dist < e["radius"] + 30.0 and _gm.p_invincible <= 0.0:
		emit_signal("enemy_hit_player", e["contact_dmg"])
		_gm.p_invincible = 0.5

	# Shooting per phase
	e["pattern_timer"] -= delta

	match e["phase"]:
		0:
			# 8 bullets in circle every 2.0s
			if e["pattern_timer"] <= 0.0:
				e["pattern_timer"] = 2.0
				for k in range(8):
					var angle: float = (TAU / 8.0) * k
					var bdir: Vector2 = Vector2(cos(angle), sin(angle))
					proj_list.append(_make_enemy_bullet(e["pos"], bdir * 320.0, e["shoot_dmg"]))

		1:
			# Spiral: rotate 30deg each shot every 0.3s
			if e["pattern_timer"] <= 0.0:
				e["pattern_timer"] = 0.3
				var base_angle: float = e["state_timer"] * 1.5  # auto-rotate over time
				for k in range(3):
					var angle: float = base_angle + (TAU / 3.0) * k
					var bdir: Vector2 = Vector2(cos(angle), sin(angle))
					proj_list.append(_make_enemy_bullet(e["pos"], bdir * 350.0, e["shoot_dmg"]))

		2:
			# Direct shot at player every 0.5s + 4 side bullets
			if e["pattern_timer"] <= 0.0:
				e["pattern_timer"] = 0.5
				# Direct
				proj_list.append(_make_enemy_bullet(e["pos"], dir * 420.0, e["shoot_dmg"]))
				# 4 side bullets at 45/90 deg offsets
				for k in range(1, 5):
					var side_dir: Vector2 = dir.rotated((TAU / 4.0) * k)
					proj_list.append(_make_enemy_bullet(e["pos"], side_dir * 300.0, e["shoot_dmg"] * 0.6))

func _make_enemy_bullet(from_pos: Vector2, vel: Vector2, dmg: float) -> Dictionary:
	return {
		"pos": from_pos,
		"vel": vel,
		"damage": dmg,
		"owner": "enemy",
		"weapon": "enemy_bullet",
		"ttl": 2.0,
		"radius": 6.0,
		"aoe": 0.0,
		"color": Color(1.0, 0.3, 0.3, 1.0),
		"trail": [],
		"dist": 0.0,
	}

# ─── Kill / Damage ────────────────────────────────────────────────────────────
func kill_enemy(enemy_list: Array, idx: int) -> void:
	var e: Dictionary = enemy_list[idx]
	if e["state"] == "dead":
		return

	var is_boss: bool = e["type"] == "boss"

	# Bomber with state "exploding" already emitted its signal without reward
	var already_emitted: bool = (e["type"] == "bomber" and e["state"] == "exploding" and e["explode_timer"] <= 0.0)

	e["hp"] = 0.0
	e["state"] = "dead"

	if not already_emitted:
		emit_signal("enemy_died", e["pos"], e["type"], e["reward"], e["xp"])

	if is_boss:
		emit_signal("boss_died", e["pos"])

	enemy_list.remove_at(idx)

func apply_damage_to_enemy(enemy_list: Array, idx: int, damage: float) -> void:
	if idx < 0 or idx >= enemy_list.size():
		return
	var e: Dictionary = enemy_list[idx]
	if e["state"] == "dead":
		return
	e["hp"] -= damage
	e["flash"] = 0.15
	if e["hp"] <= 0.0:
		kill_enemy(enemy_list, idx)

# ─── Utility ──────────────────────────────────────────────────────────────────
func get_active_count() -> int:
	return _enemy_list_ref.size() + _spawn_queue.size()
