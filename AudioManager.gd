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

var playlist = [
	{
		"file": "res://1.ogg",
		"drop_time": 26.0,
		# Track 1: viola/blu (mood notturno techno).  3x brighter degli originali
		# cosi' la nebula resta visibile anche tra una cassa e l'altra.
		"colors": [Color(0.015, 0.0, 0.045), Color(0.15, 0.03, 0.3), Color(0.0, 0.15, 0.45)]
	},
	{
		"file": "res://2.ogg",
		"drop_time": 44.0,
		# Track 2: rosso/arancio (mood acido caldo).
		"colors": [Color(0.045, 0.0, 0.015), Color(0.3, 0.03, 0.15), Color(0.45, 0.15, 0.0)]
	},
	{
		"file": "res://3.ogg",
		"drop_time": 32.0,
		# Track 3: verde (mood industrial cyberpunk).
		"colors": [Color(0.0, 0.045, 0.015), Color(0.03, 0.3, 0.15), Color(0.15, 0.45, 0.0)]
	},
	{
		"file": "res://4.ogg",
		"drop_time": 40.0,  # 145 BPM × 32 bar ≈ 53s; estimate 40s — adjust on play
		# Track 4: ciano profondo (deep ocean / nebula blue).
		"colors": [Color(0.0, 0.03, 0.06), Color(0.0, 0.18, 0.4), Color(0.05, 0.4, 0.55)]
	},
	{
		"file": "res://5.ogg",
		"drop_time": 33.0,  # 145 BPM × ~20 bar
		# Track 5: ambra / coral (warm sunset).
		"colors": [Color(0.06, 0.02, 0.0), Color(0.4, 0.18, 0.05), Color(0.6, 0.3, 0.1)]
	},
	{
		"file": "res://6.ogg",
		"drop_time": 27.0,  # 145 BPM × 16 bar ≈ 26.5s
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
	if spectrum_analyzer:
		var mag_low = spectrum_analyzer.get_magnitude_for_frequency_range(20, 250).length()
		var mag_mid = spectrum_analyzer.get_magnitude_for_frequency_range(250, 2000).length()
		var mag_high = spectrum_analyzer.get_magnitude_for_frequency_range(2000, 10000).length()
		# Gain × 6 + lerp 18 (era × 4 / lerp 10): i raw magnitudes da
		# SpectrumAnalyzer in Godot sono in 0.05-0.3 per musica normale, anche
		# con × 4 i beat sui peak non saturavano abbastanza per produrre nubi
		# "che cambiano colore". × 6 + clamp e attack più snappy garantisce che
		# bass/mid/high abbiano dynamic range pieno [0..1], così il shader può
		# disegnare bande visualmente distinte (red/cyan/pink).
		audio_low = lerp(audio_low, clamp(mag_low * 6.0, 0.0, 1.0), 18.0 * delta)
		audio_mid = lerp(audio_mid, clamp(mag_mid * 6.0, 0.0, 1.0), 18.0 * delta)
		audio_high = lerp(audio_high, clamp(mag_high * 6.0, 0.0, 1.0), 18.0 * delta)

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
	
func set_pitch_scale(scale: float):
	audio_stream_player.pitch_scale = scale
	
func get_pitch_scale() -> float:
	return audio_stream_player.pitch_scale

func _on_song_finished():
	is_transitioning = true
	transition_timer = 5.0
