class_name Balance

# ── Map ─────────────────────────────────────────────────────────────────────
const MAP_W       := 3000.0
const MAP_H       := 3000.0
const GRID_STEP   := 150.0

# ── Player ───────────────────────────────────────────────────────────────────
const PLAYER_MAX_HP      := 100.0
const PLAYER_SPEED       := 500.0
const PLAYER_RADIUS      := 22.0
const DASH_SPEED         := 1400.0
const DASH_DURATION      := 0.18
const DASH_COOLDOWN      := 2.0
const DASH_INVINCIBLE    := true

# ── Zone ─────────────────────────────────────────────────────────────────────
const ZONE_INITIAL_RADIUS := 1200.0
const ZONE_PHASES: Array = [
	{"duration": 120.0, "damage": 2.0,  "ratio": 0.70},
	{"duration":  90.0, "damage": 5.0,  "ratio": 0.45},
	{"duration":  60.0, "damage": 10.0, "ratio": 0.25},
	{"duration":  30.0, "damage": 20.0, "ratio": 0.10},
	{"duration":  15.0, "damage": 40.0, "ratio": 0.00},
]

# ── Heroes ───────────────────────────────────────────────────────────────────
const HEROES: Dictionary = {
	"assault":   {
		"name": "Штурмовик",    "desc": "Сбалансированный боец",
		"hp_mult": 1.0, "speed_mult": 1.0, "start_weapon": "smg",
		"ult_name": "Стальной шторм", "ult_desc": "2 сек. бесконечного огня",
		"ult_cd": 30.0, "color_r": 0.3, "color_g": 0.6, "color_b": 1.0,
	},
	"engineer":  {
		"name": "Инженер",      "desc": "Строит турели и стены",
		"hp_mult": 0.85, "speed_mult": 0.9, "start_weapon": "pistol",
		"ult_name": "Авто-турель", "ult_desc": "Ставит турель на 10 сек",
		"ult_cd": 25.0, "color_r": 0.9, "color_g": 0.7, "color_b": 0.2,
	},
	"berserker": {
		"name": "Берсерк",      "desc": "Высокое HP, мощные удары",
		"hp_mult": 1.8, "speed_mult": 0.85, "start_weapon": "shotgun",
		"ult_name": "Ярость", "ult_desc": "Урон x3 на 4 сек",
		"ult_cd": 35.0, "color_r": 1.0, "color_g": 0.2, "color_b": 0.1,
	},
	"phantom":   {
		"name": "Фантом",       "desc": "Быстрый снайпер, 2 рывка",
		"hp_mult": 0.75, "speed_mult": 1.25, "start_weapon": "sniper",
		"ult_name": "Призрак", "ult_desc": "Невидимость + скорость на 3 сек",
		"ult_cd": 20.0, "color_r": 0.5, "color_g": 0.0, "color_b": 0.9,
	},
}
const HERO_ORDER: Array = ["assault", "engineer", "berserker", "phantom"]

