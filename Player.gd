extends Node2D
class_name Player

# ========== HITBOX ==========
const HITBOX_RADIUS_BULLET: float = 5.0
const HITBOX_RADIUS_BODY: float = 15.0

# ========== MOVIMENTO ==========
const MAX_SPEED: float = 700.0
const ACCELERATION: float = 7000.0  # Input buffer SOTA, estrema reattività
const FRICTION: float = 5000.0

# ========== DASH ==========
const DASH_DURATION: float = 0.15
const DASH_COOLDOWN: float = 1.0
const DASH_SPEED_MULT: float = 4.0

# ========== FUOCO (cadenza in secondi) ==========
const SHOOT_RATE_NORMAL: float = 0.12
const SHOOT_RATE_BUFFED: float = 0.08
const SHOOT_RATE_RAILGUN: float = 0.5
const SHOOT_RATE_MIRROR_LASER: float = 0.15
const DRONE_SHOOT_RATE: float = 0.15

# Compat: alcuni accessi vengono ancora fatti via `player.max_speed`. I keep `max_speed`
# come alias sul costante per non rompere `Main.gd`.
var max_speed: float = MAX_SPEED
var acceleration: float = ACCELERATION
var friction: float = FRICTION
var velocity = Vector2.ZERO
var screen_size: Vector2

var roll = 0.0
var time_passed = 0.0
var ship_renderer: Node2D            # Node2D dedicato al disegno procedurale della nave
var ship_bob: float = 0.0            # Hovering verticale (smoothato in _process)
var ship_scale_y: float = 1.0        # Stretching verticale in base all'accelerazione
var flame_mat: ShaderMaterial
# I 3 ColorRect dei motori. Stash come array così possiamo applicargli lo stesso
# bob di ship_renderer e tenere ugelli + corpo "agganciati" durante l'hover.
var flames: Array = []
var flame_base_y: Array = []         # y locale di partenza di ogni fiamma (per bob delta)

var is_dashing = false
var dash_timer = 0.0
var dash_cooldown = 0.0
var dash_dir = Vector2.ZERO
var is_invincible = false

# Post-damage invincibility frames: dopo aver preso danno, ~0.4s di immunità
# per evitare lo stacking di più bullet sullo stesso frame (un wall di proiettili
# potrebbe altrimenti azzerare l'HP in un singolo tick a 60fps).
const HIT_IFRAME_DURATION: float = 0.4
var hit_iframe_timer: float = 0.0

var weapon_type = 0 # 0=normal, 1=railgun
var drone_active = false
var drone_angle = 0.0
var drone_shoot_timer = 0.0

var trail_node: Node2D
var trail_history = []

func _ready():
	screen_size = get_viewport_rect().size

	# --- PROCEDURAL FIRE SHADER ---
	flame_mat = ShaderMaterial.new()
	flame_mat.shader = preload("res://shaders/flame.gdshader")
	
	# Crea 3 motori posizionati "dietro" lo sprite (essendo aggiunti prima).
	# Restano sibling di ship_renderer (z-order: motori → corpo nave sopra) ma
	# li tracciamo in `flames` per applicargli lo stesso ship_bob — altrimenti
	# corpo che fluttua + ugelli fissi = effetto "respiro asimmetrico".
	var flame_c = ColorRect.new()
	flame_c.size = Vector2(30, 100)
	flame_c.position = Vector2(-15, 25) # Motore centrale
	flame_c.material = flame_mat
	add_child(flame_c)
	flames.append(flame_c); flame_base_y.append(flame_c.position.y)

	var flame_l = ColorRect.new()
	flame_l.size = Vector2(16, 70)
	flame_l.position = Vector2(-28, 20) # Motore sinistro (più vicino al centro)
	flame_l.material = flame_mat
	add_child(flame_l)
	flames.append(flame_l); flame_base_y.append(flame_l.position.y)

	var flame_r = ColorRect.new()
	flame_r.size = Vector2(16, 70)
	flame_r.position = Vector2(12, 20) # Motore destro (più vicino al centro)
	flame_r.material = flame_mat
	add_child(flame_r)
	flames.append(flame_r); flame_base_y.append(flame_r.position.y)

	# --- NAVE PROCEDURALE ---
	# Aggiunto DOPO i flame, così l'attaccatura dei motori è coperta dal corpo nave.
	ship_renderer = Node2D.new()
	ship_renderer.name = "ShipRenderer"
	ship_renderer.draw.connect(_on_ship_draw)
	add_child(ship_renderer)

	# --- HITBOX CORE VISUALIZER ---
	# Mostra entrambe le hitbox: anello largo = collisione corpo nemico, dot = bullet
	var hitbox_node = Node2D.new()
	hitbox_node.draw.connect(func():
		hitbox_node.draw_arc(Vector2.ZERO, HITBOX_RADIUS_BODY, 0.0, TAU, 24, Color(1.0, 0.1, 0.5, 0.18), 1.0, true)
		hitbox_node.draw_circle(Vector2.ZERO, HITBOX_RADIUS_BULLET, Color(1.0, 0.1, 0.5, 0.8))
		hitbox_node.draw_circle(Vector2.ZERO, 2.5, Color(1.0, 1.0, 1.0, 1.0))
	)
	hitbox_node.z_index = 10
	hitbox_node.name = "HitboxVisualizer"
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

