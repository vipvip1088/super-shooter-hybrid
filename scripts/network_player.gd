# =============================================================================
# network_player.gd
# SuperShooterHybrid — сетевой компонент игрока
# Клиентское предсказание + интерполяция удалённых игроков
# =============================================================================

extends Node

# ---------------------------------------------------------------------------
# Экспортируемые параметры (настраиваются в редакторе)
# ---------------------------------------------------------------------------
@export var is_local_player: bool = false
@export var peer_id: int = 0

# ---------------------------------------------------------------------------
# Константы
# ---------------------------------------------------------------------------
const SNAPSHOT_BUFFER_SIZE := 20       # максимум снапшотов в буфере
const RENDER_DELAY          := 0.1     # задержка рендера удалённых (сек)
const RECONCILE_TELEPORT    := 50.0    # пикселей — порог телепортации
const RECONCILE_BLEND_SPEED := 10.0    # скорость плавной коррекции (units/sec)
const INPUT_SEND_HZ         := 30.0
const STATE_SEND_HZ         := 20.0

# ---------------------------------------------------------------------------
# Внутренние типы
# ---------------------------------------------------------------------------
# Снапшот для буфера удалённого игрока
# {timestamp: float, position: Vector2, velocity: Vector2, rotation: float}

# Запись предсказания для reconciliation
# {sequence: int, position: Vector2, velocity: Vector2}

# ---------------------------------------------------------------------------
# Ссылки на узлы (назначаются в _ready через get_parent или экспорт)
# ---------------------------------------------------------------------------
var _parent_body: CharacterBody2D = null

# ---------------------------------------------------------------------------
# Состояние локального игрока (предсказание)
# ---------------------------------------------------------------------------
var _input_seq: int = 0
var _predicted_position: Vector2 = Vector2.ZERO
var _predicted_velocity: Vector2 = Vector2.ZERO
# Кольцевой буфер предсказаний для reconciliation
var _prediction_buffer: Array = []      # Array of Dictionaries
const PREDICTION_BUFFER_SIZE := 64

# Таймеры отправки — используем накопители вместо таймер-объектов (без alloc)
var _input_send_acc: float = 0.0
var _state_send_acc: float = 0.0
const _INPUT_INTERVAL: float  = 1.0 / INPUT_SEND_HZ
const _STATE_INTERVAL: float  = 1.0 / STATE_SEND_HZ

# ---------------------------------------------------------------------------
# Состояние удалённого игрока (интерполяция)
# ---------------------------------------------------------------------------
# Кольцевой буфер снапшотов: храним как Array[Dictionary], выделяем заранее
var _snapshot_buffer: Array = []
var _snapshot_head: int = 0             # индекс следующей записи (ring buffer)
var _snapshot_count: int = 0            # количество актуальных записей

# Текущая визуальная позиция (интерполированная)
var _render_position: Vector2 = Vector2.ZERO
var _render_rotation: float = 0.0

# Плавная коррекция: цель после reconciliation
var _correction_target: Vector2 = Vector2.ZERO
var _is_correcting: bool = false

# ---------------------------------------------------------------------------
# Инициализация
# ---------------------------------------------------------------------------
func _ready() -> void:
	_parent_body = get_parent() as CharacterBody2D

	# Преаллоцируем буферы, чтобы избежать alloc в hot path
	_snapshot_buffer.resize(SNAPSHOT_BUFFER_SIZE)
	for i in SNAPSHOT_BUFFER_SIZE:
		_snapshot_buffer[i] = {
			"timestamp": 0.0,
			"position":  Vector2.ZERO,
			"velocity":  Vector2.ZERO,
			"rotation":  0.0,
		}

	_prediction_buffer.resize(PREDICTION_BUFFER_SIZE)
	for i in PREDICTION_BUFFER_SIZE:
		_prediction_buffer[i] = {
			"sequence": 0,
			"position": Vector2.ZERO,
			"velocity": Vector2.ZERO,
		}

	if _parent_body != null:
		_predicted_position = _parent_body.global_position
		_render_position    = _parent_body.global_position

	# Подписываемся на входящие состояния от NetworkManager
	if NetworkManager != null:
		NetworkManager.player_state_received.connect(_on_network_state)

# ---------------------------------------------------------------------------
# _process — горячий путь
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if is_local_player:
		_process_local(delta)
	else:
		_process_remote(delta)

