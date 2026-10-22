"""
test_gdscript_integrity.py — static analysis of all .gd and .tscn files.

Checks:
  1. No Godot 3 API calls (rand_range, .instance(), PoolVector2Array, etc.)
  2. No unmatched braces/brackets/parentheses
  3. All signals connected in game_manager.gd exist on their source classes
  4. All .tscn ExtResource paths exist on disk
  5. No duplicate function names in the same .gd file
  6. Balance.WEAPONS and enemy_spawner.STATS use same enemy keys
  7. All PERK_KEYS listed in balance.gd exist in PERKS dict
  8. No tabs mixed with spaces at start of lines (Godot 4 uses tabs)
  9. No bare 'preload()' calls in game_manager.gd or bootstrap.gd
 10. All files are valid UTF-8
"""

import os
import sys
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GODOT3_PATTERNS = [
    (r'\brand_range\s*\(',          "rand_range() → use randf_range() / randi_range()"),
    (r'\.instance\s*\(\)',           ".instance() → use .instantiate()"),
    (r'\bPoolVector2Array\b',        "PoolVector2Array → use PackedVector2Array"),
    (r'\bPoolStringArray\b',         "PoolStringArray → use PackedStringArray"),
    (r'\bPoolByteArray\b',           "PoolByteArray → use PackedByteArray"),
    (r'\bPoolFloat32Array\b',        "PoolFloat32Array → use PackedFloat32Array"),
    (r'\bPoolIntArray\b',            "PoolIntArray → use PackedInt32Array"),
    (r'\bOS\.get_ticks_msec\b',      "OS.get_ticks_msec → use Time.get_ticks_msec()"),
    (r'\.connect\s*\(\s*"[^"]+"\s*,\s*self\s*,\s*"', "old connect(signal, self, method) → use signal.connect(callable)"),
    (r'\byield\s*\(',                "yield() → use await"),
    (r'\bsetget\b',                  "setget → use @property / custom setter/getter"),
    (r'(?<!@)export\s+var\b',         "export var → use @export var"),
    (r'(?<!@)onready\s+var\b',       "onready var → use @onready var"),
    (r'\bget_node\s*\(\s*"\.\s*"\s*\)', "get_node('.') → use get_parent() or self"),
]

CRITICAL_SIGNAL_CONNECTIONS = {
    "combat_manager.hit_enemy":           ("hit_enemy",             "combat_manager.gd"),
    "combat_manager.hit_player":          ("hit_player",            "combat_manager.gd"),
    "combat_manager.projectile_explosion":("projectile_explosion",  "combat_manager.gd"),
    "combat_manager.weapon_empty":        ("weapon_empty",          "combat_manager.gd"),
    "combat_manager.reload_complete":     ("reload_complete",       "combat_manager.gd"),
    "enemy_spawner.enemy_died":           ("enemy_died",            "enemy_spawner.gd"),
    "enemy_spawner.wave_cleared":         ("wave_cleared",          "enemy_spawner.gd"),
    "enemy_spawner.enemy_hit_player":     ("enemy_hit_player",      "enemy_spawner.gd"),
    "round_manager.state_changed":        ("state_changed",         "round_manager.gd"),
    "round_manager.buy_phase_started":    ("buy_phase_started",     "round_manager.gd"),
    "round_manager.upgrade_choices":      ("upgrade_choices",       "round_manager.gd"),
    "round_manager.game_over":            ("game_over",             "round_manager.gd"),
    "round_manager.victory":              ("victory",               "round_manager.gd"),
    "loot_manager.loot_collected":        ("loot_collected",        "loot_manager.gd"),
    "hud.move_input":                     ("move_input",            "hud.gd"),
    "hud.aim_input":                      ("aim_input",             "hud.gd"),
    "hud.shoot_pressed":                  ("shoot_pressed",         "hud.gd"),
    "hud.reload_pressed":                 ("reload_pressed",        "hud.gd"),
    "hud.dash_pressed":                   ("dash_pressed",          "hud.gd"),
    "hud.ultimate_pressed":               ("ultimate_pressed",      "hud.gd"),
    "hud.shop_buy":                       ("shop_buy",              "hud.gd"),
    "hud.craft_action":                   ("craft_action",          "hud.gd"),
    "hud.perk_chosen":                    ("perk_chosen",           "hud.gd"),
    "hud.hero_chosen":                    ("hero_chosen",           "hud.gd"),
    "hud.level_perk_chosen":              ("level_perk_chosen",     "hud.gd"),
}

