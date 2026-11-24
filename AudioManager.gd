extends Node
class_name AudioManager

var sfx_players = []
var sfx_timers: PackedFloat32Array = PackedFloat32Array()
var _sfx_bank: Dictionary = {}
var _track_cache: Dictionary = {}
var _preloading_path: String = ""
var audio_stream_player: AudioStreamPlayer
var audio_bus_idx: int
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var audio_low: float = 0.0
var audio_mid: float = 0.0
var audio_high: float = 0.0

# BPM grid telemetry (updated every frame from playback position)
var beat_phase: float = 0.0         # 0.0..1.0 within current quarter-note beat
var beat_triggered: bool = false    # true on the exact frame a quarter-note beat lands
var half_beat_triggered: bool = false
var _last_beat_idx: int = -1
var _last_half_beat_idx: int = -1

# Settato da Main dopo che la camera esiste. Usato come "listener" per il pan
# stereo degli SFX 2D: una posizione = quella della camera ⇒ pan centrato.
var camera_ref: Node2D = null

# BPM di fallback per le tracce che non lo dichiarano. 130 era il valore
# hardcoded prima del fix track-keyed (sintetizzato come "techno medio").
const DEFAULT_BPM: float = 130.0

var playlist = [
	{
		"file": "res://1.ogg",
		"drop_time": 26.0,
		"bpm": 130.0,
		# Track 1: viola/blu (mood notturno techno).  3x brighter degli originali
		# cosi' la nebula resta visibile anche tra una cassa e l'altra.
		"colors": [Color(0.015, 0.0, 0.045), Color(0.15, 0.03, 0.3), Color(0.0, 0.15, 0.45)]
	},
	{
		"file": "res://2.ogg",
		"drop_time": 44.0,
		"bpm": 130.0,
		# Track 2: rosso/arancio (mood acido caldo).
		"colors": [Color(0.045, 0.0, 0.015), Color(0.3, 0.03, 0.15), Color(0.45, 0.15, 0.0)]
	},
	{
		"file": "res://3.ogg",
		"drop_time": 32.0,
		"bpm": 130.0,
		# Track 3: verde (mood industrial cyberpunk).
		"colors": [Color(0.0, 0.045, 0.015), Color(0.03, 0.3, 0.15), Color(0.15, 0.45, 0.0)]
	},
	{
		"file": "res://4.ogg",
		"drop_time": 40.0,  # 145 BPM × 32 bar ≈ 53s; estimate 40s — adjust on play
		"bpm": 145.0,
		# Track 4: ciano profondo (deep ocean / nebula blue).
		"colors": [Color(0.0, 0.03, 0.06), Color(0.0, 0.18, 0.4), Color(0.05, 0.4, 0.55)]
	},
	{
		"file": "res://5.ogg",
		"drop_time": 33.0,  # 145 BPM × ~20 bar
		"bpm": 145.0,
		# Track 5: ambra / coral (warm sunset).
		"colors": [Color(0.06, 0.02, 0.0), Color(0.4, 0.18, 0.05), Color(0.6, 0.3, 0.1)]
	},
	{
		"file": "res://6.ogg",
		"drop_time": 27.0,  # 145 BPM × 16 bar ≈ 26.5s
		"bpm": 145.0,
		# Track 6: magenta / cosmic violet.
		"colors": [Color(0.04, 0.0, 0.05), Color(0.3, 0.05, 0.4), Color(0.5, 0.1, 0.6)]
	}
]
var current_track_idx = 0

var is_transitioning = false
var transition_timer = 0.0

