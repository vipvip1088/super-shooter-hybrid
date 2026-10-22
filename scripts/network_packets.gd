# =============================================================================
# network_packets.gd
# SuperShooterHybrid — полный реестр сетевых пакетов
# Протокол: Godot 4 ENet (MultiplayerAPI, UDP)
# =============================================================================

class_name NetworkPackets
extends RefCounted

# ---------------------------------------------------------------------------
# PacketType enum
# ---------------------------------------------------------------------------
enum PacketType {
	# --- Движение (1xx) ---
	PLAYER_STATE          = 100,  # C→S + Broadcast  unreliable 20 Hz
	PLAYER_INPUT          = 101,  # C→S              unreliable 30 Hz
	PLAYER_TELEPORT       = 102,  # S→C              reliable   by event

	# --- Боевые события (2xx) ---
	SHOOT                 = 200,  # C→S              reliable   by event
	HIT_CONFIRM           = 201,  # S→C              reliable   by event
	DAMAGE                = 202,  # S→Broadcast      reliable   by event
	PLAYER_DEATH          = 203,  # S→Broadcast      reliable   by event
	PLAYER_RESPAWN        = 204,  # S→Broadcast      reliable   by event
	WEAPON_RELOAD         = 205,  # C→S + Broadcast  reliable   by event
	GRENADE_THROW         = 206,  # C→S + Broadcast  reliable   by event
	PROJECTILE_SPAWN      = 207,  # S→Broadcast      unreliable by event

	# --- Зона (3xx) ---
	ZONE_STATE            = 300,  # S→Broadcast      reliable   0.2 Hz
	ZONE_DAMAGE_TICK      = 301,  # S→Broadcast      unreliable 1 Hz
	ZONE_PHASE_CHANGE     = 302,  # S→Broadcast      reliable   by event

	# --- Магазин / Экономика (4xx) ---
	SHOP_OPEN             = 400,  # C→S              reliable   by event
	SHOP_CATALOG          = 401,  # S→C              reliable   by event
	SHOP_BUY_REQUEST      = 402,  # C→S              reliable   by event
	SHOP_BUY_RESULT       = 403,  # S→C              reliable   by event
	ECONOMY_UPDATE        = 404,  # S→C              reliable   by event
	DROP_ITEM             = 405,  # C→S              reliable   by event
	ITEM_PICKUP           = 406,  # C→S + Broadcast  reliable   by event

	# --- Крафт (5xx) ---
	CRAFT_REQUEST         = 500,  # C→S              reliable   by event
	CRAFT_RESULT          = 501,  # S→C              reliable   by event
	BARRICADE_SPAWN       = 502,  # S→Broadcast      reliable   by event
	BARRICADE_DAMAGE      = 503,  # S→Broadcast      reliable   by event
	BARRICADE_DESTROY     = 504,  # S→Broadcast      reliable   by event

	# --- Системные (6xx) ---
	HANDSHAKE_REQUEST     = 600,  # C→S              reliable   once
	HANDSHAKE_RESPONSE    = 601,  # S→C              reliable   once
	PING                  = 602,  # C→S              unreliable 1 Hz
	PONG                  = 603,  # S→C              unreliable 1 Hz
	TIME_SYNC_REQUEST     = 604,  # C→S              reliable   by event
	TIME_SYNC_RESPONSE    = 605,  # S→C              reliable   by event
	KICK                  = 606,  # S→C              reliable   by event
	SERVER_INFO           = 607,  # S→Broadcast      reliable   by event
	PLAYER_CONNECTED      = 608,  # S→Broadcast      reliable   by event
	PLAYER_DISCONNECTED   = 609,  # S→Broadcast      reliable   by event
	ERROR_RESPONSE        = 610,  # S→C              reliable   by event

	# --- Раунд (7xx) ---
	ROUND_START           = 700,  # S→Broadcast      reliable   by event
	ROUND_END             = 701,  # S→Broadcast      reliable   by event
	ROUND_WINNER          = 702,  # S→Broadcast      reliable   by event
	ROUND_STATE_SYNC      = 703,  # S→C              reliable   on connect
	SCOREBOARD_UPDATE     = 704,  # S→Broadcast      reliable   by event
	FREEZE_PHASE_START    = 705,  # S→Broadcast      reliable   by event
	FREEZE_PHASE_END      = 706,  # S→Broadcast      reliable   by event
}

# ---------------------------------------------------------------------------
# Константы приоритетов / каналов ENet
# ---------------------------------------------------------------------------
const CHANNEL_RELIABLE   := 0  # ENet reliable ordered
const CHANNEL_UNRELIABLE := 1  # ENet unreliable unordered
const CHANNEL_STATE      := 2  # ENet unreliable sequenced (движение)

