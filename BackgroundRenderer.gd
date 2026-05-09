extends Node2D
class_name BackgroundRenderer

# Quanto la cassa (audio_low) accelera lo scroll del parallasse.
# 0.0 = nessun effetto, 3.5 = a beat pieno (audio_bass≈1.0) lo scroll è 4.5x.
# Bumpato da 2.5: con player fermo + sezione musica calma il parallasse si
# perdeva ("non scrolla") — adesso anche il floor del bass aggiunge swing.
const KICK_PARALLAX_BOOST: float = 3.5

# Real planet landmarks scrolling in the far layer. Order = solar system inner
# → outer. Cycles when exhausted.
const PLANET_PATHS := [
	"res://planets/01_mercury.png",
	"res://planets/02_venus.png",
	"res://planets/03_earth.png",
	"res://planets/04_mars.png",
	"res://planets/05_jupiter.png",
	"res://planets/06_saturn.png",
	"res://planets/07_uranus.png",
	"res://planets/08_neptune.png",
]
# Visual body diameter target, in px. Saturn's bbox is wider (rings) so we
# scale by its body width, not its bbox. Indexes match PLANET_PATHS.
const PLANET_BODY_WIDTHS := [206.0, 249.0, 253.0, 245.0, 244.0, 350.0, 255.0, 242.0]
const PLANET_BODY_TARGET_PX: float = 320.0
# -15% rispetto al giro precedente (380→320). Più "fondali", meno presenti.
const PLANET_INTERVAL_PX: float = 3500.0  # spawn one every N pixels of accumulated distance
const PLANET_SCROLL_SPEED: float = 22.0   # slow drift — landmarks come and go in ~50s
# Keep this in sync with Main.scroll_speed so the planet pacing tracks the
# global "distance" counter (a planet should appear every PLANET_INTERVAL_PX
# of in-game distance under default time dilation).
const REFERENCE_SCROLL_SPEED: float = 100.0

# ===== Strip / parallax (Phase 1.5: position-keyed lateral camera) =====
# Universe is rendered in a "strip" wider than the viewport. The viewport's
# horizontal centre tracks a smoothed `player.position.x`; each layer slides
# laterally by a depth-scaled fraction of the player's offset from centre.
# Result: real depth cue (closer layers move more) — replaces the prior
# velocity-driven `lateral_factor_*` shifts that drifted at sub-pixel rates.
const STRIP_WIDTH_MULT: float = 1.4   # 1280 viewport → 1792 strip
const LATERAL_LERP_RATE: float = 4.0  # per-second smoothing toward target offset
# Per-layer depth factors. 1.0 = full parallax (matches player motion); 0.0 =
# infinite distance (no parallax). Values from bg_v2.md §4.1, with two extra
# tiers for the CPU draw layers between deep and foreground.
const DEPTH_NEBULA: float = 0.05         # nebula shader UV offset
const DEPTH_DEEP: float = 0.20           # galaxy / nebula / BH / cluster sprites + CPU layer_deep
const DEPTH_LAYER_MID: float = 0.30      # mid procedural stars
const DEPTH_PLANET: float = 0.45         # planet sprites
const DEPTH_LAYER_NEAR: float = 0.50     # near constellation + bright stars
const DEPTH_FOREGROUND: float = 0.85     # CPU layer_top (asteroids, comets, foreground planets)

# Deep-space landmarks (galaxies, nebulae, blackholes, clusters). Each kind has
# its own pacing and visual treatment. They share the planet shader so they
# inherit the per-track palette tint and bass pulse.
# Pacing 2x più lento del precedente giro di tuning, così le landmark restano
# rare e si "sentono". Plus intervalli volutamente non-multipli tra loro per
# evitare che galaxy + nebula + cluster + blackhole spawni-no nello stesso
# istante (il fenomeno "tutti insieme" che dava confusione visiva).
const DEEP_CONFIGS := {
	"galaxy": {
		"path": "res://bg/galaxy_andromeda.png",
		"interval_px": 8000.0,
		"body_target": 410.0,
		"scroll_base": 16.0,
		"modulate": Color(0.88, 0.86, 0.95, 0.27),
		"z": -9,
		"tint_strength": 0.30,
		"rim_strength": 0.70
	},
	"nebula": {
		"path": "res://bg/nebula_ring.png",
		"interval_px": 9500.0,
		"body_target": 440.0,
		"scroll_base": 18.0,
		"modulate": Color(0.94, 0.88, 0.92, 0.25),
		"z": -9,
		"tint_strength": 0.25,
		"rim_strength": 0.45
	},
	"blackhole": {
		"path": "res://bg/blackhole_kerr.png",
		"interval_px": 12000.0,
		"body_target": 320.0,
		"scroll_base": 16.0,
		"modulate": Color(0.95, 0.95, 0.95, 0.36),
		"z": -7,  # in front of planets — striking landmark
		"tint_strength": 0.10,
		"rim_strength": 0.30
	},
	"cluster": {
		"path": "res://bg/cluster_m13.png",
		"interval_px": 6500.0,
		"body_target": 240.0,
		"scroll_base": 20.0,
		"modulate": Color(0.95, 0.92, 0.82, 0.30),
		"z": -8,
		"tint_strength": 0.20,
		"rim_strength": 0.30
	}
}

