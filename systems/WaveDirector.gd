extends Node
class_name WaveDirector

# Decide quando e cosa spawnare nel tempo. Legge `waves.json` (formato dict
# con `waves` e `fillers`, oppure array legacy). Filtra per `min_distance`,
# shuffla la queue, inietta filler ogni ~2 wave per evitare pattern prevedibili.

const FILLER_INJECT_CHANCE: float = 0.4
const FILLER_MIN_GAP: int = 2  # quante wave principali prima di iniettare un filler

var waves_pool: Array = []
var fillers_pool: Array = []
var wave_queue: Array = []
var waves_since_filler: int = 0
var wave_index: int = 0
var wave_timer: float = 3.0

# Refs (settate da Main in _ready)
var enemy_system: EnemySystem
var audio_manager: Node  # opzionale; se valorizzato, il pacing si accoppia alla traccia

# Phase coupling con la musica:
#  - BUILD-UP (3s prima del drop): rallenta gli spawn, costruisce tensione.
#  - DROP-HIT (1s dopo il drop): force-spawn quasi-istantaneo, raffica.
#  - POST-DROP CALM (3-6s dopo drop): lieve rallentamento, "post-orgasmo".
#  - NORMAL: pacing standard.
const PHASE_BUILDUP_LEAD: float = 3.0
const PHASE_DROP_HIT_WINDOW: float = 1.0
const PHASE_POST_DROP_START: float = 3.0
const PHASE_POST_DROP_END: float = 6.0

# One-shot guard del drop, keyed sull'indice della traccia. -1 = non sparato.
# Era un bool; il bool poteva restare "stuck" se la pos faceva jitter o se
# si saltava traccia mentre il flag era true. Memorizzando l'indice, il flag
# si invalida automaticamente al cambio traccia, e la doppia reset path
# (buildup branch + deep normal/pre branch) gestisce loop e seek.
var _drop_fired_for_track: int = -1

