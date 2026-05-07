extends Node2D

var max_speed = 700.0
var acceleration = 7000.0 # Input buffer SOTA, estrema reattività
var friction = 5000.0
var velocity = Vector2.ZERO
var screen_size: Vector2

var roll = 0.0
var time_passed = 0.0
var sprite: Sprite2D
var flame_mat: ShaderMaterial

var is_dashing = false
var dash_timer = 0.0
var dash_cooldown = 0.0
var dash_dir = Vector2.ZERO
var is_invincible = false

var weapon_type = 0 # 0=normal, 1=railgun
var drone_active = false
var drone_angle = 0.0
var drone_shoot_timer = 0.0

var trail_node: Node2D
var trail_history = []

func _ready():
	screen_size = get_viewport_rect().size
	sprite = Sprite2D.new()
	
	# Controlliamo se l'utente ha salvato l'immagine
	if ResourceLoader.exists("res://ship.png"):
		sprite.texture = load("res://ship.png")
		# Riduciamo la scala per rendere la navicella più piccola
		sprite.scale = Vector2(0.18, 0.18)
		
		# MAGIA: Shader per rimuovere automaticamente lo sfondo nero e le stelle
		# senza che tu debba usare Photoshop!
		var mat = ShaderMaterial.new()
		var shader = Shader.new()
		shader.code = """
        shader_type canvas_item;
        void fragment() {
            vec4 col = texture(TEXTURE, UV);
            
            // 1. Rimuove il nero di sfondo
            if (col.r < 0.05 && col.g < 0.05 && col.b < 0.05) {
                col.a = 0.0;
            }
            
            // 2. Crea un Bounding Box (rettangolo) largo per non tagliare le ali o i reattori
            // ma sufficiente a tagliare i pianeti ai bordi estremi dell'immagine.
            if (UV.x < 0.22 || UV.x > 0.78 || UV.y < 0.02 || UV.y > 0.98) {
                col.a = 0.0; // Nascondi i pianeti
            }
            
            COLOR = col;
        }
		"""
		mat.shader = shader
		sprite.material = mat
	else:
		print("ATTENZIONE: Manca il file ship.png!")
		
	# --- PROCEDURAL FIRE SHADER ---
	flame_mat = ShaderMaterial.new()
	var flame_shader = Shader.new()
	flame_shader.code = """
    shader_type canvas_item;
    uniform float power = 1.0;
    
    float noise(vec2 p) { return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }
    float smooth_noise(vec2 uv) {
        vec2 lv = fract(uv); vec2 id = floor(uv);
        lv = lv * lv * (3.0 - 2.0 * lv);
        return mix(mix(noise(id), noise(id + vec2(1,0)), lv.x), mix(noise(id + vec2(0,1)), noise(id + vec2(1,1)), lv.x), lv.y);
    }
    
    void fragment() {
        vec2 uv = UV;
        // Forma della fiamma: spessa sopra, fine sotto
        float x_dist = abs(uv.x - 0.5);
        float width = 0.5 - (uv.y * 0.4);
        
        // Scorrimento veloce animato
        vec2 nuv = uv * vec2(3.0, 6.0) - vec2(0.0, TIME * 15.0);
        float n = smooth_noise(nuv) * smooth_noise(nuv * 2.0);
        
        // Sfumature sui bordi e sulla punta (controllata dal power)
        float edge_fade = smoothstep(width, width * 0.2, x_dist);
        float y_fade = smoothstep(1.0, 0.1, uv.y / max(0.1, power)); 
        
        float intensity = n * edge_fade * y_fade * 3.0;
        
        // Colori Estremamente Estetici (HDR per Glow 100x)
        vec3 col_core = vec3(2.5, 2.0, 1.5); // Giallo/Bianco caldissimo (HDR)
        vec3 col_mid = vec3(2.0, 0.8, 0.0);   // Arancio esplosivo (HDR)
        vec3 col_edge = vec3(0.0, 1.0, 2.5);  // Base Blu Ionico (HDR)
        
        vec3 color = mix(col_edge, col_mid, smoothstep(0.1, 0.6, intensity));
        color = mix(color, col_core, smoothstep(0.6, 0.9, intensity));
        
        COLOR = vec4(color, intensity * 1.5);
    }
	"""
	flame_mat.shader = flame_shader
	
	# Crea 3 motori posizionati "dietro" lo sprite (essendo aggiunti prima)
	var flame_c = ColorRect.new()
	flame_c.size = Vector2(30, 100)
	flame_c.position = Vector2(-15, 25) # Motore centrale
	flame_c.material = flame_mat
	add_child(flame_c)
	
	var flame_l = ColorRect.new()
	flame_l.size = Vector2(16, 70)
	flame_l.position = Vector2(-28, 20) # Motore sinistro (più vicino al centro)
	flame_l.material = flame_mat
	add_child(flame_l)
	
	var flame_r = ColorRect.new()
	flame_r.size = Vector2(16, 70)
	flame_r.position = Vector2(12, 20) # Motore destro (più vicino al centro)
	flame_r.material = flame_mat
	add_child(flame_r)

	# Aggiungi lo sprite PER ULTIMO così copre l'attaccatura del fuoco
	add_child(sprite)
	
	# --- HITBOX CORE VISUALIZER ---
	var hitbox_node = Node2D.new()
	hitbox_node.draw.connect(func():
		hitbox_node.draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.1, 0.5, 0.8))
		hitbox_node.draw_circle(Vector2.ZERO, 2.5, Color(1.0, 1.0, 1.0, 1.0))
	)
	hitbox_node.z_index = 10
	add_child(hitbox_node)
	
	# --- PROCEDURAL TRAIL ---
	trail_node = Node2D.new()
	trail_node.top_level = true # Non segue la rotazione/posizione del parent in modo rigido
	add_child(trail_node)
	trail_node.draw.connect(_on_trail_draw)