# Disegna la nave proceduralmente: fusoliera + ali (con lighting L/R modulato dal
# roll per un fake-3D), cockpit HDR, trim neon e luci di posizione port/starboard.
func _on_ship_draw() -> void:
	if not ship_renderer:
		return
	var n: Node2D = ship_renderer

	# Bias di luce: roll a destra ⇒ ala destra più illuminata, sinistra in ombra.
	var light_bias: float = clamp(roll * 4.0, -1.0, 1.0)
	var lit_brightness: float = 0.85 + light_bias * 0.4
	var shadow_brightness: float = 0.85 - light_bias * 0.4

	var hull_base: Color = Color(0.32, 0.40, 0.55)
	var wing_lit: Color = Color(0.45, 0.55, 0.75) * lit_brightness
	var wing_shadow: Color = Color(0.18, 0.22, 0.32) * shadow_brightness
	var trim: Color = Color(0.4, 1.4, 3.0)         # Neon blue (HDR)
	var trim_dim: Color = Color(0.2, 0.7, 1.5)
	var cockpit_glow: Color = Color(2.5, 0.8, 3.5) # Magenta (HDR)
	var nav_red: Color = Color(3.0, 0.4, 0.4)
	var nav_green: Color = Color(0.4, 3.0, 0.6)

	# === VERTICI (origine al centro nave, naso = -y) ===
	var NOSE := Vector2(0, -45)
	var SHOULDER_L := Vector2(-7, -28)
	var SHOULDER_R := Vector2(7, -28)
	var HULL_MID_L := Vector2(-9, -8)
	var HULL_MID_R := Vector2(9, -8)
	var HULL_BACK_L := Vector2(-13, 22)
	var HULL_BACK_R := Vector2(13, 22)
	var ENGINE_L := Vector2(-22, 25)
	var ENGINE_R := Vector2(22, 25)

	var WING_TIP_L := Vector2(-55, 14)
	var WING_BACK_L := Vector2(-28, 23)
	var WING_TIP_R := Vector2(55, 14)
	var WING_BACK_R := Vector2(28, 23)

	# === ALI ===
	var left_wing := PackedVector2Array([HULL_MID_L, WING_TIP_L, WING_BACK_L, HULL_BACK_L])
	var right_wing := PackedVector2Array([HULL_MID_R, HULL_BACK_R, WING_BACK_R, WING_TIP_R])
	var lw_cols := PackedColorArray()
	lw_cols.resize(4)
	lw_cols.fill(wing_shadow)
	var rw_cols := PackedColorArray()
	rw_cols.resize(4)
	rw_cols.fill(wing_lit)
	n.draw_polygon(left_wing, lw_cols)
	n.draw_polygon(right_wing, rw_cols)

	# === FUSOLIERA ===
	var hull := PackedVector2Array([NOSE, SHOULDER_R, HULL_MID_R, HULL_BACK_R, ENGINE_R, ENGINE_L, HULL_BACK_L, HULL_MID_L, SHOULDER_L])
	var hull_cols := PackedColorArray()
	hull_cols.resize(hull.size())
	hull_cols.fill(hull_base)
	n.draw_polygon(hull, hull_cols)

	# === TRIM NEON (HDR) ===
	# Profili ali
	n.draw_polyline(PackedVector2Array([HULL_MID_L, WING_TIP_L, WING_BACK_L]), trim, 1.2, true)
	n.draw_polyline(PackedVector2Array([HULL_MID_R, WING_TIP_R, WING_BACK_R]), trim, 1.2, true)
	# Spina dorsale
	n.draw_polyline(PackedVector2Array([NOSE, Vector2(0, -10), Vector2(0, 22)]), trim_dim, 1.0, true)
	# Riga sotto-cockpit
	n.draw_line(SHOULDER_L, SHOULDER_R, trim_dim, 1.0, true)
	# Profilo fusoliera
	n.draw_polyline(PackedVector2Array([NOSE, SHOULDER_R, HULL_MID_R, HULL_BACK_R, ENGINE_R]), trim_dim, 1.0, true)
	n.draw_polyline(PackedVector2Array([NOSE, SHOULDER_L, HULL_MID_L, HULL_BACK_L, ENGINE_L]), trim_dim, 1.0, true)

	# === COCKPIT (a forma di lacrima) ===
	var cockpit := PackedVector2Array([Vector2(0, -32), Vector2(-4, -18), Vector2(0, -8), Vector2(4, -18)])
	n.draw_polygon(cockpit, PackedColorArray([cockpit_glow * 1.3, cockpit_glow, cockpit_glow * 1.5, cockpit_glow]))

	# === LUCI DI POSIZIONE port/starboard, pulsanti ===
	var pulse: float = 0.7 + 0.3 * sin(time_passed * 4.0)
	n.draw_circle(WING_TIP_L, 2.5, nav_red * pulse)
	n.draw_circle(WING_TIP_R, 2.5, nav_green * pulse)

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
			drone_shoot_timer = DRONE_SHOOT_RATE
			if get_parent().has_method("spawn_player_bullet"):
				var p1 = position + Vector2(cos(drone_angle), sin(drone_angle)) * 60.0
				var p2 = position + Vector2(cos(drone_angle + PI), sin(drone_angle + PI)) * 60.0
				# Bug pre-esistente: il 2° arg e' `dir: Vector2`, non `color`.
				# Passiamo Vector2.UP esplicito così il Color finisce nel suo slot.
				get_parent().spawn_player_bullet(p1, Vector2.UP, Color(1.0, 0.5, 3.0))
				get_parent().spawn_player_bullet(p2, Vector2.UP, Color(1.0, 0.5, 3.0))
		
	if can_move:
		if Input.is_action_pressed("move_up"):    input_dir.y -= 1
		if Input.is_action_pressed("move_down"):  input_dir.y += 1
		if Input.is_action_pressed("move_left"):  input_dir.x -= 1
		if Input.is_action_pressed("move_right"): input_dir.x += 1

		var is_touching = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if is_touching:
			# Compensa l'offset di shake della camera: get_global_mouse_position()
			# include il camera offset, quindi senza compensazione il target balla
			# con la camera e la nave segue il jitter (frustrante in mouse/touch).
			var target_pos = get_global_mouse_position()
			var main_node = get_parent()
			if main_node and main_node.get("main_camera") != null:
				target_pos -= main_node.main_camera.offset
			if position.distance_squared_to(target_pos) > 225.0:  # 15² — dead-zone
				input_dir += (target_pos - position).normalized()

		shoot_timer -= delta
		if (Input.is_action_pressed("fire") or is_touching) and shoot_timer <= 0:
			if weapon_type == 1:
				shoot_timer = SHOOT_RATE_RAILGUN
				if get_parent().has_method("spawn_railgun"):
					get_parent().spawn_railgun(position + Vector2(0, -30))
			elif weapon_type == 2:
				shoot_timer = SHOOT_RATE_MIRROR_LASER
				if get_parent().has_method("spawn_player_bullet"):
					get_parent().spawn_player_bullet(position + Vector2(0, -20), Vector2(-0.8, -1).normalized(), Color(0.2, 3.0, 1.5), 3)
					get_parent().spawn_player_bullet(position + Vector2(0, -20), Vector2(0.8, -1).normalized(), Color(0.2, 3.0, 1.5), 3)
			elif fire_buff_timer > 0.0:
				shoot_timer = SHOOT_RATE_BUFFED  # Più veloce e 4 cannoni!
				if get_parent().has_method("spawn_player_bullet"):
					get_parent().spawn_player_bullet(position + Vector2(-30, -10))
					get_parent().spawn_player_bullet(position + Vector2(-15, -20))
					get_parent().spawn_player_bullet(position + Vector2(15, -20))
					get_parent().spawn_player_bullet(position + Vector2(30, -10))
			else:
				shoot_timer = SHOOT_RATE_NORMAL
				if get_parent().has_method("spawn_player_bullet"):
					get_parent().spawn_player_bullet(position + Vector2(-22, -10))
					get_parent().spawn_player_bullet(position + Vector2(22, -10))
	
	if dash_cooldown > 0:
		dash_cooldown -= engine_delta
		
	# Tick i-frame timer post-damage; consuma indipendentemente dal dash.
	if hit_iframe_timer > 0.0:
		hit_iframe_timer = max(hit_iframe_timer - delta, 0.0)

	if is_dashing:
		dash_timer -= delta # Real time! Il dash fotte il tempo
		velocity = dash_dir * (MAX_SPEED * DASH_SPEED_MULT)
		if dash_timer <= 0:
			is_dashing = false
	else:
		if input_dir.length() > 0:
			input_dir = input_dir.normalized()
			velocity = velocity.move_toward(input_dir * MAX_SPEED, ACCELERATION * delta)

			# Attiva Dash
			if Input.is_action_pressed("dash") and dash_cooldown <= 0:
				is_dashing = true
				dash_timer = DASH_DURATION
				dash_cooldown = DASH_COOLDOWN
				dash_dir = input_dir
		else:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		
	position += velocity * delta
	position.x = clamp(position.x, 80, screen_size.x - 80)
	position.y = clamp(position.y, 80, screen_size.y - 80)

	# Stato di invulnerabilità unificato: dash o post-damage i-frame.
	# (Main.gd setta is_invincible=true durante retry; viene sovrascritto qui ma
	# il retry usa is_invincible solo come marker, non lo legge.)
	is_invincible = is_dashing or hit_iframe_timer > 0.0

	# Flash visivo durante i-frame: la nave lampeggia rapidamente (~10 Hz) così
	# il giocatore percepisce visivamente la finestra di immunità.
	if ship_renderer:
		if hit_iframe_timer > 0.0:
			ship_renderer.modulate.a = 0.35 + 0.65 * abs(sin(hit_iframe_timer * 30.0))
		else:
			ship_renderer.modulate.a = 1.0
	
	# Effetto rollio in 2D (inclina lo sprite)
	var target_roll = input_dir.x * 0.25 # inclinazione max
	roll = lerp(roll, target_roll, 10.0 * delta)
	rotation = roll
	
	# Effetti di stretching e hovering (nave procedurale)
	var speed_ratio = velocity.length() / MAX_SPEED
	ship_bob = sin(time_passed * 6.0) * 10.0 * (1.0 - speed_ratio)
	$HitboxVisualizer.position.y = ship_bob

	# Stretching verticale + intensità fuoco in base alla direzione di input
	var target_scale_y: float = 1.0
	var target_power: float = 0.5
	if input_dir.y < 0:
		target_scale_y = 1.1  # Si allunga
		target_power = 1.0    # Fuoco al massimo
	elif input_dir.y > 0:
		target_scale_y = 0.9  # Si accorcia
		target_power = 0.2    # Fuoco al minimo
	ship_scale_y = lerp(ship_scale_y, target_scale_y, 12.0 * delta)

	if ship_renderer:
		ship_renderer.position.y = ship_bob
		ship_renderer.scale.y = ship_scale_y
		ship_renderer.queue_redraw()

	# Applica lo stesso bob ai motori (siblings di ship_renderer, non figli):
	# senza questo, il corpo fluttua su/giù mentre gli ugelli restano fermi e
	# si vede una desincronizzazione fastidiosa.
	for i in flames.size():
		flames[i].position.y = flame_base_y[i] + ship_bob

	# Aggiorna l'intensità del fuoco nel material
	if flame_mat:
		var current_power = flame_mat.get_shader_parameter("power")
		if current_power == null: current_power = 0.5
		flame_mat.set_shader_parameter("power", lerp(current_power, target_power, 15.0 * delta))

	# Aggiorna il trail procedurale
	trail_history.push_front({ "pos": global_position, "rot": global_rotation })
	if trail_history.size() > (20 if is_dashing else 10):
		trail_history.pop_back()
	trail_node.queue_redraw()