# Максимальные размеры пакетов (байт) — для валидации на входе
const MAX_SIZE := {
	PacketType.PLAYER_STATE:       64,
	PacketType.PLAYER_INPUT:       32,
	PacketType.PLAYER_TELEPORT:    40,
	PacketType.SHOOT:              48,
	PacketType.HIT_CONFIRM:        40,
	PacketType.DAMAGE:             32,
	PacketType.PLAYER_DEATH:       48,
	PacketType.PLAYER_RESPAWN:     32,
	PacketType.WEAPON_RELOAD:      16,
	PacketType.GRENADE_THROW:      40,
	PacketType.PROJECTILE_SPAWN:   48,
	PacketType.ZONE_STATE:         48,
	PacketType.ZONE_DAMAGE_TICK:   24,
	PacketType.ZONE_PHASE_CHANGE:  32,
	PacketType.SHOP_OPEN:          16,
	PacketType.SHOP_CATALOG:       512,
	PacketType.SHOP_BUY_REQUEST:   24,
	PacketType.SHOP_BUY_RESULT:    48,
	PacketType.ECONOMY_UPDATE:     32,
	PacketType.DROP_ITEM:          32,
	PacketType.ITEM_PICKUP:        32,
	PacketType.CRAFT_REQUEST:      32,
	PacketType.CRAFT_RESULT:       64,
	PacketType.BARRICADE_SPAWN:    64,
	PacketType.BARRICADE_DAMAGE:   32,
	PacketType.BARRICADE_DESTROY:  24,
	PacketType.HANDSHAKE_REQUEST:  128,
	PacketType.HANDSHAKE_RESPONSE: 64,
	PacketType.PING:               16,
	PacketType.PONG:               16,
	PacketType.TIME_SYNC_REQUEST:  16,
	PacketType.TIME_SYNC_RESPONSE: 24,
	PacketType.KICK:               128,
	PacketType.SERVER_INFO:        256,
	PacketType.PLAYER_CONNECTED:   64,
	PacketType.PLAYER_DISCONNECTED:24,
	PacketType.ERROR_RESPONSE:     128,
	PacketType.ROUND_START:        64,
	PacketType.ROUND_END:          64,
	PacketType.ROUND_WINNER:       64,
	PacketType.ROUND_STATE_SYNC:   256,
	PacketType.SCOREBOARD_UPDATE:  512,
	PacketType.FREEZE_PHASE_START: 24,
	PacketType.FREEZE_PHASE_END:   16,
}

# ---------------------------------------------------------------------------
# Анимационные состояния игрока (используется в PLAYER_STATE)
# ---------------------------------------------------------------------------
enum AnimState {
	IDLE       = 0,
	RUN        = 1,
	CROUCH     = 2,
	PRONE      = 3,
	JUMP       = 4,
	FALL       = 5,
	SHOOT      = 6,
	RELOAD     = 7,
	MELEE      = 8,
	DEAD       = 9,
}

# ---------------------------------------------------------------------------
# Фазы зоны
# ---------------------------------------------------------------------------
enum ZonePhase {
	WAITING    = 0,  # ожидание начала
	SHRINKING  = 1,  # зона сжимается
	STATIC     = 2,  # пауза между сжатиями
	FINAL      = 3,  # финальная зона
}

# ---------------------------------------------------------------------------
# Коды результата покупки
# ---------------------------------------------------------------------------
enum BuyResult {
	SUCCESS          = 0,
	NOT_ENOUGH_MONEY = 1,
	ITEM_NOT_FOUND   = 2,
	INVENTORY_FULL   = 3,
	ROUND_PHASE_ERR  = 4,
}

# ---------------------------------------------------------------------------
# Коды результата крафта
# ---------------------------------------------------------------------------
enum CraftResult {
	SUCCESS          = 0,
	NOT_ENOUGH_MATS  = 1,
	RECIPE_UNKNOWN   = 2,
	INVENTORY_FULL   = 3,
	PLACEMENT_FAILED = 4,
}

# ---------------------------------------------------------------------------
# Причины кика
# ---------------------------------------------------------------------------
enum KickReason {
	SERVER_SHUTDOWN  = 0,
	CHEAT_DETECTED   = 1,
	TIMEOUT          = 2,
	ROOM_FULL        = 3,
	VERSION_MISMATCH = 4,
	BANNED           = 5,
}

# =============================================================================
# ДВИЖЕНИЕ (1xx)
# =============================================================================

