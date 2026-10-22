class_name AudioGenerator3D
extends Node

const SAMPLE_RATE := 22050
const POOL_SIZE   := 8

var _pool: Array = []
var _pool_idx: int = 0


func setup(_gm: Node) -> void:
	for _i in range(POOL_SIZE):
		var asp = AudioStreamPlayer.new()
		asp.volume_db = -6.0
		add_child(asp)
		_pool.append(asp)


# ── Public API ─────────────────────────────────────────────────────────────────
func play_shoot(weapon_id: String) -> void:
	match weapon_id:
		"ar":      _play(_synth_gunshot(0.003, 0.12, 320.0, 0.60), -4.0)
		"shotgun": _play(_synth_gunshot(0.002, 0.18, 180.0, 0.85), -2.0)
		"sniper":  _play(_synth_gunshot(0.001, 0.22, 650.0, 0.25), -3.0)
		"plasma":  _play(_synth_plasma(), -5.0)
		"grenade": _play(_synth_thump(120.0, 0.28), -3.0)
		_:         _play(_synth_gunshot(0.003, 0.14, 280.0, 0.55), -5.0)


func play_explosion() -> void:
	_play(_synth_explosion(), 0.0)


func play_hit_enemy() -> void:
	_play(_synth_hit(), -8.0)


func play_hurt() -> void:
	_play(_synth_hurt(), -6.0)


func play_pickup(type_id: String) -> void:
	match type_id:
		"money": _play(_synth_coin(), -8.0)
		"health": _play(_synth_blip(880.0, 0.12), -8.0)
		_:       _play(_synth_blip(660.0, 0.09), -10.0)


func play_reload() -> void:
	_play(_synth_swoosh(0.35), -7.0)


func play_empty() -> void:
	_play(_synth_blip(200.0, 0.06), -9.0)


func play_dash() -> void:
	_play(_synth_swoosh(0.18), -6.0)


func play_levelup() -> void:
	_play(_synth_fanfare(), -4.0)


func play_buy() -> void:
	_play(_synth_coin(), -5.0)


func play_kill() -> void:
	_play(_synth_blip(1100.0, 0.07), -10.0)


# ── Synthesis ──────────────────────────────────────────────────────────────────
func _synth_gunshot(attack: float, decay: float, base_freq: float, noise_mix: float) -> PackedFloat32Array:
	var samples := int(SAMPLE_RATE * (attack + decay))
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var env: float
		if t < attack:
			env = t / attack
		else:
			env = exp(-5.5 * (t - attack) / decay)
		var tone := sin(TAU * base_freq * t) * (1.0 - noise_mix)
		var noise := randf_range(-1.0, 1.0) * noise_mix
		buf[i] = (tone + noise) * env * 0.85
	return buf


func _synth_explosion() -> PackedFloat32Array:
	var dur := 0.9
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-4.0 * t / dur)
		var low := sin(TAU * 60.0 * t) * 0.5
		var mid := sin(TAU * 180.0 * t) * 0.25
		var noise := randf_range(-1.0, 1.0) * 0.70
		buf[i] = (low + mid + noise) * env * 0.90
	return buf


func _synth_plasma() -> PackedFloat32Array:
	var dur := 0.22
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-6.0 * t / dur)
		var freq := 800.0 + (1.0 - t / dur) * 400.0
		buf[i] = sin(TAU * freq * t) * env * 0.80
	return buf


func _synth_thump(freq: float, dur: float) -> PackedFloat32Array:
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-5.0 * t / dur)
		var f := freq * (1.0 - t / dur * 0.6)
		buf[i] = sin(TAU * f * t) * env * 0.85
	return buf


func _synth_hit() -> PackedFloat32Array:
	var dur := 0.08
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		buf[i] = randf_range(-1.0, 1.0) * exp(-10.0 * t / dur) * 0.6
	return buf


func _synth_hurt() -> PackedFloat32Array:
	var dur := 0.20
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-5.0 * t / dur)
		buf[i] = sin(TAU * 220.0 * t * (1.0 + t * 2.0)) * env * 0.7
	return buf


func _synth_swoosh(dur: float) -> PackedFloat32Array:
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var env := sin(PI * t / dur)
		var freq := 800.0 + t / dur * 1200.0
		buf[i] = (sin(TAU * freq * t) * 0.4 + randf_range(-0.3, 0.3)) * env * 0.6
	return buf


func _synth_blip(freq: float, dur: float) -> PackedFloat32Array:
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var env := sin(PI * t / dur)
		buf[i] = sin(TAU * freq * t) * env * 0.7
	return buf


func _synth_coin() -> PackedFloat32Array:
	var dur := 0.28
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var env := exp(-7.0 * t / dur)
		buf[i] = (sin(TAU * 1760.0 * t) * 0.5 + sin(TAU * 2200.0 * t) * 0.3) * env * 0.75
	return buf


func _synth_fanfare() -> PackedFloat32Array:
	var dur := 0.8
	var samples := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(samples)
	var notes := [523.0, 659.0, 784.0, 1047.0]
	var note_dur := dur / notes.size()
	for i in range(samples):
		var t := float(i) / SAMPLE_RATE
		var note_idx := int(t / note_dur) % notes.size()
		var t_in := fmod(t, note_dur)
		var env := sin(PI * t_in / note_dur)
		buf[i] = sin(TAU * notes[note_idx] * t) * env * 0.65
	return buf


# ── Playback ───────────────────────────────────────────────────────────────────
func _play(samples: PackedFloat32Array, vol_db: float) -> void:
	var asp: AudioStreamPlayer = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE

	var stream = AudioStreamWAV.new()
	stream.mix_rate = SAMPLE_RATE
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false

	var byte_buf := PackedByteArray()
	byte_buf.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		byte_buf[i * 2]     = s & 0xFF
		byte_buf[i * 2 + 1] = (s >> 8) & 0xFF
	stream.data = byte_buf

	asp.stream = stream
	asp.volume_db = vol_db
	asp.play()
