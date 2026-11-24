extends Node

signal mute_changed(is_muted: bool)

const MIX_RATE := 22050
const LOOP_EDGE_FADE_SAMPLES := 110

@export var custom_bgm: AudioStream = null
@export var bgm_volume_db: float = -10.0
@export var sfx_volume_db: float = -4.0

var is_muted: bool = false
var audio_unlocked: bool = false
var sfx_streams: Dictionary = {}
var play_counts: Dictionary = {}

var _slide_volume_db: float = -60.0
var _slide_pitch: float = 1.0

var bgm_player: AudioStreamPlayer
var slide_loop_player: AudioStreamPlayer
var boost_player: AudioStreamPlayer
var shield_pickup_player: AudioStreamPlayer
var shield_break_player: AudioStreamPlayer
var ramp_player: AudioStreamPlayer
var landing_player: AudioStreamPlayer
var biome_player: AudioStreamPlayer
var crash_player: AudioStreamPlayer


func _ready() -> void:
	_bake_all_streams()

	var bgm_stream: AudioStream = custom_bgm if custom_bgm != null else (sfx_streams.get("bgm") as AudioStream)
	bgm_player = _create_player("BgmPlayer", bgm_stream, bgm_volume_db)
	slide_loop_player = _create_player("SlideLoopPlayer", sfx_streams.get("slide") as AudioStream, -60.0)
	boost_player = _create_player("BoostPlayer", sfx_streams.get("boost") as AudioStream, sfx_volume_db)
	shield_pickup_player = _create_player("ShieldPickupPlayer", sfx_streams.get("shield_pickup") as AudioStream, sfx_volume_db)
	shield_break_player = _create_player("ShieldBreakPlayer", sfx_streams.get("shield_break") as AudioStream, sfx_volume_db)
	ramp_player = _create_player("RampPlayer", sfx_streams.get("ramp_launch") as AudioStream, sfx_volume_db)
	landing_player = _create_player("LandingPlayer", sfx_streams.get("landing") as AudioStream, sfx_volume_db)
	biome_player = _create_player("BiomePlayer", sfx_streams.get("biome_transition") as AudioStream, sfx_volume_db)
	crash_player = _create_player("CrashPlayer", sfx_streams.get("crash") as AudioStream, sfx_volume_db)

	for key in sfx_streams.keys():
		play_counts[key] = 0

	ensure_bgm_playing()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed:
			unlock_audio()
			if key_ev.keycode == KEY_M and not key_ev.echo:
				toggle_mute()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			unlock_audio()
	elif event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			unlock_audio()


func _create_player(node_name: String, stream: AudioStream, vol_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = vol_db
	player.bus = &"Master"
	add_child(player)
	return player


func unlock_audio() -> void:
	audio_unlocked = true
	ensure_bgm_playing()


func ensure_bgm_playing() -> void:
	if bgm_player and bgm_player.stream and not bgm_player.playing:
		bgm_player.volume_db = bgm_volume_db
		bgm_player.play()


func set_muted(muted: bool) -> void:
	is_muted = muted
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, is_muted)
	mute_changed.emit(is_muted)


func toggle_mute() -> bool:
	set_muted(not is_muted)
	return is_muted


func update_slide_loop(downhill_speed: float, carve_ratio: float, grounded: bool, active: bool, delta: float) -> void:
	if not slide_loop_player:
		return
	var lerp_alpha := 1.0 - exp(-16.0 * delta)
	if active and grounded and downhill_speed > 2.0:
		if not slide_loop_player.playing and slide_loop_player.stream:
			slide_loop_player.play()
		var speed_norm := clampf(downhill_speed / 85.0, 0.0, 1.0)
		var carve_abs := absf(carve_ratio)
		var drive := clampf(speed_norm * 0.72 + carve_abs * 0.28, 0.0, 1.0)
		var target_vol := lerpf(-26.0, -8.0, drive)
		var target_pitch := 0.82 + clampf(downhill_speed / 95.0, 0.0, 1.0) * 0.55 + carve_abs * 0.22
		_slide_volume_db = lerpf(_slide_volume_db, target_vol, lerp_alpha)
		_slide_pitch = lerpf(_slide_pitch, target_pitch, lerp_alpha)
		slide_loop_player.volume_db = _slide_volume_db
		slide_loop_player.pitch_scale = clampf(_slide_pitch, 0.5, 2.0)
	else:
		_slide_volume_db = lerpf(_slide_volume_db, -60.0, lerp_alpha)
		slide_loop_player.volume_db = _slide_volume_db
		if not active and _slide_volume_db <= -55.0 and slide_loop_player.playing:
			slide_loop_player.stop()