## PLAYER_STATE — снапшот состояния игрока
## Направление: C→S затем S→Broadcast | unreliable | 20 Hz
static func make_player_state(
		peer_id: int,          # int32   — id отправителя
		position: Vector3,     # float32 x3
		rotation: Vector2,     # float32 x2 (yaw, pitch)
		velocity: Vector3,     # float32 x3
		anim_state: int,       # uint8   — AnimState
		weapon_slot: int,      # uint8   — текущий слот оружия
		health: float,         # float32
		timestamp: float       # float64 — server time
) -> Dictionary:
	return {
		"type":       PacketType.PLAYER_STATE,
		"peer_id":    peer_id,
		"position":   position,
		"rotation":   rotation,
		"velocity":   velocity,
		"anim_state": anim_state,
		"weapon_slot":weapon_slot,
		"health":     health,
		"timestamp":  timestamp,
	}

static func parse_player_state(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PLAYER_STATE)
	return data

## PLAYER_INPUT — raw ввод клиента (для server-side reconciliation)
## Направление: C→S | unreliable | 30 Hz
static func make_player_input(
		sequence: int,         # uint32  — порядковый номер ввода
		move_dir: Vector2,     # float32 x2
		jump: bool,
		crouch: bool,
		prone: bool,
		shoot: bool,
		aim: bool,
		timestamp: float       # float64
) -> Dictionary:
	return {
		"type":      PacketType.PLAYER_INPUT,
		"sequence":  sequence,
		"move_dir":  move_dir,
		"jump":      jump,
		"crouch":    crouch,
		"prone":     prone,
		"shoot":     shoot,
		"aim":       aim,
		"timestamp": timestamp,
	}

static func parse_player_input(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PLAYER_INPUT)
	return data

## PLAYER_TELEPORT — принудительная коррекция позиции сервером
## Направление: S→C | reliable | by event
static func make_player_teleport(
		peer_id: int,
		position: Vector3,
		rotation: Vector2,
		reason: String        # "respawn" | "zone_push" | "correction"
) -> Dictionary:
	return {
		"type":     PacketType.PLAYER_TELEPORT,
		"peer_id":  peer_id,
		"position": position,
		"rotation": rotation,
		"reason":   reason,
	}

static func parse_player_teleport(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PLAYER_TELEPORT)
	return data

# =============================================================================
# БОЕВЫЕ СОБЫТИЯ (2xx)
# =============================================================================

## SHOOT — клиент сообщает о выстреле
## Направление: C→S | reliable | by event
static func make_shoot(
		weapon_id: int,        # uint16
		origin: Vector3,       # float32 x3
		direction: Vector3,    # float32 x3 (normalized)
		spread_seed: int,      # uint32  — seed для детерминированного разброса
		timestamp: float       # float64
) -> Dictionary:
	return {
		"type":        PacketType.SHOOT,
		"weapon_id":   weapon_id,
		"origin":      origin,
		"direction":   direction,
		"spread_seed": spread_seed,
		"timestamp":   timestamp,
	}

static func parse_shoot(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.SHOOT)
	return data

## HIT_CONFIRM — сервер подтверждает попадание стрелку
## Направление: S→C | reliable | by event
static func make_hit_confirm(
		target_peer_id: int,   # int32
		damage_dealt: float,   # float32
		hit_zone: String,      # "head"|"body"|"limb"
		weapon_id: int,        # uint16
		killed: bool
) -> Dictionary:
	return {
		"type":           PacketType.HIT_CONFIRM,
		"target_peer_id": target_peer_id,
		"damage_dealt":   damage_dealt,
		"hit_zone":       hit_zone,
		"weapon_id":      weapon_id,
		"killed":         killed,
	}

static func parse_hit_confirm(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.HIT_CONFIRM)
	return data

## DAMAGE — широковещательное уведомление об уроне
## Направление: S→Broadcast | reliable | by event
static func make_damage(
		victim_peer_id: int,   # int32
		attacker_peer_id: int, # int32  (-1 = zone/world)
		amount: float,         # float32
		new_health: float,     # float32
		hit_zone: String,      # "head"|"body"|"limb"|"zone"
		weapon_id: int         # uint16 (0 = no weapon)
) -> Dictionary:
	return {
		"type":              PacketType.DAMAGE,
		"victim_peer_id":    victim_peer_id,
		"attacker_peer_id":  attacker_peer_id,
		"amount":            amount,
		"new_health":        new_health,
		"hit_zone":          hit_zone,
		"weapon_id":         weapon_id,
	}

static func parse_damage(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.DAMAGE)
	return data

## PLAYER_DEATH — игрок убит
## Направление: S→Broadcast | reliable | by event
static func make_player_death(
		victim_peer_id: int,
		killer_peer_id: int,   # -1 = zone
		weapon_id: int,
		death_position: Vector3,
		killer_name: String,
		victim_name: String
) -> Dictionary:
	return {
		"type":            PacketType.PLAYER_DEATH,
		"victim_peer_id":  victim_peer_id,
		"killer_peer_id":  killer_peer_id,
		"weapon_id":       weapon_id,
		"death_position":  death_position,
		"killer_name":     killer_name,
		"victim_name":     victim_name,
	}

