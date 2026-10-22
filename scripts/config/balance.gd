class_name Balance

# ── Map ────────────────────────────────────────────────────────────────────
const MAP_W       := 3000.0
const MAP_H       := 3000.0
const GRID_STEP   := 150.0

# ── Player ─────────────────────────────────────────────────────────────────
const PLAYER_MAX_HP      := 100.0
const PLAYER_SPEED       := 500.0
const PLAYER_RADIUS      := 22.0
const DASH_SPEED         := 1400.0
const DASH_DURATION      := 0.18
const DASH_COOLDOWN      := 2.0
const DASH_INVINCIBLE    := true

# ── Zone ───────────────────────────────────────────────────────────────────
const ZONE_INITIAL_RADIUS := 1200.0
const ZONE_PHASES: Array = [
	{"duration": 120.0, "damage": 2.0,  "ratio": 0.70},
	{"duration":  90.0, "damage": 5.0,  "ratio": 0.45},
	{"duration":  60.0, "damage": 10.0, "ratio": 0.25},
	{"duration":  30.0, "damage": 20.0, "ratio": 0.10},
	{"duration":  15.0, "damage": 40.0, "ratio": 0.00},
]

# ── Weapons ────────────────────────────────────────────────────────────────
const WEAPONS: Dictionary = {
	"pistol":  {"damage": 25.0, "fire_rate": 0.40, "ammo": 12, "max_ammo": 12, "reload_time": 1.2, "spread": 0.05, "speed": 900.0, "range": 700.0, "pellets": 1, "aoe": 0.0,  "price": 0,    "color_r": 0.9, "color_g": 0.9, "color_b": 0.3},
	"shotgun": {"damage": 18.0, "fire_rate": 0.80, "ammo":  6, "max_ammo":  6, "reload_time": 1.5, "spread": 0.18, "speed": 750.0, "range": 350.0, "pellets": 7, "aoe": 0.0,  "price": 600,  "color_r": 1.0, "color_g": 0.6, "color_b": 0.1},
	"smg":     {"damage": 12.0, "fire_rate": 0.10, "ammo": 30, "max_ammo": 30, "reload_time": 1.8, "spread": 0.08, "speed": 850.0, "range": 550.0, "pellets": 1, "aoe": 0.0,  "price": 500,  "color_r": 0.3, "color_g": 1.0, "color_b": 0.4},
	"sniper":  {"damage": 85.0, "fire_rate": 1.50, "ammo":  5, "max_ammo":  5, "reload_time": 2.5, "spread": 0.00, "speed":1800.0, "range":1200.0, "pellets": 1, "aoe": 0.0,  "price": 1400, "color_r": 0.3, "color_g": 0.7, "color_b": 1.0},
	"plasma":  {"damage": 40.0, "fire_rate": 0.60, "ammo":  8, "max_ammo":  8, "reload_time": 2.0, "spread": 0.02, "speed": 600.0, "range": 500.0, "pellets": 1, "aoe": 80.0, "price": 900,  "color_r": 0.8, "color_g": 0.2, "color_b": 1.0},
}
const WEAPON_ORDER: Array = ["pistol", "shotgun", "smg", "sniper", "plasma"]