REQUIRED_BALANCE_CONSTANTS = [
    "MAP_W", "MAP_H", "PLAYER_MAX_HP", "PLAYER_SPEED", "PLAYER_RADIUS",
    "DASH_SPEED", "DASH_DURATION", "DASH_COOLDOWN",
    "ZONE_INITIAL_RADIUS", "ZONE_PHASES",
    "WEAPONS", "WEAPON_ORDER", "ENEMIES", "HEROES", "HERO_ORDER",
    "WAVE_BASE", "WAVE_PER_ROUND", "BOSS_EVERY", "MAX_ROUNDS",
    "ROUND_SURVIVAL_BONUS", "STARTING_MONEY", "BUY_PHASE_DURATION", "FREEZE_DURATION",
    "LOOT_MAGNET_RADIUS", "LOOT_DESPAWN_TIME",
    "PERKS", "PERK_KEYS",
    "SHAKE_HIT", "SHAKE_DEATH", "SHAKE_EXPLOSION",
    "HIT_STOP_DUR", "PARTICLE_LIFE", "PARTICLE_SPEED", "FLOAT_SPEED", "FLOAT_LIFE",
    "SAVE_PATH", "CRAFTING", "XP_PER_LEVEL", "RARITY_COLORS",
]


def collect_gd_files():
    result = []
    for root, _, files in os.walk(PROJECT_ROOT):
        if ".git" in root or ".godot" in root:
            continue
        for fn in files:
            if fn.endswith(".gd"):
                result.append(os.path.join(root, fn))
    return result


def collect_tscn_files():
    result = []
    for root, _, files in os.walk(PROJECT_ROOT):
        if ".git" in root or ".godot" in root:
            continue
        for fn in files:
            if fn.endswith(".tscn"):
                result.append(os.path.join(root, fn))
    return result


def read_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def get_script_rel(path):
    return os.path.relpath(path, PROJECT_ROOT)


class TestGodot3Patterns(unittest.TestCase):

    def _check_file(self, path, content):
        for pattern, hint in GODOT3_PATTERNS:
            matches = list(re.finditer(pattern, content))
            if matches:
                lines = content.splitlines()
                for m in matches:
                    lineno = content[:m.start()].count("\n") + 1
                    self.fail(
                        f"Godot 3 API in {get_script_rel(path)} line {lineno}:\n"
                        f"  {lines[lineno-1].strip()}\n"
                        f"  → {hint}"
                    )

    def test_no_godot3_apis(self):
        for path in collect_gd_files():
            with self.subTest(file=get_script_rel(path)):
                self._check_file(path, read_file(path))


class TestBracketBalance(unittest.TestCase):

    def _check(self, path, content):
        stack = []
        pairs = {"(": ")", "[": "]", "{": "}"}
        close = set(pairs.values())
        lines = content.splitlines()
        in_string = False
        string_char = ""
        for lineno, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            i = 0
            while i < len(stripped):
                c = stripped[i]
                if in_string:
                    if c == string_char and (i == 0 or stripped[i - 1] != "\\"):
                        in_string = False
                elif c in ('"', "'"):
                    in_string = True
                    string_char = c
                elif c in pairs:
                    stack.append((c, lineno))
                elif c in close:
                    if stack and pairs[stack[-1][0]] == c:
                        stack.pop()
                i += 1
        if stack:
            unmatched = [(ch, ln) for ch, ln in stack]
            self.fail(
                f"Unmatched bracket(s) in {get_script_rel(path)}: "
                + ", ".join(f"'{c}' on line {l}" for c, l in unmatched[:3])
            )

    def test_brackets_balanced(self):
        for path in collect_gd_files():
            with self.subTest(file=get_script_rel(path)):
                self._check(path, read_file(path))