static func parse_player_death(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PLAYER_DEATH)
	return data

## PLAYER_RESPAWN — возрождение (если режим позволяет)
## Направление: S→Broadcast | reliable | by event
static func make_player_respawn(
		peer_id: int,
		spawn_position: Vector3,
		health: float
) -> Dictionary:
	return {
		"type":           PacketType.PLAYER_RESPAWN,
		"peer_id":        peer_id,
		"spawn_position": spawn_position,
		"health":         health,
	}

static func parse_player_respawn(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PLAYER_RESPAWN)
	return data

## WEAPON_RELOAD — начало перезарядки
## Направление: C→S + S→Broadcast | reliable | by event
static func make_weapon_reload(
		peer_id: int,
		weapon_id: int,
		duration_sec: float    # float32 — анимационное время
) -> Dictionary:
	return {
		"type":         PacketType.WEAPON_RELOAD,
		"peer_id":      peer_id,
		"weapon_id":    weapon_id,
		"duration_sec": duration_sec,
	}

static func parse_weapon_reload(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.WEAPON_RELOAD)
	return data

## GRENADE_THROW — бросок гранаты
## Направление: C→S + S→Broadcast | reliable | by event
static func make_grenade_throw(
		peer_id: int,
		grenade_type: String,  # "frag"|"smoke"|"flash"
		origin: Vector3,
		velocity: Vector3,
		spawn_id: int          # uint32 — уникальный id снаряда
) -> Dictionary:
	return {
		"type":         PacketType.GRENADE_THROW,
		"peer_id":      peer_id,
		"grenade_type": grenade_type,
		"origin":       origin,
		"velocity":     velocity,
		"spawn_id":     spawn_id,
	}

static func parse_grenade_throw(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.GRENADE_THROW)
	return data

## PROJECTILE_SPAWN — спавн снаряда (пуля, граната) на клиентах
## Направление: S→Broadcast | unreliable | by event
static func make_projectile_spawn(
		spawn_id: int,
		owner_peer_id: int,
		proj_type: String,     # "bullet"|"grenade"|"rocket"
		origin: Vector3,
		velocity: Vector3,
		timestamp: float
) -> Dictionary:
	return {
		"type":          PacketType.PROJECTILE_SPAWN,
		"spawn_id":      spawn_id,
		"owner_peer_id": owner_peer_id,
		"proj_type":     proj_type,
		"origin":        origin,
		"velocity":      velocity,
		"timestamp":     timestamp,
	}

static func parse_projectile_spawn(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PROJECTILE_SPAWN)
	return data

# =============================================================================
# ЗОНА (3xx)
# =============================================================================

## ZONE_STATE — полное состояние зоны
## Направление: S→Broadcast | reliable | 0.2 Hz (каждые 5 сек)
static func make_zone_state(
		phase: int,            # ZonePhase
		current_center: Vector2,   # float32 x2 (XZ)
		current_radius: float,     # float32
		target_center: Vector2,    # float32 x2
		target_radius: float,      # float32
		shrink_duration: float,    # float32 — секунды до конца фазы
		phase_timer: float,        # float32 — сколько осталось до следующей фазы
		damage_per_sec: float      # float32
) -> Dictionary:
	return {
		"type":             PacketType.ZONE_STATE,
		"phase":            phase,
		"current_center":   current_center,
		"current_radius":   current_radius,
		"target_center":    target_center,
		"target_radius":    target_radius,
		"shrink_duration":  shrink_duration,
		"phase_timer":      phase_timer,
		"damage_per_sec":   damage_per_sec,
	}

static func parse_zone_state(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ZONE_STATE)
	return data

## ZONE_DAMAGE_TICK — периодический урон от зоны
## Направление: S→Broadcast | unreliable | 1 Hz
static func make_zone_damage_tick(
		affected_peers: Array,  # Array[int] — peer_id вне зоны
		damage_amount: float,
		server_time: float
) -> Dictionary:
	return {
		"type":            PacketType.ZONE_DAMAGE_TICK,
		"affected_peers":  affected_peers,
		"damage_amount":   damage_amount,
		"server_time":     server_time,
	}

static func parse_zone_damage_tick(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ZONE_DAMAGE_TICK)
	return data

## ZONE_PHASE_CHANGE — переход на следующую фазу
## Направление: S→Broadcast | reliable | by event
static func make_zone_phase_change(
		new_phase: int,         # ZonePhase
		new_center: Vector2,
		new_radius: float,
		transition_time: float, # float32 — сколько секунд на сжатие
		phase_number: int       # uint8
) -> Dictionary:
	return {
		"type":            PacketType.ZONE_PHASE_CHANGE,
		"new_phase":       new_phase,
		"new_center":      new_center,
		"new_radius":      new_radius,
		"transition_time": transition_time,
		"phase_number":    phase_number,
	}