var layer_deep = []
var layer_mid = []
var layer_near = []
var layer_top = []

var nebula_bg: ColorRect
var nebula_time: float = 0.0
var planet_layer: Node2D
var planet_textures: Array = []
var planet_sequence: int = 0
var planet_distance_accum: float = PLANET_INTERVAL_PX * 0.85  # seed: first one entro ~5s di gioco
var current_palette_tint: Vector3 = Vector3(0.5, 0.3, 0.8)
var last_audio_low: float = 0.0

var deep_layer: Node2D
var deep_textures: Dictionary = {}
var deep_distance_accum: Dictionary = {}

var screen_size: Vector2

# Strip / parallax state. `viewport_offset_x` is the smoothed lateral camera
# position in *strip-relative* coords: 0 = strip centred on viewport, +N = the
# viewport is N px right of centre (i.e. layers shift left by N*depth on
# screen). Clamped to ±max_player_offset so the strongest layer (DEPTH_FOREGROUND)
# never exposes the strip's hard edges.
var strip_width: float = 0.0
var strip_pad: float = 0.0
var max_player_offset: float = 0.0
var viewport_offset_x: float = 0.0

func _ready():
	z_index = -10
	screen_size = get_viewport_rect().size
	strip_width = screen_size.x * STRIP_WIDTH_MULT
	strip_pad = (strip_width - screen_size.x) * 0.5
	# Foreground layer at depth d shifts by d * |player_offset| px on screen. To
	# keep its content inside the strip we need d_max * |player_offset| ≤ strip_pad,
	# i.e. |player_offset| ≤ strip_pad / d_max. Default: 256 / 0.85 ≈ 301 px —
	# roughly half-screen of player travel before parallax saturates.
	max_player_offset = strip_pad / DEPTH_FOREGROUND

	# --- LAYER 0: NEBULA SHADER (Colored Universe Background) ---
	# Z absoluto: il shader output è OPAQUE (alpha=1.0). Senza z_as_relative=false
	# eredita parent z=-10 e copriva i pianeti (che con relative=true finivano a
	# effective z=-26 → sotto al nebula → invisibili). Forziamo z assoluto -12
	# così la nebula è davvero il fondale.
	nebula_bg = ColorRect.new()
	nebula_bg.size = screen_size + Vector2(400, 400) # Overscan per evitare bordi neri
	nebula_bg.position = Vector2(-200, -200)
	nebula_bg.show_behind_parent = true
	nebula_bg.z_as_relative = false
	nebula_bg.z_index = -12
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/nebula.gdshader")
	nebula_bg.material = mat
	add_child(nebula_bg)

	# --- LAYER 1.5: PLANET LANDMARKS (real photos, scrolling slow, far) ---
	# Z absoluto -6 (sopra nebula -12, sopra le stelle procedurali a z=-10 del
	# parent _draw, sotto al gameplay -3 e sopra). Senza z_as_relative=false i
	# sprites finivano a z=-26 e venivano coperti dalla nebula opaca.
	planet_layer = Node2D.new()
	planet_layer.z_as_relative = false
	planet_layer.z_index = -6
	add_child(planet_layer)
	for path in PLANET_PATHS:
		if ResourceLoader.exists(path):
			planet_textures.append(load(path))
		else:
			planet_textures.append(null)
			push_warning("Planet asset missing: " + path)

	# --- LAYER 1.4: DEEP-SPACE LANDMARKS (galaxies, nebulae, blackholes, clusters) ---
	# Each kind has its own pacing and z-index so they don't collide with planets.
	# We let each Sprite carry its own z_index from the config (made absolute in
	# _spawn_deep_landmark via z_as_relative=false). Container itself is absolute
	# at z=-9 just to insulate from inheritance accidents.
	deep_layer = Node2D.new()
	deep_layer.z_as_relative = false
	deep_layer.z_index = -9
	add_child(deep_layer)
	for kind in DEEP_CONFIGS:
		var cfg: Dictionary = DEEP_CONFIGS[kind]
		var path: String = cfg["path"]
		if ResourceLoader.exists(path):
			deep_textures[kind] = load(path)
		else:
			push_warning("Deep landmark asset missing: " + path)
		# Stagger DETERMINISTICO per evitare che galaxy/cluster/nebula/blackhole
		# spawni tutto insieme. Ogni tipo parte a una "frazione" diversa del
		# proprio intervallo: cluster vede subito (0.85), galaxy poco dopo
		# (0.65), nebula a metà (0.45), blackhole in lontananza (0.25). Combinato
		# con i diversi interval_px, la cadenza percepita è più ariosa.
		var initial_frac: float
		match kind:
			"cluster":   initial_frac = 0.85
			"galaxy":    initial_frac = 0.65
			"nebula":    initial_frac = 0.45
			"blackhole": initial_frac = 0.25
			_:           initial_frac = 0.50
		deep_distance_accum[kind] = float(cfg["interval_px"]) * initial_frac

	_init_layers()

