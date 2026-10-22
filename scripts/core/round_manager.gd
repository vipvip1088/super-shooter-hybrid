class_name RoundManager
extends Node

signal state_changed(new_state: String)
signal round_started(round_num: int)
signal buy_phase_started(duration: float, money: int)
signal upgrade_choices(perks: Array)
signal game_over()
signal victory()

enum State { FREEZE, BUY_PHASE, PLAYING, UPGRADE, GAME_OVER, VICTORY }

var _gm:    Node
var _state: int  = State.FREEZE
var _timer: float = 0.0


func setup(game_manager: Node) -> void:
	_gm = game_manager
	_state = State.FREEZE
	_timer = Balance.FREEZE_DURATION


func get_state() -> String:
	return State.keys()[_state]


func is_playing() -> bool:
	return _state == State.PLAYING


func is_in_shop() -> bool:
	return _state == State.BUY_PHASE


func start_buy_phase() -> void:
	_state = State.BUY_PHASE
	_timer = Balance.BUY_PHASE_DURATION
	_gm.p_money += Balance.ROUND_SURVIVAL_BONUS
	emit_signal("buy_phase_started", Balance.BUY_PHASE_DURATION, _gm.p_money)
	emit_signal("state_changed", "BUY_PHASE")


func start_round(round_num: int) -> void:
	_state = State.PLAYING
	emit_signal("round_started", round_num)
	emit_signal("state_changed", "PLAYING")


func trigger_upgrade() -> void:
	_state = State.UPGRADE
	var choices := _pick_perks(3)
	emit_signal("upgrade_choices", choices)
	emit_signal("state_changed", "UPGRADE")


func apply_perk(perk_key: String) -> void:
	if perk_key == "":
		_advance_round()
		return
	var perk: Dictionary = Balance.PERKS.get(perk_key, {})
	if perk.is_empty():
		_advance_round()
		return
	var effect: String = perk["effect"]
	var value: float   = perk["value"]
	match effect:
		"max_hp":
			_gm.p_max_hp += value
			_gm.p_hp = minf(_gm.p_hp + value, _gm.p_max_hp)
		"loot_mult":
			_gm.p_loot_mult  = value
		"reload_mult":
			_gm.p_reload_mult = value
		"zone_resist":
			_gm.p_zone_resist = value
		"kill_bonus":
			_gm.p_kill_bonus  = value
		"ammo_mult":
			var wd: Dictionary = _gm.combat_manager.get_weapon(_gm.p_weapon)
			if not wd.is_empty():
				_gm.p_max_ammo = int(wd["ammo"] * value)
				_gm.p_ammo = _gm.p_max_ammo
		"hit_stop":
			_gm.p_hit_stop_dur = value
		"last_stand":
			_gm.p_last_stand   = value
	_gm.p_perks.append(perk_key)
	_advance_round()


func trigger_game_over() -> void:
	_state = State.GAME_OVER
	emit_signal("game_over")
	emit_signal("state_changed", "GAME_OVER")


func update(delta: float) -> void:
	_timer = maxf(0.0, _timer - delta)
	match _state:
		State.FREEZE:
			if _timer <= 0.0:
				start_buy_phase()
		State.BUY_PHASE:
			if _timer <= 0.0:
				start_round(_gm.current_round)
		State.PLAYING:
			pass
		State.UPGRADE:
			pass


func _advance_round() -> void:
	_gm.current_round += 1
	if _gm.current_round > Balance.MAX_ROUNDS:
		_state = State.VICTORY
		emit_signal("victory")
		emit_signal("state_changed", "VICTORY")
	else:
		_state = State.FREEZE
		_timer = Balance.FREEZE_DURATION
		emit_signal("state_changed", "FREEZE")


func _pick_perks(count: int) -> Array:
	var available: Array = []
	for k in Balance.PERK_KEYS:
		if k not in _gm.p_perks:
			available.append(k)
	available.shuffle()
	var result: Array = []
	for i in range(mini(count, available.size())):
		result.append(available[i])
	return result