static func parse_zone_phase_change(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ZONE_PHASE_CHANGE)
	return data

# =============================================================================
# МАГАЗИН / ЭКОНОМИКА (4xx)
# =============================================================================

## SHOP_OPEN — клиент запрашивает открытие магазина
## Направление: C→S | reliable | by event
static func make_shop_open(peer_id: int) -> Dictionary:
	return {
		"type":    PacketType.SHOP_OPEN,
		"peer_id": peer_id,
	}

static func parse_shop_open(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.SHOP_OPEN)
	return data

## SHOP_CATALOG — сервер отправляет каталог доступных товаров
## Направление: S→C | reliable | by event
## items: Array[{id:int, name:String, cost:int, category:String, available:bool}]
static func make_shop_catalog(
		peer_id: int,
		items: Array,
		player_money: int
) -> Dictionary:
	return {
		"type":         PacketType.SHOP_CATALOG,
		"peer_id":      peer_id,
		"items":        items,
		"player_money": player_money,
	}

static func parse_shop_catalog(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.SHOP_CATALOG)
	return data

## SHOP_BUY_REQUEST — запрос покупки товара
## Направление: C→S | reliable | by event
static func make_shop_buy_request(
		peer_id: int,
		item_id: int,          # uint16
		quantity: int          # uint8
) -> Dictionary:
	return {
		"type":     PacketType.SHOP_BUY_REQUEST,
		"peer_id":  peer_id,
		"item_id":  item_id,
		"quantity": quantity,
	}

static func parse_shop_buy_request(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.SHOP_BUY_REQUEST)
	return data

## SHOP_BUY_RESULT — результат покупки
## Направление: S→C | reliable | by event
static func make_shop_buy_result(
		peer_id: int,
		item_id: int,
		quantity: int,
		result_code: int,      # BuyResult
		new_balance: int,      # int32 — баланс после покупки
		message: String        # "" если success
) -> Dictionary:
	return {
		"type":        PacketType.SHOP_BUY_RESULT,
		"peer_id":     peer_id,
		"item_id":     item_id,
		"quantity":    quantity,
		"result_code": result_code,
		"new_balance": new_balance,
		"message":     message,
	}

static func parse_shop_buy_result(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.SHOP_BUY_RESULT)
	return data

## ECONOMY_UPDATE — обновление баланса/инвентаря
## Направление: S→C | reliable | by event
static func make_economy_update(
		peer_id: int,
		new_balance: int,
		delta: int,            # int32 — изменение (+ или -)
		reason: String         # "kill_reward"|"round_bonus"|"purchase"
) -> Dictionary:
	return {
		"type":        PacketType.ECONOMY_UPDATE,
		"peer_id":     peer_id,
		"new_balance": new_balance,
		"delta":       delta,
		"reason":      reason,
	}

static func parse_economy_update(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ECONOMY_UPDATE)
	return data

## DROP_ITEM — игрок выбрасывает предмет
## Направление: C→S | reliable | by event
static func make_drop_item(
		peer_id: int,
		item_id: int,
		quantity: int,
		drop_position: Vector3
) -> Dictionary:
	return {
		"type":          PacketType.DROP_ITEM,
		"peer_id":       peer_id,
		"item_id":       item_id,
		"quantity":      quantity,
		"drop_position": drop_position,
	}

static func parse_drop_item(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.DROP_ITEM)
	return data

## ITEM_PICKUP — подбор предмета с земли
## Направление: C→S + S→Broadcast | reliable | by event
static func make_item_pickup(
		peer_id: int,
		world_item_id: int,    # uint32 — id предмета в мире
		item_id: int,
		quantity: int,
		success: bool
) -> Dictionary:
	return {
		"type":          PacketType.ITEM_PICKUP,
		"peer_id":       peer_id,
		"world_item_id": world_item_id,
		"item_id":       item_id,
		"quantity":      quantity,
		"success":       success,
	}

static func parse_item_pickup(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ITEM_PICKUP)
	return data

# =============================================================================
# КРАФТ (5xx)
# =============================================================================

## CRAFT_REQUEST — клиент запрашивает крафт
## Направление: C→S | reliable | by event
static func make_craft_request(
		peer_id: int,
		recipe_id: int,        # uint16
		quantity: int,         # uint8
		placement_pos: Vector3 # float32 x3 — для баррикад
) -> Dictionary:
	return {
		"type":          PacketType.CRAFT_REQUEST,
		"peer_id":       peer_id,
		"recipe_id":     recipe_id,
		"quantity":      quantity,
		"placement_pos": placement_pos,
	}