func _ready():
	# Bus layout caricato da default_bus_layout.tres (Master con SpectrumAnalyzer
	# all'effect index 0). Critico per il web export: Godot 4 ha un bug per cui
	# i bus aggiunti runtime via AudioServer.add_bus() / set_bus_send() NON
	# vengono routati nel build web → audio totalmente silente, anche se
	# l'AudioContext è running. Definendoli nella resource il problema sparisce.
	#   ref: https://github.com/godotengine/godot/issues/115560
	#   thread godot forum: "no audio in web export" (mar 2025)
	audio_bus_idx = 0  # Master
	spectrum_analyzer = AudioServer.get_bus_effect_instance(audio_bus_idx, 0)

	audio_stream_player = AudioStreamPlayer.new()
	audio_stream_player.bus = "Master"
	audio_stream_player.finished.connect(_on_song_finished)
	add_child(audio_stream_player)
	
	# SFX poolati come AudioStreamPlayer2D: il pan stereo viene dalla position
	# relativa alla Camera2D attiva (Godot la usa come listener di default in 2D).
	# attenuation = 0 ⇒ nessun falloff con distanza (gli SFX restano sempre alla
	# loudness richiesta), max_distance generoso, panning_strength morbido (0.6)
	# per non sbattere troppo da un orecchio all'altro.
	sfx_timers.resize(8)
	sfx_timers.fill(0.0)
	for i in range(8):
		var p = AudioStreamPlayer2D.new()
		p.bus = "Master"
		p.attenuation = 0.0
		p.max_distance = 5000.0
		p.panning_strength = 0.6
		add_child(p)
		sfx_players.append(p)
	_build_sfx_bank()

func _process(delta):
	# Tick fixed SFX slot timers (zero SceneTreeTimer allocations per shot).
	for i in range(sfx_timers.size()):
		if sfx_timers[i] > 0.0:
			sfx_timers[i] -= delta
			if sfx_timers[i] <= 0.0:
				sfx_timers[i] = 0.0
				sfx_players[i].stop()

	# Spectrum reading: works fine on desktop Godot, but on Godot 4 web export
	# AudioEffectSpectrumAnalyzer often returns near-zero magnitudes despite
	# audio playing (known limitation: WebAudio chain doesn't always feed the
	# effect properly). Without a fallback the nebula goes static on Pages.
	#
	# Strategy: read the spectrum, BUT also synthesise a fallback "beat" from
	# the music playback position. If the spectrum is alive, the real beats
	# dominate; if it's dead (web), the synth carries the reactivity at the
	# track's actual BPM (declared in playlist[], DEFAULT_BPM if missing).
	var mag_low: float = 0.0
	var mag_mid: float = 0.0
	var mag_high: float = 0.0
	if spectrum_analyzer:
		mag_low = spectrum_analyzer.get_magnitude_for_frequency_range(20, 250).length()
		mag_mid = spectrum_analyzer.get_magnitude_for_frequency_range(250, 2000).length()
		mag_high = spectrum_analyzer.get_magnitude_for_frequency_range(2000, 10000).length()

	var real_low: float = clamp(mag_low * 6.0, 0.0, 1.0)
	var real_mid: float = clamp(mag_mid * 6.0, 0.0, 1.0)
	var real_high: float = clamp(mag_high * 6.0, 0.0, 1.0)

	# Synth fallback: pulse derived dalla BPM della traccia corrente, tramite
	# playback position. Solo attivo quando la musica suona — TITLE/silenzio
	# resta calmo. Prima del fix track-keyed era hardcoded 130 BPM; tracce 4-6
	# (145 BPM) andavano fuori-fase su WebGL Compatibility.
	var synth_low: float = 0.0
	var synth_mid: float = 0.0
	var synth_high: float = 0.0
	beat_triggered = false
	half_beat_triggered = false
	if audio_stream_player and audio_stream_player.playing:
		var t: float = audio_stream_player.get_playback_position()
		var bps: float = get_current_bpm() / 60.0  # beats per second
		var beat: float = t * bps  # phase in cycles (1.0 = un beat completo)
		var b_idx: int = int(floor(beat))
		var hb_idx: int = int(floor(beat * 2.0))
		if b_idx != _last_beat_idx:
			_last_beat_idx = b_idx
			beat_triggered = true
		if hb_idx != _last_half_beat_idx:
			_last_half_beat_idx = hb_idx
			half_beat_triggered = true
		# Sharp bass kick: pow makes the pulse spiky instead of sinusoidal
		var b_phase: float = fmod(beat, 1.0)
		beat_phase = b_phase
		synth_low = pow(1.0 - b_phase, 3.0) * 0.7  # decays from 0.7 to 0
		# Mid: rolling 8th-note pulse (2 cicli per beat = 4π = 12.566 rad)
		synth_mid = (0.5 + 0.5 * sin(beat * TAU * 2.0)) * 0.45
		# High: rapid 16th hi-hat pulse (4 cicli per beat = 8π = 25.133 rad)
		synth_high = (0.5 + 0.5 * sin(beat * TAU * 4.0)) * 0.35
	else:
		_last_beat_idx = -1
		_last_half_beat_idx = -1
		beat_phase = 0.0

	# Take max of real and synth: spectrum-driven peaks win when alive, synth
	# floors the value when spectrum is dead (web).
	audio_low = lerp(audio_low, max(real_low, synth_low), 18.0 * delta)
	audio_mid = lerp(audio_mid, max(real_mid, synth_mid), 18.0 * delta)
	audio_high = lerp(audio_high, max(real_high, synth_high), 18.0 * delta)