# Pulizia dei landmark (pianeti + galassie/nebulose/blackhole/cluster) — chiamata
# da Main al retry così non sopravvivono dal run morto. I layer procedurali
# (stelle, costellazioni, comete) restano: sono ambient, non hanno senso reset.
func clear_landmarks() -> void:
	for child in planet_layer.get_children():
		child.queue_free()
	for child in deep_layer.get_children():
		child.queue_free()
	planet_distance_accum = PLANET_INTERVAL_PX * 0.85
	for kind in DEEP_CONFIGS:
		var f: float
		match kind:
			"cluster":   f = 0.85
			"galaxy":    f = 0.65
			"nebula":    f = 0.45
			"blackhole": f = 0.25
			_:           f = 0.50
		deep_distance_accum[kind] = float(DEEP_CONFIGS[kind]["interval_px"]) * f
	planet_sequence = 0

# Map a strip-anchored x to the screen-space x for a layer of given depth.
# Strip coords range over [0, strip_width]; screen coords over [0, screen_w].
# When viewport_offset_x = 0 the strip is centred on the viewport, so a body
# at strip_x = strip_width/2 renders at screen_w/2. As the player moves right,
# viewport_offset_x grows positive and layers shift left by depth * offset —
# stronger for foreground (DEPTH_FOREGROUND), barely visible for deep layers
# (DEPTH_DEEP), invisible for the nebula (handled in shader at DEPTH_NEBULA).
func _strip_to_screen_x(strip_x: float, depth: float) -> float:
	return strip_x - strip_pad - viewport_offset_x * depth

func _init_layers():
	# Densità ridotta: prima ~120 elementi tra stars+flares+constellations →
	# percepiti come "rumore". Ora ~50 totali, distribuiti per dare profondità
	# ma non saturare. Inoltre brightness sotto 1.0 per evitare bloom HDR
	# (glow_hdr_threshold=0.9 in Main): le stelline dovrebbero essere puntiformi,
	# non aloni.

	# 1. LAYER DEEP (Galaxies, tiny flares) — far/quasi-statico
	for i in range(2):
		layer_deep.append({
			"type": "galaxy",
			"strip_x": randf_range(-200, strip_width + 200), "pos": Vector2(0.0, randf() * screen_size.y),
			"speed": randf_range(2.0, 5.0),
			"size": randf_range(5.0, 10.0),
			"angle": randf() * PI * 2.0,
			"arms": randi() % 2 + 2,
			"brightness": randf_range(0.04, 0.10)
		})
	for i in range(5):
		layer_deep.append({
			"type": "flare",
			"strip_x": randf_range(-200, strip_width + 200), "pos": Vector2(0.0, randf() * screen_size.y),
			"speed": randf_range(2.0, 6.0),
			"pulse_offset": randf() * PI * 2.0,
			"pulse_speed": randf_range(0.5, 1.0)
		})

	# 2-3. LAYER MID + NEAR — drasticamente ridotti perché ora il nebula
	# shader fa lo starfield principale (loop perfetto + twinkle + colori).
	# Qui restano pochi tocchi di "vicino" (streak veloci che danno senso di
	# velocità in foreground) + una costellazione cosmetica.
	for i in range(8):
		layer_mid.append({
			"strip_x": randf_range(-200, strip_width + 200), "pos": Vector2(0.0, randf() * screen_size.y),
			"speed": randf_range(40.0, 90.0),
			"brightness": randf_range(0.20, 0.40)
		})

	var num_stars = randi() % 4 + 3
	var c_strip_x: float = randf_range(-200, strip_width + 200)
	var c_pos_y: float = randf() * screen_size.y
	var speed = randf_range(2.0, 8.0)
	var stars = []
	for s in range(num_stars):
		stars.append(Vector2(randf_range(-200, 200), randf_range(-200, 200)))
	layer_near.append({
		"type": "constellation",
		"strip_x": c_strip_x,
		"pos": Vector2(0.0, c_pos_y),  # pos.x recomputed each frame from strip_x
		"speed": speed,
		"stars": stars,
		"brightness": randf_range(0.35, 0.6)
	})
	for i in range(6):
		layer_near.append({
			"type": "star",
			"strip_x": randf_range(-200, strip_width + 200), "pos": Vector2(0.0, randf() * screen_size.y),
			"speed": randf_range(120.0, 220.0),
			"brightness": randf_range(0.40, 0.75)
		})
		
	# 4. LAYER TOP (Planets, Asteroids, Comets)
	for i in range(2):
		layer_top.append({
			"type": "planet",
			"strip_x": randf_range(-200, strip_width + 200), "pos": Vector2(0.0, randf() * screen_size.y),
			"speed": randf_range(30.0, 50.0),
			"radius": randf_range(30.0, 60.0),
			"color": Color(randf_range(0.1, 0.3), randf_range(0.1, 0.3), randf_range(0.2, 0.4), 0.7),
			"ring": randf() > 0.5
		})
	for i in range(2):
		var num_ast = randi() % 5 + 3
		var asteroids = []
		for ast in range(num_ast):
			var a_pts = PackedVector2Array()
			var a_rad = randf_range(3.0, 8.0)
			for a in range(6):
				var ang = a * (PI * 2.0 / 6.0)
				var rad = a_rad * randf_range(0.6, 1.4)
				a_pts.append(Vector2(cos(ang), sin(ang)) * rad)
			asteroids.append({
				"offset": Vector2(randf_range(-40, 40), randf_range(-40, 40)),
				"pts": a_pts,
				"rot": randf() * PI,
				"rot_speed": randf_range(-1.5, 1.5)
			})
		layer_top.append({
			"type": "asteroid_group",
			"strip_x": randf_range(-200, strip_width + 200), "pos": Vector2(0.0, randf() * screen_size.y),
			"speed": randf_range(80.0, 120.0),
			"asteroids": asteroids
		})
	for i in range(2):
		layer_top.append({
			"type": "comet",
			"strip_x": randf_range(-200, strip_width + 200), "pos": Vector2(0.0, randf() * screen_size.y),
			"speed": randf_range(300.0, 500.0),
			"dir": Vector2(randf_range(-0.5, 0.5), 1.0).normalized(),
			"length": randf_range(80.0, 150.0)
		})

	# Resize: ricomputa strip dimensions + nebula overscan. Senza questo,
	# `strip_width` e `nebula_bg.size` restavano calcolati dallo screen
	# iniziale → su resize il parallasse usava una strip proporzionata
	# al vecchio viewport (lateral offset clamps wrong, depth scaling off)
	# e la nebula lasciava bordi neri se il viewport è cresciuto.
	get_window().size_changed.connect(_on_viewport_resized)

