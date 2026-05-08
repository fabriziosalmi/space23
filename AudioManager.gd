extends Node
class_name AudioManager

var sfx_players = []
var audio_stream_player: AudioStreamPlayer
var audio_bus_idx: int
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var audio_low: float = 0.0
var audio_mid: float = 0.0
var audio_high: float = 0.0

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
	for i in range(8):
		var p = AudioStreamPlayer2D.new()
		p.bus = "Master"
		p.attenuation = 0.0
		p.max_distance = 5000.0
		p.panning_strength = 0.6
		add_child(p)
		sfx_players.append(p)

func _process(delta):
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
	if audio_stream_player and audio_stream_player.playing:
		var t: float = audio_stream_player.get_playback_position()
		var bps: float = get_current_bpm() / 60.0  # beats per second
		var beat: float = t * bps  # phase in cycles (1.0 = un beat completo)
		# Sharp bass kick: pow makes the pulse spiky instead of sinusoidal
		var b_phase: float = fmod(beat, 1.0)
		synth_low = pow(1.0 - b_phase, 3.0) * 0.7  # decays from 0.7 to 0
		# Mid: rolling 8th-note pulse (2 cicli per beat = 4π = 12.566 rad)
		synth_mid = (0.5 + 0.5 * sin(beat * TAU * 2.0)) * 0.45
		# High: rapid 16th hi-hat pulse (4 cicli per beat = 8π = 25.133 rad)
		synth_high = (0.5 + 0.5 * sin(beat * TAU * 4.0)) * 0.35

	# Take max of real and synth: spectrum-driven peaks win when alive, synth
	# floors the value when spectrum is dead (web).
	audio_low = lerp(audio_low, max(real_low, synth_low), 18.0 * delta)
	audio_mid = lerp(audio_mid, max(real_mid, synth_mid), 18.0 * delta)
	audio_high = lerp(audio_high, max(real_high, synth_high), 18.0 * delta)

func load_and_play_track(idx: int):
	current_track_idx = idx
	var track = playlist[idx]
	var stream = load(track.file)
	audio_stream_player.stream = stream
	audio_stream_player.play()

# Riusa la traccia musicale corrente come fonte di SFX, scegliendo un offset
# random tra 10s e 20s di playback come "snippet". È una scelta di design
# intenzionale (concatenative-synth-poor-man's): gli SFX risuonano sempre
# armonicamente con la musica, non sono campioni indipendenti.
# `pos` opzionale: se passata, l'SFX pana stereo in base alla posizione relativa
# alla camera (che Godot 4 usa come listener 2D). Senza `pos`, viene allineato
# alla camera ⇒ centrato (no pan).
func play_sfx(pitch: float, volume: float = 0.0, pos: Vector2 = Vector2.INF):
	for p in sfx_players:
		if not p.playing and audio_stream_player.stream != null:
			p.stream = audio_stream_player.stream
			p.pitch_scale = pitch
			p.volume_db = volume
			# Posizione: pos esplicita se valida, altrimenti listener (camera).
			if pos.x != INF and camera_ref != null:
				p.global_position = pos
			elif camera_ref != null:
				p.global_position = camera_ref.global_position
			p.play(randf_range(10.0, 20.0))
			get_tree().create_timer(0.1).timeout.connect(p.stop)
			break

func get_playback_position() -> float:
	return audio_stream_player.get_playback_position()

func get_current_drop_time() -> float:
	return playlist[current_track_idx].drop_time

func get_current_bpm() -> float:
	return playlist[current_track_idx].get("bpm", DEFAULT_BPM)

func set_pitch_scale(scale: float):
	audio_stream_player.pitch_scale = scale
	
func get_pitch_scale() -> float:
	return audio_stream_player.pitch_scale

func _on_song_finished():
	is_transitioning = true
	transition_timer = 5.0