func stop_slide_loop() -> void:
	_slide_volume_db = -60.0
	if slide_loop_player:
		slide_loop_player.volume_db = -60.0
		if slide_loop_player.playing:
			slide_loop_player.stop()


func _play_sfx(player_node: AudioStreamPlayer, key: String, pitch: float = 1.0) -> void:
	play_counts[key] = int(play_counts.get(key, 0)) + 1
	if not player_node or not player_node.stream:
		return
	player_node.volume_db = sfx_volume_db
	player_node.pitch_scale = pitch
	player_node.play()


func play_boost(stack_count: int = 1) -> void:
	var pitch := clampf(1.0 + float(maxi(0, stack_count - 1)) * 0.08, 1.0, 1.65)
	_play_sfx(boost_player, "boost", pitch)


func play_shield_pickup() -> void:
	_play_sfx(shield_pickup_player, "shield_pickup", 1.0)


func play_shield_break() -> void:
	_play_sfx(shield_break_player, "shield_break", 1.0)


func play_ramp_launch() -> void:
	_play_sfx(ramp_player, "ramp_launch", 1.0)


func play_landing(impact: float = 0.7) -> void:
	var pitch := clampf(1.08 - impact * 0.14, 0.82, 1.12)
	_play_sfx(landing_player, "landing", pitch)


func play_biome_transition() -> void:
	_play_sfx(biome_player, "biome_transition", 1.0)


func play_crash() -> void:
	_play_sfx(crash_player, "crash", 1.0)


func _bake_all_streams() -> void:
	sfx_streams["bgm"] = _make_wav(_bake_bgm(), true)
	sfx_streams["slide"] = _make_wav(_bake_slide_loop(), true)
	sfx_streams["boost"] = _make_wav(_bake_boost(), false)
	sfx_streams["shield_pickup"] = _make_wav(_bake_shield_pickup(), false)
	sfx_streams["shield_break"] = _make_wav(_bake_shield_break(), false)
	sfx_streams["ramp_launch"] = _make_wav(_bake_ramp_launch(), false)
	sfx_streams["landing"] = _make_wav(_bake_landing(), false)
	sfx_streams["biome_transition"] = _make_wav(_bake_biome_transition(), false)
	sfx_streams["crash"] = _make_wav(_bake_crash(), false)


func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var count := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = count
	return wav