func _on_viewport_resized() -> void:
	screen_size = get_viewport_rect().size
	strip_width = screen_size.x * STRIP_WIDTH_MULT
	strip_pad = (strip_width - screen_size.x) * 0.5
	max_player_offset = strip_pad / DEPTH_FOREGROUND
	if nebula_bg:
		nebula_bg.size = screen_size + Vector2(400, 400)
		nebula_bg.position = Vector2(-200, -200)

func update_background(delta: float, global_speed_multiplier: float, c_bg: Color, c_neb1: Color, c_neb2: Color, audio_low: float, audio_mid: float, audio_high: float = 0.0, player_x: float = -1.0):
	# Cassa = boost momentaneo dello scroll. Pulsa con la traccia.
	var effective_speed: float = global_speed_multiplier + audio_low * KICK_PARALLAX_BOOST

	# Lateral camera: smoothed track of player offset from viewport centre.
	# Clamped so DEPTH_FOREGROUND * |offset| ≤ strip_pad — the strongest-parallax
	# layer never exposes the strip's hard edges. `player_x = -1` is the sentinel
	# for "no player" (TITLE state) → strip-centred, no lateral motion.
	var target_offset: float = 0.0
	if player_x >= 0.0:
		target_offset = clamp(player_x - screen_size.x * 0.5, -max_player_offset, max_player_offset)
	viewport_offset_x = lerp(viewport_offset_x, target_offset, LATERAL_LERP_RATE * delta)

	# Floor "respiro" sul bass: raise minimo a ~0.15–0.25 per dare un kick
	# baseline anche nei silenzi assoluti, ma SOTTO i picchi reali dell'audio
	# (che spesso > 0.4 con il gain × 4 corrente). Il shader ha bass_baseline=2.5
	# che è la luce sempre-on; il floor qui aggiunge solo una pulsazione lenta.
	var ambient_pulse: float = 0.20 + 0.08 * sin(Time.get_ticks_msec() / 1000.0 * 0.7)
	var shader_audio_low: float = max(audio_low, ambient_pulse)

	nebula_time += delta * effective_speed
	if nebula_bg and nebula_bg.material:
		nebula_bg.material.set_shader_parameter("scroll_time", nebula_time)
		nebula_bg.material.set_shader_parameter("audio_low", shader_audio_low)
		nebula_bg.material.set_shader_parameter("audio_mid", audio_mid)
		nebula_bg.material.set_shader_parameter("audio_high", audio_high)
		nebula_bg.material.set_shader_parameter("c_bg", Vector3(c_bg.r, c_bg.g, c_bg.b))
		nebula_bg.material.set_shader_parameter("c_neb1", Vector3(c_neb1.r, c_neb1.g, c_neb1.b))
		nebula_bg.material.set_shader_parameter("c_neb2", Vector3(c_neb2.r, c_neb2.g, c_neb2.b))
		# Normalised lateral offset for the shader's UV shift. The shader
		# multiplies by DEPTH_NEBULA internally → cloud / starfield drift
		# barely perceptibly when the player leans laterally.
		nebula_bg.material.set_shader_parameter("lateral_offset", viewport_offset_x / screen_size.x)

	# Planet landmarks: drive their tint from the current palette and let them
	# pulse on the bass. Per il pacing/scroll usiamo un floor disaccoppiato dal
	# time-dilation di gameplay: i pianeti sono scenografia parallasse, se
	# global_speed crolla a 0.05 (player fermo) gli accumulators si congelano e
	# i pianeti non entrano mai in viewport. Questo NON altera l'effective_speed
	# usato sopra per nebula/scroll e audio_low del shader.
	current_palette_tint = Vector3(c_neb1.r, c_neb1.g, c_neb1.b)
	last_audio_low = audio_low
	var parallax_speed: float = max(global_speed_multiplier, 0.4) + audio_low * KICK_PARALLAX_BOOST
	_tick_planets(delta, parallax_speed)
	_tick_deep_landmarks(delta, parallax_speed)

	# CPU layers: each entry stores `strip_x` (anchor in strip coords) and `pos`
	# (cached render position). Y scrolls per-frame as before; X is recomputed
	# every frame from `strip_x` and the layer's depth factor — replaces the
	# old velocity-keyed `lateral_factor_*` drift, which accumulated sub-pixel
	# shifts that drifted unboundedly when the player held a direction.
	var all_layers = [layer_deep, layer_mid, layer_near, layer_top]
	var depths: Array = [DEPTH_DEEP, DEPTH_LAYER_MID, DEPTH_LAYER_NEAR, DEPTH_FOREGROUND]
	var li: int = 0
	for layer in all_layers:
		var depth: float = depths[li]
		for e in layer:
			if e.has("dir"): # comet — moves freely in strip space
				e.strip_x += e.dir.x * e.speed * effective_speed * delta
				e.pos.y += e.dir.y * e.speed * effective_speed * delta
				if e.pos.y > screen_size.y + 200 or e.strip_x < -200 or e.strip_x > strip_width + 200:
					e.pos.y = -200
					e.strip_x = randf_range(-200, strip_width + 200)
					# Randomize direction on wrap. Without this, a comet that
					# entered moving SW would re-enter from the top-left still
					# heading SW — could exit the strip immediately, and the
					# comet's drawn tail would point NE while motion is SW
					# (visually contradictory). Mirrors the spawn formula in
					# _init_layers.
					e.dir = Vector2(randf_range(-0.5, 0.5), 1.0).normalized()
					# 2% chance: super-comet variante. Coda 2× più lunga,
					# velocità 1.5×. Discoverable, non costante — il giocatore
					# ne vede 1 ogni ~minuto e gli sembra raro / speciale.
					if randf() < 0.02:
						e.length = randf_range(220.0, 280.0)
						e.speed = randf_range(500.0, 700.0)
					else:
						e.length = randf_range(80.0, 150.0)
						e.speed = randf_range(300.0, 500.0)
			else:
				e.pos.y += e.speed * effective_speed * delta
				if e.pos.y > screen_size.y + 150:
					e.pos.y = -150
					e.strip_x = randf_range(-200, strip_width + 200)
			e.pos.x = _strip_to_screen_x(e.strip_x, depth)

			if e.has("rot"): # asteroid (single)
				e.rot += e.rot_speed * effective_speed * delta

			if e.has("asteroids"): # asteroid group
				for ast in e.asteroids:
					ast.rot += ast.rot_speed * effective_speed * delta
		li += 1
					
	# Pass audio_mid to draw
	# We can store it as meta or just call queue_redraw() and use a property
	set_meta("audio_mid", audio_mid)
	queue_redraw()

