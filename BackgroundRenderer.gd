extends Node2D
class_name BackgroundRenderer

# Quanto la cassa (audio_low) accelera lo scroll del parallasse.
# 0.0 = nessun effetto, 2.5 = a beat pieno (audio_bass≈1.0) lo scroll è 3.5x.
const KICK_PARALLAX_BOOST: float = 2.5

var layer_deep = []
var layer_mid = []
var layer_near = []
var layer_top = []

var nebula_bg: ColorRect
var nebula_time: float = 0.0

var screen_size: Vector2

func _ready():
	z_index = -10
	screen_size = get_viewport_rect().size
	
	# --- LAYER 0: NEBULA SHADER (Colored Universe Background) ---
	nebula_bg = ColorRect.new()
	nebula_bg.size = screen_size + Vector2(400, 400) # Overscan per evitare bordi neri
	nebula_bg.position = Vector2(-200, -200)
	nebula_bg.show_behind_parent = true
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/nebula.gdshader")
	nebula_bg.material = mat
	add_child(nebula_bg)
	
	_init_layers()

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

func update_background(delta: float, global_speed_multiplier: float, c_bg: Color, c_neb1: Color, c_neb2: Color, audio_bass: float, audio_mid: float):
	# Cassa = boost momentaneo dello scroll. Pulsa con la traccia.
	var effective_speed: float = global_speed_multiplier + audio_bass * KICK_PARALLAX_BOOST

	nebula_time += delta * effective_speed
	if nebula_bg and nebula_bg.material:
		nebula_bg.material.set_shader_parameter("scroll_time", nebula_time)
		nebula_bg.material.set_shader_parameter("audio_bass", audio_bass)
		nebula_bg.material.set_shader_parameter("c_bg", Vector3(c_bg.r, c_bg.g, c_bg.b))
		nebula_bg.material.set_shader_parameter("c_neb1", Vector3(c_neb1.r, c_neb1.g, c_neb1.b))
		nebula_bg.material.set_shader_parameter("c_neb2", Vector3(c_neb2.r, c_neb2.g, c_neb2.b))

	# Scroll
	var all_layers = [layer_deep, layer_mid, layer_near, layer_top]
	for layer in all_layers:
		for e in layer:
			if e.has("dir"): # E' una cometa
				e.pos += e.dir * e.speed * effective_speed * delta
				if e.pos.y > screen_size.y + 200 or e.pos.x < -200 or e.pos.x > screen_size.x + 200:
					e.pos.y = -200
					e.pos.x = randf_range(-200, screen_size.x + 200)
			else:
				e.pos.y += e.speed * effective_speed * delta
				if e.pos.y > screen_size.y + 150:
					e.pos.y = -150
					e.pos.x = randf_range(-200, screen_size.x + 200)

			if e.has("rot"): # E' un asteroide
				e.rot += e.rot_speed * effective_speed * delta

			if e.has("asteroids"): # E' un gruppo di asteroidi
				for ast in e.asteroids:
					ast.rot += ast.rot_speed * effective_speed * delta
					
	# Pass audio_mid to draw
	# We can store it as meta or just call queue_redraw() and use a property
	set_meta("audio_mid", audio_mid)
	queue_redraw()

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
			draw_rect(Rect2(e.pos - Vector2(1,1), Vector2(2, 2)), Color(1.8, 1.8, 1.8, e.brightness)) # HDR Glow
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
