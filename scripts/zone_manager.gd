extends Node
class_name ZoneManager

# --- Zone phases: radius shrinks each phase ---
const PHASE_DATA: Array[Dictionary] = [
	{"duration": 120.0, "damage_per_sec": 2.0,  "target_radius_ratio": 0.7},
	{"duration": 90.0,  "damage_per_sec": 5.0,  "target_radius_ratio": 0.45},
	{"duration": 60.0,  "damage_per_sec": 10.0, "target_radius_ratio": 0.25},
	{"duration": 30.0,  "damage_per_sec": 20.0, "target_radius_ratio": 0.1},
	{"duration": 15.0,  "damage_per_sec": 40.0, "target_radius_ratio": 0.0},
]

var map_radius: float = 2000.0
var zone_center: Vector2 = Vector2.ZERO

var current_radius: float = 2000.0
var target_radius: float = 2000.0
var current_phase: int = 0
var phase_timer: float = 0.0
var is_shrinking: bool = false
var shrink_speed: float = 0.0

signal phase_changed(phase_index: int)
signal zone_radius_updated(radius: float)

func _ready() -> void:
	current_radius = map_radius
	_start_phase(0)

func _start_phase(index: int) -> void:
	if index >= PHASE_DATA.size():
		return
	current_phase = index
	phase_timer = PHASE_DATA[index]["duration"]
	target_radius = map_radius * PHASE_DATA[index]["target_radius_ratio"]
	shrink_speed = (current_radius - target_radius) / phase_timer
	is_shrinking = true
	phase_changed.emit(current_phase)

func _process(delta: float) -> void:
	if not is_shrinking:
		return
	phase_timer -= delta
	if current_radius > target_radius:
		current_radius = maxf(target_radius, current_radius - shrink_speed * delta)
		zone_radius_updated.emit(current_radius)

	if phase_timer <= 0.0:
		current_radius = target_radius
		is_shrinking = false
		var next := current_phase + 1
		if next < PHASE_DATA.size():
			_start_phase(next)

func is_position_inside_zone(pos: Vector2) -> bool:
	return pos.distance_to(zone_center) <= current_radius

func get_damage_per_second() -> float:
	if current_phase >= PHASE_DATA.size():
		return PHASE_DATA[-1]["damage_per_sec"]
	return PHASE_DATA[current_phase]["damage_per_sec"]

func apply_zone_damage(player: Player, delta: float) -> void:
	if not player.is_alive():
		return
	if not is_position_inside_zone(player.global_position):
		player.take_damage(get_damage_per_second() * delta)

func get_zone_state() -> Dictionary:
	return {
		"center": zone_center,
		"current_radius": current_radius,
		"target_radius": target_radius,
		"phase": current_phase,
		"phase_timer": phase_timer,
		"damage_per_sec": get_damage_per_second(),
	}