func _has_visible_landmark() -> bool:
	# "Visible" = sprite gia parzialmente in viewport o sta per entrare. Range
	# generoso (-500..screen+300) perche i landmark sono ora 400-800 px → il
	# guard deve considerare lo sprite come "visibile" anche con il centro
	# fuori viewport, finche i bordi sono dentro. Con la strip 1.4× alcuni
	# sprite possono essere parcheggiati off-screen-X (a strip_x agli estremi):
	# li escludiamo dal guard così un landmark visibile-solo-se-leani non
	# blocca lo spawn della prossima landmark on-axis.
	for c in planet_layer.get_children():
		if c is Sprite2D \
				and c.position.y > -500 and c.position.y < screen_size.y + 300 \
				and c.position.x > -300 and c.position.x < screen_size.x + 300:
			return true
	for c in deep_layer.get_children():
		if c is Sprite2D \
				and c.position.y > -500 and c.position.y < screen_size.y + 300 \
				and c.position.x > -300 and c.position.x < screen_size.x + 300:
			return true
	return false

func _tick_planets(delta: float, effective_speed: float) -> void:
	# Accumulate "distance traveled" for planet spawn pacing.
	planet_distance_accum += effective_speed * REFERENCE_SCROLL_SPEED * delta

	if planet_distance_accum >= PLANET_INTERVAL_PX:
		# Cap accumulator a interval per evitare burst di spawn quando lo
		# schermo si libera. Così appena la landmark precedente esce dal
		# viewport, la prossima parte SUBITO ma una sola.
		if _has_visible_landmark():
			planet_distance_accum = PLANET_INTERVAL_PX
		else:
			planet_distance_accum -= PLANET_INTERVAL_PX
			_spawn_planet()

	# Drive existing planets: scroll + slight strip-space drift + per-frame
	# shader uniforms (palette tint follows current track, bass pulses size).
	# X is recomputed every frame from the planet's `strip_x` anchor → lateral
	# parallax follows player position with depth factor DEPTH_PLANET (0.45),
	# replacing the prior velocity-driven shift that drifted unboundedly.
	for child in planet_layer.get_children():
		var sp := child as Sprite2D
		if sp == null:
			continue
		var sc_speed: float = float(sp.get_meta("scroll_speed", PLANET_SCROLL_SPEED))
		var x_drift: float = float(sp.get_meta("x_drift", 0.0))
		var anchor: float = float(sp.get_meta("strip_x", strip_width * 0.5))
		# x_drift advances the strip-anchor (slow horizontal "crossing" feel) —
		# kept in strip space so the parallax framing remains consistent.
		anchor += x_drift * delta
		sp.set_meta("strip_x", anchor)
		sp.position.y += sc_speed * effective_speed * delta
		sp.position.x = _strip_to_screen_x(anchor, DEPTH_PLANET)

		if sp.material:
			sp.material.set_shader_parameter("tint", current_palette_tint)
			sp.material.set_shader_parameter("audio_low", last_audio_low)

		if sp.position.y > screen_size.y + 450:
			sp.queue_free()