static func parse_craft_request(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.CRAFT_REQUEST)
	return data

## CRAFT_RESULT — результат крафта
## Направление: S→C | reliable | by event
static func make_craft_result(
		peer_id: int,
		recipe_id: int,
		result_code: int,      # CraftResult
		produced_item_id: int, # uint16 (0 если неудача)
		quantity: int,
		consumed_materials: Dictionary,  # {item_id: quantity}
		message: String
) -> Dictionary:
	return {
		"type":               PacketType.CRAFT_RESULT,
		"peer_id":            peer_id,
		"recipe_id":          recipe_id,
		"result_code":        result_code,
		"produced_item_id":   produced_item_id,
		"quantity":           quantity,
		"consumed_materials": consumed_materials,
		"message":            message,
	}

static func parse_craft_result(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.CRAFT_RESULT)
	return data

## BARRICADE_SPAWN — спавн баррикады в мире
## Направление: S→Broadcast | reliable | by event
static func make_barricade_spawn(
		barricade_id: int,     # uint32 — уникальный id объекта
		owner_peer_id: int,
		barricade_type: String,# "wood_wall"|"metal_wall"|"sandbag"
		position: Vector3,
		rotation: Vector3,     # Euler angles
		max_health: float,
		current_health: float
) -> Dictionary:
	return {
		"type":            PacketType.BARRICADE_SPAWN,
		"barricade_id":    barricade_id,
		"owner_peer_id":   owner_peer_id,
		"barricade_type":  barricade_type,
		"position":        position,
		"rotation":        rotation,
		"max_health":      max_health,
		"current_health":  current_health,
	}

static func parse_barricade_spawn(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.BARRICADE_SPAWN)
	return data

## BARRICADE_DAMAGE — урон баррикаде
## Направление: S→Broadcast | reliable | by event
static func make_barricade_damage(
		barricade_id: int,
		attacker_peer_id: int,
		damage: float,
		new_health: float
) -> Dictionary:
	return {
		"type":              PacketType.BARRICADE_DAMAGE,
		"barricade_id":      barricade_id,
		"attacker_peer_id":  attacker_peer_id,
		"damage":            damage,
		"new_health":        new_health,
	}

static func parse_barricade_damage(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.BARRICADE_DAMAGE)
	return data

## BARRICADE_DESTROY — уничтожение баррикады
## Направление: S→Broadcast | reliable | by event
static func make_barricade_destroy(
		barricade_id: int,
		destroyer_peer_id: int # -1 = zone/explosion
) -> Dictionary:
	return {
		"type":               PacketType.BARRICADE_DESTROY,
		"barricade_id":       barricade_id,
		"destroyer_peer_id":  destroyer_peer_id,
	}

static func parse_barricade_destroy(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.BARRICADE_DESTROY)
	return data

# =============================================================================
# СИСТЕМНЫЕ (6xx)
# =============================================================================

## HANDSHAKE_REQUEST — клиент подключается
## Направление: C→S | reliable | once
static func make_handshake_request(
		client_version: String,# "1.0.0"
		player_name: String,
		auth_token: String,    # JWT или session token
		platform: String       # "android"|"ios"|"pc"
) -> Dictionary:
	return {
		"type":           PacketType.HANDSHAKE_REQUEST,
		"client_version": client_version,
		"player_name":    player_name,
		"auth_token":     auth_token,
		"platform":       platform,
	}

static func parse_handshake_request(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.HANDSHAKE_REQUEST)
	return data

## HANDSHAKE_RESPONSE — ответ сервера на подключение
## Направление: S→C | reliable | once
static func make_handshake_response(
		accepted: bool,
		assigned_peer_id: int,
		server_version: String,
		server_time: float,    # float64 — текущее серверное время
		reject_reason: String  # "" если accepted
) -> Dictionary:
	return {
		"type":             PacketType.HANDSHAKE_RESPONSE,
		"accepted":         accepted,
		"assigned_peer_id": assigned_peer_id,
		"server_version":   server_version,
		"server_time":      server_time,
		"reject_reason":    reject_reason,
	}

static func parse_handshake_response(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.HANDSHAKE_RESPONSE)
	return data

## PING — измерение задержки
## Направление: C→S | unreliable | 1 Hz
static func make_ping(
		sequence: int,         # uint16
		client_time: float     # float64
) -> Dictionary:
	return {
		"type":        PacketType.PING,
		"sequence":    sequence,
		"client_time": client_time,
	}

static func parse_ping(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PING)
	return data

## PONG — ответ на ping
## Направление: S→C | unreliable | 1 Hz
static func make_pong(
		sequence: int,
		client_time: float,    # float64 — эхо из PING
		server_time: float     # float64
) -> Dictionary:
	return {
		"type":        PacketType.PONG,
		"sequence":    sequence,
		"client_time": client_time,
		"server_time": server_time,
	}

