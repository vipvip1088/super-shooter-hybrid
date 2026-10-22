"""
Unit tests for SuperShooterHybrid game logic.
Simulates GDScript classes in Python for fast CI/local testing.
Run: python tests/test_game_logic.py
"""

import unittest
import sys
import math


# ─── Python mirrors of GDScript classes ───────────────────────────────────────

class Player:
    MAX_HEALTH = 100.0

    def __init__(self):
        self.health = self.MAX_HEALTH
        self.money = 0
        self.round_kills = 0
        self.inventory = {"weapon": "", "ammo": 0, "wood": 0, "metal": 0}
        self._alive = True
        self.position = (0.0, 0.0)

    def is_alive(self): return self._alive

    def take_damage(self, amount):
        if amount <= 0:
            return
        self.health = max(0.0, self.health - amount)
        if self.health <= 0.0:
            self._alive = False

    def heal(self, amount):
        if amount <= 0:
            return
        self.health = min(self.MAX_HEALTH, self.health + amount)

    def equip_weapon(self, wid): self.inventory["weapon"] = wid
    def add_ammo(self, n): self.inventory["ammo"] = max(0, self.inventory["ammo"] + n)

    def consume_ammo(self, n):
        if self.inventory["ammo"] < n: return False
        self.inventory["ammo"] -= n
        return True

    def add_resource(self, t, n):
        self.inventory.setdefault(t, 0)
        self.inventory[t] += n

    def consume_resource(self, t, n):
        if self.inventory.get(t, 0) < n: return False
        self.inventory[t] -= n
        return True

    def add_money(self, n): self.money += n
    def spend_money(self, n):
        if self.money < n: return False
        self.money -= n
        return True

    def award_kill(self): self.round_kills += 1; self.add_money(300)
    def reset_round_stats(self): self.round_kills = 0


class ZoneManager:
    PHASE_DATA = [
        {"duration": 120.0, "damage_per_sec": 2.0,  "target_radius_ratio": 0.7},
        {"duration": 90.0,  "damage_per_sec": 5.0,  "target_radius_ratio": 0.45},
        {"duration": 60.0,  "damage_per_sec": 10.0, "target_radius_ratio": 0.25},
        {"duration": 30.0,  "damage_per_sec": 20.0, "target_radius_ratio": 0.1},
        {"duration": 15.0,  "damage_per_sec": 40.0, "target_radius_ratio": 0.0},
    ]

    def __init__(self, map_radius=2000.0):
        self.map_radius = map_radius
        self.zone_center = (0.0, 0.0)
        self.current_radius = map_radius
        self.target_radius = map_radius
        self.current_phase = 0
        self.phase_timer = 0.0
        self.shrink_speed = 0.0
        self._start_phase(0)

    def _start_phase(self, index):
        if index >= len(self.PHASE_DATA):
            return
        self.current_phase = index
        self.phase_timer = self.PHASE_DATA[index]["duration"]
        self.target_radius = self.map_radius * self.PHASE_DATA[index]["target_radius_ratio"]
        self.shrink_speed = (self.current_radius - self.target_radius) / max(self.phase_timer, 0.001)

    def process(self, delta):
        self.phase_timer -= delta
        if self.current_radius > self.target_radius:
            self.current_radius = max(self.target_radius, self.current_radius - self.shrink_speed * delta)
        if self.phase_timer <= 0.0:
            self.current_radius = self.target_radius
            nxt = self.current_phase + 1
            if nxt < len(self.PHASE_DATA):
                self._start_phase(nxt)

    def _dist(self, pos):
        cx, cy = self.zone_center
        return math.sqrt((pos[0]-cx)**2 + (pos[1]-cy)**2)

    def is_position_inside_zone(self, pos):
        return self._dist(pos) <= self.current_radius

    def get_damage_per_second(self):
        idx = min(self.current_phase, len(self.PHASE_DATA)-1)
        return self.PHASE_DATA[idx]["damage_per_sec"]

    def apply_zone_damage(self, player, delta):
        if not player.is_alive():
            return
        if not self.is_position_inside_zone(player.position):
            player.take_damage(self.get_damage_per_second() * delta)