func _on_trail_draw():
	if trail_history.size() < 2: return
	
	# Disegna le scie laterali (sulle ali)
	for side in [-1, 1]:
		var pts = PackedVector2Array()
		for i in range(trail_history.size()):
			var p = trail_history[i]
			var offset = Vector2(25 * side, 10).rotated(p.rot)
			# Trasforma da globale a locale per il trail_node
			pts.append(p.pos - trail_node.global_position + offset)
			
		for i in range(pts.size() - 1):
			var alpha = 1.0 - (float(i) / trail_history.size())
			trail_node.draw_line(pts[i], pts[i+1], Color(0.2, 1.5, 3.0, alpha), 4.0 * alpha)
			
	# Se stiamo dashando, disegna anche una scia centrale massiccia
	if is_dashing:
		var pts = PackedVector2Array()
		for i in range(trail_history.size()):
			var p = trail_history[i]
			pts.append(p.pos - trail_node.global_position)
		for i in range(pts.size() - 1):
			var alpha = 1.0 - (float(i) / trail_history.size())
			trail_node.draw_line(pts[i], pts[i+1], Color(3.0, 3.0, 3.0, alpha), 15.0 * alpha)
			
	# Draw drones
	if drone_active:
		var p1 = Vector2(cos(drone_angle), sin(drone_angle)) * 60.0
		var p2 = Vector2(cos(drone_angle + PI), sin(drone_angle + PI)) * 60.0
		trail_node.draw_circle(p1, 6.0, Color(1.0, 0.5, 3.0))
		trail_node.draw_circle(p2, 6.0, Color(1.0, 0.5, 3.0))

var can_move = true
var shoot_timer = 0.0
var fire_buff_timer = 0.0

