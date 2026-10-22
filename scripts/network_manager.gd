# =============================================================================
# network_manager.gd
# SuperShooterHybrid — Singleton сетевого менеджера
# Godot 4 / ENet / GDScript
# =============================================================================

extends Node

# ---------------------------------------------------------------------------
# Сигналы
# ---------------------------------------------------------------------------
signal player_state_received(peer_id: int, state: Dictionary)
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal connected_to_server()

# ---------------------------------------------------------------------------
# Константы
# ---------------------------------------------------------------------------
const CHANNEL_RELIABLE   := 0
const CHANNEL_UNRELIABLE := 1
const CHANNEL_STATE      := 2

const PING_INTERVAL      := 1.0   # секунды между PING-пакетами
const PING_HISTORY_SIZE  := 8     # скользящее среднее RTT
const MAX_PACKET_SIZE    := 512   # байт — защита от oversized-пакетов
const CLOCK_SAMPLES      := 10    # выборок для NTP-подобной синхронизации

# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------
var _peer: ENetMultiplayerPeer = null
var _is_server := false

# Ping / RTT
var ping_ms: Dictionary = {}                 # peer_id -> float (ms)
var _ping_seq: int = 0
var _ping_pending: Dictionary = {}           # seq -> {send_time, peer_id}
var _ping_history: Dictionary = {}           # peer_id -> Array[float]
var _ping_timer: float = 0.0

# Синхронизация часов (NTP-подобная)
var _clock_offset: float = 0.0              # offset = server_time - local_time
var _clock_samples: Array[float] = []

# Защита от дублей: последний sequence на peer
var _last_input_seq: Dictionary = {}         # peer_id -> int

