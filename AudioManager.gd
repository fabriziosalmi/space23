extends Node
class_name AudioManager

var sfx_players = []
var audio_stream_player: AudioStreamPlayer
var audio_bus_idx: int
var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var audio_low: float = 0.0
var audio_mid: float = 0.0
var audio_high: float = 0.0

var playlist = [
	{
		"file": "res://1.mp3",
		"drop_time": 26.0,
		"colors": [Color(0.005, 0.0, 0.015), Color(0.05, 0.01, 0.1), Color(0.0, 0.05, 0.15)]
	},
	{
		"file": "res://2.mp3",
		"drop_time": 44.0,
		"colors": [Color(0.015, 0.0, 0.005), Color(0.1, 0.01, 0.05), Color(0.15, 0.05, 0.0)]
	},
	{
		"file": "res://3.mp3",
		"drop_time": 32.0,
		"colors": [Color(0.0, 0.015, 0.005), Color(0.01, 0.1, 0.05), Color(0.05, 0.15, 0.0)]
	}
]
var current_track_idx = 0

var is_transitioning = false
var transition_timer = 0.0

func _ready():
	audio_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(audio_bus_idx)
	AudioServer.set_bus_name(audio_bus_idx, "MusicBus")
	AudioServer.set_bus_send(audio_bus_idx, "Master")
	
	var spectrum = AudioEffectSpectrumAnalyzer.new()
	spectrum.buffer_length = 0.1
	AudioServer.add_bus_effect(audio_bus_idx, spectrum)
	spectrum_analyzer = AudioServer.get_bus_effect_instance(audio_bus_idx, 0)
	
	audio_stream_player = AudioStreamPlayer.new()
	audio_stream_player.bus = "MusicBus"
	audio_stream_player.finished.connect(_on_song_finished)
	add_child(audio_stream_player)
	
	for i in range(8):
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		sfx_players.append(p)

func _process(delta):
	if spectrum_analyzer:
		var mag_low = spectrum_analyzer.get_magnitude_for_frequency_range(20, 250).length()
		var mag_mid = spectrum_analyzer.get_magnitude_for_frequency_range(250, 2000).length()
		var mag_high = spectrum_analyzer.get_magnitude_for_frequency_range(2000, 10000).length()
		audio_low = lerp(audio_low, clamp(mag_low * 2.0, 0.0, 1.0), 10.0 * delta)
		audio_mid = lerp(audio_mid, clamp(mag_mid * 2.0, 0.0, 1.0), 10.0 * delta)
		audio_high = lerp(audio_high, clamp(mag_high * 2.0, 0.0, 1.0), 10.0 * delta)

func load_and_play_track(idx: int):
	current_track_idx = idx
	var track = playlist[idx]
	var stream = load(track.file)
	audio_stream_player.stream = stream
	audio_stream_player.play()

func play_sfx(pitch: float, volume: float = 0.0):
	for p in sfx_players:
		if not p.playing and audio_stream_player.stream != null:
			p.stream = audio_stream_player.stream 
			p.pitch_scale = pitch
			p.volume_db = volume
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