# ── Enemies ────────────────────────────────────────────────────────────────
const ENEMIES: Dictionary = {
	"rusher":  {"max_hp":   60.0, "speed": 320.0, "contact_dmg": 15.0, "shoot_dmg":  0.0, "shoot_range":   0.0, "agro": 600.0, "radius": 18.0, "reward": 150, "xp": 10,  "r": 1.0, "g": 0.5, "b": 0.1},
	"shooter": {"max_hp":   45.0, "speed": 150.0, "contact_dmg":  0.0, "shoot_dmg": 12.0, "shoot_range": 420.0, "agro": 500.0, "radius": 16.0, "reward": 200, "xp": 15,  "r": 0.7, "g": 0.2, "b": 1.0},
	"tank":    {"max_hp":  250.0, "speed":  80.0, "contact_dmg": 30.0, "shoot_dmg":  0.0, "shoot_range":   0.0, "agro": 400.0, "radius": 30.0, "reward": 350, "xp": 25,  "r": 0.5, "g": 0.5, "b": 0.5},
	"bomber":  {"max_hp":   50.0, "speed": 280.0, "contact_dmg": 60.0, "shoot_dmg":  0.0, "shoot_range":   0.0, "agro": 500.0, "radius": 20.0, "reward": 200, "xp": 20,  "r": 1.0, "g": 0.15,"b": 0.15},
	"boss":    {"max_hp": 1000.0, "speed": 120.0, "contact_dmg": 25.0, "shoot_dmg": 20.0, "shoot_range": 600.0, "agro":2000.0, "radius": 50.0, "reward":2000, "xp": 200, "r": 1.0, "g": 0.8, "b": 0.0},
}

# ── Wave formula ───────────────────────────────────────────────────────────
const WAVE_BASE        := 3
const WAVE_PER_ROUND   := 2
const BOSS_EVERY       := 5
const MAX_ROUNDS       := 10
const HP_SCALE_PER_ROUND := 0.15

# ── Economy ────────────────────────────────────────────────────────────────
const ROUND_SURVIVAL_BONUS := 500
const STARTING_MONEY       := 800
const BUY_PHASE_DURATION   := 12.0
const FREEZE_DURATION      := 3.0

# ── Loot drop chances ──────────────────────────────────────────────────────
const LOOT_MONEY_CHANCE  := 1.0
const LOOT_HEALTH_CHANCE := 0.18
const LOOT_AMMO_CHANCE   := 0.35
const LOOT_WOOD_CHANCE   := 0.28
const LOOT_METAL_CHANCE  := 0.22
const LOOT_MAGNET_RADIUS := 180.0
const LOOT_DESPAWN_TIME  := 15.0

# ── Perks ──────────────────────────────────────────────────────────────────
const PERKS: Dictionary = {
	"tough":        {"name": "Живучий",     "desc": "+25 макс HP",         "effect": "max_hp",     "value": 25.0},
	"scavenger":    {"name": "Мародёр",     "desc": "Лут с врагов ×1.5",   "effect": "loot_mult",  "value": 1.5},
	"quick_hands":  {"name": "Быстрые руки","desc": "Перезарядка ×2",      "effect": "reload_mult","value": 2.0},
	"zone_runner":  {"name": "Бегун",       "desc": "Урон зоны −40%",      "effect": "zone_resist","value": 0.4},
	"headhunter":   {"name": "Охотник",     "desc": "Убийство +$150",      "effect": "kill_bonus", "value": 150.0},
	"arsenal":      {"name": "Арсенал",     "desc": "Обойма +60%",         "effect": "ammo_mult",  "value": 1.6},
	"steel_nerves": {"name": "Стальные нервы","desc":"Хит-стоп 0.05s",     "effect": "hit_stop",   "value": 0.05},
	"last_stand":   {"name": "Последний бой","desc": "HP<20% → скорость+30%","effect":"last_stand","value": 1.3},
}
const PERK_KEYS: Array = ["tough","scavenger","quick_hands","zone_runner","headhunter","arsenal","steel_nerves","last_stand"]

# ── FX ─────────────────────────────────────────────────────────────────────
const SHAKE_HIT        := Vector2(0.30, 0.15)
const SHAKE_DEATH      := Vector2(1.20, 0.50)
const SHAKE_EXPLOSION  := Vector2(0.80, 0.30)
const HIT_STOP_DUR     := 0.07
const PARTICLE_LIFE    := 0.55
const PARTICLE_SPEED   := 230.0
const FLOAT_SPEED      := 90.0
const FLOAT_LIFE       := 1.2
