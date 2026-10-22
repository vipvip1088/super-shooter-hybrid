"""
test_3d_logic.py — Python unit tests for 3D game logic.

Tests damage math, wave generation, weapon balance, zone shrink,
and ballistics without requiring Godot runtime.
"""
import unittest
import math


# ── Inline constants (mirrors balance.gd) ────────────────────────────────────
WEAPONS3D = {
    "ar":      {"damage": 22.0,  "fire_rate": 0.12, "ammo": 30, "reload": 1.8,
                 "spread": 0.03, "range": 55.0, "hitscan": True,  "pellets": 1,
                 "aoe": 0.0, "proj_speed": 0.0, "price": 0},
    "shotgun": {"damage": 18.0,  "fire_rate": 0.70, "ammo": 6,  "reload": 2.2,
                 "spread": 0.18, "range": 18.0, "hitscan": True,  "pellets": 8,
                 "aoe": 0.0, "proj_speed": 0.0, "price": 300},
    "sniper":  {"damage": 140.0, "fire_rate": 1.50, "ammo": 5,  "reload": 2.8,
                 "spread": 0.002,"range":120.0, "hitscan": True,  "pellets": 1,
                 "aoe": 0.0, "proj_speed": 0.0, "price": 500},
    "plasma":  {"damage": 55.0,  "fire_rate": 0.45, "ammo": 18, "reload": 2.0,
                 "spread": 0.02, "range": 45.0, "hitscan": False, "pellets": 1,
                 "aoe": 3.5, "proj_speed": 28.0,"price": 400},
    "grenade": {"damage": 110.0, "fire_rate": 1.20, "ammo": 4,  "reload": 2.5,
                 "spread": 0.04, "range": 28.0, "hitscan": False, "pellets": 1,
                 "aoe": 7.0, "proj_speed": 18.0,"price": 600},
}
ENEMIES3D = {
    "rusher":   {"hp": 80.0,   "speed": 7.5,  "dmg": 15.0,  "atk_range": 1.8,
                  "shoot_dmg": 0.0,  "shoot_range": 0.0,  "reward": 50},
    "sniper_e": {"hp": 55.0,   "speed": 3.0,  "dmg":  8.0,  "atk_range": 1.5,
                  "shoot_dmg": 38.0, "shoot_range": 32.0, "reward": 80},
    "tank":     {"hp": 320.0,  "speed": 2.8,  "dmg": 28.0,  "atk_range": 2.2,
                  "shoot_dmg": 0.0,  "shoot_range": 0.0,  "reward": 150},
    "kamikaze": {"hp": 45.0,   "speed": 9.0,  "dmg": 90.0,  "atk_range": 1.6,
                  "shoot_dmg": 0.0,  "shoot_range": 0.0,  "reward": 60},
    "boss":     {"hp":1200.0,  "speed": 4.2,  "dmg": 45.0,  "atk_range": 3.0,
                  "shoot_dmg": 22.0, "shoot_range": 28.0, "reward": 1000},
}
ZONE_PHASES = [
    {"duration": 60.0, "damage": 3.0,  "end_ratio": 0.70},
    {"duration": 45.0, "damage": 6.0,  "end_ratio": 0.45},
    {"duration": 30.0, "damage": 12.0, "end_ratio": 0.22},
    {"duration": 20.0, "damage": 25.0, "end_ratio": 0.08},
]
ZONE_START_R   = 38.0
WAVE3D_BASE    = 4
WAVE3D_STEP    = 2
HP3D_SCALE     = 0.12
BOSS3D_WAVE    = 5
ARENA_SIZE     = 80.0
ARENA_HALF     = 40.0
P3D_MAX_HP     = 100.0
P3D_SPEED      = 8.0
P3D_DASH_DIST  = 6.0
P3D_DASH_DUR   = 0.20
XP_PER_LEVEL   = [100, 160, 240, 340, 460, 600, 760, 940, 1140, 1360,
                   1600, 1860, 2140, 2440, 2760, 3100, 3460, 3840, 4240, 4660]


# ── Helpers ───────────────────────────────────────────────────────────────────
def aoe_falloff(dist, radius):
    """Same formula as game_manager_3d: 1.0 - clamp(d/r, 0, 1) * 0.5"""
    return 1.0 - min(max(dist / radius, 0.0), 1.0) * 0.5


def hp_scale(wave):
    return 1.0 + wave * HP3D_SCALE


def wave_enemy_count(wave_num):
    return WAVE3D_BASE + (wave_num - 1) * WAVE3D_STEP