func _bake_bgm() -> PackedFloat32Array:
	var duration := 8.0
	var count := int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)

	# 120 BPM => 32 eighth notes across 8.0s (0.25s each)
	# Upbeat Japanese Yo pentatonic melody in D (D E G A B) + octave shifts
	var lead_notes: Array[float] = [
		587.33, 659.25, 783.99, 880.00, 783.99, 659.25, 587.33, 440.00,
		493.88, 587.33, 659.25, 783.99, 880.00, 783.99, 659.25, 587.33,
		587.33, 783.99, 880.00, 987.77, 880.00, 783.99, 659.25, 587.33,
		440.00, 587.33, 659.25, 880.00, 783.99, 659.25, 587.33, 440.00,
	]
	var bass_roots: Array[float] = [
		73.42, 146.83, 73.42, 146.83, 73.42, 146.83, 73.42, 146.83,
		98.00, 196.00, 98.00, 196.00, 110.00, 220.00, 110.00, 220.00,
		73.42, 146.83, 73.42, 146.83, 98.00, 196.00, 98.00, 196.00,
		110.00, 220.00, 98.00, 196.00, 73.42, 146.83, 110.00, 146.83,
	]

	var step_len := 0.25
	var step_samples := int(step_len * float(MIX_RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var sr := float(MIX_RATE)

	for step_idx in 32:
		var start_i := step_idx * step_samples
		var end_i := mini(count, start_i + step_samples)
		var lead_freq: float = lead_notes[step_idx]
		var bass_freq: float = bass_roots[step_idx]
		var has_hat := (step_idx % 2 == 1)
		var has_kick := (step_idx % 4 == 0)
		var local_len := end_i - start_i
		var hp_prev := 0.0
		var noise_prev := 0.0
		for j in local_len:
			var t := float(j) / sr
			var atk := clampf(t / 0.006, 0.0, 1.0)
			var lead_env := atk * exp(-t * 7.5)
			var lead := (sin(TAU * lead_freq * t) + 0.35 * sin(TAU * lead_freq * 2.0 * t)) * lead_env * 0.24

			var bass_env := clampf(t / 0.005, 0.0, 1.0) * exp(-t * 5.2)
			var bass := (sin(TAU * bass_freq * t) + 0.22 * sin(TAU * bass_freq * 3.0 * t)) * bass_env * 0.28

			var perc := 0.0
			if has_kick and t < 0.14:
				var k_freq := lerpf(135.0, 46.0, clampf(t / 0.08, 0.0, 1.0))
				perc += sin(TAU * k_freq * t) * exp(-t * 24.0) * 0.26
			if has_hat and t < 0.055:
				var wn := rng.randf_range(-1.0, 1.0)
				hp_prev = 0.72 * (hp_prev + wn - noise_prev)
				noise_prev = wn
				perc += hp_prev * exp(-t * 68.0) * 0.16

			samples[start_i + j] = clampf(lead + bass + perc, -0.85, 0.85)

	var half_count := count >> 1
	for i in mini(LOOP_EDGE_FADE_SAMPLES, half_count):
		var edge_w := float(i) / float(LOOP_EDGE_FADE_SAMPLES)
		samples[i] *= edge_w
		samples[count - 1 - i] *= edge_w

	return samples


func _bake_slide_loop() -> PackedFloat32Array:
	var duration := 2.0
	var overlap := 2205
	var count := int(duration * float(MIX_RATE))
	var raw_count := count + overlap
	var raw := PackedFloat32Array()
	raw.resize(raw_count)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4201
	var lp := 0.0
	var hp := 0.0
	var prev_in := 0.0

	for i in raw_count:
		var wn := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, wn, 0.36)
		hp = 0.84 * (hp + lp - prev_in)
		prev_in = lp
		raw[i] = clampf(hp * 0.75, -0.85, 0.85)

	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		if i < overlap:
			var w := float(i) / float(overlap)
			samples[i] = raw[i] * w + raw[count + i] * (1.0 - w)
		else:
			samples[i] = raw[i]
	return samples


func _bake_boost() -> PackedFloat32Array:
	var duration := 0.42
	var count := int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var sr := float(MIX_RATE)
	var phase_a := 0.0
	var phase_b := 0.0
	for i in count:
		var t := float(i) / sr
		var p := t / duration
		var freq := lerpf(320.0, 980.0, p * p)
		phase_a += TAU * freq / sr
		phase_b += TAU * (freq * 1.5) / sr
		var env := clampf(t / 0.015, 0.0, 1.0) * pow(1.0 - p, 1.35)
		var chime := sin(TAU * 1174.66 * t) * exp(-maxf(0.0, t - 0.05) * 11.0) * 0.25 if t >= 0.05 else 0.0
		samples[i] = (sin(phase_a) * 0.45 + sin(phase_b) * 0.25) * env + chime
	return samples


func _bake_shield_pickup() -> PackedFloat32Array:
	var duration := 0.34
	var count := int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var sr := float(MIX_RATE)
	for i in count:
		var t := float(i) / sr
		var val := 0.0
		# Crystalline two-tone arpeggio: A5 -> E6
		var t1_env := clampf(t / 0.008, 0.0, 1.0) * exp(-t * 10.0)
		val += (sin(TAU * 880.0 * t) * 0.42 + sin(TAU * 1760.0 * t) * 0.18) * t1_env
		if t >= 0.09:
			var t2 := t - 0.09
			var t2_env := clampf(t2 / 0.008, 0.0, 1.0) * exp(-t2 * 9.0)
			val += (sin(TAU * 1318.51 * t2) * 0.46 + sin(TAU * 2637.02 * t2) * 0.16) * t2_env
		samples[i] = clampf(val, -0.9, 0.9)
	return samples


func _bake_shield_break() -> PackedFloat32Array:
	var duration := 0.38
	var count := int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var sr := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var sub_phase := 0.0
	var hp := 0.0
	var prev_wn := 0.0
	for i in count:
		var t := float(i) / sr
		var p := t / duration
		var sub_f := lerpf(135.0, 42.0, clampf(t / 0.18, 0.0, 1.0))
		sub_phase += TAU * sub_f / sr
		var thump := sin(sub_phase) * exp(-t * 14.0) * 0.55

		var wn := rng.randf_range(-1.0, 1.0)
		hp = 0.65 * (hp + wn - prev_wn)
		prev_wn = wn
		var shatter_env := exp(-t * 15.0) * clampf(1.0 - p, 0.0, 1.0)
		var glass_pings := (
			sin(TAU * 1940.0 * t) * 0.25 +
			sin(TAU * 2820.0 * t) * 0.22 +
			sin(TAU * 3680.0 * t) * 0.18 +
			hp * 0.35
		) * shatter_env
		samples[i] = clampf(thump + glass_pings, -0.95, 0.95)
	return samples


func _bake_ramp_launch() -> PackedFloat32Array:
	var duration := 0.36
	var count := int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var sr := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	var phase := 0.0
	var lp := 0.0
	for i in count:
		var t := float(i) / sr
		var p := t / duration
		var freq := lerpf(190.0, 560.0, p)
		phase += TAU * freq / sr
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), lerpf(0.08, 0.42, p))
		var env := clampf(t / 0.02, 0.0, 1.0) * pow(1.0 - p, 1.2)
		samples[i] = clampf((sin(phase) * 0.38 + lp * 0.45) * env, -0.9, 0.9)
	return samples


