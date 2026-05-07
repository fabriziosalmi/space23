extends Node2D

var distance = 0.0
var scroll_speed = 100.0 # pixels per second
var is_playing = false
var global_speed_multiplier = 1.0
var target_speed_multiplier = 1.0
var nebula_time = 0.0
var nebula_bg: ColorRect

# --- GAMEPLAY DATA ---
var enemies = []
var player_bullets = []
var enemy_bullets = []
var explosions = []
var powerups = []
var railguns = []
var black_holes = []
var enemy_spawn_timer = 2.0
var score_points = 0
var shake_intensity = 0.0
var hit_stop_timer = 0.0
var sfx_players = []

var enemy_types = [
	{
		"hp": 2, "speed": [150.0, 250.0], "color": Color(0.1, 0.8, 0.3),
		"pts": PackedVector2Array([Vector2(0, 15), Vector2(-15, -10), Vector2(15, -10)]),
		"ai": 1, "shoot": [2.0, 4.0]
	},
	{
		"hp": 5, "speed": [80.0, 150.0], "color": Color(0.8, 0.1, 0.2),
		"pts": PackedVector2Array([Vector2(0, 20), Vector2(-25, -15), Vector2(-10, -5), Vector2(10, -5), Vector2(25, -15)]),
		"ai": 0, "shoot": [1.5, 3.0]
	},
	{
		"hp": 15, "speed": [40.0, 70.0], "color": Color(0.8, 0.6, 0.1),
		"pts": PackedVector2Array([Vector2(0, 30), Vector2(-35, 5), Vector2(-25, -20), Vector2(25, -20), Vector2(35, 5)]),
		"ai": 2, "shoot": [1.0, 2.0]
	}
]

# Audio
var audio_manager

var current_c_bg = Color(0.005, 0.0, 0.015)
var current_c_neb1 = Color(0.05, 0.01, 0.1)
var current_c_neb2 = Color(0.0, 0.05, 0.15)
var target_c_bg = current_c_bg
var target_c_neb1 = current_c_neb1
var target_c_neb2 = current_c_neb2

var is_intro = false
var intro_timer = 5.0
var main_camera: Camera2D

var game_state = "TITLE" # "TITLE", "INTRO", "PLAYING"
var player_name = "PLAYER 1"
var player_hp = 100.0

var ui_layer: CanvasLayer
var title_label: Label
var name_input: LineEdit
var hp_bar: ProgressBar
var hud_score: Label
var game_over_container: VBoxContainer
var final_score_label: Label
var game_over_timer = 0.0

@onready var player = preload("res://Player.tscn").instantiate()

var world_env: WorldEnvironment
var pp_rect: ColorRect

var screen_size: Vector2

var bg_renderer