# ── Weapons (10 types) ────────────────────────────────────────────────────────
const WEAPONS: Dictionary = {
	"pistol":    {
		"damage": 25.0, "fire_rate": 0.40, "ammo": 12, "max_ammo": 12,
		"reload_time": 1.2, "spread": 0.05, "speed": 900.0, "range": 700.0,
		"pellets": 1, "aoe": 0.0, "price": 0, "rarity": "common",
		"color_r": 0.9, "color_g": 0.9, "color_b": 0.3,
	},
	"shotgun":   {
		"damage": 18.0, "fire_rate": 0.80, "ammo": 6,  "max_ammo": 6,
		"reload_time": 1.5, "spread": 0.18, "speed": 750.0, "range": 350.0,
		"pellets": 7, "aoe": 0.0, "price": 600, "rarity": "common",
		"color_r": 1.0, "color_g": 0.6, "color_b": 0.1,
	},
	"smg":       {
		"damage": 12.0, "fire_rate": 0.10, "ammo": 30, "max_ammo": 30,
		"reload_time": 1.8, "spread": 0.08, "speed": 850.0, "range": 550.0,
		"pellets": 1, "aoe": 0.0, "price": 500, "rarity": "common",
		"color_r": 0.3, "color_g": 1.0, "color_b": 0.4,
	},
	"sniper":    {
		"damage": 85.0, "fire_rate": 1.50, "ammo": 5,  "max_ammo": 5,
		"reload_time": 2.5, "spread": 0.00, "speed": 1800.0, "range": 1200.0,
		"pellets": 1, "aoe": 0.0, "price": 1400, "rarity": "rare",
		"color_r": 0.3, "color_g": 0.7, "color_b": 1.0,
	},
	"plasma":    {
		"damage": 40.0, "fire_rate": 0.60, "ammo": 8,  "max_ammo": 8,
		"reload_time": 2.0, "spread": 0.02, "speed": 600.0, "range": 500.0,
		"pellets": 1, "aoe": 80.0, "price": 900, "rarity": "rare",
		"color_r": 0.8, "color_g": 0.2, "color_b": 1.0,
	},
	"rocket":    {
		"damage": 70.0, "fire_rate": 1.20, "ammo": 4,  "max_ammo": 4,
		"reload_time": 2.8, "spread": 0.01, "speed": 550.0, "range": 600.0,
		"pellets": 1, "aoe": 120.0, "price": 1200, "rarity": "epic",
		"color_r": 1.0, "color_g": 0.4, "color_b": 0.0,
	},
	"laser":     {
		"damage": 50.0, "fire_rate": 0.25, "ammo": 20, "max_ammo": 20,
		"reload_time": 1.6, "spread": 0.00, "speed": 3000.0, "range": 1000.0,
		"pellets": 1, "aoe": 0.0, "price": 1100, "rarity": "epic",
		"color_r": 0.0, "color_g": 1.0, "color_b": 0.8,
	},
	"minigun":   {
		"damage": 8.0,  "fire_rate": 0.05, "ammo": 60, "max_ammo": 60,
		"reload_time": 3.0, "spread": 0.15, "speed": 900.0, "range": 450.0,
		"pellets": 1, "aoe": 0.0, "price": 1800, "rarity": "epic",
		"color_r": 0.7, "color_g": 0.9, "color_b": 0.1,
	},
	"ricochet":  {
		"damage": 30.0, "fire_rate": 0.55, "ammo": 10, "max_ammo": 10,
		"reload_time": 1.4, "spread": 0.02, "speed": 1000.0, "range": 800.0,
		"pellets": 1, "aoe": 0.0, "price": 800, "rarity": "rare",
		"color_r": 0.4, "color_g": 0.8, "color_b": 1.0,
	},
	"flamethrower": {
		"damage": 6.0,  "fire_rate": 0.08, "ammo": 40, "max_ammo": 40,
		"reload_time": 2.2, "spread": 0.20, "speed": 400.0, "range": 280.0,
		"pellets": 3, "aoe": 0.0, "price": 950, "rarity": "rare",
		"color_r": 1.0, "color_g": 0.3, "color_b": 0.0,
	},
}
const WEAPON_ORDER: Array = [
	"pistol","shotgun","smg","sniper","plasma",
	"rocket","laser","minigun","ricochet","flamethrower"
]

const RARITY_COLORS: Dictionary = {
	"common":    Color(0.8, 0.8, 0.8),
	"rare":      Color(0.2, 0.5, 1.0),
	"epic":      Color(0.7, 0.2, 1.0),
	"legendary": Color(1.0, 0.6, 0.0),
}

# ── Enemies ───────────────────────────────────────────────────────────────────
const ENEMIES: Dictionary = {
	"rusher":  {"max_hp":   60.0, "speed": 320.0, "contact_dmg": 15.0, "shoot_dmg":  0.0, "shoot_range":   0.0, "agro": 600.0,  "radius": 18.0, "reward": 150,  "xp": 10,  "r": 1.0, "g": 0.5, "b": 0.1},
	"shooter": {"max_hp":   45.0, "speed": 150.0, "contact_dmg":  0.0, "shoot_dmg": 12.0, "shoot_range": 420.0, "agro": 500.0,  "radius": 16.0, "reward": 200,  "xp": 15,  "r": 0.7, "g": 0.2, "b": 1.0},
	"tank":    {"max_hp":  250.0, "speed":  80.0, "contact_dmg": 30.0, "shoot_dmg":  0.0, "shoot_range":   0.0, "agro": 400.0,  "radius": 30.0, "reward": 350,  "xp": 25,  "r": 0.5, "g": 0.5, "b": 0.5},
	"bomber":  {"max_hp":   50.0, "speed": 280.0, "contact_dmg": 60.0, "shoot_dmg":  0.0, "shoot_range":   0.0, "agro": 500.0,  "radius": 20.0, "reward": 200,  "xp": 20,  "r": 1.0, "g": 0.15,"b": 0.15},
	"boss":    {"max_hp": 1000.0, "speed": 120.0, "contact_dmg": 25.0, "shoot_dmg": 20.0, "shoot_range": 600.0, "agro": 2000.0, "radius": 50.0, "reward": 2000, "xp": 200, "r": 1.0, "g": 0.8, "b": 0.0},
	"elite":   {"max_hp":  200.0, "speed": 220.0, "contact_dmg": 20.0, "shoot_dmg": 18.0, "shoot_range": 350.0, "agro": 700.0,  "radius": 22.0, "reward": 500,  "xp": 50,  "r": 0.8, "g": 0.0, "b": 0.8},
}

# ── Wave formula ──────────────────────────────────────────────────────────────
const WAVE_BASE          := 3
const WAVE_PER_ROUND     := 2
const BOSS_EVERY         := 5
const MAX_ROUNDS         := 10
const HP_SCALE_PER_ROUND := 0.15

# ── Economy ───────────────────────────────────────────────────────────────────
const ROUND_SURVIVAL_BONUS := 500
const STARTING_MONEY       := 800
const BUY_PHASE_DURATION   := 15.0
const FREEZE_DURATION      := 3.0