func _get_or_load_track(path: String) -> AudioStream:
	if _track_cache.has(path):
		return _track_cache[path]
	var stream: AudioStream = null
	if _preloading_path == path:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			stream = ResourceLoader.load_threaded_get(path)
		_preloading_path = ""
	if stream == null:
		stream = load(path)
	if stream != null:
		_track_cache[path] = stream
	return stream

func _preload_next_track(idx: int) -> void:
	if playlist.is_empty():
		return
	var next_idx: int = (idx + 1) % playlist.size()
	var next_path: String = playlist[next_idx].file
	if _track_cache.has(next_path) or _preloading_path == next_path:
		return
	if ResourceLoader.load_threaded_request(next_path, "AudioStream") == OK:
		_preloading_path = next_path

func load_and_play_track(idx: int):
	current_track_idx = idx
	var track = playlist[idx]
	audio_stream_player.stream = _get_or_load_track(track.file)
	audio_stream_player.play()
	_preload_next_track(idx)

# Procedural PCM WAV synthesizer (22050 Hz, 16-bit mono). Generated once at
# boot (< 60 KB total RAM) so SFX have zero OGG-seek latency, consistent punch,
# and crisp separation from the music mix on both desktop and WebAssembly.
const _SFX_SR: int = 22050

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n: int = samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var v: int = clampi(int(samples[i] * 32767.0), -32768, 32767)
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _SFX_SR
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_chirp(dur: float, f0: float, f1: float, amp: float, noise_mix: float = 0.0, decay_pow: float = 2.0) -> AudioStreamWAV:
	var n: int = int(dur * _SFX_SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 17.0 + f1 * 3.0)
	for i in range(n):
		var u: float = float(i) / float(n)
		var env: float = pow(1.0 - u, decay_pow) * min(1.0, float(i) / 40.0)
		var freq: float = lerpf(f0, f1, pow(u, 0.65))
		phase += TAU * freq / float(_SFX_SR)
		var tone: float = sin(phase)
		var s: float = tone * (1.0 - noise_mix) + rng.randf_range(-1.0, 1.0) * noise_mix
		buf[i] = clampf(s * env * amp, -1.0, 1.0)
	return _make_wav(buf)

