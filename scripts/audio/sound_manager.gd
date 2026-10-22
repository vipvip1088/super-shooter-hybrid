## sound_manager.gd — procedural audio engine via AudioStreamGenerator
## Generates all sounds mathematically: no .wav/.ogg files needed.
## Each sound is a short synthesis recipe (envelope + waveform).
class_name SoundManager
extends Node

const SAMPLE_RATE := 44100
const MAX_CHANNELS := 8

var _gm: Node
var _players: Array = []


func setup(game_manager: Node) -> void:
	_gm = game_manager
	for i in range(MAX_CHANNELS):
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		_players.append(ap)


# ── Public API ──────────────────────────────────────────────────────────────

func play_shoot(weapon_id: String) -> void:
	match weapon_id:
		"pistol":    _synth_gunshot(0.06, 0.12, 440.0, 0.3)
		"shotgun":   _synth_gunshot(0.08, 0.20, 180.0, 0.6)
		"smg":       _synth_gunshot(0.03, 0.08, 600.0, 0.25)
		"sniper":    _synth_gunshot(0.04, 0.30, 280.0, 0.55)
		"plasma":    _synth_plasma(0.15)
		"rocket":    _synth_gunshot(0.10, 0.35, 120.0, 0.7)
		"laser":     _synth_laser(0.12)
		"minigun":   _synth_gunshot(0.02, 0.05, 700.0, 0.15)
		"ricochet":  _synth_gunshot(0.05, 0.14, 500.0, 0.3)
		"flamethrower": _synth_noise(0.06, 0.25)
		_:           _synth_gunshot(0.05, 0.12, 400.0, 0.3)


func play_explosion() -> void:
	_synth_explosion(0.4)


func play_hit() -> void:
	_synth_hit(0.08)


func play_hurt() -> void:
	_synth_hurt(0.15)


func play_kill() -> void:
	_synth_blip(0.10, 880.0, 0.2)


func play_pickup() -> void:
	_synth_pickup(0.12)


func play_reload() -> void:
	_synth_blip(0.08, 660.0, 0.15)


func play_empty() -> void:
	_synth_blip(0.05, 200.0, 0.3)


func play_dash() -> void:
	_synth_swoosh(0.12)


func play_ultimate() -> void:
	_synth_blip(0.25, 1320.0, 0.5)


func play_buy() -> void:
	_synth_coin(0.15)


func play_levelup() -> void:
	_synth_fanfare(0.3)


# ── Synthesis helpers ───────────────────────────────────────────────────────

func _get_free_player() -> AudioStreamPlayer:
	for p in _players:
		if not (p as AudioStreamPlayer).playing:
			return p as AudioStreamPlayer
	return _players[0] as AudioStreamPlayer


func _play_samples(samples: PackedFloat32Array, vol: float = 0.8) -> void:
	if samples.is_empty():
		return
	var stream := AudioStreamWAV.new()
	stream.format      = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo      = false
	stream.mix_rate    = SAMPLE_RATE
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s := int(clampf(samples[i] * vol, -1.0, 1.0) * 32767.0)
		bytes[i * 2]     = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	stream.data = bytes
	var p := _get_free_player()
	p.stream = stream
	p.play()


func _synth_gunshot(attack: float, decay: float, base_freq: float, noise_mix: float) -> void:
	var total := int((attack + decay) * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t      := float(i) / SAMPLE_RATE
		var env    := exp(-t / decay) * (1.0 - exp(-t / maxf(attack, 0.001)))
		var freq   := base_freq * exp(-t * 12.0)
		var tone   := sin(t * freq * TAU)
		var noise  := randf_range(-1.0, 1.0)
		buf[i] = lerp(tone, noise, noise_mix) * env
	_play_samples(buf, 0.9)


func _synth_explosion(duration: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t   := float(i) / SAMPLE_RATE
		var env := exp(-t / (duration * 0.4)) * (1.0 - exp(-t * 80.0))
		var sub := sin(t * 60.0 * TAU) * 0.5
		var mid := randf_range(-1.0, 1.0) * exp(-t * 8.0)
		buf[i] = (sub + mid) * env
	_play_samples(buf, 1.0)


func _synth_plasma(duration: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t    := float(i) / SAMPLE_RATE
		var env  := (1.0 - t / duration) * sin(t * 30.0)
		var tone := sin(t * (800.0 - t * 1000.0) * TAU)
		buf[i] = tone * env
	_play_samples(buf, 0.7)


func _synth_laser(duration: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t    := float(i) / SAMPLE_RATE
		var freq := lerp(1200.0, 300.0, t / duration)
		var env  := exp(-t / duration)
		buf[i] = sin(t * freq * TAU) * env
	_play_samples(buf, 0.6)


func _synth_noise(attack: float, duration: float) -> void:
	var total := int((attack + duration) * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	var lp := 0.0
	for i in range(total):
		var t   := float(i) / SAMPLE_RATE
		var env := exp(-t / duration) * (1.0 - exp(-t / maxf(attack, 0.001)))
		lp = lerp(lp, randf_range(-1.0, 1.0), 0.3)
		buf[i] = lp * env
	_play_samples(buf, 0.75)


func _synth_hit(duration: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t   := float(i) / SAMPLE_RATE
		var env := exp(-t / duration)
		buf[i] = randf_range(-1.0, 1.0) * env
	_play_samples(buf, 0.4)


func _synth_hurt(duration: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t   := float(i) / SAMPLE_RATE
		var env := sin(PI * t / duration)
		buf[i] = sin(t * 180.0 * TAU) * env * randf_range(0.8, 1.0)
	_play_samples(buf, 0.65)


func _synth_blip(duration: float, freq: float, vol: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t   := float(i) / SAMPLE_RATE
		var env := sin(PI * t / duration)
		buf[i] = sin(t * freq * TAU) * env
	_play_samples(buf, vol)


func _synth_pickup(duration: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t    := float(i) / SAMPLE_RATE
		var freq := lerp(440.0, 880.0, t / duration)
		var env  := sin(PI * t / duration)
		buf[i] = sin(t * freq * TAU) * env
	_play_samples(buf, 0.45)


func _synth_swoosh(duration: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t   := float(i) / SAMPLE_RATE
		var env := sin(PI * t / duration)
		var lp  := randf_range(-1.0, 1.0) * 0.3
		var tone := sin(t * lerp(600.0, 200.0, t / duration) * TAU) * 0.7
		buf[i] = (lp + tone) * env
	_play_samples(buf, 0.5)


func _synth_coin(duration: float) -> void:
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t   := float(i) / SAMPLE_RATE
		var env := exp(-t / (duration * 0.5))
		buf[i] = sin(t * 1760.0 * TAU) * env + sin(t * 2200.0 * TAU) * env * 0.5
	_play_samples(buf, 0.4)


func _synth_fanfare(duration: float) -> void:
	var freqs := [523.25, 659.25, 783.99, 1046.5]  # C5 E5 G5 C6
	var total := int(duration * SAMPLE_RATE)
	var buf   := PackedFloat32Array()
	buf.resize(total)
	for i in range(total):
		var t    := float(i) / SAMPLE_RATE
		var seg  := int(t / (duration / float(freqs.size())))
		seg = clampi(seg, 0, freqs.size() - 1)
		var freq := freqs[seg]
		var env  := sin(PI * fmod(t, duration / float(freqs.size())) / (duration / float(freqs.size())))
		buf[i] = sin(t * freq * TAU) * env
	_play_samples(buf, 0.5)
