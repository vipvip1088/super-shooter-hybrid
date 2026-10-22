class_name LootManager
extends Node

signal loot_collected(type: String, amount: int)

var _gm: Node


func setup(game_manager: Node) -> void:
	_gm = game_manager


func spawn_loot(pos: Vector2, loot_mult: float) -> void:
	var items: Array = _gm.loot_items
	var adjusted_money: float = Balance.LOOT_MONEY_CHANCE * loot_mult

	if randf() < adjusted_money:
		var amount := int(randf_range(50.0, 150.0) * loot_mult)
		items.append({
			"pos":  Vector2(pos),
			"type": "money",
			"value": amount,
			"timer": Balance.LOOT_DESPAWN_TIME
		})

	if randf() < Balance.LOOT_HEALTH_CHANCE:
		items.append({
			"pos":  Vector2(pos),
			"type": "health",
			"value": 25,
			"timer": Balance.LOOT_DESPAWN_TIME
		})

	if randf() < Balance.LOOT_AMMO_CHANCE:
		items.append({
			"pos":  Vector2(pos),
			"type": "ammo",
			"value": 1,
			"timer": Balance.LOOT_DESPAWN_TIME
		})

	if randf() < Balance.LOOT_WOOD_CHANCE:
		items.append({
			"pos":  Vector2(pos),
			"type": "wood",
			"value": 10,
			"timer": Balance.LOOT_DESPAWN_TIME
		})

	if randf() < Balance.LOOT_METAL_CHANCE:
		items.append({
			"pos":  Vector2(pos),
			"type": "metal",
			"value": 5,
			"timer": Balance.LOOT_DESPAWN_TIME
		})

	if randf() < Balance.LOOT_CHIP_CHANCE:
		items.append({
			"pos":  Vector2(pos),
			"type": "chips",
			"value": 1,
			"timer": Balance.LOOT_DESPAWN_TIME
		})


func update(delta: float, player_pos: Vector2) -> void:
	var items: Array = _gm.loot_items
	for i in range(items.size() - 1, -1, -1):
		var item = items[i]
		item["timer"] -= delta

		var d: float = player_pos.distance_to(item["pos"])
		var mm_raw = _gm.get("p_magnet_mult")
		var mm: float = float(mm_raw) if mm_raw != null else 1.0
		var magnet_r: float = Balance.LOOT_MAGNET_RADIUS * mm
		if d < magnet_r:
			var dir := (player_pos - item["pos"]).normalized()
			var pull_speed := lerpf(200.0, 600.0, 1.0 - d / maxf(magnet_r, 1.0))
			item["pos"] += dir * pull_speed * delta

		if d < 24.0:
			_collect(item)
			items.remove_at(i)
			continue

		if item["timer"] <= 0.0:
			items.remove_at(i)


func _collect(item: Dictionary) -> void:
	var t: String = item["type"]
	var v: int    = item["value"]
	match t:
		"money":
			_gm.p_money += v
		"health":
			_gm.p_hp = minf(_gm.p_hp + v, _gm.p_max_hp)
		"ammo":
			if not _gm.p_is_reloading:
				_gm.p_ammo = mini(_gm.p_ammo + _gm.p_max_ammo, _gm.p_max_ammo)
		"wood":
			_gm.p_wood  += v
		"metal":
			_gm.p_metal += v
		"chips":
			_gm.p_chips += v
	emit_signal("loot_collected", t, v)