func _ready():
	screen_size = get_viewport_rect().size
	
	audio_manager = load("res://AudioManager.gd").new()
	add_child(audio_manager)
	
	bg_renderer = load("res://BackgroundRenderer.gd").new()
	add_child(bg_renderer)
	
	audio_manager.load_and_play_track(0)
	
	# --- POST-PROCESSING: 100x GRAPHICS ---
	var env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 1.8
	env.glow_bloom = 0.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.9 # Solo gli oggetti luminosi brilleranno
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100 # Sopra tutto
	pp_rect = ColorRect.new()
	pp_rect.size = screen_size
	pp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pp_mat = ShaderMaterial.new()
	var pp_shader = Shader.new()
	pp_shader.code = """
    shader_type canvas_item;
    uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
    uniform float zoom_blur = 0.0;
    uniform float grayscale = 0.0;
    uniform vec2 bh_pos = vec2(0.5);
    uniform float bh_intensity = 0.0;
    
    void fragment() {
        vec2 uv = SCREEN_UV;
        
        // --- Distorsione a Clessidra (Pinch Laterale) ---
        // Tira le coordinate UV verso il centro lungo l'asse X, in base all'altezza Y
        vec2 center_dist = uv - vec2(0.5);
        float pinch = sin(uv.y * 3.14159) * 0.06; // Forza della distorsione
        uv.x -= center_dist.x * pinch;
        
        // --- BUCO NERO (Gravitational Lensing) ---
        bool in_bh = false;
        if (bh_intensity > 0.0) {
            vec2 bh_dir = uv - bh_pos;
            bh_dir.x *= 1.77; // Correzione aspect ratio
            float bh_dist = length(bh_dir);
            if (bh_dist < 0.5) {
                float pull = smoothstep(0.5, 0.0, bh_dist);
                uv -= bh_dir * (pull * pull) * bh_intensity * 0.8;
                if (bh_dist < 0.02 * bh_intensity) {
                    COLOR = vec4(0.0, 0.0, 0.0, 1.0);
                    in_bh = true;
                }
            }
        }
        
        if (!in_bh) {
            // Ricalcola la direzione dopo la distorsione per aberrazione e vignettatura
        vec2 dir = uv - vec2(0.5);
        float dist = length(dir);
        
        // 1. Aberrazione Cromatica Leggera (R e B shiftati ai bordi)
        float shift = dist * 0.006;
        float r = texture(screen_tex, uv + dir * shift).r;
        float g = texture(screen_tex, uv).g;
        float b = texture(screen_tex, uv - dir * shift).b;
        vec3 color = vec3(r, g, b);
        
        // 2. Vignettatura Cinematografica
        float vignette = smoothstep(0.8, 0.2, dist);
        color *= mix(0.4, 1.0, vignette);
        
        // 3. Scanlines CRT sottilissime
        float scanline = sin(uv.y * 1000.0) * 0.03;
        color -= scanline;
        
        // 4. Zoom Blur FX (Esplosioni / Fotofinish)
        if (zoom_blur > 0.0) {
            vec3 b_color = vec3(0.0);
            float tot = 0.0;
            for(int i=0; i<12; i++){
                float f = float(i) / 12.0;
                float w = 1.0 - f;
                vec2 s_uv = uv + center_dist * f * zoom_blur;
                b_color += texture(screen_tex, s_uv).rgb * w;
                tot += w;
            }
            color = mix(color, b_color / tot, min(zoom_blur * 4.0, 1.0));
        }
        
        // 5. Grayscale FX (Game Over)
        if (grayscale > 0.0) {
            float gray = dot(color, vec3(0.299, 0.587, 0.114));
            color = mix(color, vec3(gray), grayscale);
        }
        
        COLOR = vec4(color, 1.0);
        }
    }
    """
	pp_mat.shader = pp_shader
	pp_rect.material = pp_mat
	canvas_layer.add_child(pp_rect)
	add_child(canvas_layer)
	
	# --- LAYER 0: NEBULA SHADER (Colored Universe Background) ---
	nebula_bg = ColorRect.new()
	nebula_bg.size = screen_size + Vector2(400, 400) # Overscan per evitare bordi neri
	nebula_bg.position = Vector2(-200, -200)
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
    shader_type canvas_item;
    uniform float scroll_time = 0.0;
    uniform float audio_bass = 0.0;
    
    uniform vec3 c_bg = vec3(0.005, 0.0, 0.015);
    uniform vec3 c_neb1 = vec3(0.05, 0.01, 0.1);
    uniform vec3 c_neb2 = vec3(0.0, 0.05, 0.15);
    
    // Noise algorithm
    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
    }
    float noise(vec2 x) {
        vec2 i = floor(x);
        vec2 f = fract(x);
        float a = hash(i);
        float b = hash(i + vec2(1.0, 0.0));
        float c = hash(i + vec2(0.0, 1.0));
        float d = hash(i + vec2(1.0, 1.0));
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
    }
    float fbm(vec2 x) {
        float v = 0.0;
        float a = 0.5;
        vec2 shift = vec2(100.0);
        mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.50)));
        for (int i = 0; i < 5; ++i) {
            v += a * noise(x);
            x = rot * x * 2.0 + shift;
            a *= 0.5;
        }
        return v;
    }
    
    void fragment() {
        vec2 uv = UV;
        // Scroll animato custom
        vec2 scroll_uv = uv + vec2(0.0, -scroll_time * 0.015);
        
        float n1 = fbm(scroll_uv * 3.0);
        float n2 = fbm(scroll_uv * 2.0 + vec2(5.2, 1.3));
        
        vec3 final_color = mix(c_bg, c_neb1, smoothstep(0.3, 0.8, n1));
        final_color = mix(final_color, c_neb2, smoothstep(0.4, 0.9, n2));
        
        // Effetto Strobo Elegante: illumina solo le nubi di sfondo a tempo di cassa
        float strobe = audio_bass * 8.0; 
        final_color += final_color * strobe;
        
        COLOR = vec4(final_color, 1.0);
    }
    """
	mat.shader = shader
	nebula_bg.material = mat
	# Fondamentale: mettiamo la nebulosa sul piano Z più profondo per non coprire _draw
	nebula_bg.z_index = -100
	add_child(nebula_bg)
	
	# Setup UI e HUD in un CanvasLayer separato (Sotto il PP per avere l'effetto CRT!)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 99 
	
	hud_score = Label.new()
	hud_score.position = Vector2(20, 20)
	hud_score.text = "Score: 0"
	hud_score.add_theme_font_size_override("font_size", 24)
	ui_layer.add_child(hud_score)
	
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(20, 60)
	hp_bar.size = Vector2(200, 20)
	hp_bar.max_value = 100
	hp_bar.value = 100
	ui_layer.add_child(hp_bar)
	
	title_label = Label.new()
	title_label.text = "SPACE23\nINSERT COIN"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.position = Vector2(screen_size.x / 2.0 - 150, screen_size.y / 2.0 - 60)
	ui_layer.add_child(title_label)
	
	name_input = LineEdit.new()
	name_input.position = Vector2(screen_size.x / 2.0 - 100, screen_size.y / 2.0 + 30)
	name_input.size = Vector2(200, 40)
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.text_submitted.connect(_on_name_submitted)
	ui_layer.add_child(name_input)
	
	hud_score.hide()
	hp_bar.hide()
	
	# Game Over UI
	game_over_container = VBoxContainer.new()
	game_over_container.alignment = BoxContainer.ALIGNMENT_CENTER
	game_over_container.size = Vector2(400, 200)
	game_over_container.position = Vector2(screen_size.x / 2.0 - 200, screen_size.y / 2.0 - 100)
	game_over_container.hide()
	
	var go_label = Label.new()
	go_label.text = "G A M E   O V E R"
	go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_label.add_theme_font_size_override("font_size", 48)
	go_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	game_over_container.add_child(go_label)
	
	final_score_label = Label.new()
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score_label.add_theme_font_size_override("font_size", 24)
	game_over_container.add_child(final_score_label)
	
	var retry_button = Button.new()
	retry_button.text = "R E T R Y"
	retry_button.add_theme_font_size_override("font_size", 32)
	retry_button.pressed.connect(_on_retry_pressed)
	game_over_container.add_child(retry_button)
	
	ui_layer.add_child(game_over_container)
	add_child(ui_layer)
	name_input.grab_focus()
	
	add_child(player)
	player.position = Vector2(screen_size.x / 2, screen_size.y - 160)
	
	main_camera = Camera2D.new()
	main_camera.position = screen_size / 2.0 # Centro normale per il Title Screen
	main_camera.zoom = Vector2(1.0, 1.0) 
	add_child(main_camera)
	
	player.can_move = false
	game_state = "TITLE"

func _on_name_submitted(new_text: String):
	player_name = new_text
	if player_name == "": player_name = "PLAYER 1"
	
	title_label.queue_free()
	name_input.queue_free()
	hud_score.show()
	hp_bar.show()
	
	game_state = "INTRO"
	is_intro = true
	is_playing = true
	
	# Prepara la camera per il Super Zoom
	main_camera.position = Vector2(screen_size.x / 2, screen_size.y - 160)
	main_camera.zoom = Vector2(4.0, 4.0)

func spawn_player_bullet(pos: Vector2, color: Color = Color(0.2, 1.5, 3.0)):
	player_bullets.append({ "pos": pos, "speed": 1200.0, "color": color })

func spawn_explosion(pos: Vector2, color: Color, scale_mod: float, is_super: bool = false):
	var ex = {
		"pos": pos,
		"color": color,
		"life": 1.5 if is_super else 0.4,
		"max_life": 1.5 if is_super else 0.4,
		"is_super": is_super,
		"shards": [],
		"shockwaves": []
	}
	
	var num_waves = 2 if is_super else 1
	for i in range(num_waves):
		ex.shockwaves.append({ "radius": 0.0, "speed": randf_range(300.0, 800.0) * scale_mod })
		
	var num_shards = 40 if is_super else 8
	for i in range(num_shards):
		var angle = randf() * PI * 2.0
		var speed = randf_range(100.0, 500.0) * scale_mod
		var pts = PackedVector2Array()
		var size = randf_range(5.0, 25.0) * scale_mod
		for j in range(3):
			var a = (j * (PI*2.0/3.0)) + randf_range(-0.5, 0.5)
			var r = size * randf_range(0.3, 1.0)
			pts.append(Vector2(cos(a), sin(a)) * r)
			
		ex.shards.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"rot": randf() * PI * 2.0,
			"rot_speed": randf_range(-8.0, 8.0),
			"pts": pts
		})
	explosions.append(ex)

func trigger_game_over():
	game_state = "GAMEOVER"
	game_over_timer = 0.0
	player_hp = 0
	hp_bar.value = 0
	player.can_move = false
	player.visible = false
	add_shake(60.0)
	spawn_explosion(player.position, Color(4.0, 1.0, 0.5), 3.0, true)
	target_speed_multiplier = 0.0 # Tempo fermo completamente

func _on_retry_pressed():
	get_tree().reload_current_scene()

func add_shake(amount: float):
	shake_intensity = min(shake_intensity + amount, 80.0)

func trigger_hit_stop(duration: float):
	hit_stop_timer = max(hit_stop_timer, duration)

func spawn_railgun(pos: Vector2):
	railguns.append({ "pos": pos, "life": 0.2 })
	audio_manager.play_sfx(0.2, 5.0)
	add_shake(15.0)

func _spawn_enemy(type_idx: int, pos: Vector2, diff: float):
	var e_type = enemy_types[type_idx]
	enemies.append({
		"pos": pos,
		"hp": int(e_type.hp * diff),
		"speed": randf_range(e_type.speed[0], e_type.speed[1]) * diff,
		"ai_type": e_type.ai,
		"ai_timer": 0.0,
		"ai_state": "ENTER",
		"shoot_timer": randf_range(e_type.shoot[0], e_type.shoot[1]),
		"color": e_type.color,
		"pts": e_type.pts,
		"hit_flash": 0.0
	})

func _process(delta):
	if shake_intensity > 0:
		main_camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_intensity
		shake_intensity = lerp(shake_intensity, 0.0, 15.0 * delta)
	else:
		main_camera.offset = Vector2.ZERO
		
	if hit_stop_timer > 0:
		hit_stop_timer -= delta
		queue_redraw()
		return
		
	if game_state == "TITLE":
		global_speed_multiplier = 0.05 # Lo spazio si muove quasi impercettibilmente
		bg_renderer.update_background(delta, global_speed_multiplier, current_c_bg, current_c_neb1, current_c_neb2, audio_manager.audio_low, audio_manager.audio_mid)
		queue_redraw()
		return
		
	if not is_playing:
		return
		
	if game_state == "GAMEOVER":
		game_over_timer += delta
		
		# Fotofinish effect: slow motion estremo, zoom e blur!
		main_camera.zoom = main_camera.zoom.lerp(Vector2(2.5, 2.5), 0.8 * delta)
		main_camera.position = main_camera.position.lerp(player.position, 1.5 * delta)
		audio_manager.audio_stream_player.pitch_scale = lerp(audio_manager.audio_stream_player.pitch_scale, 0.01, 1.0 * delta)
		
		if pp_rect and pp_rect.material:
			var current_blur = pp_rect.material.get_shader_parameter("zoom_blur")
			if current_blur == null: current_blur = 0.0
			pp_rect.material.set_shader_parameter("zoom_blur", lerp(current_blur, 0.4, 1.5 * delta))
			
			var current_gray = pp_rect.material.get_shader_parameter("grayscale")
			if current_gray == null: current_gray = 0.0
			pp_rect.material.set_shader_parameter("grayscale", lerp(current_gray, 1.0, 1.5 * delta))
			
		if game_over_timer > 3.0 and not game_over_container.visible:
			final_score_label.text = player_name + " - SCORE: " + str(int(distance) + score_points)
			game_over_container.show()
		
	if is_intro:
		intro_timer -= delta
		main_camera.zoom = main_camera.zoom.lerp(Vector2(1.0, 1.0), 0.8 * delta)
		main_camera.position = main_camera.position.lerp(screen_size / 2.0, 0.8 * delta)
		target_speed_multiplier = 0.1 # Slow motion totale nell'intro
		
		if intro_timer <= 0:
			is_intro = false
			player.can_move = true
			main_camera.zoom = Vector2(1.0, 1.0)
			main_camera.position = screen_size / 2.0
			
	elif audio_manager.is_transitioning:
		audio_manager.transition_timer -= delta
		
		# Effetto di transizione: buio totale e slow motion
		target_c_bg = Color(0,0,0)
		target_c_neb1 = Color(0,0,0)
		target_c_neb2 = Color(0,0,0)
		target_speed_multiplier = 0.5 
		
		if audio_manager.transition_timer <= 0:
			audio_manager.is_transitioning = false
			audio_manager.current_track_idx = (audio_manager.current_track_idx + 1) % audio_manager.playlist.size()
			audio_manager.load_and_play_track(audio_manager.current_track_idx)
			
			var t_colors = audio_manager.playlist[audio_manager.current_track_idx].colors
			target_c_bg = t_colors[0]
			target_c_neb1 = t_colors[1]
			target_c_neb2 = t_colors[2]
	else:
		var base_target_speed = 1.0
		var pos = audio_manager.get_playback_position()
		var drop = audio_manager.get_current_drop_time()
		if pos >= drop:
			base_target_speed = 4.0 # Velocità warp
			
		# SUPERHOT MECHANIC: Time Dilation
		var speed_ratio = clamp(player.velocity.length() / player.max_speed, 0.05, 1.0)
		if player.is_dashing: speed_ratio = 1.0 # Dash forza il tempo reale
		target_speed_multiplier = base_target_speed * speed_ratio
			
		# --- PARALLASSE CAMERA BASATA SUL PLAYER ---
		# La telecamera si sposta leggermente seguendo la nave sull'asse X
		var target_cam_x = (screen_size.x / 2.0) + (player.position.x - (screen_size.x / 2.0)) * 0.15
		main_camera.position.x = lerp(main_camera.position.x, target_cam_x, 3.0 * delta)
		
	global_speed_multiplier = lerp(global_speed_multiplier, target_speed_multiplier, 1.5 * delta)
	
	# --- GAME LOOP (Nemici e Armi) ---
	if not is_intro and not audio_manager.is_transitioning:
		enemy_spawn_timer -= delta
		if enemy_spawn_timer <= 0:
			var diff = 1.0 + (distance / 5000.0) # Difficoltà crescente con la distanza
			enemy_spawn_timer = randf_range(3.0, 6.0) / clamp(diff * 0.5, 1.0, 3.0)
			
			var wave_type = randi() % 3
			var base_y = -100
			
			if wave_type == 0: # V-Shape Scout
				var cx = randf_range(200, screen_size.x - 200)
				for w in range(5):
					var offset_x = (w - 2) * 60
					var offset_y = abs(w - 2) * -50
					_spawn_enemy(0, Vector2(cx + offset_x, base_y + offset_y), diff)
			elif wave_type == 1: # Linea Orizzontale Fighter
				var start_x = randf_range(100, screen_size.x - 300)
				for w in range(3):
					_spawn_enemy(1, Vector2(start_x + w * 100, base_y), diff)
			elif wave_type == 2: # Tank con Scorta Scout
				var cx = randf_range(200, screen_size.x - 200)
				_spawn_enemy(2, Vector2(cx, base_y), diff) # Tank
				_spawn_enemy(0, Vector2(cx - 80, base_y + 40), diff) # Scout sx
				_spawn_enemy(0, Vector2(cx + 80, base_y + 40), diff) # Scout dx
			
	for i in range(player_bullets.size() - 1, -1, -1):
		var b = player_bullets[i]
		b.pos.y -= b.speed * delta
		if b.pos.y < -50:
			player_bullets.remove_at(i)
			continue
		var hit = false
		for j in range(enemies.size() - 1, -1, -1):
			var e = enemies[j]
			if b.pos.distance_to(e.pos) < 35.0:
				e.hp -= 1
				hit = true
				e.hit_flash = 0.1 # Feedback visivo
				spawn_explosion(b.pos, Color(0.5, 1.0, 2.0), 0.3)
				if e.hp <= 0:
					spawn_explosion(e.pos, Color(3.0, 1.0, 0.2), 1.0)
					if randf() > 0.8: # 20% drop powerup
						powerups.append({ "pos": e.pos, "type": randi() % 4 })
					enemies.remove_at(j)
					score_points += 250
				break
		if hit:
			player_bullets.remove_at(i)
			
	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		e.ai_timer += delta
		if e.hit_flash > 0:
			e.hit_flash -= delta
			
		# Nuove intelligenze artificiali
		if e.ai_type == 0: # Fighter: Scende, ferma, carica e spara, fugge
			if e.ai_state == "ENTER":
				e.pos.y += e.speed * global_speed_multiplier * delta
				if e.pos.y > 150:
					e.ai_state = "CHARGE"
					e.ai_timer = 1.0
			elif e.ai_state == "CHARGE":
				e.pos.x += randf_range(-2, 2)
				e.ai_timer -= delta
				if e.ai_timer <= 0:
					e.ai_state = "LEAVE"
					audio_manager.play_sfx(0.5, 0.0)
					for a in [-0.2, 0.0, 0.2]:
						var dir = (player.position - e.pos).rotated(a).normalized()
						enemy_bullets.append({ "pos": e.pos, "dir": dir, "speed": 400.0 })
			elif e.ai_state == "LEAVE":
				e.pos.y -= e.speed * global_speed_multiplier * delta
				if e.pos.y < -100: e.hp = 0
		elif e.ai_type == 1: # Scout: Curva dolce, swarm se vicino
			e.pos.y += e.speed * global_speed_multiplier * delta
			if e.pos.distance_to(player.position) < 300.0:
				e.pos = e.pos.move_toward(player.position, e.speed * 0.9 * global_speed_multiplier * delta)
			else:
				e.pos.x += sin(e.ai_timer * 3.0) * 80.0 * delta
		elif e.ai_type == 2: # Tank: Insegue il player molto lento
			e.pos.y += e.speed * 0.5 * global_speed_multiplier * delta
			e.pos.x = lerp(e.pos.x, player.position.x, 0.5 * delta)
			e.shoot_timer -= delta
			if e.shoot_timer <= 0:
				e.shoot_timer = randf_range(2.0, 4.0)
				var dir = (player.position - e.pos).normalized()
				enemy_bullets.append({ "pos": e.pos, "dir": dir, "speed": 350.0 })
			
		if e.pos.distance_to(player.position) < 40.0 and not player.is_invincible:
			spawn_explosion(player.position, Color(3.0, 0.5, 0.5), 0.8)
			add_shake(25.0)
			trigger_hit_stop(0.05)
			enemies.remove_at(i)
			player_hp -= 30.0
			hp_bar.value = player_hp
			if player_hp <= 0 and game_state != "GAMEOVER":
				trigger_game_over()
		elif e.pos.y > screen_size.y + 100:
			enemies.remove_at(i)
			
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b = enemy_bullets[i]
		b.pos += b.dir * b.speed * delta
		if b.pos.distance_to(player.position) < 15.0 and not player.is_invincible:
			spawn_explosion(player.position, Color(3.0, 0.2, 0.2), 0.5)
			add_shake(10.0)
			trigger_hit_stop(0.02)
			enemy_bullets.remove_at(i)
			player_hp -= 15.0
			hp_bar.value = player_hp
			if player_hp <= 0 and game_state != "GAMEOVER":
				trigger_game_over()
		elif b.pos.distance_to(player.position) < 45.0 and not b.has("grazed") and not player.is_invincible:
			b["grazed"] = true
			score_points += 50
			audio_manager.play_sfx(3.0, -10.0)
		elif b.pos.y > screen_size.y + 100 or b.pos.x < -100 or b.pos.x > screen_size.x + 100:
			enemy_bullets.remove_at(i)
			
	for i in range(explosions.size() - 1, -1, -1):
		var ex = explosions[i]
		ex.life -= delta
		for j in range(ex.shards.size()):
			ex.shards[j].pos += ex.shards[j].vel * delta
			ex.shards[j].vel *= 0.92
			ex.shards[j].rot += ex.shards[j].rot_speed * delta
		for j in range(ex.shockwaves.size()):
			ex.shockwaves[j].radius += ex.shockwaves[j].speed * delta
		if ex.life <= 0:
			explosions.remove_at(i)
			
	for i in range(powerups.size() - 1, -1, -1):
		var p = powerups[i]
		p.pos.y += 80.0 * global_speed_multiplier * delta
		if p.pos.distance_to(player.position) < 30.0:
			if p.type == 0:
				audio_manager.play_sfx(2.5, 5.0)
				player_hp = min(player_hp + 40.0, 100.0)
				hp_bar.value = player_hp
				spawn_explosion(player.position, Color(0.2, 3.0, 0.5), 0.5) # Verde curativo
			elif p.type == 1:
				audio_manager.play_sfx(3.5, 5.0)
				player.fire_buff_timer = 10.0
				player.weapon_type = 1
				spawn_explosion(player.position, Color(3.0, 0.5, 3.0), 0.5) # Viola armi
			elif p.type == 2:
				audio_manager.play_sfx(2.0, 5.0)
				player.fire_buff_timer = 15.0
				player.drone_active = true
				spawn_explosion(player.position, Color(0.5, 3.0, 3.0), 0.5) # Azzurro drones
			elif p.type == 3:
				audio_manager.play_sfx(0.1, 10.0)
				spawn_explosion(player.position, Color(0.0, 0.0, 0.0), 2.0)
				add_shake(40.0)
				black_holes.append({ "pos": p.pos, "life": 6.0 })
			powerups.remove_at(i)
		elif p.pos.y > screen_size.y + 100:
			powerups.remove_at(i)
			
	# Railguns (Hit detection)
	for i in range(railguns.size() - 1, -1, -1):
		var r = railguns[i]
		r.life -= delta
		if r.life <= 0:
			railguns.remove_at(i)
		else:
			var rect = Rect2(r.pos.x - 15, -1000, 30, r.pos.y + 1000)
			for j in range(enemies.size() - 1, -1, -1):
				var e = enemies[j]
				if rect.has_point(e.pos):
					e.hp -= 30 * delta # Piercing continuous massive damage
					e.hit_flash = 0.1
					if e.hp <= 0:
						trigger_hit_stop(0.05)
						audio_manager.play_sfx(1.5, -5.0)
						spawn_explosion(e.pos, Color(3.0, 1.0, 0.2), 1.0)
						if randf() > 0.8: powerups.append({ "pos": e.pos, "type": randi() % 4 })
						enemies.remove_at(j)
						score_points += 250
						
	# BLACK HOLES (Gravity and Absorption)
	for i in range(black_holes.size() - 1, -1, -1):
		var bh = black_holes[i]
		bh.life -= delta
		if bh.life <= 0:
			black_holes.remove_at(i)
		else:
			var pull_force = 400.0 * min(bh.life, 1.0)
			for e in enemies:
				var dist = e.pos.distance_to(bh.pos)
				if dist < 500.0: e.pos = e.pos.move_toward(bh.pos, (pull_force / max(dist, 10.0)) * 200.0 * delta)
				if dist < 20.0: e.hp -= 100
			for b in enemy_bullets:
				var dist = b.pos.distance_to(bh.pos)
				if dist < 500.0: b.pos = b.pos.move_toward(bh.pos, (pull_force / max(dist, 10.0)) * 300.0 * delta)
				if dist < 20.0: b.pos.y = 9999
				
	if pp_rect and pp_rect.material:
		if black_holes.size() > 0:
			var bh = black_holes[0]
			var bh_uv = (bh.pos - main_camera.position + (screen_size / 2.0)) / screen_size
			var intensity = min(bh.life, 2.0) / 2.0
			pp_rect.material.set_shader_parameter("bh_pos", bh_uv)
			pp_rect.material.set_shader_parameter("bh_intensity", intensity)
		else:
			pp_rect.material.set_shader_parameter("bh_intensity", 0.0)
	
	# Transizione Colori Nebulosa
	current_c_bg = current_c_bg.lerp(target_c_bg, 0.8 * delta)
	current_c_neb1 = current_c_neb1.lerp(target_c_neb1, 0.8 * delta)
	current_c_neb2 = current_c_neb2.lerp(target_c_neb2, 0.8 * delta)
	
	# --- AUDIO REACTIVE ---
	# Ripristina glow fisso a 1.8 per non impattare su tutto
	if world_env and world_env.environment:
		world_env.environment.glow_intensity = 1.8
	
	# Aggiorna background manager
	bg_renderer.update_background(delta, global_speed_multiplier, current_c_bg, current_c_neb1, current_c_neb2, audio_manager.audio_low, audio_manager.audio_mid)
	
	distance += scroll_speed * global_speed_multiplier * delta
	hud_score.text = player_name + " - Score: " + str(int(distance) + score_points)
	
	queue_redraw()

func _draw():
	var time = Time.get_ticks_msec() / 1000.0
	
	# --- RENDER GIOCO: ARMI E NEMICI ---
	for b in player_bullets:
		draw_rect(Rect2(b.pos - Vector2(2, 12), Vector2(4, 24)), b.color)
		
	for e in enemies:
		var draw_color = e.color
		if e.hit_flash > 0:
			draw_color = Color(10.0, 10.0, 10.0) # Flash HDR estremo
			
		var c_arr = PackedColorArray()
		c_arr.resize(e.pts.size())
		c_arr.fill(draw_color)
		draw_set_transform(e.pos, 0.0, Vector2.ONE)
		draw_polygon(e.pts, c_arr)
		draw_circle(Vector2(0,0), 6.0, Color(2.5, 0.5, 0.5)) # Core glow
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		
	for p in powerups:
		if p.type == 0:
			draw_circle(p.pos, 8.0, Color(0.2, 2.5, 0.5)) # Medkit
			draw_circle(p.pos, 4.0, Color(1.0, 1.0, 1.0))
		elif p.type == 1:
			draw_circle(p.pos, 8.0, Color(3.0, 0.5, 3.0)) # Railgun Viola
			draw_circle(p.pos, 4.0, Color(1.0, 1.0, 1.0))
		elif p.type == 2:
			draw_circle(p.pos, 8.0, Color(0.5, 3.0, 3.0)) # Drones Azzurro
			draw_circle(p.pos, 4.0, Color(1.0, 1.0, 1.0))
		elif p.type == 3:
			draw_circle(p.pos, 8.0, Color(0.0, 0.0, 0.0)) # Black Hole Nero
			draw_circle(p.pos, 4.0, Color(4.0, 0.5, 4.0)) # Bordo Violaceo HDR
			
	for r in railguns:
		draw_rect(Rect2(r.pos.x - 15, 0, 30, r.pos.y), Color(3.0, 0.5, 3.0, r.life * 5.0))
		draw_rect(Rect2(r.pos.x - 5, 0, 10, r.pos.y), Color(4.0, 3.0, 4.0, r.life * 5.0))
		
	for bh in black_holes:
		var alpha = min(bh.life, 1.0)
		draw_circle(bh.pos, 15.0, Color(0, 0, 0, alpha)) # Event horizon
		draw_arc(bh.pos, 25.0 + sin(time * 20.0)*5.0, 0, PI*2, 32, Color(2.0, 0.5, 3.0, alpha), 3.0, true)
		draw_arc(bh.pos, 35.0 + cos(time * 15.0)*10.0, 0, PI*2, 32, Color(4.0, 1.0, 1.0, alpha*0.5), 1.0, true)
		
	for b in enemy_bullets:
		draw_circle(b.pos, 5.0, Color(2.5, 0.8, 0.2))
		draw_circle(b.pos, 2.0, Color(4.0, 2.0, 1.0))
		
	for ex in explosions:
		var alpha = ex.life / ex.max_life
		var c = ex.color
		c.a = alpha
		
		for sw in ex.shockwaves:
			draw_arc(ex.pos, sw.radius, 0, PI*2, 32, c * 1.5, 2.0 + (alpha * 5.0), true)
			if ex.is_super:
				draw_arc(ex.pos, sw.radius * 0.9, 0, PI*2, 32, Color(1,1,1, alpha), 1.0, true)
				
		if ex.is_super:
			draw_circle(ex.pos, (1.0 - alpha) * 150.0, c * 0.5) # Core implosivo
			
		for s in ex.shards:
			draw_set_transform(s.pos, s.rot, Vector2.ONE)
			draw_polygon(s.pts, PackedColorArray([c, c, c]))
			draw_polyline(s.pts + PackedVector2Array([s.pts[0]]), Color(3.0, 3.0, 3.0, alpha), 1.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			
	# --- RADAR HUD ---
	if game_state != "TITLE":
		var cam_tl = main_camera.position - screen_size / 2.0
		for e in enemies:
			if e.pos.y < cam_tl.y:
				# Disegna un triangolino rosso sul bordo alto dello schermo
				var indicator_x = clamp(e.pos.x, cam_tl.x + 20, cam_tl.x + screen_size.x - 20)
				var pts = PackedVector2Array([
					Vector2(indicator_x, cam_tl.y + 30),
					Vector2(indicator_x - 10, cam_tl.y + 15),
					Vector2(indicator_x + 10, cam_tl.y + 15)
				])
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_polygon(pts, PackedColorArray([Color(1.0, 0.0, 0.0, 0.8), Color(1.0, 0.0, 0.0, 0.8), Color(1.0, 0.0, 0.0, 0.8)]))