func _tick_deep_landmarks(delta: float, effective_speed: float) -> void:
	# Per-kind distance accumulators → independent pacing. Anche qui guard di
	# esclusività: se c'è già una landmark in viewport (planet o deep), questo
	# spawn viene posticipato. Cap dell'accumulator a interval per evitare burst.
	for kind in DEEP_CONFIGS:
		deep_distance_accum[kind] += effective_speed * REFERENCE_SCROLL_SPEED * delta
		var interval: float = float(DEEP_CONFIGS[kind]["interval_px"])
		if deep_distance_accum[kind] >= interval:
			if _has_visible_landmark():
				deep_distance_accum[kind] = interval
			else:
				deep_distance_accum[kind] -= interval
				_spawn_deep_landmark(kind)

	# Update active deep landmarks: scroll, strip-space drift, per-frame shader
	# uniforms. X recomputed every frame from `strip_x` anchor at DEPTH_DEEP
	# (0.20) — gentle lateral parallax, deep landmarks read as far away.
	for child in deep_layer.get_children():
		var sp := child as Sprite2D
		if sp == null:
			continue
		var sc_speed: float = float(sp.get_meta("scroll_speed", 20.0))
		var x_drift: float = float(sp.get_meta("x_drift", 0.0))
		var anchor: float = float(sp.get_meta("strip_x", strip_width * 0.5))
		anchor += x_drift * delta
		sp.set_meta("strip_x", anchor)
		sp.position.y += sc_speed * effective_speed * delta
		sp.position.x = _strip_to_screen_x(anchor, DEPTH_DEEP)
		if sp.material:
			sp.material.set_shader_parameter("tint", current_palette_tint)
			sp.material.set_shader_parameter("audio_low", last_audio_low)
		if sp.position.y > screen_size.y + 500:
			sp.queue_free()