static func parse_pong(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PONG)
	return data

## TIME_SYNC_REQUEST — запрос синхронизации времени
## Направление: C→S | reliable | by event (при подключении и каждые 30 сек)
static func make_time_sync_request(
		client_time: float,    # float64
		request_id: int        # uint16
) -> Dictionary:
	return {
		"type":        PacketType.TIME_SYNC_REQUEST,
		"client_time": client_time,
		"request_id":  request_id,
	}

static func parse_time_sync_request(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.TIME_SYNC_REQUEST)
	return data

## TIME_SYNC_RESPONSE — ответ синхронизации
## Направление: S→C | reliable | by event
static func make_time_sync_response(
		request_id: int,
		client_time_echo: float,# float64 — эхо из запроса
		server_time: float,     # float64
		server_tick: int        # uint64 — игровой тик
) -> Dictionary:
	return {
		"type":              PacketType.TIME_SYNC_RESPONSE,
		"request_id":        request_id,
		"client_time_echo":  client_time_echo,
		"server_time":       server_time,
		"server_tick":       server_tick,
	}

static func parse_time_sync_response(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.TIME_SYNC_RESPONSE)
	return data

## KICK — принудительное отключение игрока
## Направление: S→C | reliable | by event
static func make_kick(
		peer_id: int,
		reason_code: int,      # KickReason
		message: String,       # читаемое сообщение
		ban_duration_sec: int  # 0 = не бан, >0 = длительность бана
) -> Dictionary:
	return {
		"type":             PacketType.KICK,
		"peer_id":          peer_id,
		"reason_code":      reason_code,
		"message":          message,
		"ban_duration_sec": ban_duration_sec,
	}

static func parse_kick(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.KICK)
	return data

## SERVER_INFO — общая информация о сервере/комнате
## Направление: S→Broadcast | reliable | by event
static func make_server_info(
		room_id: String,
		map_name: String,
		max_players: int,
		current_players: int,
		game_mode: String,     # "battle_royale"|"deathmatch"|"survival"
		tick_rate: int         # uint8 — Hz
) -> Dictionary:
	return {
		"type":            PacketType.SERVER_INFO,
		"room_id":         room_id,
		"map_name":        map_name,
		"max_players":     max_players,
		"current_players": current_players,
		"game_mode":       game_mode,
		"tick_rate":       tick_rate,
	}

static func parse_server_info(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.SERVER_INFO)
	return data

## PLAYER_CONNECTED — новый игрок вошёл
## Направление: S→Broadcast | reliable | by event
static func make_player_connected(
		peer_id: int,
		player_name: String,
		platform: String,
		team_id: int           # int8 (-1 = solo)
) -> Dictionary:
	return {
		"type":        PacketType.PLAYER_CONNECTED,
		"peer_id":     peer_id,
		"player_name": player_name,
		"platform":    platform,
		"team_id":     team_id,
	}

static func parse_player_connected(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PLAYER_CONNECTED)
	return data

## PLAYER_DISCONNECTED — игрок покинул сервер
## Направление: S→Broadcast | reliable | by event
static func make_player_disconnected(
		peer_id: int,
		reason: String         # "left"|"timeout"|"kicked"
) -> Dictionary:
	return {
		"type":    PacketType.PLAYER_DISCONNECTED,
		"peer_id": peer_id,
		"reason":  reason,
	}

static func parse_player_disconnected(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.PLAYER_DISCONNECTED)
	return data

## ERROR_RESPONSE — общий ответ об ошибке
## Направление: S→C | reliable | by event
static func make_error_response(
		peer_id: int,
		error_code: int,       # uint16
		related_packet_type: int, # PacketType который вызвал ошибку
		message: String
) -> Dictionary:
	return {
		"type":                 PacketType.ERROR_RESPONSE,
		"peer_id":              peer_id,
		"error_code":           error_code,
		"related_packet_type":  related_packet_type,
		"message":              message,
	}

static func parse_error_response(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ERROR_RESPONSE)
	return data

# =============================================================================
# РАУНД (7xx)
# =============================================================================

## ROUND_START — начало раунда
## Направление: S→Broadcast | reliable | by event
static func make_round_start(
		round_number: int,     # uint16
		round_duration_sec: float, # float32 — максимальная длительность
		buy_phase_duration: float, # float32 — длительность фазы покупки
		spawn_points: Dictionary,  # {peer_id: Vector3}
		starting_money: int    # int32 — деньги у всех на старте
) -> Dictionary:
	return {
		"type":                 PacketType.ROUND_START,
		"round_number":         round_number,
		"round_duration_sec":   round_duration_sec,
		"buy_phase_duration":   buy_phase_duration,
		"spawn_points":         spawn_points,
		"starting_money":       starting_money,
	}

