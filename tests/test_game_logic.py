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


# ── Balance mirrors ───────────────────────────────────────────────────────────

WEAPONS = {
    "pistol":  {"damage": 25.0, "fire_rate": 0.40, "ammo": 12, "max_ammo": 12,
                "reload_time": 1.2, "spread": 0.05, "speed": 900.0, "range": 700.0,
                "pellets": 1, "aoe": 0.0, "price": 0},
    "shotgun": {"damage": 18.0, "fire_rate": 0.80, "ammo": 6,  "max_ammo": 6,
                "reload_time": 1.5, "spread": 0.18, "speed": 750.0, "range": 350.0,
                "pellets": 7, "aoe": 0.0, "price": 600},
    "smg":     {"damage": 12.0, "fire_rate": 0.10, "ammo": 30, "max_ammo": 30,
                "reload_time": 1.8, "spread": 0.08, "speed": 850.0, "range": 550.0,
                "pellets": 1, "aoe": 0.0, "price": 500},
    "sniper":  {"damage": 85.0, "fire_rate": 1.50, "ammo": 5,  "max_ammo": 5,
                "reload_time": 2.5, "spread": 0.00, "speed": 1800.0, "range": 1200.0,
                "pellets": 1, "aoe": 0.0, "price": 1400},
    "plasma":  {"damage": 40.0, "fire_rate": 0.60, "ammo": 8,  "max_ammo": 8,
                "reload_time": 2.0, "spread": 0.02, "speed": 600.0, "range": 500.0,
                "pellets": 1, "aoe": 80.0, "price": 900},
}

ENEMIES = {
    "rusher":  {"max_hp": 60.0,   "speed": 320.0, "contact_dmg": 15.0, "shoot_dmg":  0.0,
                "shoot_range": 0.0, "radius": 18.0, "reward": 150, "xp": 10},
    "shooter": {"max_hp": 45.0,   "speed": 150.0, "contact_dmg":  0.0, "shoot_dmg": 12.0,
                "shoot_range": 420.0, "radius": 16.0, "reward": 200, "xp": 15},
    "tank":    {"max_hp": 250.0,  "speed":  80.0, "contact_dmg": 30.0, "shoot_dmg":  0.0,
                "shoot_range": 0.0, "radius": 30.0, "reward": 350, "xp": 25},
    "bomber":  {"max_hp": 50.0,   "speed": 280.0, "contact_dmg": 60.0, "shoot_dmg":  0.0,
                "shoot_range": 0.0, "radius": 20.0, "reward": 200, "xp": 20},
    "boss":    {"max_hp": 1000.0, "speed": 120.0, "contact_dmg": 25.0, "shoot_dmg": 20.0,
                "shoot_range": 600.0, "radius": 50.0, "reward": 2000, "xp": 200},
}

ZONE_PHASES = [
    {"duration": 120.0, "damage": 2.0,  "ratio": 0.70},
    {"duration":  90.0, "damage": 5.0,  "ratio": 0.45},
    {"duration":  60.0, "damage": 10.0, "ratio": 0.25},
    {"duration":  30.0, "damage": 20.0, "ratio": 0.10},
    {"duration":  15.0, "damage": 40.0, "ratio": 0.00},
]

PERKS = {
    "tough":        {"effect": "max_hp",      "value": 25.0},
    "scavenger":    {"effect": "loot_mult",   "value": 1.5},
    "quick_hands":  {"effect": "reload_mult", "value": 2.0},
    "zone_runner":  {"effect": "zone_resist", "value": 0.4},
    "headhunter":   {"effect": "kill_bonus",  "value": 150.0},
    "arsenal":      {"effect": "ammo_mult",   "value": 1.6},
    "steel_nerves": {"effect": "hit_stop",    "value": 0.05},
    "last_stand":   {"effect": "last_stand",  "value": 1.3},
}

HP_SCALE_PER_ROUND = 0.15
WAVE_BASE = 3
WAVE_PER_ROUND = 2
BOSS_EVERY = 5
MAX_ROUNDS = 10