# ── XP / Levels ───────────────────────────────────────────────────────────────
const XP_PER_LEVEL: Array = [
	100, 160, 240, 340, 460, 600, 760, 940, 1140, 1360,
	1600, 1860, 2140, 2440, 2760, 3100, 3460, 3840, 4240, 4660,
]

# ── Loot ──────────────────────────────────────────────────────────────────────
const LOOT_MONEY_CHANCE  := 1.0
const LOOT_HEALTH_CHANCE := 0.18
const LOOT_AMMO_CHANCE   := 0.35
const LOOT_WOOD_CHANCE   := 0.28
const LOOT_METAL_CHANCE  := 0.22
const LOOT_CHIP_CHANCE   := 0.12
const LOOT_MAGNET_RADIUS := 180.0
const LOOT_DESPAWN_TIME  := 15.0

# ── Crafting recipes ─────────────────────────────────────────────────────────
const CRAFTING: Dictionary = {
	"barricade":   {"wood": 5, "metal": 0, "chips": 0, "result": "barricade",  "desc": "Деревянное укрытие"},
	"metal_wall":  {"wood": 3, "metal": 4, "chips": 0, "result": "metal_wall", "desc": "Металлическая стена"},
	"medkit":      {"wood": 0, "metal": 0, "chips": 3, "result": "heal_50",    "desc": "Аптечка (+50 HP)"},
	"ammo_box":    {"wood": 2, "metal": 1, "chips": 0, "result": "full_ammo",  "desc": "Ящик патронов"},
	"grenade":     {"wood": 0, "metal": 2, "chips": 2, "result": "grenade",    "desc": "Граната (AOE 100)"},
	"turret":      {"wood": 5, "metal": 8, "chips": 3, "result": "turret",     "desc": "Авто-турель (engineer only)"},
}

# ── Perks (15 total) ──────────────────────────────────────────────────────────
const PERKS: Dictionary = {
	"tough":           {"name": "Живучий",       "desc": "+25 макс HP",                   "effect": "max_hp",        "value": 25.0},
	"scavenger":       {"name": "Мародёр",       "desc": "Лут с врагов x1.5",             "effect": "loot_mult",     "value": 1.5},
	"quick_hands":     {"name": "Быстрые руки",  "desc": "Перезарядка x2",                "effect": "reload_mult",   "value": 2.0},
	"zone_runner":     {"name": "Бегун",         "desc": "Урон зоны −40%",                "effect": "zone_resist",   "value": 0.4},
	"headhunter":      {"name": "Охотник",       "desc": "Убийство +$150",                "effect": "kill_bonus",    "value": 150.0},
	"arsenal":         {"name": "Арсенал",       "desc": "Обойма +60%",                   "effect": "ammo_mult",     "value": 1.6},
	"steel_nerves":    {"name": "Стальные нервы","desc": "Хит-стоп 0.05s",               "effect": "hit_stop",      "value": 0.05},
	"last_stand":      {"name": "Последний бой", "desc": "HP<20% → скорость+30%",         "effect": "last_stand",    "value": 1.3},
	"vampire":         {"name": "Вампир",        "desc": "Убийство восстанавливает 5 HP", "effect": "vampire",       "value": 5.0},
	"double_shot":     {"name": "Двойной выстрел","desc": "Выпускает 2 снаряда",          "effect": "double_shot",   "value": 1.0},
	"shield":          {"name": "Щит",           "desc": "Поглощает первые 50 урона",     "effect": "shield",        "value": 50.0},
	"explosive_rounds":{"name": "Взрывные пули", "desc": "Снаряды имеют AOE 30",          "effect": "explosive",     "value": 30.0},
	"speed_boost":     {"name": "Адреналин",     "desc": "Скорость +20%",                 "effect": "speed_mult",    "value": 1.2},
	"berserker_perk":  {"name": "Берсерк",       "desc": "Урон +50% при HP<50%",          "effect": "berserker",     "value": 1.5},
	"magnet":          {"name": "Магнит",        "desc": "Радиус подбора лута x3",        "effect": "magnet",        "value": 3.0},
}
const PERK_KEYS: Array = [
	"tough","scavenger","quick_hands","zone_runner","headhunter",
	"arsenal","steel_nerves","last_stand","vampire","double_shot",
	"shield","explosive_rounds","speed_boost","berserker_perk","magnet",
]

# ── FX ────────────────────────────────────────────────────────────────────────
const SHAKE_HIT        := Vector2(0.30, 0.15)
const SHAKE_DEATH      := Vector2(1.20, 0.50)
const SHAKE_EXPLOSION  := Vector2(0.80, 0.30)
const HIT_STOP_DUR     := 0.07
const PARTICLE_LIFE    := 0.55
const PARTICLE_SPEED   := 230.0
const FLOAT_SPEED      := 90.0
const FLOAT_LIFE       := 1.2

# ── Save ──────────────────────────────────────────────────────────────────────
const SAVE_PATH := "user://save_data.json"
