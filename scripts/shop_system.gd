extends Node
class_name ShopSystem

const CATALOG: Dictionary = {
	"pistol":    {"type": "weapon", "price": 200,  "ammo_bonus": 30},
	"smg":       {"type": "weapon", "price": 500,  "ammo_bonus": 60},
	"rifle":     {"type": "weapon", "price": 900,  "ammo_bonus": 90},
	"sniper":    {"type": "weapon", "price": 1400, "ammo_bonus": 20},
	"ammo_sm":   {"type": "ammo",   "price": 100,  "ammo_bonus": 30},
	"ammo_lg":   {"type": "ammo",   "price": 200,  "ammo_bonus": 90},
	"armor":     {"type": "armor",  "price": 400,  "armor_bonus": 50},
}

var is_shop_open: bool = false

signal purchase_success(item_id: String, remaining_money: int)
signal purchase_failed(item_id: String, reason: String)
signal shop_opened()
signal shop_closed()

func open_shop() -> void:
	is_shop_open = true
	shop_opened.emit()

func close_shop() -> void:
	is_shop_open = false
	shop_closed.emit()

func buy(player: Player, item_id: String) -> bool:
	if not is_shop_open:
		purchase_failed.emit(item_id, "shop_closed")
		return false

	if item_id not in CATALOG:
		purchase_failed.emit(item_id, "unknown_item")
		return false

	var item: Dictionary = CATALOG[item_id]
	var price: int = item["price"]

	if not player.spend_money(price):
		purchase_failed.emit(item_id, "insufficient_funds")
		return false

	_apply_item(player, item_id, item)
	purchase_success.emit(item_id, player.money)
	return true

func _apply_item(player: Player, item_id: String, item: Dictionary) -> void:
	match item["type"]:
		"weapon":
			player.equip_weapon(item_id)
			player.add_ammo(item.get("ammo_bonus", 0))
		"ammo":
			player.add_ammo(item.get("ammo_bonus", 0))
		"armor":
			player.heal(item.get("armor_bonus", 0))

func get_catalog() -> Dictionary:
	return CATALOG.duplicate(true)

func get_affordable_items(player_money: int) -> Array[String]:
	var result: Array[String] = []
	for id in CATALOG:
		if CATALOG[id]["price"] <= player_money:
			result.append(id)
	return result

func award_round_money(player: Player, kills: int, survived: bool) -> int:
	var earned: int = 0
	earned += kills * 300
	if survived:
		earned += 500
	else:
		earned += 200
	player.add_money(earned)
	return earned