static func parse_round_start(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ROUND_START)
	return data

## ROUND_END — конец раунда
## Направление: S→Broadcast | reliable | by event
static func make_round_end(
		round_number: int,
		reason: String,        # "elimination"|"time_limit"|"zone"|"objective"
		duration_sec: float,   # float32 — сколько длился раунд
		survivors: Array       # Array[int] — peer_id выживших
) -> Dictionary:
	return {
		"type":         PacketType.ROUND_END,
		"round_number": round_number,
		"reason":       reason,
		"duration_sec": duration_sec,
		"survivors":    survivors,
	}

static func parse_round_end(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ROUND_END)
	return data

## ROUND_WINNER — объявление победителя раунда/матча
## Направление: S→Broadcast | reliable | by event
static func make_round_winner(
		winner_peer_id: int,   # -1 = draw / команда
		winner_team_id: int,   # -1 = solo
		winner_name: String,
		kills: int,            # uint8
		damage_dealt: float,   # float32
		is_match_winner: bool  # финальный победитель матча
) -> Dictionary:
	return {
		"type":            PacketType.ROUND_WINNER,
		"winner_peer_id":  winner_peer_id,
		"winner_team_id":  winner_team_id,
		"winner_name":     winner_name,
		"kills":           kills,
		"damage_dealt":    damage_dealt,
		"is_match_winner": is_match_winner,
	}

static func parse_round_winner(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ROUND_WINNER)
	return data

## ROUND_STATE_SYNC — полная синхронизация состояния раунда (при подключении)
## Направление: S→C | reliable | on connect
## player_states: Array[{peer_id, name, health, position, money, kills, deaths}]
static func make_round_state_sync(
		round_number: int,
		time_elapsed_sec: float,
		phase: String,         # "buy"|"active"|"end"
		player_states: Array,
		zone_state: Dictionary # результат make_zone_state()
) -> Dictionary:
	return {
		"type":              PacketType.ROUND_STATE_SYNC,
		"round_number":      round_number,
		"time_elapsed_sec":  time_elapsed_sec,
		"phase":             phase,
		"player_states":     player_states,
		"zone_state":        zone_state,
	}

static func parse_round_state_sync(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.ROUND_STATE_SYNC)
	return data

## SCOREBOARD_UPDATE — обновление таблицы очков
## Направление: S→Broadcast | reliable | by event
## entries: Array[{peer_id, name, kills, deaths, damage, money, alive:bool}]
static func make_scoreboard_update(
		round_number: int,
		entries: Array
) -> Dictionary:
	return {
		"type":         PacketType.SCOREBOARD_UPDATE,
		"round_number": round_number,
		"entries":      entries,
	}

static func parse_scoreboard_update(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.SCOREBOARD_UPDATE)
	return data

## FREEZE_PHASE_START — начало freeze-time (фаза покупки)
## Направление: S→Broadcast | reliable | by event
static func make_freeze_phase_start(
		duration_sec: float,   # float32
		round_number: int
) -> Dictionary:
	return {
		"type":         PacketType.FREEZE_PHASE_START,
		"duration_sec": duration_sec,
		"round_number": round_number,
	}

static func parse_freeze_phase_start(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.FREEZE_PHASE_START)
	return data

## FREEZE_PHASE_END — конец freeze-time, игра началась
## Направление: S→Broadcast | reliable | by event
static func make_freeze_phase_end(round_number: int) -> Dictionary:
	return {
		"type":         PacketType.FREEZE_PHASE_END,
		"round_number": round_number,
	}

static func parse_freeze_phase_end(data: Dictionary) -> Dictionary:
	assert(data.get("type") == PacketType.FREEZE_PHASE_END)
	return data

# =============================================================================
# УТИЛИТЫ
# =============================================================================

## Определяет канал ENet для данного типа пакета
static func get_channel(packet_type: int) -> int:
	match packet_type:
		PacketType.PLAYER_STATE, \
		PacketType.PLAYER_INPUT, \
		PacketType.PROJECTILE_SPAWN, \
		PacketType.ZONE_DAMAGE_TICK, \
		PacketType.PING, \
		PacketType.PONG:
			return CHANNEL_UNRELIABLE
		PacketType.PLAYER_STATE:
			return CHANNEL_STATE
		_:
			return CHANNEL_RELIABLE

## Возвращает человекочитаемое имя пакета
static func get_type_name(packet_type: int) -> String:
	return PacketType.keys()[PacketType.values().find(packet_type)] \
		if PacketType.values().has(packet_type) \
		else "UNKNOWN(%d)" % packet_type