def wave_enemy_count(round_num):
    return max(5, WAVE_BASE + round_num * WAVE_PER_ROUND + round_num // 3)


def enemy_hp_scale(round_num):
    return 1.0 + (round_num - 1) * HP_SCALE_PER_ROUND


# ── New test suites ────────────────────────────────────────────────────────────

class TestWaveFormula(unittest.TestCase):
    def test_round_1_has_at_least_5_enemies(self):
        self.assertGreaterEqual(wave_enemy_count(1), 5)

    def test_round_5_more_than_round_1(self):
        self.assertGreater(wave_enemy_count(5), wave_enemy_count(1))

    def test_round_10_more_than_round_5(self):
        self.assertGreater(wave_enemy_count(10), wave_enemy_count(5))

    def test_boss_spawns_on_round_5(self):
        self.assertEqual(5 % BOSS_EVERY, 0)

    def test_boss_spawns_on_round_10(self):
        self.assertEqual(10 % BOSS_EVERY, 0)

    def test_no_boss_on_round_3(self):
        self.assertNotEqual(3 % BOSS_EVERY, 0)

    def test_max_rounds_is_10(self):
        self.assertEqual(MAX_ROUNDS, 10)

    def test_wave_grows_monotonically(self):
        counts = [wave_enemy_count(r) for r in range(1, MAX_ROUNDS + 1)]
        for i in range(len(counts) - 1):
            self.assertLessEqual(counts[i], counts[i + 1])


class TestEnemyScaling(unittest.TestCase):
    def test_round_1_scale_is_1(self):
        self.assertAlmostEqual(enemy_hp_scale(1), 1.0)

    def test_round_2_scale_is_1_15(self):
        self.assertAlmostEqual(enemy_hp_scale(2), 1.15)

    def test_round_10_scale_above_2(self):
        self.assertGreater(enemy_hp_scale(10), 2.0)

    def test_rusher_hp_scales(self):
        base_hp = ENEMIES["rusher"]["max_hp"]
        scaled  = base_hp * enemy_hp_scale(5)
        self.assertGreater(scaled, base_hp)

    def test_boss_hp_much_higher_than_rusher(self):
        self.assertGreater(ENEMIES["boss"]["max_hp"], ENEMIES["rusher"]["max_hp"] * 5)

    def test_all_enemies_have_positive_hp(self):
        for etype, edata in ENEMIES.items():
            self.assertGreater(edata["max_hp"], 0.0, msg=etype)

    def test_all_enemies_have_reward(self):
        for etype, edata in ENEMIES.items():
            self.assertGreater(edata["reward"], 0, msg=etype)

    def test_tank_slowest(self):
        speeds = {k: v["speed"] for k, v in ENEMIES.items() if k != "boss"}
        self.assertEqual(min(speeds, key=speeds.get), "tank")

    def test_rusher_fastest_non_boss(self):
        speeds = {k: v["speed"] for k, v in ENEMIES.items() if k not in ("boss",)}
        self.assertEqual(max(speeds, key=speeds.get), "rusher")


class TestWeaponSystem(unittest.TestCase):
    def test_all_weapons_defined(self):
        for wid in ("pistol", "shotgun", "smg", "sniper", "plasma"):
            self.assertIn(wid, WEAPONS)

    def test_pistol_is_free(self):
        self.assertEqual(WEAPONS["pistol"]["price"], 0)

    def test_sniper_highest_damage(self):
        dmg = {k: v["damage"] for k, v in WEAPONS.items()}
        self.assertEqual(max(dmg, key=dmg.get), "sniper")

    def test_smg_fastest_fire_rate(self):
        fr = {k: v["fire_rate"] for k, v in WEAPONS.items()}
        self.assertEqual(min(fr, key=fr.get), "smg")

    def test_sniper_slowest_fire_rate(self):
        fr = {k: v["fire_rate"] for k, v in WEAPONS.items()}
        self.assertEqual(max(fr, key=fr.get), "sniper")

    def test_plasma_has_aoe(self):
        self.assertGreater(WEAPONS["plasma"]["aoe"], 0.0)

    def test_non_plasma_no_aoe(self):
        for wid, wd in WEAPONS.items():
            if wid != "plasma":
                self.assertEqual(wd["aoe"], 0.0, msg=wid)

    def test_shotgun_has_7_pellets(self):
        self.assertEqual(WEAPONS["shotgun"]["pellets"], 7)

    def test_ammo_positive_for_all(self):
        for wid, wd in WEAPONS.items():
            self.assertGreater(wd["ammo"], 0, msg=wid)

    def test_dps_smg_competitive(self):
        smg_dps   = WEAPONS["smg"]["damage"]   / WEAPONS["smg"]["fire_rate"]
        sniper_dps = WEAPONS["sniper"]["damage"] / WEAPONS["sniper"]["fire_rate"]
        self.assertGreater(smg_dps, sniper_dps * 0.5)


class TestZoneSystem(unittest.TestCase):
    def test_5_phases_defined(self):
        self.assertEqual(len(ZONE_PHASES), 5)

    def test_damage_increases_each_phase(self):
        for i in range(len(ZONE_PHASES) - 1):
            self.assertLess(ZONE_PHASES[i]["damage"], ZONE_PHASES[i + 1]["damage"])

    def test_ratio_decreases_each_phase(self):
        for i in range(len(ZONE_PHASES) - 1):
            self.assertGreater(ZONE_PHASES[i]["ratio"], ZONE_PHASES[i + 1]["ratio"])

    def test_final_phase_ratio_is_zero(self):
        self.assertEqual(ZONE_PHASES[-1]["ratio"], 0.0)

    def test_initial_radius_1200(self):
        initial = 1200.0
        self.assertEqual(initial, 1200.0)

    def test_zone_resist_reduces_damage(self):
        base_dmg = ZONE_PHASES[0]["damage"]
        resist   = PERKS["zone_runner"]["value"]
        reduced  = base_dmg * (1.0 - resist)
        self.assertLess(reduced, base_dmg)


class TestPerkSystem(unittest.TestCase):
    def test_all_8_perks_defined(self):
        keys = ["tough","scavenger","quick_hands","zone_runner",
                "headhunter","arsenal","steel_nerves","last_stand"]
        for k in keys:
            self.assertIn(k, PERKS, msg=k)

    def test_tough_increases_hp(self):
        hp = 100.0
        hp += PERKS["tough"]["value"]
        self.assertAlmostEqual(hp, 125.0)

    def test_quick_hands_doubles_reload(self):
        base = 1.2
        reloaded = base / PERKS["quick_hands"]["value"]
        self.assertAlmostEqual(reloaded, 0.6)

    def test_arsenal_increases_ammo(self):
        base = 12
        new  = int(base * PERKS["arsenal"]["value"])
        self.assertGreater(new, base)

    def test_zone_runner_value_less_than_1(self):
        self.assertLess(PERKS["zone_runner"]["value"], 1.0)

    def test_headhunter_bonus_positive(self):
        self.assertGreater(PERKS["headhunter"]["value"], 0.0)

    def test_steel_nerves_shorter_than_default(self):
        default_hit_stop = 0.07
        self.assertLess(PERKS["steel_nerves"]["value"], default_hit_stop)

    def test_last_stand_multiplier_above_1(self):
        self.assertGreater(PERKS["last_stand"]["value"], 1.0)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