func load_from_json(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data = json.get_data()
	if typeof(data) == TYPE_ARRAY:
		# Backward compat: array semplice = lista wave senza fillers
		waves_pool = data
		fillers_pool = []
	elif typeof(data) == TYPE_DICTIONARY:
		waves_pool = data.get("waves", [])
		fillers_pool = data.get("fillers", [])

func reset(initial_timer: float = 3.0) -> void:
	wave_queue = []
	waves_since_filler = 0
	wave_index = 0
	wave_timer = initial_timer
	_drop_fired_for_track = -1

func tick(delta: float, distance: float, screen_size: Vector2) -> void:
	# Phase coupling con la musica: il vero "AI Director" è la traccia. Calcoliamo
	# un moltiplicatore sulla wave_timer in base a dove siamo nel brano.
	var phase_mult: float = 1.0
	var phase: String = "normal"
	if audio_manager and audio_manager.audio_stream_player and audio_manager.audio_stream_player.stream:
		var current_idx: int = audio_manager.current_track_idx
		# Track change auto-invalidates the drop guard: la nuova traccia ha il
		# suo drop_time e deve poter fire-are indipendentemente da cosa è
		# successo nella precedente.
		if _drop_fired_for_track != -1 and _drop_fired_for_track != current_idx:
			_drop_fired_for_track = -1

		var pos: float = audio_manager.get_playback_position()
		var drop: float = audio_manager.get_current_drop_time()
		var dt: float = pos - drop  # offset dal drop (negativo = pre-drop)
		if dt < 0.0 and dt > -PHASE_BUILDUP_LEAD:
			phase = "buildup"
			phase_mult = 1.5  # rallenta spawn → tensione, anticipazione
			_drop_fired_for_track = -1
		elif dt >= 0.0 and dt < PHASE_DROP_HIT_WINDOW:
			phase = "drop"
			# Force-spawn one-shot al primo frame post-drop: butta in arena una raffica.
			# Guard track-keyed: se è già stato sparato per questa traccia, skip.
			if _drop_fired_for_track != current_idx:
				_drop_fired_for_track = current_idx
				wave_timer = 0.0  # consumiamo subito una wave
			phase_mult = 0.6  # spawn più frequenti durante il drop
		elif dt >= PHASE_POST_DROP_START and dt < PHASE_POST_DROP_END:
			phase = "post_drop"
			phase_mult = 1.3  # leggero respiro dopo l'orgasmo
		else:
			# Reset del guard solo quando siamo "deep pre" (prima del buildup,
			# es. seek indietro o loop) o "deep normal" (post post-drop, ready
			# per un eventuale secondo drop event della traccia). NON resettare
			# nel transitorio [DROP_HIT_WINDOW, POST_DROP_START] = [1.0, 3.0):
			# se la pos jitter-asse brevemente in dietro nel drop window, un
			# reset qui causerebbe un re-fire indesiderato.
			if dt < -PHASE_BUILDUP_LEAD or dt >= PHASE_POST_DROP_END:
				_drop_fired_for_track = -1

	wave_timer -= delta
	if wave_timer > 0:
		return
	var diff: float = Main.diff_for_distance(distance)
	var w_data = _next_wave(distance)
	if w_data == null:
		# Nessuna wave disponibile (es. distance=0 e tutte filtrate): riprova presto.
		wave_timer = 1.0
		return
	wave_timer = (float(w_data.get("delay", 5.0)) / clamp(diff * 0.5, 1.0, 3.0)) * phase_mult
	_spawn_pattern(w_data, diff, screen_size)
	wave_index += 1

func _build_wave_queue(distance: float) -> void:
	var available: Array = []
	for w in waves_pool:
		if distance >= float(w.get("min_distance", 0)):
			available.append(w)
	available.shuffle()
	wave_queue = available

func _next_wave(distance: float) -> Variant:
	waves_since_filler += 1
	if waves_since_filler >= FILLER_MIN_GAP and fillers_pool.size() > 0 and randf() < FILLER_INJECT_CHANCE:
		waves_since_filler = 0
		return fillers_pool[randi() % fillers_pool.size()]
	if wave_queue.is_empty():
		_build_wave_queue(distance)
	if wave_queue.is_empty():
		return null
	return wave_queue.pop_back()

func _spawn_pattern(w_data: Dictionary, diff: float, screen_size: Vector2) -> void:
	if not enemy_system:
		return
	var type: String = w_data.get("type", "v_shape")

	# Modifiers opzionali per variazione tra wave dello stesso pattern.
	var density: float = float(w_data.get("density", 1.0))
	var speed_mult: float = float(w_data.get("speed_mult", 1.0))
	var color_mod: Color = _parse_color(w_data.get("color_mod", null))
	var count: int = max(1, int(round(int(w_data.get("count", 1)) * density)))

	match type:
		"v_shape":
			var cx: float = randf_range(200, screen_size.x - 200)
			for w in range(count):
				var offset_x: float = (w - int(count / 2)) * 60
				var offset_y: float = abs(w - int(count / 2)) * -50
				enemy_system.spawn(0, Vector2(cx + offset_x, -100 + offset_y), diff, speed_mult, color_mod)
		"horizontal":
			var start_x: float = randf_range(100, screen_size.x - 300)
			for w in range(count):
				enemy_system.spawn(1, Vector2(start_x + w * 90, -100), diff, speed_mult, color_mod)
		"tank_escort":
			var cx: float = randf_range(200, screen_size.x - 200)
			enemy_system.spawn(2, Vector2(cx, -100), diff, speed_mult, color_mod)        # Tank
			enemy_system.spawn(0, Vector2(cx - 80, -60), diff, speed_mult, color_mod)    # Scout sx
			enemy_system.spawn(0, Vector2(cx + 80, -60), diff, speed_mult, color_mod)    # Scout dx
		"double_tank":
			enemy_system.spawn(2, Vector2(screen_size.x * 0.25, -100), diff, speed_mult, color_mod)
			enemy_system.spawn(2, Vector2(screen_size.x * 0.75, -100), diff, speed_mult, color_mod)
		"spinner":
			enemy_system.spawn(3, Vector2(screen_size.x / 2.0, -100), diff, speed_mult, color_mod)
		"invaders":
			var start_x_inv: float = (screen_size.x / 2.0) - ((count / 2) * 80)
			for w in range(count):
				enemy_system.spawn(4, Vector2(start_x_inv + w * 80, -100 - (w % 2) * 40), diff, speed_mult, color_mod)
		"octopus_grid":
			# 2 rows × N columns of OCTOPUS (#6), staggered.
			var cols: int = max(2, count / 2)
			var oct_x: float = (screen_size.x / 2.0) - (cols / 2.0) * 70.0
			for w in range(count):
				var row: int = int(w / cols)
				var col: int = w % cols
				enemy_system.spawn(6, Vector2(oct_x + col * 70 + row * 35, -100 - row * 70), diff, speed_mult, color_mod)
		"crab_line":
			# Wide horizontal CRAB (#7) line entering as a wall.
			var cstart_x: float = randf_range(120, screen_size.x - 120 - count * 100)
			for w in range(count):
				enemy_system.spawn(7, Vector2(cstart_x + w * 100, -100), diff, speed_mult, color_mod)
		"squid_swarm":
			# SQUID (#8) entering from random top-edge positions, fast scouts.
			for w in range(count):
				var sx: float = randf_range(80, screen_size.x - 80)
				var sy: float = -100.0 - randf_range(0, 200)
				enemy_system.spawn(8, Vector2(sx, sy), diff, speed_mult, color_mod)
		"mantis_dive":
			# MANTIS (#9) in a v-formation diving from the top.
			var mx: float = randf_range(250, screen_size.x - 250)
			for w in range(count):
				var ox: float = (w - int(count / 2)) * 80
				var oy: float = abs(w - int(count / 2)) * -60
				enemy_system.spawn(9, Vector2(mx + ox, -100 + oy), diff, speed_mult, color_mod)
		"dread_pair":
			# Two DREAD (#10) heavy walls converging.
			enemy_system.spawn(10, Vector2(screen_size.x * 0.3, -120), diff, speed_mult, color_mod)
			enemy_system.spawn(10, Vector2(screen_size.x * 0.7, -120), diff, speed_mult, color_mod)
		"sentinel_arc":
			# SENTINEL (#11) in a downward arc.
			var ax: float = screen_size.x / 2.0
			var radius: float = 220.0
			for w in range(count):
				var t: float = float(w) / max(1, count - 1)
				var ang: float = lerp(-PI / 3.0, PI / 3.0, t) + PI / 2.0  # arc opening downward
				var pos: Vector2 = Vector2(ax + cos(ang) * radius, -100.0 + sin(ang) * radius * 0.4)
				enemy_system.spawn(11, pos, diff, speed_mult, color_mod)

# Parser color_mod: accetta null (no tint), [r,g,b], [r,g,b,a].
func _parse_color(v) -> Color:
	if v == null:
		return Color(1, 1, 1, 1)
	if typeof(v) == TYPE_ARRAY and v.size() >= 3:
		var a: float = 1.0 if v.size() < 4 else float(v[3])
		return Color(float(v[0]), float(v[1]), float(v[2]), a)
	return Color(1, 1, 1, 1)
