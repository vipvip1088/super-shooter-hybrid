class_name DamageNumbers3D
extends Node3D

const MAX_ACTIVE := 20
var _pool: Array = []

func _ready() -> void:
	for _i in range(MAX_ACTIVE):
		_pool.append(_make_label())


func spawn(world_pos: Vector3, amount: int) -> void:
	var lbl = _get_free()
	if not lbl:
		return
	lbl.global_position = world_pos
	lbl.text = str(amount)
	lbl.modulate = Color(1.0, 0.9, 0.1) if amount < 50 else Color(1.0, 0.3, 0.1)
	lbl.visible = true
	lbl.set_meta("timer", 0.9)
	lbl.set_meta("vel_y", 2.2)


func _process(delta: float) -> void:
	for lbl in _pool:
		if not lbl.visible:
			continue
		var t: float = lbl.get_meta("timer", 0.0) - delta
		lbl.set_meta("timer", t)
		var vy: float = lbl.get_meta("vel_y", 2.0)
		lbl.global_position.y += vy * delta
		lbl.set_meta("vel_y", vy * 0.88)
		lbl.modulate.a = clampf(t / 0.9, 0.0, 1.0)
		if t <= 0.0:
			lbl.visible = false


func _make_label() -> Label3D:
	var lbl := Label3D.new()
	lbl.text = "0"
	lbl.font_size = 56
	lbl.outline_size = 6
	lbl.modulate = Color(1.0, 0.9, 0.1)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.visible = false
	add_child(lbl)
	return lbl


func _get_free() -> Label3D:
	for lbl in _pool:
		if not lbl.visible:
			return lbl
	# All busy: steal oldest (first)
	_pool[0].visible = false
	return _pool[0]