func _synth_arpeggio(dur: float, f0: float, f1: float, amp: float) -> AudioStreamWAV:
	var n: int = int(dur * _SFX_SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase: float = 0.0
	var half: int = n >> 1
	for i in range(n):
		var u: float = float(i) / float(n)
		var freq: float = f0 if i < half else f1
		phase += TAU * freq / float(_SFX_SR)
		var env: float = pow(1.0 - u, 1.5) * min(1.0, float(i) / 30.0)
		buf[i] = clampf((sin(phase) * 0.75 + sin(phase * 2.0) * 0.25) * env * amp, -1.0, 1.0)
	return _make_wav(buf)

func _build_sfx_bank() -> void:
	_sfx_bank = {
		"shoot":     _synth_chirp(0.055, 1350.0, 340.0, 0.28, 0.06, 2.2),
		"graze":     _synth_arpeggio(0.050, 2600.0, 3900.0, 0.30),
		"hit":       _synth_chirp(0.140, 190.0, 42.0, 0.72, 0.28, 1.6),
		"kill":      _synth_chirp(0.130, 420.0, 85.0, 0.50, 0.35, 1.9),
		"bomb":      _synth_chirp(0.360, 145.0, 26.0, 0.85, 0.32, 1.3),
		"dash":      _synth_chirp(0.120, 280.0, 880.0, 0.35, 0.40, 1.7),
		"pickup":    _synth_arpeggio(0.150, 523.25, 783.99, 0.45),
		"railgun":   _synth_chirp(0.200, 960.0, 90.0, 0.65, 0.35, 1.5),
		"charge":    _synth_chirp(0.110, 580.0, 1760.0, 0.38, 0.05, 1.4),
		"heartbeat": _synth_chirp(0.110, 72.0, 42.0, 0.55, 0.0, 2.5),
	}

func _infer_sfx_kind(pitch: float, volume: float) -> String:
	if pitch >= 2.8 and volume <= -8.0:
		return "shoot"
	if pitch >= 2.4 and volume >= 3.0:
		return "pickup"
	if pitch >= 2.3:
		return "charge"
	if pitch >= 1.8 and volume >= 3.0:
		return "pickup"
	if pitch <= 0.25 and volume >= 4.0:
		return "bomb"
	if pitch <= 0.45 and volume <= -10.0:
		return "heartbeat"
	if pitch <= 0.45:
		return "hit"
	return "kill"

func is_on_beat(tolerance_phase: float = 0.16) -> bool:
	if not (audio_stream_player and audio_stream_player.playing):
		return false
	return beat_phase <= tolerance_phase or beat_phase >= (1.0 - tolerance_phase)

# Riproduce un SFX sintetizzato dal bank PCM con pan stereo 2D.
# `kind` opzionale: se omesso viene inferito da pitch/volume per piena
# retrocompatibilità coi call-site esistenti.
# `pitch_override` > 0 forza un pitch esatto (es. scala pentatonica su graze).
func play_sfx(pitch: float, volume: float = 0.0, pos: Vector2 = Vector2.INF, kind: String = "", pitch_override: float = -1.0):
	var key: String = kind if kind != "" and _sfx_bank.has(kind) else _infer_sfx_kind(pitch, volume)
	var stream: AudioStreamWAV = _sfx_bank.get(key, null)
	if stream == null:
		return
	var dur: float = stream.get_length()
	for i in range(sfx_players.size()):
		if sfx_timers[i] <= 0.0:
			var p: AudioStreamPlayer2D = sfx_players[i]
			p.stream = stream
			p.pitch_scale = pitch_override if pitch_override > 0.0 else randf_range(0.96, 1.04)
			p.volume_db = clampf(volume, -18.0, 3.0)
			if pos.x != INF and camera_ref != null:
				p.global_position = pos
			elif camera_ref != null:
				p.global_position = camera_ref.global_position
			p.play()
			sfx_timers[i] = dur + 0.02
			break

func get_playback_position() -> float:
	return audio_stream_player.get_playback_position()

func get_current_drop_time() -> float:
	return playlist[current_track_idx].drop_time

func get_current_bpm() -> float:
	return playlist[current_track_idx].get("bpm", DEFAULT_BPM)

func _on_song_finished():
	is_transitioning = true
	transition_timer = 5.0