func _process_local(delta: float) -> void:
	# 1. Собираем инпут
	var move_dir := _read_input_dir()
	var is_shoot := Input.is_action_pressed("shoot")

	# 2. Клиентское предсказание: применяем движение немедленно
	_apply_local_prediction(move_dir, delta)

	# 3. Отправка инпута 30 Hz
	_input_send_acc += delta
	if _input_send_acc >= _INPUT_INTERVAL:
		_input_send_acc -= _INPUT_INTERVAL
		_send_input(move_dir, is_shoot)

	# 4. Отправка состояния 20 Hz
	_state_send_acc += delta
	if _state_send_acc >= _STATE_INTERVAL:
		_state_send_acc -= _STATE_INTERVAL
		_send_state()

	# 5. Плавная коррекция расхождения
	if _is_correcting and _parent_body != null:
		var dist := _parent_body.global_position.distance_to(_correction_target)
		if dist < 1.0:
			_parent_body.global_position = _correction_target
			_is_correcting = false
		else:
			_parent_body.global_position = _parent_body.global_position.lerp(
				_correction_target,
				clampf(RECONCILE_BLEND_SPEED * delta, 0.0, 1.0)
			)

func _process_remote(delta: float) -> void:
	if _snapshot_count < 2 or _parent_body == null:
		return

	# Рендеримся с задержкой RENDER_DELAY относительно серверного времени
	var render_time: float = NetworkManager.get_server_time() - RENDER_DELAY

	# Находим два снапшота, между которыми находится render_time
	var snap_a: Dictionary
	var snap_b: Dictionary
	var found := false

	# Ищем в буфере. Буфер кольцевой — итерируем по count снапшотам
	for i in (_snapshot_count - 1):
		var idx_a := (_snapshot_head - _snapshot_count + i) & (SNAPSHOT_BUFFER_SIZE - 1)
		var idx_b := (_snapshot_head - _snapshot_count + i + 1) & (SNAPSHOT_BUFFER_SIZE - 1)
		var a: Dictionary = _snapshot_buffer[idx_a]
		var b: Dictionary = _snapshot_buffer[idx_b]
		if a["timestamp"] <= render_time and render_time <= b["timestamp"]:
			snap_a = a
			snap_b = b
			found = true
			break

	if not found:
		# Нет подходящего интервала — берём последний снапшот
		var last_idx := (_snapshot_head - 1) & (SNAPSHOT_BUFFER_SIZE - 1)
		_render_position = _snapshot_buffer[last_idx]["position"]
		_render_rotation = _snapshot_buffer[last_idx]["rotation"]
	else:
		var t_range: float = snap_b["timestamp"] - snap_a["timestamp"]
		# Защита от деления на ноль (одинаковые метки)
		var alpha: float = 0.0 if t_range < 0.00001 else \
			clampf((render_time - snap_a["timestamp"]) / t_range, 0.0, 1.0)
		_render_position = snap_a["position"].lerp(snap_b["position"], alpha)
		_render_rotation = lerpf(snap_a["rotation"], snap_b["rotation"], alpha)

	_parent_body.global_position = _render_position
	_parent_body.rotation        = _render_rotation

# ---------------------------------------------------------------------------
# Публичный API
# ---------------------------------------------------------------------------

## Принять серверное состояние (для локального — reconciliation; для удалённого — буфер)
func apply_server_state(state: Dictionary) -> void:
	if is_local_player:
		_reconcile(state)
	else:
		_push_snapshot(state)

## Получить текущий снапшот для отправки
func get_snapshot() -> Dictionary:
	if _parent_body == null:
		return {}
	return {
		"peer_id":    peer_id,
		"position":   {"x": _parent_body.global_position.x, "y": _parent_body.global_position.y},
		"rotation":   _parent_body.rotation,
		"velocity":   {"x": _parent_body.velocity.x, "y": _parent_body.velocity.y},
		"anim_state": 0,
		"health":     _get_health(),
		"timestamp":  NetworkManager.get_server_time(),
	}

# ---------------------------------------------------------------------------
# Входящие сетевые пакеты
# ---------------------------------------------------------------------------
func _on_network_state(sender_id: int, state: Dictionary) -> void:
	var ptype: int = state.get("type", -1)
	match ptype:
		NetworkPackets.PacketType.PLAYER_STATE:
			var state_peer: int = state.get("peer_id", sender_id)
			if state_peer == peer_id:
				apply_server_state(state)
		NetworkPackets.PacketType.PLAYER_TELEPORT:
			var tp_peer: int = state.get("peer_id", sender_id)
			if tp_peer == peer_id:
				_apply_teleport(state)

# ---------------------------------------------------------------------------
# Клиентское предсказание
# ---------------------------------------------------------------------------
func _read_input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_action_pressed("move_right"): d.x += 1.0
	if Input.is_action_pressed("move_left"):  d.x -= 1.0
	if Input.is_action_pressed("move_down"):  d.y += 1.0
	if Input.is_action_pressed("move_up"):    d.y -= 1.0
	if d.length_squared() > 0.0:
		d = d.normalized()
	return d

