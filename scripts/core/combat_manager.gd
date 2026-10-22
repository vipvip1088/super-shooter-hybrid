class_name CombatManager
extends Node

signal hit_enemy(enemy_index: int, damage: float, is_aoe: bool)
signal hit_player(damage: float)
signal projectile_explosion(pos: Vector2, radius: float, damage: float)
signal weapon_empty(weapon_id: String)
signal reload_complete(weapon_id: String, new_ammo: int)

var _gm:           Node
var _fire_cooldown: float = 0.0
var _reload_mult:   float = 1.0


func setup(game_manager: Node) -> void:
	_gm          = game_manager
	_fire_cooldown = 0.0
	_reload_mult   = 1.0


func get_weapon(weapon_id: String) -> Dictionary:
	if weapon_id in Balance.WEAPONS:
		return Balance.WEAPONS[weapon_id].duplicate()
	return {}


func try_shoot(origin: Vector2, direction: Vector2, proj_list: Array) -> bool:
	if _gm.p_is_reloading:
		return false
	if _fire_cooldown > 0.0:
		return false
	if _gm.p_ammo <= 0:
		return false

	var wd: Dictionary = get_weapon(_gm.p_weapon)
	if wd.is_empty():
		return false

	var spread:    float  = float(wd["spread"])
	var speed:     float  = float(wd["speed"])
	var damage:    float  = float(wd["damage"])
	var aoe:       float  = float(wd["aoe"])
	var pellets:   int    = int(wd["pellets"])
	var weapon_id: String = _gm.p_weapon

	var proj_color := _weapon_color(weapon_id)
	var proj_radius := _weapon_radius(weapon_id)
	var base_angle  := direction.angle()
	var ttl_base    := (float(wd["range"]) / speed) + 0.15

	var shots := pellets if pellets > 1 else 1
	for _i in range(shots):
		var angle := base_angle + randf_range(-spread, spread)
		var vel   := Vector2(cos(angle), sin(angle)) * speed
		proj_list.append({
			"pos":    Vector2(origin),
			"vel":    vel,
			"damage": damage,
			"owner":  "player",
			"weapon": weapon_id,
			"ttl":    ttl_base,
			"radius": proj_radius,
			"aoe":    aoe,
			"color":  proj_color,
			"trail":  [],
			"dist":   0.0,
		})

	_gm.p_ammo       -= 1
	_fire_cooldown    = float(wd["fire_rate"])

	if _gm.p_ammo <= 0:
		emit_signal("weapon_empty", weapon_id)

	return true


func _weapon_color(weapon_id: String) -> Color:
	if weapon_id in Balance.WEAPONS:
		var wd: Dictionary = Balance.WEAPONS[weapon_id]
		return Color(float(wd["color_r"]), float(wd["color_g"]), float(wd["color_b"]), 1.0)
	return Color(1.0, 1.0, 1.0, 1.0)


func _weapon_radius(weapon_id: String) -> float:
	match weapon_id:
		"shotgun":      return 7.0
		"plasma":       return 14.0
		"rocket":       return 12.0
		"minigun":      return 4.0
		"flamethrower": return 8.0
		_:              return 5.0


func start_reload() -> void:
	if _gm.p_is_reloading:
		return
	if _gm.p_ammo == _gm.p_max_ammo:
		return
	var wd: Dictionary = get_weapon(_gm.p_weapon)
	if wd.is_empty():
		return
	_gm.p_is_reloading = true
	_gm.p_reload_timer = float(wd["reload_time"]) / _reload_mult


func create_explosion(center: Vector2, radius: float, damage: float,
		enemy_list: Array, _proj_list: Array) -> void:
	emit_signal("projectile_explosion", center, radius, damage)
	_apply_aoe_damage(center, radius, damage, enemy_list)


