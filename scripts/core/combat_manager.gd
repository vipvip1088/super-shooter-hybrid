class_name CombatManager
extends Node

signal hit_enemy(enemy_index: int, damage: float, is_aoe: bool)
signal hit_player(damage: float)
signal projectile_explosion(pos: Vector2, radius: float, damage: float)
signal weapon_empty(weapon_id: String)
signal reload_complete(weapon_id: String, new_ammo: int)
signal kill_confirmed(enemy_index: int)

const _weapons: Dictionary = {
	"pistol": {
		"damage": 25.0,
		"fire_rate": 0.40,
		"ammo": 12,
		"reload_time": 1.2,
		"spread": 0.05,
		"speed": 900.0,
		"range": 700.0,
		"pellets": 1,
		"aoe": 0.0,
		"price": 0
	},
	"shotgun": {
		"damage": 18.0,
		"fire_rate": 0.80,
		"ammo": 6,
		"reload_time": 1.5,
		"spread": 0.18,
		"speed": 750.0,
		"range": 350.0,
		"pellets": 7,
		"aoe": 0.0,
		"price": 600
	},
	"smg": {
		"damage": 12.0,
		"fire_rate": 0.10,
		"ammo": 30,
		"reload_time": 1.8,
		"spread": 0.08,
		"speed": 850.0,
		"range": 550.0,
		"pellets": 1,
		"aoe": 0.0,
		"price": 500
	},
	"sniper": {
		"damage": 85.0,
		"fire_rate": 1.50,
		"ammo": 5,
		"reload_time": 2.5,
		"spread": 0.00,
		"speed": 1800.0,
		"range": 1200.0,
		"pellets": 1,
		"aoe": 0.0,
		"price": 1400
	},
	"plasma": {
		"damage": 40.0,
		"fire_rate": 0.60,
		"ammo": 8,
		"reload_time": 2.0,
		"spread": 0.02,
		"speed": 600.0,
		"range": 500.0,
		"pellets": 1,
		"aoe": 80.0,
		"price": 900
	}
}

var _gm: Node
var _fire_cooldown: float = 0.0
var _reload_mult: float = 1.0


func setup(game_manager: Node) -> void:
	_gm = game_manager
	_fire_cooldown = 0.0
	_reload_mult = 1.0


func get_weapon(weapon_id: String) -> Dictionary:
	if weapon_id in _weapons:
		return _weapons[weapon_id].duplicate()
	return {}


func try_shoot(origin: Vector2, direction: Vector2, proj_list: Array) -> bool:
	if _gm.p_is_reloading:
		return false
	if _fire_cooldown > 0.0:
		return false
	if _gm.p_ammo <= 0:
		return false

	var weapon_data: Dictionary = get_weapon(_gm.p_weapon)
	if weapon_data.is_empty():
		return false

	var spread: float = weapon_data["spread"]
	var speed: float = weapon_data["speed"]
	var damage: float = weapon_data["damage"]
	var aoe: float = weapon_data["aoe"]
	var pellets: int = weapon_data["pellets"]
	var weapon_id: String = _gm.p_weapon

	var proj_color: Color
	match weapon_id:
		"pistol":
			proj_color = Color(1.0, 1.0, 0.3, 1.0)
		"shotgun":
			proj_color = Color(1.0, 0.6, 0.1, 1.0)
		"smg":
			proj_color = Color(0.4, 1.0, 0.4, 1.0)
		"sniper":
			proj_color = Color(0.3, 0.8, 1.0, 1.0)
		"plasma":
			proj_color = Color(0.8, 0.2, 1.0, 1.0)
		_:
			proj_color = Color(1.0, 1.0, 1.0, 1.0)

	var proj_radius: float = 4.0
	if weapon_id == "shotgun":
		proj_radius = 8.0
	elif weapon_id == "plasma":
		proj_radius = 14.0

	var base_angle: float = direction.angle()
	var ttl_base: float = (weapon_data["range"] / speed) + 0.1

	if pellets == 7:
		for _p in range(7):
			var angle: float = base_angle + randf_range(-spread, spread)
			var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
			proj_list.append({
				"pos": Vector2(origin.x, origin.y),
				"vel": vel,
				"damage": damage,
				"owner": "player",
				"weapon": weapon_id,
				"ttl": ttl_base,
				"radius": proj_radius,
				"aoe": aoe,
				"color": proj_color,
				"trail": [],
				"dist": 0.0
			})
	else:
		var angle: float = base_angle + randf_range(-spread, spread)
		var vel: Vector2 = Vector2(cos(angle), sin(angle)) * speed
		proj_list.append({
			"pos": Vector2(origin.x, origin.y),
			"vel": vel,
			"damage": damage,
			"owner": "player",
			"weapon": weapon_id,
			"ttl": ttl_base,
			"radius": proj_radius,
			"aoe": aoe,
			"color": proj_color,
			"trail": [],
			"dist": 0.0
		})

	_gm.p_ammo -= 1
	_fire_cooldown = weapon_data["fire_rate"]

	if _gm.p_ammo <= 0:
		emit_signal("weapon_empty", weapon_id)

	return true