class ShopSystem:
    CATALOG = {
        "pistol":  {"type": "weapon", "price": 200,  "ammo_bonus": 30},
        "smg":     {"type": "weapon", "price": 500,  "ammo_bonus": 60},
        "rifle":   {"type": "weapon", "price": 900,  "ammo_bonus": 90},
        "sniper":  {"type": "weapon", "price": 1400, "ammo_bonus": 20},
        "ammo_sm": {"type": "ammo",   "price": 100,  "ammo_bonus": 30},
        "ammo_lg": {"type": "ammo",   "price": 200,  "ammo_bonus": 90},
        "armor":   {"type": "armor",  "price": 400,  "armor_bonus": 50},
    }

    def __init__(self):
        self.is_shop_open = False

    def open_shop(self): self.is_shop_open = True
    def close_shop(self): self.is_shop_open = False

    def buy(self, player, item_id):
        if not self.is_shop_open: return False, "shop_closed"
        if item_id not in self.CATALOG: return False, "unknown_item"
        item = self.CATALOG[item_id]
        if not player.spend_money(item["price"]): return False, "insufficient_funds"
        self._apply_item(player, item_id, item)
        return True, "ok"

    def _apply_item(self, player, item_id, item):
        t = item["type"]
        if t == "weapon":
            player.equip_weapon(item_id)
            player.add_ammo(item.get("ammo_bonus", 0))
        elif t == "ammo":
            player.add_ammo(item.get("ammo_bonus", 0))
        elif t == "armor":
            player.heal(item.get("armor_bonus", 0))

    def award_round_money(self, player, kills, survived):
        earned = kills * 300 + (500 if survived else 200)
        player.add_money(earned)
        return earned

    def get_affordable_items(self, money):
        return [k for k, v in self.CATALOG.items() if v["price"] <= money]


class CraftingSystem:
    RECIPES = {
        "wood_barricade":  {"cost": {"wood": 5},              "hp": 50},
        "metal_barricade": {"cost": {"metal": 3},             "hp": 120},
        "reinforced_wall": {"cost": {"wood": 3, "metal": 5},  "hp": 250},
    }

    def can_craft(self, player, recipe_id):
        if recipe_id not in self.RECIPES: return False
        for res, needed in self.RECIPES[recipe_id]["cost"].items():
            if player.inventory.get(res, 0) < needed: return False
        return True

    def craft(self, player, recipe_id):
        if recipe_id not in self.RECIPES: return False, "unknown_recipe"
        if not self.can_craft(player, recipe_id): return False, "insufficient_resources"
        for res, amt in self.RECIPES[recipe_id]["cost"].items():
            player.consume_resource(res, amt)
        hp = self.RECIPES[recipe_id]["hp"]
        return True, hp

    def get_craftable_recipes(self, player):
        return [r for r in self.RECIPES if self.can_craft(player, r)]


# ─── Tests ────────────────────────────────────────────────────────────────────