func _apply_local_prediction(move_dir: Vector2, delta: float) -> void:
	if _parent_body == null:
		return
	# Повторяем ту же логику, что и на сервере (детерминированно)
	var speed: float = _parent_body.get("SPEED") if _parent_body.get("SPEED") != null else 300.0
	_parent_body.velocity = move_dir * speed
	_parent_body.move_and_slide()
	_predicted_position = _parent_body.global_position
	_predicted_velocity = _parent_body.velocity

	# Сохраняем в буфер предсказаний (ring buffer)
	var slot := _input_seq & (PREDICTION_BUFFER_SIZE - 1)
	var entry: Dictionary = _prediction_buffer[slot]
	entry["sequence"] = _input_seq
	entry["position"].x = _predicted_position.x
	entry["position"].y = _predicted_position.y
	entry["velocity"].x = _predicted_velocity.x
	entry["velocity"].y = _predicted_velocity.y

func _send_input(move_dir: Vector2, is_shoot: bool) -> void:
	_input_seq = (_input_seq + 1) & 0xFFFFFFFF
	var input := {
		"type":      NetworkPackets.PacketType.PLAYER_INPUT,
		"sequence":  _input_seq,
		"move_dir":  {"x": move_dir.x, "y": move_dir.y},
		"shoot":     is_shoot,
		"timestamp": NetworkManager.get_server_time(),
	}
	NetworkManager.send_player_input(input)

func _send_state() -> void:
	var snap := get_snapshot()
	if not snap.is_empty():
		snap["type"] = NetworkPackets.PacketType.PLAYER_STATE
		NetworkManager.send_player_state(snap)

# ---------------------------------------------------------------------------
# Reconciliation (согласование) — только для локального игрока
# ---------------------------------------------------------------------------
func _reconcile(server_state: Dictionary) -> void:
	if _parent_body == null:
		return

	var raw_pos = server_state.get("position", null)
	if raw_pos == null:
		return

	var server_pos := Vector2(
		float(raw_pos.get("x", 0.0)),
		float(raw_pos.get("y", 0.0))
	)

	var error := _parent_body.global_position.distance_to(server_pos)

	if error > RECONCILE_TELEPORT:
		# Расхождение критическое — телепортируем
		_parent_body.global_position = server_pos
		_predicted_position = server_pos
		_is_correcting = false
	elif error > 1.0:
		# Небольшое расхождение — плавная коррекция
		_correction_target = server_pos
		_is_correcting = true

# ---------------------------------------------------------------------------
# Телепорт от сервера (принудительный)
# ---------------------------------------------------------------------------
func _apply_teleport(data: Dictionary) -> void:
	if _parent_body == null:
		return
	var raw_pos = data.get("position", null)
	if raw_pos == null:
		return
	var pos := Vector2(float(raw_pos.get("x", 0.0)), float(raw_pos.get("y", 0.0)))
	_parent_body.global_position = pos
	_parent_body.rotation = float(data.get("rotation", 0.0))
	_predicted_position = pos
	_is_correcting = false
	if not is_local_player:
		_render_position = pos

# ---------------------------------------------------------------------------
# Буфер снапшотов — только для удалённых игроков
# ---------------------------------------------------------------------------
func _push_snapshot(state: Dictionary) -> void:
	var raw_pos = state.get("position", null)
	if raw_pos == null:
		return

	var ts: float = float(state.get("timestamp", 0.0))

	# Игнорируем снапшоты из прошлого (защита от out-of-order при wraparound)
	if _snapshot_count > 0:
		var prev_idx := (_snapshot_head - 1) & (SNAPSHOT_BUFFER_SIZE - 1)
		if ts <= _snapshot_buffer[prev_idx]["timestamp"]:
			return

	# Запись в кольцевой буфер без alloc
	var slot: int = _snapshot_head
	var entry: Dictionary = _snapshot_buffer[slot]
	entry["timestamp"] = ts
	entry["position"].x = float(raw_pos.get("x", 0.0))
	entry["position"].y = float(raw_pos.get("y", 0.0))
	entry["rotation"]   = float(state.get("rotation", 0.0))

	var raw_vel = state.get("velocity", null)
	if raw_vel != null:
		entry["velocity"].x = float(raw_vel.get("x", 0.0))
		entry["velocity"].y = float(raw_vel.get("y", 0.0))
	else:
		entry["velocity"].x = 0.0
		entry["velocity"].y = 0.0

	_snapshot_head = (_snapshot_head + 1) & (SNAPSHOT_BUFFER_SIZE - 1)
	_snapshot_count = mini(_snapshot_count + 1, SNAPSHOT_BUFFER_SIZE)

# ---------------------------------------------------------------------------
# Вспомогательные
# ---------------------------------------------------------------------------
func _get_health() -> float:
	if _parent_body == null:
		return 0.0
	var h = _parent_body.get("health")
	return float(h) if h != null else 0.0