# ─────────────────────────────────────────────────────────────────────────────
class TestWeaponBalance(unittest.TestCase):

    def test_weapon_count(self):
        self.assertGreaterEqual(len(WEAPONS3D), 5)

    def test_all_weapons_have_required_keys(self):
        required = {"damage", "fire_rate", "ammo", "reload", "spread",
                    "range", "hitscan", "pellets", "aoe"}
        for wid, wdat in WEAPONS3D.items():
            for key in required:
                self.assertIn(key, wdat, f"{wid} missing {key}")

    def test_sniper_has_highest_single_shot_damage(self):
        single_shot = {wid: d["damage"] for wid, d in WEAPONS3D.items() if d["pellets"] == 1}
        self.assertEqual(max(single_shot, key=single_shot.get), "sniper")

    def test_shotgun_total_pellet_damage_is_high(self):
        sg = WEAPONS3D["shotgun"]
        total = sg["damage"] * sg["pellets"]
        self.assertGreater(total, 100)

    def test_grenade_has_aoe(self):
        self.assertGreater(WEAPONS3D["grenade"]["aoe"], 0.0)

    def test_plasma_is_projectile(self):
        self.assertFalse(WEAPONS3D["plasma"]["hitscan"])
        self.assertGreater(WEAPONS3D["plasma"]["proj_speed"], 0.0)

    def test_ar_is_hitscan(self):
        self.assertTrue(WEAPONS3D["ar"]["hitscan"])

    def test_fire_rates_are_positive(self):
        for wid, wdat in WEAPONS3D.items():
            self.assertGreater(wdat["fire_rate"], 0.0, f"{wid} fire_rate invalid")

    def test_hitscan_weapons_have_zero_proj_speed(self):
        for wid, wdat in WEAPONS3D.items():
            if wdat["hitscan"]:
                self.assertEqual(wdat["proj_speed"], 0.0, f"{wid} should have proj_speed 0")

    def test_dps_ar_greater_than_sniper(self):
        ar_dps = WEAPONS3D["ar"]["damage"] / WEAPONS3D["ar"]["fire_rate"]
        sniper_dps = WEAPONS3D["sniper"]["damage"] / WEAPONS3D["sniper"]["fire_rate"]
        self.assertGreater(ar_dps, sniper_dps)


class TestDamageCalculations(unittest.TestCase):

    def test_aoe_center_is_full_damage(self):
        dmg = 100.0
        result = dmg * aoe_falloff(0.0, 5.0)
        self.assertAlmostEqual(result, 100.0)

    def test_aoe_edge_is_50_percent(self):
        dmg = 100.0
        result = dmg * aoe_falloff(5.0, 5.0)
        self.assertAlmostEqual(result, 50.0)

    def test_aoe_midpoint_falloff(self):
        result = aoe_falloff(2.5, 5.0)
        self.assertAlmostEqual(result, 0.75)

    def test_aoe_outside_radius_is_50_percent(self):
        # Beyond radius, clamp kicks in → still 50%
        result = aoe_falloff(10.0, 5.0)
        self.assertAlmostEqual(result, 0.50)

    def test_melee_kills_low_hp_enemy(self):
        rusher_hp = ENEMIES3D["rusher"]["hp"]
        ar_dmg = WEAPONS3D["ar"]["damage"]
        shots_needed = math.ceil(rusher_hp / ar_dmg)
        self.assertGreater(shots_needed, 0)
        self.assertLessEqual(shots_needed, 10)

    def test_sniper_one_shots_rusher(self):
        self.assertGreater(WEAPONS3D["sniper"]["damage"], ENEMIES3D["rusher"]["hp"])

    def test_sniper_does_not_one_shot_tank(self):
        self.assertLess(WEAPONS3D["sniper"]["damage"], ENEMIES3D["tank"]["hp"])

    def test_player_hp_positive(self):
        self.assertGreater(P3D_MAX_HP, 0.0)

    def test_kamikaze_explode_damage_is_high(self):
        self.assertGreater(ENEMIES3D["kamikaze"]["dmg"], 70.0)