func _bake_landing() -> PackedFloat32Array:
	var duration := 0.18
	var count := int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var sr := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5502
	var phase := 0.0
	var lp := 0.0
	for i in count:
		var t := float(i) / sr
		var p := t / duration
		var freq := lerpf(145.0, 48.0, clampf(p * 1.4, 0.0, 1.0))
		phase += TAU * freq / sr
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.28)
		var thump := sin(phase) * exp(-t * 22.0) * 0.62
		var crunch := lp * exp(-t * 28.0) * 0.32
		samples[i] = clampf(thump + crunch, -0.9, 0.9)
	return samples


func _bake_biome_transition() -> PackedFloat32Array:
	var duration := 1.20
	var count := int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var sr := float(MIX_RATE)
	for i in count:
		var t := float(i) / sr
		var atk := clampf(t / 0.012, 0.0, 1.0)
		var bell := (
			sin(TAU * 293.66 * t) * 0.42 * exp(-t * 2.4) +
			sin(TAU * 587.33 * t) * 0.24 * exp(-t * 3.1) +
			sin(TAU * 810.50 * t) * 0.14 * exp(-t * 4.5) +
			sin(TAU * 1116.00 * t) * 0.08 * exp(-t * 6.0)
		) * atk
		var chime := 0.0
		if t >= 0.06:
			var tc1 := t - 0.06
			chime += sin(TAU * 880.0 * tc1) * clampf(tc1 / 0.01, 0.0, 1.0) * exp(-tc1 * 5.0) * 0.22
		if t >= 0.18:
			var tc2 := t - 0.18
			chime += sin(TAU * 1174.66 * tc2) * clampf(tc2 / 0.01, 0.0, 1.0) * exp(-tc2 * 4.5) * 0.24
		samples[i] = clampf(bell + chime, -0.95, 0.95)
	return samples


func _bake_crash() -> PackedFloat32Array:
	var duration := 0.55
	var count := int(duration * float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(count)
	var sr := float(MIX_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6610
	var tone_phase := 0.0
	var lp := 0.0
	for i in count:
		var t := float(i) / sr
		var p := t / duration
		var freq := 340.0
		if t > 0.14 and t <= 0.29:
			freq = 260.0
		elif t > 0.29:
			freq = 165.0
		tone_phase += TAU * freq / sr
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.25)
		var tone := clampf(sin(tone_phase) * 1.4, -0.8, 0.8) * exp(-t * 3.6) * 0.42
		var impact := lp * exp(-t * 16.0) * 0.48
		samples[i] = clampf((tone + impact) * clampf(1.0 - p * 0.5, 0.0, 1.0), -0.95, 0.95)
	return samples