func _spawn_deep_landmark(kind: String) -> void:
	if not deep_textures.has(kind):
		return
	var tex = deep_textures[kind]
	if tex == null:
		return
	var cfg: Dictionary = DEEP_CONFIGS[kind]

	var sp := Sprite2D.new()
	sp.texture = tex
	# Z absoluto dal config (galaxy/nebula -9, cluster -8, blackhole -7). Sopra
	# la nebula (-12), sotto i pianeti (-6).
	sp.z_as_relative = false
	sp.z_index = int(cfg["z"])

	var body_target: float = float(cfg["body_target"])
	var tex_w: float = float(tex.get_width())
	var size_jitter: float = randf_range(0.78, 1.25)
	var scale_factor: float = (body_target / tex_w) * size_jitter
	sp.scale = Vector2(scale_factor, scale_factor)

	# Spread across the *strip* (1.4× viewport) with margin. Spawn ry alta
	# (-450..-600) perché i landmark adesso sono giganti (body fino a 800 px).
	# Con half_height ~400, ry=-500 mette il bottom del sprite a y=-100 (appena
	# sopra il viewport): il landmark "scivola dentro" pulito.
	var margin: float = 220.0
	var rx_strip: float = randf_range(margin, strip_width - margin)
	var ry: float = -randf_range(450, 600)
	sp.set_meta("strip_x", rx_strip)
	sp.position = Vector2(_strip_to_screen_x(rx_strip, DEPTH_DEEP), ry)
	sp.modulate = cfg["modulate"]
	sp.rotation = randf_range(-0.4, 0.4)  # slight tilt — these are not "facing camera"

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/planet.gdshader")
	mat.set_shader_parameter("tint", current_palette_tint)
	mat.set_shader_parameter("audio_low", last_audio_low)
	mat.set_shader_parameter("tint_strength", float(cfg["tint_strength"]))
	mat.set_shader_parameter("rim_strength", float(cfg["rim_strength"]))
	sp.material = mat

	sp.set_meta("scroll_speed", float(cfg["scroll_base"]) * randf_range(0.8, 1.25))
	sp.set_meta("x_drift", randf_range(-15.0, 15.0))
	deep_layer.add_child(sp)

func _spawn_planet() -> void:
	if planet_textures.is_empty():
		return
	var idx: int = planet_sequence % planet_textures.size()
	planet_sequence += 1
	var tex = planet_textures[idx]
	if tex == null:
		return

	var sp := Sprite2D.new()
	sp.texture = tex
	# Z absoluto: senza relative=false ereditava da planet_layer e finiva a -26,
	# COPERTO dalla nebula opaca → pianeti invisibili nonostante spawnassero
	# correttamente. Adesso z=-6 li mette sopra la nebula (-12) e sopra le
	# stelle procedurali (-10).
	sp.z_as_relative = false
	sp.z_index = -6

	# Body-relative scaling so all planets occupy the same visual diameter
	# regardless of bbox (Saturn's rings make its bbox far wider than its body).
	var body_w: float = PLANET_BODY_WIDTHS[idx]
	# Random size variance ±25% to keep things from feeling templated.
	var size_jitter: float = randf_range(0.78, 1.18)
	var scale_factor: float = (PLANET_BODY_TARGET_PX / body_w) * size_jitter
	sp.scale = Vector2(scale_factor, scale_factor)

	# Spread X across the full *strip* width (1.4× viewport) with margin so the
	# planet body doesn't clip the strip edge. Bias odd/even spawns toward
	# opposite halves to avoid stacking columns. With the wider strip, planets
	# can spawn off-axis (visible only when player leans sideways) — the doc's
	# "explorable on a small scale" payoff.
	var half: float = strip_width * 0.5
	var margin: float = 180.0
	var rx_strip: float
	if planet_sequence % 2 == 0:
		rx_strip = randf_range(margin, half - 40)
	else:
		rx_strip = randf_range(half + 40, strip_width - margin)

	# Y entry jitter — spawn ben sopra il viewport perché il pianeta è enorme
	# (body 600 + jitter scale = sprite ~600-700 px). ry=-400 lascia il bottom
	# del sprite appena sopra al viewport top, scivola dentro in modo organico.
	var ry: float = -randf_range(380, 500)

	# A slow horizontal drift gives the impression they're crossing the scene
	# rather than scrolling vertically in lockstep. Drift advances the strip
	# anchor (see _tick_planets), not the screen-space position directly.
	var x_drift: float = randf_range(-12.0, 12.0)

	sp.set_meta("strip_x", rx_strip)
	sp.position = Vector2(_strip_to_screen_x(rx_strip, DEPTH_PLANET), ry)
	# Modulate quasi-bianco con leggera tinta perla; alpha 0.32 (-15% del giro
	# precedente): planet ancora più "fondale".
	sp.modulate = Color(0.92, 0.91, 0.96, 0.32)

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/planet.gdshader")
	mat.set_shader_parameter("tint", current_palette_tint)
	mat.set_shader_parameter("audio_low", last_audio_low)
	sp.material = mat

	sp.set_meta("scroll_speed", PLANET_SCROLL_SPEED * randf_range(0.85, 1.2))
	sp.set_meta("x_drift", x_drift)
	planet_layer.add_child(sp)

