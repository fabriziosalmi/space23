extends Node2D
class_name BackgroundRenderer

# Quanto la cassa (audio_low) accelera lo scroll del parallasse.
# 0.0 = nessun effetto, 2.5 = a beat pieno (audio_bass≈1.0) lo scroll è 3.5x.
const KICK_PARALLAX_BOOST: float = 2.5

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
const PLANET_BODY_TARGET_PX: float = 220.0
# Pacing tarato per primo pianeta visibile entro ~5-8s di gioco e ricorrenza
# ~15-20s a parallax_speed medio. Era 2500/22 → primo pianeta tra 30-50s di
# attesa: troppo, il giocatore non vedeva mai una landmark.
const PLANET_INTERVAL_PX: float = 1800.0  # spawn one every N pixels of accumulated distance
const PLANET_SCROLL_SPEED: float = 55.0   # parallax planets feel distant ma in movimento visibile
# Keep this in sync with Main.scroll_speed so the planet pacing tracks the
# global "distance" counter (a planet should appear every PLANET_INTERVAL_PX
# of in-game distance under default time dilation).
const REFERENCE_SCROLL_SPEED: float = 100.0

# Deep-space landmarks (galaxies, nebulae, blackholes, clusters). Each kind has
# its own pacing and visual treatment. They share the planet shader so they
# inherit the per-track palette tint and bass pulse.
# Pacing taratura: intervalli ridotti e scroll_base raddoppiato così le
# landmark deep-space sono effettivamente avvistabili durante una run normale.
# Prima: galaxy ogni 6500px @ 12 px/sec → ~120s tra una galassia e l'altra +
# 30s di traversata = il giocatore non le vedeva quasi mai.
const DEEP_CONFIGS := {
	"galaxy": {
		"path": "res://bg/galaxy_andromeda.png",
		"interval_px": 5000.0,
		"body_target": 380.0,
		"scroll_base": 30.0,
		"modulate": Color(0.85, 0.85, 0.95, 0.65),
		"z": -9,
		"tint_strength": 0.30,
		"rim_strength": 0.70
	},
	"nebula": {
		"path": "res://bg/nebula_ring.png",
		"interval_px": 5500.0,
		"body_target": 360.0,
		"scroll_base": 35.0,
		"modulate": Color(1.0, 1.0, 1.0, 0.60),
		"z": -9,
		"tint_strength": 0.25,
		"rim_strength": 0.45
	},
	"blackhole": {
		"path": "res://bg/blackhole_kerr.png",
		"interval_px": 7000.0,
		"body_target": 320.0,
		"scroll_base": 32.0,
		"modulate": Color(1.0, 1.0, 1.0, 0.85),
		"z": -7,  # in front of planets — striking landmark
		"tint_strength": 0.10,
		"rim_strength": 0.30
	},
	"cluster": {
		"path": "res://bg/cluster_m13.png",
		"interval_px": 3500.0,
		"body_target": 220.0,
		"scroll_base": 45.0,
		"modulate": Color(1.0, 1.0, 0.92, 0.65),
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

func _ready():
	z_index = -10
	screen_size = get_viewport_rect().size

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
		# Stagger initial accumulators verso valori alti così la prima landmark
		# di ogni tipo entra in scena entro 10-30s, non dopo 100+.
		deep_distance_accum[kind] = float(cfg["interval_px"]) * randf_range(0.55, 0.85)

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
		deep_distance_accum[kind] = float(DEEP_CONFIGS[kind]["interval_px"]) * randf_range(0.55, 0.85)
	planet_sequence = 0

func _init_layers():
	# 1. LAYER DEEP (Galaxies, tiny flares)
	for i in range(4):
		layer_deep.append({
			"type": "galaxy",
			"pos": Vector2(randf_range(-200, screen_size.x + 200), randf() * screen_size.y),
			"speed": randf_range(2.0, 5.0),
			"size": randf_range(5.0, 12.0),
			"angle": randf() * PI * 2.0,
			"arms": randi() % 2 + 2,
			"brightness": randf_range(0.05, 0.15)
		})
	for i in range(10):
		layer_deep.append({
			"type": "flare",
			"pos": Vector2(randf_range(-200, screen_size.x + 200), randf() * screen_size.y),
			"speed": randf_range(2.0, 6.0),
			"pulse_offset": randf() * PI * 2.0,
			"pulse_speed": randf_range(0.5, 1.0)
		})
		
	# 2. LAYER MID (Distant static stars)
	for i in range(70):
		layer_mid.append({
			"pos": Vector2(randf_range(-200, screen_size.x + 200), randf() * screen_size.y),
			"speed": randf_range(15.0, 30.0),
			"brightness": randf_range(0.1, 0.4)
		})
		
	# 3. LAYER NEAR (Fast stars and Constellations)
	for i in range(4): # Costellazioni giganti
		var num_stars = randi() % 5 + 4
		var c_pos = Vector2(randf_range(-200, screen_size.x + 200), randf() * screen_size.y)
		var speed = randf_range(2.0, 8.0) # Quasi ferme
		var stars = []
		for s in range(num_stars):
			# Estensione enorme
			stars.append(Vector2(randf_range(-200, 200), randf_range(-200, 200)))
		layer_near.append({
			"type": "constellation",
			"pos": c_pos,
			"speed": speed,
			"stars": stars,
			"brightness": randf_range(0.6, 1.0)
		})
	for i in range(30):
		layer_near.append({
			"type": "star",
			"pos": Vector2(randf_range(-200, screen_size.x + 200), randf() * screen_size.y),
			"speed": randf_range(60.0, 100.0),
			"brightness": randf_range(0.5, 1.0)
		})
		
	# 4. LAYER TOP (Planets, Asteroids, Comets)
	for i in range(2):
		layer_top.append({
			"type": "planet",
			"pos": Vector2(randf_range(-200, screen_size.x + 200), randf() * screen_size.y),
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
			"pos": Vector2(randf_range(-200, screen_size.x + 200), randf() * screen_size.y),
			"speed": randf_range(80.0, 120.0),
			"asteroids": asteroids
		})
	for i in range(2):
		layer_top.append({
			"type": "comet",
			"pos": Vector2(randf_range(-200, screen_size.x + 200), randf() * screen_size.y),
			"speed": randf_range(300.0, 500.0),
			"dir": Vector2(randf_range(-0.5, 0.5), 1.0).normalized(),
			"length": randf_range(80.0, 150.0)
		})

func update_background(delta: float, global_speed_multiplier: float, c_bg: Color, c_neb1: Color, c_neb2: Color, audio_low: float, audio_mid: float, audio_high: float = 0.0, player_vel_x: float = 0.0):
	# Cassa = boost momentaneo dello scroll. Pulsa con la traccia.
	var effective_speed: float = global_speed_multiplier + audio_low * KICK_PARALLAX_BOOST

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

	# Planet landmarks: drive their tint from the current palette and let them
	# pulse on the bass. Per il pacing/scroll usiamo un floor disaccoppiato dal
	# time-dilation di gameplay: i pianeti sono scenografia parallasse, se
	# global_speed crolla a 0.05 (player fermo) gli accumulators si congelano e
	# i pianeti non entrano mai in viewport. Questo NON altera l'effective_speed
	# usato sopra per nebula/scroll e audio_low del shader.
	current_palette_tint = Vector3(c_neb1.r, c_neb1.g, c_neb1.b)
	last_audio_low = audio_low
	var parallax_speed: float = max(global_speed_multiplier, 0.4) + audio_low * KICK_PARALLAX_BOOST
	_tick_planets(delta, parallax_speed, player_vel_x)
	_tick_deep_landmarks(delta, parallax_speed, player_vel_x)

	# Scroll. Per dare un senso di profondità reattivo al movimento del player,
	# shiftiamo i layer più "vicini" in direzione opposta a player.velocity.x.
	# Fattori scelti empiricamente: il layer mid (lontano) si muove pochissimo,
	# il near di più, il top molto poco perché contiene corpi celesti grandi
	# (pianeti/asteroidi/comete) che con drift forte stonano.
	# Max shift @ MAX_SPEED=700: mid ~0.07 px/frame, near ~0.4 px/frame, top ~0.14.
	var lateral_factor_mid: float = 0.0001
	var lateral_factor_near: float = 0.0006
	var lateral_factor_top: float = 0.0002
	var all_layers = [layer_deep, layer_mid, layer_near, layer_top]
	var lateral_factors = [0.0, lateral_factor_mid, lateral_factor_near, lateral_factor_top]
	var li: int = 0
	for layer in all_layers:
		var lat_shift: float = -player_vel_x * lateral_factors[li] * delta * 60.0
		for e in layer:
			if e.has("dir"): # E' una cometa
				e.pos += e.dir * e.speed * effective_speed * delta
				if e.pos.y > screen_size.y + 200 or e.pos.x < -200 or e.pos.x > screen_size.x + 200:
					e.pos.y = -200
					e.pos.x = randf_range(-200, screen_size.x + 200)
			else:
				e.pos.y += e.speed * effective_speed * delta
				e.pos.x += lat_shift
				if e.pos.y > screen_size.y + 150:
					e.pos.y = -150
					e.pos.x = randf_range(-200, screen_size.x + 200)

			if e.has("rot"): # E' un asteroide
				e.rot += e.rot_speed * effective_speed * delta

			if e.has("asteroids"): # E' un gruppo di asteroidi
				for ast in e.asteroids:
					ast.rot += ast.rot_speed * effective_speed * delta
		li += 1
					
	# Pass audio_mid to draw
	# We can store it as meta or just call queue_redraw() and use a property
	set_meta("audio_mid", audio_mid)
	queue_redraw()

func _tick_planets(delta: float, effective_speed: float, player_vel_x: float = 0.0) -> void:
	# Accumulate "distance traveled" for planet spawn pacing.
	planet_distance_accum += effective_speed * REFERENCE_SCROLL_SPEED * delta

	if planet_distance_accum >= PLANET_INTERVAL_PX:
		planet_distance_accum -= PLANET_INTERVAL_PX
		_spawn_planet()

	# Lateral parallax shift dei pianeti (layer "lontano" → factor piccolo).
	# 0.00015 al MAX_SPEED 700 = ~6 px/sec, percepibile ma non distrae.
	var lat_shift: float = -player_vel_x * 0.00015 * delta * 60.0

	# Drive existing planets: scroll + slight horizontal drift + per-frame
	# shader uniforms (palette tint follows current track, bass pulses size).
	for child in planet_layer.get_children():
		var sp := child as Sprite2D
		if sp == null:
			continue
		var sc_speed: float = float(sp.get_meta("scroll_speed", PLANET_SCROLL_SPEED))
		var x_drift: float = float(sp.get_meta("x_drift", 0.0))
		sp.position.y += sc_speed * effective_speed * delta
		sp.position.x += x_drift * delta + lat_shift

		if sp.material:
			sp.material.set_shader_parameter("tint", current_palette_tint)
			sp.material.set_shader_parameter("audio_low", last_audio_low)

		if sp.position.y > screen_size.y + 200:
			sp.queue_free()

func _tick_deep_landmarks(delta: float, effective_speed: float, player_vel_x: float = 0.0) -> void:
	# Per-kind distance accumulators → independent pacing.
	for kind in DEEP_CONFIGS:
		deep_distance_accum[kind] += effective_speed * REFERENCE_SCROLL_SPEED * delta
		var interval: float = float(DEEP_CONFIGS[kind]["interval_px"])
		if deep_distance_accum[kind] >= interval:
			deep_distance_accum[kind] -= interval
			_spawn_deep_landmark(kind)

	# Lateral parallax dei deep landmarks (layer più lontano dei pianeti).
	var lat_shift: float = -player_vel_x * 0.00008 * delta * 60.0

	# Update active deep landmarks: scroll, drift, palette tint per frame.
	for child in deep_layer.get_children():
		var sp := child as Sprite2D
		if sp == null:
			continue
		var sc_speed: float = float(sp.get_meta("scroll_speed", 20.0))
		var x_drift: float = float(sp.get_meta("x_drift", 0.0))
		sp.position.y += sc_speed * effective_speed * delta
		sp.position.x += x_drift * delta + lat_shift
		if sp.material:
			sp.material.set_shader_parameter("tint", current_palette_tint)
			sp.material.set_shader_parameter("audio_low", last_audio_low)
		if sp.position.y > screen_size.y + 250:
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

	# Spread across screen with margin so the body doesn't clip; randomized.
	# Spawn appena sopra il viewport (-180..-280) così il landmark è visibile
	# in pochi secondi dopo lo spawn — era -360..-600 e con scroll a 12-28 px/sec
	# servivano 15-50s di traversata prima che entrasse in scena.
	var margin: float = 220.0
	var rx: float = randf_range(margin, screen_size.x - margin)
	var ry: float = -randf_range(180, 280)
	sp.position = Vector2(rx, ry)
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

	# Spread X across the full screen width with margin so the planet body
	# doesn't clip the edge. Bias odd/even spawns toward opposite halves to
	# avoid stacking columns.
	var half: float = screen_size.x * 0.5
	var margin: float = 180.0
	var rx: float
	if planet_sequence % 2 == 0:
		rx = randf_range(margin, half - 40)
	else:
		rx = randf_range(half + 40, screen_size.x - margin)

	# Y entry jitter — spawn appena sopra il viewport così il pianeta è visibile
	# entro 1-2s. Era -260..-480 con scroll 22 px/sec → 12-22s di traversata
	# prima che entrasse in scena.
	var ry: float = -randf_range(120, 200)

	# A slow horizontal drift gives the impression they're crossing the scene
	# rather than scrolling vertically in lockstep.
	var x_drift: float = randf_range(-12.0, 12.0)

	sp.position = Vector2(rx, ry)
	# Slight desaturation + alpha so they read as distant.
	sp.modulate = Color(0.88, 0.86, 0.95, 0.9)

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
				
	# 2. DRAW LAYER MID
	for e in layer_mid:
		draw_rect(Rect2(e.pos, Vector2(1, 1)), Color(1.5 + audio_mid*3.0, 1.5 + audio_mid*3.0, 1.5 + audio_mid*3.0, e.brightness)) # HDR Glow
		
	# 3. DRAW LAYER NEAR
	for e in layer_near:
		if e.type == "star":
			draw_rect(Rect2(e.pos, Vector2(1, 1)), Color(1.8, 1.8, 1.8, e.brightness)) # HDR Glow — singolo pixel come il layer_mid
		elif e.type == "constellation":
			draw_set_transform(e.pos, 0.0, Vector2.ONE)
			for s in range(e.stars.size() - 1):
				draw_line(e.stars[s], e.stars[s+1], Color(1.2 + audio_mid*2.0, 1.2 + audio_mid*2.0, 1.2 + audio_mid*2.0, e.brightness * 0.08), 1.0) # Molto trasparenti
			for s in e.stars:
				draw_rect(Rect2(s, Vector2(1, 1)), Color(1.8, 1.8, 1.8, e.brightness * 0.2)) # Piccole e deboli
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
			draw_circle(e.pos, 3.0, Color(2.0, 3.5, 5.0))
			var mid = e.pos - e.dir * (e.length * 0.3)
			var end = e.pos - e.dir * e.length
			draw_line(e.pos, mid, Color(1.0, 2.0, 4.0, 0.8), 2.0)
			draw_line(mid, end, Color(0.5, 1.0, 3.0, 0.2), 1.0)