func update(delta: float, player_pos: Vector2, enemy_list: Array, proj_list: Array) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	if _gm.p_is_reloading:
		_gm.p_reload_timer -= delta
		if _gm.p_reload_timer <= 0.0:
			_gm.p_is_reloading = false
			_gm.p_ammo         = _gm.p_max_ammo
			emit_signal("reload_complete", _gm.p_weapon, _gm.p_ammo)

	for i in range(proj_list.size() - 1, -1, -1):
		var p = proj_list[i]
		var move: Vector2 = p["vel"] * delta
		p["pos"] += move
		p["dist"] += move.length()
		p["ttl"]  -= delta

		p["trail"].append(Vector2(p["pos"]))
		if (p["trail"] as Array).size() > 6:
			(p["trail"] as Array).pop_front()

		var weapon_range: float = 400.0
		var pw: String = p["weapon"]
		if pw in Balance.WEAPONS:
			weapon_range = float(Balance.WEAPONS[pw]["range"])

		if float(p["ttl"]) <= 0.0 or float(p["dist"]) > weapon_range:
			if float(p["aoe"]) > 0.0 and pw != "enemy_bullet":
				emit_signal("projectile_explosion", p["pos"], p["aoe"], p["damage"])
				_apply_aoe_damage(p["pos"], float(p["aoe"]), float(p["damage"]), enemy_list)
			if i < proj_list.size():
				proj_list.remove_at(i)
			continue

		if p["owner"] == "player":
			_check_player_proj(i, p, enemy_list, proj_list)
		elif p["owner"] == "enemy":
			if _gm.p_invincible <= 0.0:
				var dist_to_player: float = (p["pos"] as Vector2).distance_to(player_pos)
				if dist_to_player < float(p["radius"]) + 22.0:
					emit_signal("hit_player", float(p["damage"]))
					if i < proj_list.size():
						proj_list.remove_at(i)


func _check_player_proj(proj_idx: int, proj: Dictionary,
		enemy_list: Array, proj_list: Array) -> void:
	for j in range(enemy_list.size() - 1, -1, -1):
		var e = enemy_list[j]
		if float(e["hp"]) <= 0.0:
			continue
		var dist: float = (proj["pos"] as Vector2).distance_to(e["pos"])
		if dist < float(proj["radius"]) + float(e["radius"]):
			if float(proj["aoe"]) > 0.0:
				emit_signal("projectile_explosion", proj["pos"], proj["aoe"], proj["damage"])
				_apply_aoe_damage(proj["pos"], float(proj["aoe"]), float(proj["damage"]), enemy_list)
				if proj_idx < proj_list.size():
					proj_list.remove_at(proj_idx)
			else:
				emit_signal("hit_enemy", j, float(proj["damage"]), false)
				if proj_idx < proj_list.size():
					proj_list.remove_at(proj_idx)
			return


func _apply_aoe_damage(center: Vector2, radius: float, damage: float, enemy_list: Array) -> void:
	for j in range(enemy_list.size() - 1, -1, -1):
		var e = enemy_list[j]
		if float(e["hp"]) <= 0.0:
			continue
		var dist: float = center.distance_to(e["pos"])
		if dist < radius + float(e["radius"]):
			var falloff := 1.0 - clampf(dist / radius, 0.0, 1.0) * 0.5
			emit_signal("hit_enemy", j, damage * falloff, true)

	if _gm.p_invincible <= 0.0:
		var dist_to_player: float = center.distance_to(_gm.p_pos)
		if dist_to_player < radius + 22.0:
			emit_signal("hit_player", damage * 0.5)


func auto_aim(player_pos: Vector2, enemy_list: Array, max_range: float) -> Vector2:
	var best_dist := max_range + 1.0
	var result    := Vector2.ZERO
	for e in enemy_list:
		if float(e["hp"]) <= 0.0:
			continue
		var d: float = player_pos.distance_to(e["pos"])
		if d < best_dist:
			best_dist = d
			result    = ((e["pos"] as Vector2) - player_pos).normalized()
	return result


func set_reload_multiplier(mult: float) -> void:
	_reload_mult = mult


func get_fire_cooldown() -> float:
	return _fire_cooldown


func is_reloading() -> bool:
	return _gm.p_is_reloading