func start_reload() -> void:
	if _gm.p_is_reloading:
		return
	if _gm.p_ammo == _gm.p_max_ammo:
		return

	var weapon_data: Dictionary = get_weapon(_gm.p_weapon)
	if weapon_data.is_empty():
		return

	_gm.p_is_reloading = true
	_gm.p_reload_timer = weapon_data["reload_time"] / _reload_mult


func update(delta: float, player_pos: Vector2, enemy_list: Array, proj_list: Array) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	if _gm.p_is_reloading:
		_gm.p_reload_timer -= delta
		if _gm.p_reload_timer <= 0.0:
			_gm.p_is_reloading = false
			_gm.p_ammo = _gm.p_max_ammo
			emit_signal("reload_complete", _gm.p_weapon, _gm.p_ammo)

	for i in range(proj_list.size() - 1, -1, -1):
		var p = proj_list[i]
		var move: Vector2 = p["vel"] * delta
		p["pos"] += move
		p["dist"] += move.length()
		p["ttl"] -= delta

		p["trail"].append(Vector2(p["pos"].x, p["pos"].y))
		if p["trail"].size() > 5:
			p["trail"].pop_front()

		var weapon_range: float = 400.0
		if p["weapon"] in _weapons:
			weapon_range = get_weapon(p["weapon"])["range"]

		if p["ttl"] <= 0.0 or p["dist"] > weapon_range:
			if p["weapon"] == "plasma" and p["aoe"] > 0.0:
				emit_signal("projectile_explosion", p["pos"], p["aoe"], p["damage"])
				_apply_aoe_damage(p["pos"], p["aoe"], p["damage"], enemy_list, proj_list)
			if i < proj_list.size():
				proj_list.remove_at(i)
			continue

		if p["owner"] == "player":
			_check_player_proj_vs_enemies(i, p, enemy_list, proj_list)
		elif p["owner"] == "enemy":
			if _gm.p_invincible <= 0.0:
				var dist_to_player: float = p["pos"].distance_to(player_pos)
				if dist_to_player < p["radius"] + 22.0:
					emit_signal("hit_player", p["damage"])
					if i < proj_list.size():
						proj_list.remove_at(i)


func _check_player_proj_vs_enemies(proj_idx: int, proj: Dictionary, enemy_list: Array, proj_list: Array) -> void:
	for j in range(enemy_list.size() - 1, -1, -1):
		var e = enemy_list[j]
		if e["hp"] <= 0.0:
			continue
		var dist: float = proj["pos"].distance_to(e["pos"])
		if dist < proj["radius"] + e["radius"]:
			if proj["aoe"] > 0.0:
				emit_signal("projectile_explosion", proj["pos"], proj["aoe"], proj["damage"])
				_apply_aoe_damage(proj["pos"], proj["aoe"], proj["damage"], enemy_list, proj_list)
				if proj_idx < proj_list.size():
					proj_list.remove_at(proj_idx)
			else:
				emit_signal("hit_enemy", j, proj["damage"], false)
				if proj_list.size() > proj_idx:
					proj_list.remove_at(proj_idx)
			return


func _apply_aoe_damage(center: Vector2, radius: float, damage: float, enemy_list: Array, proj_list: Array) -> void:
	for j in range(enemy_list.size() - 1, -1, -1):
		var e = enemy_list[j]
		if e["hp"] <= 0.0:
			continue
		var dist: float = center.distance_to(e["pos"])
		if dist < radius + e["radius"]:
			emit_signal("hit_enemy", j, damage, true)

	if _gm.p_invincible <= 0.0:
		var dist_to_player: float = center.distance_to(_gm.p_pos)
		if dist_to_player < radius + 22.0:
			emit_signal("hit_player", damage)


func auto_aim(player_pos: Vector2, enemy_list: Array, max_range: float) -> Vector2:
	var best_dist: float = max_range + 1.0
	var result: Vector2 = Vector2.ZERO
	for e in enemy_list:
		if e["hp"] <= 0.0:
			continue
		var d: float = player_pos.distance_to(e["pos"])
		if d < best_dist:
			best_dist = d
			result = (e["pos"] - player_pos).normalized()
	return result


func set_reload_multiplier(mult: float) -> void:
	_reload_mult = mult


func get_fire_cooldown() -> float:
	return _fire_cooldown


func is_reloading() -> bool:
	return _gm.p_is_reloading