func _process(delta):
	time_passed += delta
	var input_dir = Vector2.ZERO
	
	var engine_delta = delta * max(get_parent().global_speed_multiplier, 0.05)
	
	if fire_buff_timer > 0.0:
		fire_buff_timer -= engine_delta
	else:
		weapon_type = 0
		drone_active = false
		
	if drone_active:
		drone_angle += engine_delta * 4.0
		drone_shoot_timer -= engine_delta
		if drone_shoot_timer <= 0:
			drone_shoot_timer = 0.15
			if get_parent().has_method("spawn_player_bullet"):
				var p1 = position + Vector2(cos(drone_angle), sin(drone_angle)) * 60.0
				var p2 = position + Vector2(cos(drone_angle + PI), sin(drone_angle + PI)) * 60.0
				get_parent().spawn_player_bullet(p1, Color(1.0, 0.5, 3.0))
				get_parent().spawn_player_bullet(p2, Color(1.0, 0.5, 3.0))
		
	if can_move:
		if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W): input_dir.y -= 1
		if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): input_dir.x += 1
		
		shoot_timer -= engine_delta
		if Input.is_key_pressed(KEY_SPACE) and shoot_timer <= 0:
			if weapon_type == 1:
				shoot_timer = 0.5 # Railgun rate
				if get_parent().has_method("spawn_railgun"):
					get_parent().spawn_railgun(position + Vector2(0, -30))
			elif weapon_type == 2:
				shoot_timer = 0.15 # Mirror Laser
				if get_parent().has_method("spawn_player_bullet"):
					get_parent().spawn_player_bullet(position + Vector2(0, -20), Vector2(-0.8, -1).normalized(), Color(0.2, 3.0, 1.5), 3)
					get_parent().spawn_player_bullet(position + Vector2(0, -20), Vector2(0.8, -1).normalized(), Color(0.2, 3.0, 1.5), 3)
			elif fire_buff_timer > 0.0:
				shoot_timer = 0.08 # Più veloce e 4 cannoni!
				if get_parent().has_method("spawn_player_bullet"):
					get_parent().spawn_player_bullet(position + Vector2(-30, -10))
					get_parent().spawn_player_bullet(position + Vector2(-15, -20))
					get_parent().spawn_player_bullet(position + Vector2(15, -20))
					get_parent().spawn_player_bullet(position + Vector2(30, -10))
			else:
				shoot_timer = 0.12 # Cadenza normale
				if get_parent().has_method("spawn_player_bullet"):
					get_parent().spawn_player_bullet(position + Vector2(-22, -10))
					get_parent().spawn_player_bullet(position + Vector2(22, -10))
	
	if dash_cooldown > 0:
		dash_cooldown -= engine_delta
		
	if is_dashing:
		dash_timer -= delta # Real time! Il dash fotte il tempo
		velocity = dash_dir * (max_speed * 4.0)
		is_invincible = true
		if dash_timer <= 0:
			is_dashing = false
			is_invincible = false
	else:
		is_invincible = false
		if input_dir.length() > 0:
			input_dir = input_dir.normalized()
			velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
			
			# Attiva Dash
			if Input.is_key_pressed(KEY_SHIFT) and dash_cooldown <= 0:
				is_dashing = true
				dash_timer = 0.15 # Durata del dash
				dash_cooldown = 1.0
				dash_dir = input_dir
		else:
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		
	position += velocity * delta
	position.x = clamp(position.x, 80, screen_size.x - 80)
	position.y = clamp(position.y, 80, screen_size.y - 80)
	
	# Effetto rollio in 2D (inclina lo sprite)
	var target_roll = input_dir.x * 0.25 # inclinazione max
	roll = lerp(roll, target_roll, 10.0 * delta)
	rotation = roll
	
	# Effetti di stretching e hovering
	if sprite.texture != null:
		# Hovering quando ferma
		var speed_ratio = velocity.length() / max_speed
		var bob = sin(time_passed * 6.0) * 10.0 * (1.0 - speed_ratio)
		sprite.position.y = bob
		
		# Stretching basato sull'accelerazione
		var base_scale = 0.18
		var target_scale_y = base_scale
		var target_power = 0.5
		
		if input_dir.y < 0: 
			target_scale_y = base_scale * 1.1 # Si allunga
			target_power = 1.0 # Fuoco al massimo
		elif input_dir.y > 0: 
			target_scale_y = base_scale * 0.9 # Si accorcia
			target_power = 0.2 # Fuoco al minimo
			
		sprite.scale.y = lerp(sprite.scale.y, target_scale_y, 12.0 * delta)
		
		# Aggiorna l'intensità del fuoco nel material
		if flame_mat:
			var current_power = flame_mat.get_shader_parameter("power")
			if current_power == null: current_power = 0.5
			var new_power = lerp(current_power, target_power, 15.0 * delta)
			flame_mat.set_shader_parameter("power", new_power)
			
	# Aggiorna il trail procedurale
	trail_history.push_front({ "pos": global_position, "rot": global_rotation })
	if trail_history.size() > (20 if is_dashing else 10):
		trail_history.pop_back()
	trail_node.queue_redraw()