func _draw():
	var time = Time.get_ticks_msec() / 1000.0
	var audio_mid = get_meta("audio_mid") if has_meta("audio_mid") else 0.0

	# 1. DRAW LAYER DEEP
	for e in layer_deep:
		if e.type == "galaxy":
			draw_set_transform(e.pos, e.angle + time * 0.05, Vector2.ONE)
			for arm in range(e.arms):
				var arm_ang = arm * (PI * 2.0 / float(e.arms))
				for step in range(2, int(e.size), 2):
					var r = float(step)
					var theta = arm_ang + r * 0.15 
					var p = Vector2(cos(theta), sin(theta)) * r
					var alpha_fade = 1.0 - (r / e.size)
					draw_rect(Rect2(p, Vector2(1,1)), Color(1, 1, 1, e.brightness * alpha_fade))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			
		elif e.type == "flare":
			var pulse = sin(time * e.pulse_speed + e.pulse_offset)
			if pulse > 0.9: 
				var intensity = (pulse - 0.9) * 10.0
				draw_rect(Rect2(e.pos, Vector2(1, 1)), Color(2.5, 2.5, 2.5, intensity * 0.4)) # HDR Glow
				
	# 2. DRAW LAYER MID — brightness sotto 1.0 (no bloom). Audio-mid sale fino a
	# ~1.4 sui peak ma non in modo continuo.
	for e in layer_mid:
		var b: float = 0.85 + audio_mid * 0.6
		draw_rect(Rect2(e.pos, Vector2(1, 1)), Color(b, b, b, e.brightness))

	# 3. DRAW LAYER NEAR — stesso trattamento, leggermente più luminose.
	for e in layer_near:
		if e.type == "star":
			draw_rect(Rect2(e.pos, Vector2(1, 1)), Color(0.95, 0.95, 0.95, e.brightness))
		elif e.type == "constellation":
			draw_set_transform(e.pos, 0.0, Vector2.ONE)
			var lb: float = 0.85 + audio_mid * 0.5
			for s in range(e.stars.size() - 1):
				draw_line(e.stars[s], e.stars[s+1], Color(lb, lb, lb, e.brightness * 0.08), 1.0)
			for s in e.stars:
				draw_rect(Rect2(s, Vector2(1, 1)), Color(0.95, 0.95, 0.95, e.brightness * 0.2))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. DRAW LAYER TOP
	for e in layer_top:
		if e.type == "planet":
			if e.ring:
				draw_set_transform(e.pos, 0.3, Vector2(1.0, 0.3))
				for r in range(3):
					draw_arc(Vector2.ZERO, e.radius * 1.5 + r*2, PI, PI*2, 16, Color(1, 1, 1, 0.3), 1.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				
			draw_circle(e.pos, e.radius, e.color)
			draw_circle(e.pos + Vector2(e.radius*0.25, e.radius*0.25), e.radius*0.8, Color(0, 0, 0, 0.6))
			
			if e.ring:
				draw_set_transform(e.pos, 0.3, Vector2(1.0, 0.3))
				for r in range(3):
					draw_arc(Vector2.ZERO, e.radius * 1.5 + r*2, 0, PI, 16, Color(1, 1, 1, 0.3), 1.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				
		elif e.type == "asteroid_group":
			for ast in e.asteroids:
				var draw_pos = e.pos + ast.offset
				draw_set_transform(draw_pos, ast.rot, Vector2.ONE)
				var ast_col = Color(0.2, 0.2, 0.2, 0.8)
				var c_arr = PackedColorArray()
				c_arr.resize(ast.pts.size())
				c_arr.fill(ast_col)
				draw_polygon(ast.pts, c_arr)
				draw_polyline(ast.pts + PackedVector2Array([ast.pts[0]]), Color(0.1, 0.1, 0.1, 0.8), 1.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			
		elif e.type == "comet":
			# Edge-fade per nascondere il loop reset (teleport bottom→top): user
			# vedeva uno "scatto"/disturbo quando la cometa wrapava. Con alpha
			# fade nei 80px ai bordi del viewport, il teleport avviene mentre la
			# cometa è invisibile → percepito come due comete diverse, non come
			# un loop visibile.
			var fade: float = 1.0
			if e.pos.y < 80.0:
				fade = clamp(e.pos.y / 80.0, 0.0, 1.0)
			elif e.pos.y > screen_size.y - 80.0:
				fade = clamp((screen_size.y - e.pos.y) / 80.0, 0.0, 1.0)
			if e.pos.x < 80.0:
				fade = min(fade, clamp(e.pos.x / 80.0, 0.0, 1.0))
			elif e.pos.x > screen_size.x - 80.0:
				fade = min(fade, clamp((screen_size.x - e.pos.x) / 80.0, 0.0, 1.0))
			if fade <= 0.01:
				continue
			draw_circle(e.pos, 3.0, Color(2.0 * fade, 3.5 * fade, 5.0 * fade))
			var mid = e.pos - e.dir * (e.length * 0.3)
			var end = e.pos - e.dir * e.length
			draw_line(e.pos, mid, Color(1.0 * fade, 2.0 * fade, 4.0 * fade, 0.8 * fade), 2.0)
			draw_line(mid, end, Color(0.5 * fade, 1.0 * fade, 3.0 * fade, 0.2 * fade), 1.0)