# ---------------------------------------------------------------------------
# Инициализация
# ---------------------------------------------------------------------------
func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ---------------------------------------------------------------------------
# Публичный API — подключение
# ---------------------------------------------------------------------------
func setup_server(port: int, max_players: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, max_players, 3)  # 3 канала
	if err != OK:
		push_error("NetworkManager: не удалось запустить сервер на порту %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = _peer
	_is_server = true
	return OK

func setup_client(address: String, port: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port, 3)
	if err != OK:
		push_error("NetworkManager: не удалось подключиться к %s:%d: %s" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = _peer
	_is_server = false
	return OK

func disconnect_peer() -> void:
	if _peer == null:
		return
	_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	ping_ms.clear()
	_ping_pending.clear()
	_ping_history.clear()
	_last_input_seq.clear()
	_clock_samples.clear()
	_clock_offset = 0.0

# ---------------------------------------------------------------------------
# Отправка пакетов
# ---------------------------------------------------------------------------

## Отправить позицию игрока — unreliable, channel STATE (2)
func send_player_state(state: Dictionary) -> void:
	if not _is_connected():
		return
	var bytes := _encode(state)
	if bytes.is_empty():
		return
	# Широковещание: 0 = все peers; на канале STATE
	multiplayer.multiplayer_peer.set_target_peer(0)
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).set_transfer_channel(CHANNEL_STATE)
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	multiplayer.send_bytes(bytes, 0, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, CHANNEL_STATE)

## Отправить инпут игрока — unreliable, channel UNRELIABLE (1)
func send_player_input(input: Dictionary) -> void:
	if not _is_connected():
		return
	var bytes := _encode(input)
	if bytes.is_empty():
		return
	multiplayer.send_bytes(bytes, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, CHANNEL_UNRELIABLE)

## Отправить надёжный пакет произвольного типа
## target_peer: 0 = broadcast, 1 = server, >1 = конкретный peer
func send_reliable(packet_type: int, data: Dictionary, target_peer: int = 0) -> void:
	if not _is_connected():
		return
	data["type"] = packet_type
	var bytes := _encode(data)
	if bytes.is_empty():
		return
	multiplayer.send_bytes(bytes, target_peer, MultiplayerPeer.TRANSFER_MODE_RELIABLE, CHANNEL_RELIABLE)

# ---------------------------------------------------------------------------
# Основной цикл
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _is_connected():
		return
	_tick_ping(delta)
	_poll_packets()

func _tick_ping(delta: float) -> void:
	_ping_timer += delta
	if _ping_timer < PING_INTERVAL:
		return
	_ping_timer = 0.0

	if _is_server:
		# Сервер не шлёт PING — он отвечает PONG
		return

	_ping_seq = (_ping_seq + 1) & 0xFFFF
	var now := Time.get_unix_time_from_system()
	_ping_pending[_ping_seq] = {"send_time": now, "peer_id": 1}

	var ping_pkt := {
		"type":        NetworkPackets.PacketType.PING,
		"sequence":    _ping_seq,
		"client_time": now,
	}
	var bytes := _encode(ping_pkt)
	if not bytes.is_empty():
		multiplayer.send_bytes(bytes, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, CHANNEL_UNRELIABLE)

	# Очищаем зависшие PING (> 5 сек без ответа)
	var expired: Array[int] = []
	for seq: int in _ping_pending:
		if now - _ping_pending[seq]["send_time"] > 5.0:
			expired.append(seq)
	for seq: int in expired:
		_ping_pending.erase(seq)

func _poll_packets() -> void:
	# Godot 4 MultiplayerAPI доставляет пакеты через сигнал peer_packet
	# Дополнительный опрос не нужен — пакеты приходят через _receive_bytes
	pass

# ---------------------------------------------------------------------------
# Входящие пакеты
# ---------------------------------------------------------------------------
func _ready_network() -> void:
	# Подключаем low-level приём байтов
	multiplayer.peer_packet.connect(_on_peer_packet)

## Вызывается при получении raw-байтов от peers
func _on_peer_packet(sender_id: int, packet: PackedByteArray) -> void:
	_parse_packet(packet, sender_id)

func _parse_packet(bytes: PackedByteArray, sender_id: int) -> void:
	if bytes.size() > MAX_PACKET_SIZE:
		push_warning("NetworkManager: oversized packet от peer %d (%d байт)" % [sender_id, bytes.size()])
		return

	var data: Variant = bytes_to_var(bytes)
	if not data is Dictionary:
		push_warning("NetworkManager: некорректный пакет от peer %d" % sender_id)
		return

	var ptype: int = data.get("type", -1)
	match ptype:
		NetworkPackets.PacketType.PLAYER_STATE:
			_handle_player_state(data, sender_id)
		NetworkPackets.PacketType.PLAYER_INPUT:
			_handle_player_input(data, sender_id)
		NetworkPackets.PacketType.PLAYER_TELEPORT:
			player_state_received.emit(sender_id, data)
		NetworkPackets.PacketType.PING:
			_handle_ping(data, sender_id)
		NetworkPackets.PacketType.PONG:
			_handle_pong(data)
		NetworkPackets.PacketType.TIME_SYNC_RESPONSE:
			_handle_time_sync_response(data)
		_:
			# Остальные пакеты перенаправляются наверх через общий сигнал
			player_state_received.emit(sender_id, data)

func _handle_player_state(data: Dictionary, sender_id: int) -> void:
	player_state_received.emit(sender_id, data)

func _handle_player_input(data: Dictionary, sender_id: int) -> void:
	var seq: int = data.get("sequence", 0)
	var last: int = _last_input_seq.get(sender_id, -1)

	# Защита от дублей и replay-атак: принимаем только нарастающий sequence
	# Учитываем wraparound uint32
	if last >= 0:
		var diff := (seq - last) & 0xFFFFFFFF
		if diff == 0 or diff > 0x7FFFFFFF:
			return  # дубль или слишком старый пакет

	_last_input_seq[sender_id] = seq
	player_state_received.emit(sender_id, data)

func _handle_ping(data: Dictionary, sender_id: int) -> void:
	if not _is_server:
		return
	var pong := {
		"type":        NetworkPackets.PacketType.PONG,
		"sequence":    data.get("sequence", 0),
		"client_time": data.get("client_time", 0.0),
		"server_time": Time.get_unix_time_from_system(),
	}
	var bytes := _encode(pong)
	if not bytes.is_empty():
		multiplayer.send_bytes(bytes, sender_id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, CHANNEL_UNRELIABLE)

func _handle_pong(data: Dictionary) -> void:
	var seq: int = data.get("sequence", -1)
	if not _ping_pending.has(seq):
		return  # устаревший или дублированный PONG

	var info: Dictionary = _ping_pending[seq]
	_ping_pending.erase(seq)

	var rtt_ms: float = (Time.get_unix_time_from_system() - info["send_time"]) * 1000.0
	var peer_id: int = info["peer_id"]

	# Скользящее среднее RTT
	if not _ping_history.has(peer_id):
		_ping_history[peer_id] = []
	var hist: Array = _ping_history[peer_id]
	hist.append(rtt_ms)
	if hist.size() > PING_HISTORY_SIZE:
		hist.pop_front()
	var total := 0.0
	for v: float in hist:
		total += v
	ping_ms[peer_id] = total / hist.size()

	# Синхронизация часов: NTP-подобный алгоритм
	# offset = server_time - (client_send + rtt/2)
	var server_time: float = data.get("server_time", 0.0)
	var client_send: float = data.get("client_time", 0.0)
	var offset := server_time - (client_send + (rtt_ms * 0.0005))  # rtt_ms/2 в секундах
	_clock_samples.append(offset)
	if _clock_samples.size() > CLOCK_SAMPLES:
		_clock_samples.pop_front()
	# Используем медиану для устойчивости к джиттеру
	var sorted := _clock_samples.duplicate()
	sorted.sort()
	_clock_offset = sorted[sorted.size() / 2]

func _handle_time_sync_response(data: Dictionary) -> void:
	# Аналогично PONG — уточняем clock offset через надёжный канал
	var server_time: float = data.get("server_time", 0.0)
	var client_echo: float = data.get("client_time_echo", 0.0)
	if server_time == 0.0:
		return
	var now := Time.get_unix_time_from_system()
	var one_way := (now - client_echo) * 0.5
	var offset := server_time + one_way - now
	_clock_samples.append(offset)
	if _clock_samples.size() > CLOCK_SAMPLES:
		_clock_samples.pop_front()
	var sorted := _clock_samples.duplicate()
	sorted.sort()
	_clock_offset = sorted[sorted.size() / 2]

# ---------------------------------------------------------------------------
# Синхронизация времени
# ---------------------------------------------------------------------------

## Возвращает предполагаемое серверное время (секунды)
func get_server_time() -> float:
	return Time.get_unix_time_from_system() + _clock_offset

func get_ping_ms(peer_id: int = 1) -> float:
	return ping_ms.get(peer_id, 0.0)

# ---------------------------------------------------------------------------
# Коллбэки MultiplayerAPI
# ---------------------------------------------------------------------------
func _on_peer_connected(peer_id: int) -> void:
	ping_ms[peer_id] = 0.0
	_ping_history[peer_id] = []
	player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	ping_ms.erase(peer_id)
	_ping_history.erase(peer_id)
	_last_input_seq.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	connected_to_server.emit()
	# Запрашиваем синхронизацию времени сразу после подключения
	_request_time_sync()

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	player_disconnected.emit(1)

# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------
func _is_connected() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _encode(data: Dictionary) -> PackedByteArray:
	var bytes := var_to_bytes(data)
	if bytes.size() > MAX_PACKET_SIZE:
		push_warning("NetworkManager: пакет %d превышает MAX_PACKET_SIZE" % data.get("type", -1))
		return PackedByteArray()
	return bytes

func _request_time_sync() -> void:
	var now := Time.get_unix_time_from_system()
	var req := {
		"type":        NetworkPackets.PacketType.TIME_SYNC_REQUEST,
		"client_time": now,
		"request_id":  _ping_seq & 0xFFFF,
	}
	var bytes := _encode(req)
	if not bytes.is_empty():
		multiplayer.send_bytes(bytes, 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, CHANNEL_RELIABLE)