class TestPlayer(unittest.TestCase):
    def setUp(self): self.p = Player()

    def test_initial_health(self):
        self.assertEqual(self.p.health, 100.0)

    def test_take_damage_reduces_health(self):
        self.p.take_damage(30)
        self.assertAlmostEqual(self.p.health, 70.0)

    def test_damage_cannot_go_below_zero(self):
        self.p.take_damage(999)
        self.assertEqual(self.p.health, 0.0)
        self.assertFalse(self.p.is_alive())

    def test_zero_damage_has_no_effect(self):
        self.p.take_damage(0)
        self.assertEqual(self.p.health, 100.0)

    def test_heal_restores_health(self):
        self.p.take_damage(40)
        self.p.heal(20)
        self.assertAlmostEqual(self.p.health, 80.0)

    def test_heal_capped_at_max(self):
        self.p.heal(500)
        self.assertEqual(self.p.health, 100.0)

    def test_ammo_management(self):
        self.p.add_ammo(50)
        self.assertEqual(self.p.inventory["ammo"], 50)
        ok = self.p.consume_ammo(20)
        self.assertTrue(ok)
        self.assertEqual(self.p.inventory["ammo"], 30)

    def test_consume_ammo_fails_when_empty(self):
        ok = self.p.consume_ammo(5)
        self.assertFalse(ok)

    def test_resource_add_and_consume(self):
        self.p.add_resource("wood", 10)
        self.assertEqual(self.p.inventory["wood"], 10)
        ok = self.p.consume_resource("wood", 3)
        self.assertTrue(ok)
        self.assertEqual(self.p.inventory["wood"], 7)

    def test_resource_consume_fails_when_insufficient(self):
        ok = self.p.consume_resource("metal", 99)
        self.assertFalse(ok)

    def test_money_add_and_spend(self):
        self.p.add_money(1000)
        ok = self.p.spend_money(400)
        self.assertTrue(ok)
        self.assertEqual(self.p.money, 600)

    def test_spend_money_fails_when_broke(self):
        ok = self.p.spend_money(1)
        self.assertFalse(ok)
        self.assertEqual(self.p.money, 0)

    def test_kill_award(self):
        self.p.award_kill()
        self.assertEqual(self.p.round_kills, 1)
        self.assertEqual(self.p.money, 300)

    def test_reset_round_stats(self):
        self.p.award_kill()
        self.p.reset_round_stats()
        self.assertEqual(self.p.round_kills, 0)


class TestZoneManager(unittest.TestCase):
    def setUp(self): self.z = ZoneManager(map_radius=1000.0)

    def test_initial_radius_equals_map(self):
        self.assertEqual(self.z.current_radius, 1000.0)

    def test_radius_shrinks_over_time(self):
        self.z.process(60.0)
        self.assertLess(self.z.current_radius, 1000.0)

    def test_phase_advances(self):
        self.z.process(120.1)
        self.assertEqual(self.z.current_phase, 1)

    def test_position_inside_zone(self):
        self.assertTrue(self.z.is_position_inside_zone((0, 0)))

    def test_position_outside_zone(self):
        self.assertFalse(self.z.is_position_inside_zone((5000, 5000)))

    def test_zone_damage_applied_outside(self):
        p = Player()
        p.position = (5000.0, 5000.0)
        self.z.apply_zone_damage(p, 1.0)
        self.assertLess(p.health, 100.0)

    def test_no_zone_damage_inside(self):
        p = Player()
        p.position = (0.0, 0.0)
        self.z.apply_zone_damage(p, 1.0)
        self.assertEqual(p.health, 100.0)

    def test_no_zone_damage_on_dead_player(self):
        p = Player()
        p.take_damage(100)
        p.position = (5000.0, 5000.0)
        self.z.apply_zone_damage(p, 1.0)
        self.assertEqual(p.health, 0.0)

    def test_damage_increases_per_phase(self):
        d0 = ZoneManager.PHASE_DATA[0]["damage_per_sec"]
        d1 = ZoneManager.PHASE_DATA[1]["damage_per_sec"]
        self.assertGreater(d1, d0)

    def test_radius_stops_at_target(self):
        for _ in range(1000):
            self.z.process(1.0)
        self.assertGreaterEqual(self.z.current_radius, 0.0)


