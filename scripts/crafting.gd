extends Node
class_name CraftingSystem

const RECIPES: Dictionary = {
	"wood_barricade": {
		"cost": {"wood": 5},
		"description": "Light wooden barricade (50 HP)",
		"hp": 50,
	},
	"metal_barricade": {
		"cost": {"metal": 3},
		"description": "Metal barricade (120 HP)",
		"hp": 120,
	},
	"reinforced_wall": {
		"cost": {"wood": 3, "metal": 5},
		"description": "Reinforced wall (250 HP)",
		"hp": 250,
	},
}

signal craft_success(recipe_id: String, hp: int)
signal craft_failed(recipe_id: String, reason: String)

func can_craft(player: Player, recipe_id: String) -> bool:
	if recipe_id not in RECIPES:
		return false
	var cost: Dictionary = RECIPES[recipe_id]["cost"]
	for resource in cost:
		var needed: int = cost[resource]
		var has: int = player.inventory.get(resource, 0)
		if has < needed:
			return false
	return true

func craft(player: Player, recipe_id: String) -> bool:
	if recipe_id not in RECIPES:
		craft_failed.emit(recipe_id, "unknown_recipe")
		return false

	if not can_craft(player, recipe_id):
		craft_failed.emit(recipe_id, "insufficient_resources")
		return false

	var cost: Dictionary = RECIPES[recipe_id]["cost"]
	for resource in cost:
		player.consume_resource(resource, cost[resource])

	var hp: int = RECIPES[recipe_id]["hp"]
	craft_success.emit(recipe_id, hp)
	return true

func get_recipes() -> Dictionary:
	return RECIPES.duplicate(true)

func get_craftable_recipes(player: Player) -> Array[String]:
	var result: Array[String] = []
	for id in RECIPES:
		if can_craft(player, id):
			result.append(id)
	return result