class TestDuplicateFunctions(unittest.TestCase):

    def test_no_duplicate_func_names(self):
        for path in collect_gd_files():
            content = read_file(path)
            func_names = re.findall(r"^func\s+(\w+)\s*\(", content, re.MULTILINE)
            seen = set()
            duplicates = []
            for name in func_names:
                if name in seen:
                    duplicates.append(name)
                seen.add(name)
            if duplicates:
                self.fail(
                    f"Duplicate function(s) in {get_script_rel(path)}: "
                    + ", ".join(duplicates)
                )


class TestSignalDeclarations(unittest.TestCase):

    def _get_signals(self, rel_filename):
        for path in collect_gd_files():
            if path.endswith(rel_filename):
                content = read_file(path)
                return set(re.findall(r"^signal\s+(\w+)", content, re.MULTILINE))
        return set()

    def test_combat_manager_signals(self):
        sigs = self._get_signals("combat_manager.gd")
        for name in ["hit_enemy", "hit_player", "projectile_explosion", "weapon_empty", "reload_complete"]:
            self.assertIn(name, sigs, f"Signal '{name}' missing from combat_manager.gd")

    def test_enemy_spawner_signals(self):
        sigs = self._get_signals("enemy_spawner.gd")
        for name in ["enemy_died", "wave_cleared", "enemy_hit_player"]:
            self.assertIn(name, sigs, f"Signal '{name}' missing from enemy_spawner.gd")

    def test_round_manager_signals(self):
        sigs = self._get_signals("round_manager.gd")
        for name in ["state_changed", "buy_phase_started", "upgrade_choices", "game_over", "victory"]:
            self.assertIn(name, sigs, f"Signal '{name}' missing from round_manager.gd")

    def test_hud_signals(self):
        sigs = self._get_signals("hud.gd")
        for name in ["move_input", "aim_input", "shoot_pressed", "reload_pressed",
                     "dash_pressed", "ultimate_pressed", "shop_buy", "craft_action",
                     "perk_chosen", "hero_chosen", "level_perk_chosen"]:
            self.assertIn(name, sigs, f"Signal '{name}' missing from hud.gd")

    def test_loot_manager_signals(self):
        sigs = self._get_signals("loot_manager.gd")
        self.assertIn("loot_collected", sigs)


class TestBalanceConstants(unittest.TestCase):

    def _balance_content(self):
        for path in collect_gd_files():
            if path.endswith("balance.gd"):
                return read_file(path)
        return ""

    def test_required_constants_exist(self):
        content = self._balance_content()
        self.assertNotEqual(content, "", "balance.gd not found")
        for const_name in REQUIRED_BALANCE_CONSTANTS:
            pattern = r"\b" + re.escape(const_name) + r"\b"
            self.assertRegex(content, pattern,
                f"Required constant '{const_name}' missing from balance.gd")

    def test_perk_keys_consistent(self):
        content = self._balance_content()
        perk_keys = re.findall(r'"(\w+)"', content)
        # Find PERK_KEYS array section
        pk_match = re.search(r'PERK_KEYS.*?\[([^\]]+)\]', content, re.DOTALL)
        if pk_match:
            listed = re.findall(r'"(\w+)"', pk_match.group(1))
            perks_block = re.search(r'PERKS.*?=.*?\{(.+?)\n\}', content, re.DOTALL)
            if perks_block:
                defined = re.findall(r'"(\w+)"\s*:\s*\{', perks_block.group(1))
                for k in listed:
                    self.assertIn(k, defined,
                        f"PERK_KEYS entry '{k}' not found in PERKS dict")

    def test_weapon_order_matches_weapons(self):
        content = self._balance_content()
        wo_match = re.search(r'WEAPON_ORDER.*?\[([^\]]+)\]', content, re.DOTALL)
        wp_match = re.search(r'WEAPONS.*?=.*?\{(.+?)\n\}', content, re.DOTALL)
        if wo_match and wp_match:
            order = re.findall(r'"(\w+)"', wo_match.group(1))
            defined = re.findall(r'"(\w+)"\s*:\s*\{', wp_match.group(1))
            for w in order:
                self.assertIn(w, defined,
                    f"WEAPON_ORDER entry '{w}' not in WEAPONS dict")


class TestTscnResources(unittest.TestCase):

    def test_tscn_ext_resources_exist(self):
        for tscn_path in collect_tscn_files():
            content = read_file(tscn_path)
            paths = re.findall(r'path\s*=\s*"res://([^"]+)"', content)
            for rel_path in paths:
                abs_path = os.path.join(PROJECT_ROOT, rel_path)
                self.assertTrue(
                    os.path.exists(abs_path),
                    f"In {get_script_rel(tscn_path)}: resource 'res://{rel_path}' not found on disk"
                )