class TestShopSystem(unittest.TestCase):
    def setUp(self):
        self.shop = ShopSystem()
        self.p = Player()
        self.p.add_money(2000)

    def test_buy_fails_when_shop_closed(self):
        ok, reason = self.shop.buy(self.p, "pistol")
        self.assertFalse(ok)
        self.assertEqual(reason, "shop_closed")

    def test_buy_weapon_success(self):
        self.shop.open_shop()
        ok, _ = self.shop.buy(self.p, "pistol")
        self.assertTrue(ok)
        self.assertEqual(self.p.inventory["weapon"], "pistol")
        self.assertEqual(self.p.inventory["ammo"], 30)
        self.assertEqual(self.p.money, 1800)

    def test_buy_ammo_only(self):
        self.shop.open_shop()
        ok, _ = self.shop.buy(self.p, "ammo_lg")
        self.assertTrue(ok)
        self.assertEqual(self.p.inventory["ammo"], 90)

    def test_buy_armor_heals(self):
        self.p.take_damage(60)
        self.shop.open_shop()
        self.shop.buy(self.p, "armor")
        self.assertAlmostEqual(self.p.health, 90.0)

    def test_buy_fails_insufficient_funds(self):
        self.p.spend_money(2000)
        self.shop.open_shop()
        ok, reason = self.shop.buy(self.p, "pistol")
        self.assertFalse(ok)
        self.assertEqual(reason, "insufficient_funds")

    def test_buy_unknown_item(self):
        self.shop.open_shop()
        ok, reason = self.shop.buy(self.p, "rocket_launcher")
        self.assertFalse(ok)
        self.assertEqual(reason, "unknown_item")

    def test_award_round_money_survived(self):
        earned = self.shop.award_round_money(self.p, kills=2, survived=True)
        self.assertEqual(earned, 1100)
        self.assertEqual(self.p.money, 3100)

    def test_award_round_money_died(self):
        earned = self.shop.award_round_money(self.p, kills=0, survived=False)
        self.assertEqual(earned, 200)

    def test_affordable_items_empty_wallet(self):
        items = self.shop.get_affordable_items(0)
        self.assertEqual(items, [])

    def test_affordable_items_full_wallet(self):
        items = self.shop.get_affordable_items(9999)
        self.assertEqual(len(items), len(ShopSystem.CATALOG))


class TestCraftingSystem(unittest.TestCase):
    def setUp(self):
        self.craft = CraftingSystem()
        self.p = Player()

    def _give_resources(self):
        self.p.add_resource("wood", 20)
        self.p.add_resource("metal", 20)

    def test_craft_wood_barricade(self):
        self._give_resources()
        ok, hp = self.craft.craft(self.p, "wood_barricade")
        self.assertTrue(ok)
        self.assertEqual(hp, 50)
        self.assertEqual(self.p.inventory["wood"], 15)

    def test_craft_metal_barricade(self):
        self._give_resources()
        ok, hp = self.craft.craft(self.p, "metal_barricade")
        self.assertTrue(ok)
        self.assertEqual(hp, 120)
        self.assertEqual(self.p.inventory["metal"], 17)

    def test_craft_reinforced_wall(self):
        self._give_resources()
        ok, hp = self.craft.craft(self.p, "reinforced_wall")
        self.assertTrue(ok)
        self.assertEqual(hp, 250)
        self.assertEqual(self.p.inventory["wood"], 17)
        self.assertEqual(self.p.inventory["metal"], 15)

    def test_craft_fails_no_resources(self):
        ok, reason = self.craft.craft(self.p, "wood_barricade")
        self.assertFalse(ok)
        self.assertEqual(reason, "insufficient_resources")

    def test_craft_unknown_recipe(self):
        ok, reason = self.craft.craft(self.p, "space_laser")
        self.assertFalse(ok)
        self.assertEqual(reason, "unknown_recipe")

    def test_can_craft_check(self):
        self.p.add_resource("wood", 5)
        self.assertTrue(self.craft.can_craft(self.p, "wood_barricade"))

    def test_cannot_craft_check_partial(self):
        self.p.add_resource("wood", 4)
        self.assertFalse(self.craft.can_craft(self.p, "wood_barricade"))

    def test_get_craftable_recipes(self):
        self._give_resources()
        recipes = self.craft.get_craftable_recipes(self.p)
        self.assertIn("wood_barricade", recipes)
        self.assertIn("metal_barricade", recipes)
        self.assertIn("reinforced_wall", recipes)

    def test_resources_consumed_exactly(self):
        self.p.add_resource("wood", 5)
        self.craft.craft(self.p, "wood_barricade")
        self.assertEqual(self.p.inventory["wood"], 0)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