class TestEnemyHP(unittest.TestCase):

    def test_hp_scale_wave1(self):
        self.assertAlmostEqual(hp_scale(1), 1.12)

    def test_hp_scale_increases_per_wave(self):
        for w in range(1, 10):
            self.assertGreater(hp_scale(w + 1), hp_scale(w))

    def test_boss_has_most_hp(self):
        max_hp = max(e["hp"] for e in ENEMIES3D.values())
        self.assertEqual(max_hp, ENEMIES3D["boss"]["hp"])

    def test_kamikaze_has_lowest_hp(self):
        min_hp = min(e["hp"] for e in ENEMIES3D.values())
        self.assertEqual(min_hp, ENEMIES3D["kamikaze"]["hp"])

    def test_tank_hp_more_than_3x_rusher(self):
        self.assertGreater(ENEMIES3D["tank"]["hp"], ENEMIES3D["rusher"]["hp"] * 3)

    def test_scaled_boss_wave5(self):
        base = ENEMIES3D["boss"]["hp"]
        scaled = base * hp_scale(5)
        self.assertGreater(scaled, base)


class TestWaveGeneration(unittest.TestCase):

    def test_wave1_count(self):
        self.assertEqual(wave_enemy_count(1), 4)

    def test_wave2_count(self):
        self.assertEqual(wave_enemy_count(2), 6)

    def test_wave_count_increases(self):
        for w in range(1, 8):
            self.assertGreater(wave_enemy_count(w + 1), wave_enemy_count(w))

    def test_boss_spawns_on_wave5(self):
        self.assertEqual(5 % BOSS3D_WAVE, 0)

    def test_wave_count_formula(self):
        for w in range(1, 11):
            expected = WAVE3D_BASE + (w - 1) * WAVE3D_STEP
            self.assertEqual(wave_enemy_count(w), expected)


class TestZoneShrink(unittest.TestCase):

    def test_zone_phases_count(self):
        self.assertGreaterEqual(len(ZONE_PHASES), 4)

    def test_zone_ratios_decrease(self):
        for i in range(len(ZONE_PHASES) - 1):
            self.assertGreater(
                ZONE_PHASES[i]["end_ratio"],
                ZONE_PHASES[i+1]["end_ratio"]
            )

    def test_final_zone_is_small(self):
        self.assertLessEqual(ZONE_PHASES[-1]["end_ratio"], 0.10)

    def test_zone_damage_increases_per_phase(self):
        for i in range(len(ZONE_PHASES) - 1):
            self.assertGreater(ZONE_PHASES[i+1]["damage"], ZONE_PHASES[i]["damage"])

    def test_zone_total_time(self):
        total = sum(p["duration"] for p in ZONE_PHASES)
        self.assertGreater(total, 120.0)

    def test_zone_start_radius_covers_arena(self):
        # Zone should start close to arena half-size
        self.assertAlmostEqual(ZONE_START_R, ARENA_HALF - 2.0, delta=3.0)


class TestPlayerMovement(unittest.TestCase):

    def test_dash_speed(self):
        dash_speed = P3D_DASH_DIST / P3D_DASH_DUR
        self.assertGreater(dash_speed, P3D_SPEED * 2)

    def test_dash_distance_positive(self):
        self.assertGreater(P3D_DASH_DIST, 0.0)

    def test_base_speed_in_range(self):
        self.assertGreater(P3D_SPEED, 4.0)
        self.assertLess(P3D_SPEED, 20.0)

    def test_arena_size(self):
        self.assertAlmostEqual(ARENA_HALF, ARENA_SIZE / 2.0)


class TestXPProgression(unittest.TestCase):

    def test_xp_level_count(self):
        self.assertGreaterEqual(len(XP_PER_LEVEL), 10)

    def test_xp_increases_per_level(self):
        for i in range(len(XP_PER_LEVEL) - 1):
            self.assertGreater(XP_PER_LEVEL[i+1], XP_PER_LEVEL[i])

    def test_total_xp_to_max_level(self):
        total = sum(XP_PER_LEVEL)
        self.assertGreater(total, 5000)

    def test_level1_xp_is_reachable(self):
        # Should take ~3-5 kills to first level up
        self.assertLessEqual(XP_PER_LEVEL[0], 200)


class TestArenaLayout(unittest.TestCase):

    def test_arena_is_square(self):
        self.assertAlmostEqual(ARENA_SIZE, 80.0)

    def test_spawn_ring_inside_arena(self):
        spawn_r = ARENA_HALF - 3.0
        self.assertGreater(spawn_r, 0.0)
        self.assertLess(spawn_r, ARENA_HALF)

    def test_zone_start_inside_arena(self):
        self.assertLess(ZONE_START_R, ARENA_HALF)


if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for cls in [TestWeaponBalance, TestDamageCalculations, TestEnemyHP,
                TestWaveGeneration, TestZoneShrink, TestPlayerMovement,
                TestXPProgression, TestArenaLayout]:
        suite.addTests(loader.loadTestsFromTestCase(cls))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    import sys
    sys.exit(0 if result.wasSuccessful() else 1)