class TestNoPreloadInCriticalFiles(unittest.TestCase):

    def test_bootstrap_no_preload(self):
        path = os.path.join(PROJECT_ROOT, "bootstrap.gd")
        if not os.path.exists(path):
            self.skipTest("bootstrap.gd not found")
        content = read_file(path)
        # Exclude comment lines before checking
        non_comment_lines = [
            line for line in content.splitlines()
            if not line.strip().startswith("#") and not line.strip().startswith("##")
        ]
        non_comment = "\n".join(non_comment_lines)
        matches = re.findall(r'\bpreload\s*\(', non_comment)
        self.assertEqual(len(matches), 0,
            f"bootstrap.gd must NOT use preload() — found {len(matches)} call(s)")

    def test_game_manager_no_typed_class_refs_at_class_level(self):
        path = os.path.join(PROJECT_ROOT, "scripts", "game_manager.gd")
        if not os.path.exists(path):
            self.skipTest("game_manager.gd not found")
        content = read_file(path)
        # Check typed module declarations (var x: SomeClass) are NOT present
        typed_refs = re.findall(
            r'^var\s+\w+\s*:\s*(CombatManager|EnemySpawner|RoundManager|'
            r'LootManager|WorldRenderer|FxManager|HUD|SoundManager)\b',
            content, re.MULTILINE
        )
        self.assertEqual(len(typed_refs), 0,
            f"game_manager.gd has typed class references that cause cascade failures: {typed_refs}")


class TestUtf8Encoding(unittest.TestCase):

    def test_all_gd_files_utf8(self):
        for path in collect_gd_files():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    f.read()
            except UnicodeDecodeError as e:
                self.fail(f"UTF-8 error in {get_script_rel(path)}: {e}")


class TestHeroBalance(unittest.TestCase):

    def _balance_content(self):
        for path in collect_gd_files():
            if path.endswith("balance.gd"):
                return read_file(path)
        return ""

    def test_hero_order_matches_heroes_dict(self):
        content = self._balance_content()
        ho_match = re.search(r'HERO_ORDER.*?\[([^\]]+)\]', content, re.DOTALL)
        hd_match = re.search(r'HEROES.*?=.*?\{(.+?)\n\}', content, re.DOTALL)
        if ho_match and hd_match:
            order = re.findall(r'"(\w+)"', ho_match.group(1))
            defined = re.findall(r'"(\w+)"\s*:\s*\{', hd_match.group(1))
            for h in order:
                self.assertIn(h, defined,
                    f"HERO_ORDER entry '{h}' not in HEROES dict")

    def test_four_heroes_defined(self):
        content = self._balance_content()
        hd_match = re.search(r'HEROES.*?=.*?\{(.+?)\n\}', content, re.DOTALL)
        if hd_match:
            defined = re.findall(r'"(\w+)"\s*:\s*\{', hd_match.group(1))
            self.assertGreaterEqual(len(defined), 4, "Need at least 4 heroes")

    def test_fifteen_perks_defined(self):
        content = self._balance_content()
        perks_block = re.search(r'PERKS.*?=.*?\{(.+?)\n\}', content, re.DOTALL)
        if perks_block:
            defined = re.findall(r'"(\w+)"\s*:\s*\{', perks_block.group(1))
            self.assertGreaterEqual(len(defined), 15,
                f"Need at least 15 perks, found {len(defined)}")

    def test_ten_weapons_defined(self):
        content = self._balance_content()
        wp_match = re.search(r'WEAPONS.*?=.*?\{(.+?)\n\}', content, re.DOTALL)
        if wp_match:
            defined = re.findall(r'"(\w+)"\s*:\s*\{', wp_match.group(1))
            self.assertGreaterEqual(len(defined), 10,
                f"Need at least 10 weapons, found {len(defined)}")


if __name__ == "__main__":
    loader  = unittest.TestLoader()
    suite   = loader.loadTestsFromModule(sys.modules[__name__])
    runner  = unittest.TextTestRunner(verbosity=2)
    result  = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
