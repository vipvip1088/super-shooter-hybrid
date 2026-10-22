class_name SaveManager
extends Node

func save_crystals(amount: int) -> void:
	var data := load_data()
	data["crystals"] = amount
	data["last_save"] = Time.get_datetime_string_from_system()
	_write(data)


func load_data() -> Dictionary:
	if not FileAccess.file_exists(Balance.SAVE_PATH):
		return {}
	var f := FileAccess.open(Balance.SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var result = json.get_data()
	if result is Dictionary:
		return result
	return {}


func save_run_result(round_reached: int, kills: int, crystals: int) -> void:
	var data := load_data()
	var best_round: int = int(data.get("best_round", 0))
	var best_kills:  int = int(data.get("best_kills",  0))
	if round_reached > best_round:
		data["best_round"] = round_reached
	if kills > best_kills:
		data["best_kills"] = kills
	data["crystals"]  = crystals
	data["total_runs"] = int(data.get("total_runs", 0)) + 1
	data["last_save"] = Time.get_datetime_string_from_system()
	_write(data)


func _write(data: Dictionary) -> void:
	var f := FileAccess.open(Balance.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open " + Balance.SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
