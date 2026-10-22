extends CharacterBody2D
class_name Player

# --- Constants ---
const SPEED := 300.0
const MAX_HEALTH := 100.0

# --- State ---
var health: float = MAX_HEALTH
var money: int = 0
var round_kills: int = 0

var inventory: Dictionary = {
	"weapon": "",
	"ammo": 0,
	"wood": 0,
	"metal": 0,
}

# --- Signals ---
signal health_changed(new_health: float)
signal died()
signal resource_collected(type: String, amount: int)
signal money_changed(new_amount: int)

func _ready() -> void:
	health = MAX_HEALTH

func _physics_process(delta: float) -> void:
	_handle_movement(delta)

func _handle_movement(_delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		direction.x += 1.0
	if Input.is_action_pressed("move_left"):
		direction.x -= 1.0
	if Input.is_action_pressed("move_down"):
		direction.y += 1.0
	if Input.is_action_pressed("move_up"):
		direction.y -= 1.0

	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	velocity = direction * SPEED
	move_and_slide()

func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health)
	if health <= 0.0:
		_die()

func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = minf(MAX_HEALTH, health + amount)
	health_changed.emit(health)

func is_alive() -> bool:
	return health > 0.0

func _die() -> void:
	died.emit()
	set_physics_process(false)

# --- Inventory helpers ---
func equip_weapon(weapon_id: String) -> void:
	inventory["weapon"] = weapon_id

func add_ammo(amount: int) -> void:
	inventory["ammo"] = maxi(0, inventory["ammo"] + amount)

func consume_ammo(amount: int) -> bool:
	if inventory["ammo"] < amount:
		return false
	inventory["ammo"] -= amount
	return true

func add_resource(type: String, amount: int) -> void:
	if type not in inventory:
		inventory[type] = 0
	inventory[type] += amount
	resource_collected.emit(type, amount)

func consume_resource(type: String, amount: int) -> bool:
	if type not in inventory or inventory[type] < amount:
		return false
	inventory[type] -= amount
	return true

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true

func award_kill() -> void:
	round_kills += 1
	add_money(300)

func reset_round_stats() -> void:
	round_kills = 0
