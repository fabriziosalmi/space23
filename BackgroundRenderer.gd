extends Node2D
class_name BackgroundRenderer

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
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	uniform vec3 c_bg = vec3(0.005, 0.0, 0.015);
	uniform vec3 c_neb1 = vec3(0.05, 0.01, 0.1);
	uniform vec3 c_neb2 = vec3(0.0, 0.05, 0.15);
	uniform float scroll_time = 0.0;
	uniform float audio_bass = 0.0;
	
	// Funzione Noise procedurale
	vec2 random2(vec2 p) {
		return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
	}
	float noise(vec2 p) {
		vec2 i = floor(p);
		vec2 f = fract(p);
		vec2 u = f*f*(3.0-2.0*f);
		return mix( mix( dot( random2(i + vec2(0.0,0.0) ), f - vec2(0.0,0.0) ), 
						 dot( random2(i + vec2(1.0,0.0) ), f - vec2(1.0,0.0) ), u.x),
					mix( dot( random2(i + vec2(0.0,1.0) ), f - vec2(0.0,1.0) ), 
						 dot( random2(i + vec2(1.0,1.0) ), f - vec2(1.0,1.0) ), u.x), u.y);
	}
	// FBM (Fractal Brownian Motion)
	float fbm(vec2 p) {
		float f = 0.0;
		float w = 0.5;
		for (int i=0; i<5; i++) {
			f += w * noise(p);
			p *= 2.0;
			w *= 0.5;
		}
		return f;
	}
	
	void fragment() {
		vec2 uv = UV;
		uv.y += scroll_time * 0.05;
		
		float n1 = fbm(uv * 3.0 + vec2(scroll_time * 0.02, scroll_time * 0.05));
		float n2 = fbm(uv * 6.0 - vec2(scroll_time * 0.01, scroll_time * 0.03));
		
		vec3 color = c_bg;
		color = mix(color, c_neb1, smoothstep(0.1, 0.8, n1));
		color = mix(color, c_neb2, smoothstep(0.2, 0.9, n2));
		
		float strobe = audio_bass * 8.0; 
		color += c_neb1 * n1 * strobe;
		color += c_neb2 * n2 * strobe * 0.5;
		
		COLOR = vec4(color, 1.0);
	}
	"""
	mat.shader = shader
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
	nebula_time += delta * global_speed_multiplier
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
				e.pos += e.dir * e.speed * global_speed_multiplier * delta
				if e.pos.y > screen_size.y + 200 or e.pos.x < -200 or e.pos.x > screen_size.x + 200:
					e.pos.y = -200
					e.pos.x = randf_range(-200, screen_size.x + 200)
			else:
				e.pos.y += e.speed * global_speed_multiplier * delta
				if e.pos.y > screen_size.y + 150:
					e.pos.y = -150
					e.pos.x = randf_range(-200, screen_size.x + 200)
					
			if e.has("rot"): # E' un asteroide
				e.rot += e.rot_speed * global_speed_multiplier * delta
				
			if e.has("asteroids"): # E' un gruppo di asteroidi
				for ast in e.asteroids:
					ast.rot += ast.rot_speed * global_speed_multiplier * delta
					
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
			draw_circle(e.pos, e.radius, e.color)
			draw_circle(e.pos + Vector2(e.radius*0.25, e.radius*0.25), e.radius*0.8, Color(0, 0, 0, 0.6))
			if e.ring:
				draw_set_transform(e.pos, 0.3, Vector2(1.0, 0.3))
				for r in range(3):
					draw_arc(Vector2.ZERO, e.radius * 1.5 + r*2, 0, PI*2, 32, Color(1, 1, 1, 0.3), 1.5)
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
