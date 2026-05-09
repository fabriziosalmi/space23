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
const DRONE_SHOOT_RATE: float = 0.15

# Compat: alcuni accessi vengono ancora fatti via `player.max_speed`. I keep `max_speed`
# come alias sul costante per non rompere `Main.gd`.
var max_speed: float = MAX_SPEED
var acceleration: float = ACCELERATION
var friction: float = FRICTION
var velocity = Vector2.ZERO
var screen_size: Vector2

# Typed ref to the Main orchestrator. Set by Main._ready right after add_child(player)
# so it's already wired before the first _process / first draw signal fires. Replaces
# the prior pattern of `var pn = get_parent(); if pn and pn.get("audio_manager") != null:`
# which silently no-op'd on rename instead of failing fast (and accumulated ~30 LOC of
# defensive checks across this file).
var main: Main

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

# Hit flash: brevissimo "lampo bianco" sul corpo all'impatto (≈80ms). Diverso
# dall'iframe alpha-flicker: questo è una saturazione luminosa istantanea,
# letta dal cervello come "ho preso il colpo". Triggerato da Main.damage_player.
const HIT_FLASH_DURATION: float = 0.08
var hit_flash_timer: float = 0.0

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

	# Tier-3: trail color shifts toward white-hot on bass kicks.
	var bass_kick: float = main.audio_manager.audio_low
	# Base color = neon blue Color(0.2, 1.5, 3.0). Su bass: lerp verso
	# Color(2.5, 2.5, 3.0) (bianco-hot quasi). Subtle ma sentibile.
	var trail_r: float = 0.2 + bass_kick * 2.3
	var trail_g: float = 1.5 + bass_kick * 1.0
	var trail_b: float = 3.0 + bass_kick * 0.0  # blu già al massimo
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
			trail_node.draw_line(pts[i], pts[i+1], Color(trail_r, trail_g, trail_b, alpha), 4.0 * alpha)
			
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

# Trigger del hit flash. Chiamato da Main.damage_player quando il player viene
# colpito. Visibile come bagliore bianco istantaneo (~80ms) sovrapposto al body.
func trigger_hit_flash() -> void:
	hit_flash_timer = HIT_FLASH_DURATION

# SFX shoot: stesso pitch/volume del graze (3.0 / -10dB) — alto e discreto, non
# copre la musica e si sente chiaramente sopra le esplosioni. Pan dalla pos
# del player. Il railgun è escluso (RailgunSystem ha il suo SFX dedicato).
func _play_shoot_sfx() -> void:
	main.audio_manager.play_sfx(3.0, -10.0, position)

# Disegna la nave proceduralmente: fusoliera + ali (con lighting L/R modulato dal
# roll per un fake-3D), cockpit HDR audio-reattivo, trim neon che pulsa col bass,
# luci di posizione port/starboard.
func _on_ship_draw() -> void:
	if not ship_renderer:
		return
	var n: Node2D = ship_renderer

	# Bias di luce: roll a destra ⇒ ala destra più illuminata, sinistra in ombra.
	var light_bias: float = clamp(roll * 4.0, -1.0, 1.0)
	var lit_brightness: float = 0.85 + light_bias * 0.4
	var shadow_brightness: float = 0.85 - light_bias * 0.4

	# === Reattività audio + HP (live-modulated colors) ===
	# Tier-1 polish: il trim neon pulsa coi bass, il cockpit cambia colore e
	# pulse-rate a HP basso.
	var audio_low_now: float = main.audio_manager.audio_low
	var hp_ratio: float = clamp(main.player_hp / Main.PLAYER_HP_MAX, 0.0, 1.0)
	# 1.0 idle → ~1.55 a peak audio_low. Sotto soglia bloom = pulsazione neon
	# leggera. Sopra → trim "vibra" sui kick.
	var trim_glow_mult: float = 1.0 + audio_low_now * 0.55
	# Cockpit health pulse: full HP = magenta steady; basso HP = rosso allarme
	# che lampeggia veloce. Pulse rate cresce da 4Hz a 18Hz, amp da 0.15 a 0.6.
	var hp_low: float = 1.0 - hp_ratio
	var cockpit_pulse_rate: float = 4.0 + hp_low * 14.0
	var cockpit_pulse: float = sin(time_passed * cockpit_pulse_rate)
	var cockpit_amp: float = 0.15 + hp_low * 0.45
	var cockpit_brightness: float = 1.0 + cockpit_pulse * cockpit_amp
	# Calm-breath layer: a velocità bassa la nave "respira" ad ~0.5 Hz, una
	# pulsazione molto più lenta della HP-pulse. A piena velocità il breath
	# si fonde col pulse dell'audio (poco percepibile) — ma da fermi il sub-
	# liminale "il pilota respira" sells una piccola umanità senza essere
	# vistoso. Modulato da (1 - speed_ratio): max effetto fermo, zero a MAX.
	var calm_speed_inv: float = 1.0 - clamp(velocity.length() / MAX_SPEED, 0.0, 1.0)
	cockpit_brightness *= 1.0 + 0.06 * calm_speed_inv * sin(time_passed * 3.0)
	var cockpit_color_full: Color = Color(2.5, 0.8, 3.5)   # magenta sano
	var cockpit_color_dying: Color = Color(3.5, 0.5, 0.5)  # rosso allarme

	var hull_base: Color = Color(0.32, 0.40, 0.55)
	var wing_lit: Color = Color(0.45, 0.55, 0.75) * lit_brightness
	var wing_shadow: Color = Color(0.18, 0.22, 0.32) * shadow_brightness
	var trim: Color = Color(0.4, 1.4, 3.0) * trim_glow_mult        # Neon blue (HDR + audio)
	var trim_dim: Color = Color(0.2, 0.7, 1.5) * trim_glow_mult
	var cockpit_glow: Color = cockpit_color_full.lerp(cockpit_color_dying, hp_low) * cockpit_brightness
	# nav_red/nav_green era HDR 3.0 su un singolo draw_circle 2.5px → vedi
	# i commenti sui draw_circle delle nav_lights più sotto. Adesso il core
	# HDR è ridotto a 1.3 (lieve bloom invece di artefatto blocky) e la luce
	# vive in 3 cerchi concentrici geometric (vedi sotto). Conservato il nome
	# come "core color" per chiarezza.
	var nav_red_core: Color = Color(1.3, 0.4, 0.4)
	var nav_green_core: Color = Color(0.4, 1.3, 0.45)

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

	# === Tier-2: Damage deformation ===
	# Sotto soglia 60% HP, applica piccoli offset deterministici (basati su
	# hp_low + position seed) ai vertici esterni delle ali e della coda.
	# A HP=60% no dent, a HP=0% massimo. Determinista (no jitter random
	# per-frame che farebbe vibrare la silhouette in modo nervoso).
	var damage: float = clamp((1.0 - hp_ratio - 0.4) / 0.6, 0.0, 1.0)
	if damage > 0.0:
		var d_amp: float = damage * 6.0
		# Offsets per-vertice: usa coords come seed → coerenti, non variano nel tempo
		WING_TIP_L += Vector2(d_amp * 0.4, -d_amp * 0.6)
		WING_BACK_L += Vector2(d_amp * 0.3, d_amp * 0.4)
		WING_TIP_R += Vector2(-d_amp * 0.5, d_amp * 0.3)
		WING_BACK_R += Vector2(-d_amp * 0.2, -d_amp * 0.5)
		HULL_BACK_L += Vector2(d_amp * 0.4, 0)
		HULL_BACK_R += Vector2(-d_amp * 0.3, 0)
		# A HP basso, anche il muso si "incrina" verso un lato
		NOSE += Vector2(d_amp * 0.5, d_amp * 0.4)

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

	# === LUCI DI POSIZIONE port/starboard — rounded glow a 3 cerchi ===
	# Era un singolo draw_circle 2.5px con HDR rgb 3.0 (nav_red/nav_green).
	# Il core HDR brillantissimo su area minima triggerava artefatti blocky
	# del bloom downsample di Godot 2D: il glow fa multi-mip downsample → un
	# punto bright HDR diventa un quadrato di pochi pixel al lowest mip,
	# visibile come "dark square box" stagliato contro il bg nero.
	# Fix: glow geometrico a 3 cerchi concentrici (halo dim → mid → core
	# leggermente HDR). Il bloom resta soft, il gradient è sempre circolare
	# a qualsiasi mip / risoluzione, e il visual "luce di posizione neon"
	# resta riconoscibile.
	var pulse: float = 0.7 + 0.3 * sin(time_passed * 4.0)
	# Red (port, ala sinistra)
	n.draw_circle(WING_TIP_L, 8.0, Color(0.5, 0.1, 0.1, 0.18))     # outer halo dim
	n.draw_circle(WING_TIP_L, 4.5, Color(1.0, 0.25, 0.25, 0.55))   # mid glow
	n.draw_circle(WING_TIP_L, 2.0, nav_red_core * pulse)           # core moderately HDR
	# Green (starboard, ala destra)
	n.draw_circle(WING_TIP_R, 8.0, Color(0.1, 0.5, 0.2, 0.18))
	n.draw_circle(WING_TIP_R, 4.5, Color(0.25, 1.0, 0.4, 0.55))
	n.draw_circle(WING_TIP_R, 2.0, nav_green_core * pulse)

var can_move = true
var shoot_timer = 0.0
# Timer separati per railgun e drones: prima un singolo `fire_buff_timer`
# veniva sovrascritto da entrambi i pickup → drones (15s) seguito da railgun
# (10s) accorciava la durata drones a 10s, e weapon_type non veniva mai
# resettato dai pickup non-railgun (quindi prendere drones mentre hai railgun
# manteneva railgun attivo per 15s con weapon_type=1).
var railgun_timer: float = 0.0
var drone_timer: float = 0.0

func _process(delta):
	# Freeze guards: Main._process congela i `*_system.tick` su pause e su
	# hit-stop, ma Player._process non è subordinato a Main e gira sempre.
	# Senza questi guard:
	#   - is_paused: il player si muoveva, sparava (bullet accumulati in
	#     player_bullets ma ProjectileSystem.tick non girava → all'unpause
	#     partivano in massa dal punto di nascita), powerup decadevano.
	#   - hit_stop_timer > 0: stesso pattern durante il freeze post-kill
	#     (fino a 1.2s su boss kill). Bullet sparati durante hit-stop si
	#     accumulavano e partivano in burst alla fine del freeze.
	if main and (main.is_paused or main.hit_stop_timer > 0.0):
		return

	time_passed += delta
	var input_dir = Vector2.ZERO

	# Tutti i Player timer decadono in tempo reale (delta puro). Prima alcuni
	# usavano `engine_delta = delta * gsm` causando scaling indesiderati col
	# tempo del mondo:
	#   - drop boost (gsm=4×): railgun "10s" durava 2.5s reali, drone "15s"
	#     durava 3.75s reali, dash_cooldown "1s" durava 0.25s reali (player
	#     dasha 4× più frequente nel momento più caotico — feature accidentale)
	#   - intro/transition (gsm 0.1-0.5): timer 5-10× più lunghi del nominale
	# Era misto: shoot_timer/dash_timer/iframe già in real time, mentre
	# powerup/cooldown in engine time. Ora tutto consistente: il pickup di
	# 10s dura 10s wallclock indipendente da gsm.
	if railgun_timer > 0.0:
		railgun_timer -= delta
	else:
		weapon_type = 0
	if drone_timer > 0.0:
		drone_timer -= delta
	else:
		drone_active = false

	if drone_active:
		drone_angle += delta * 4.0
		drone_shoot_timer -= delta
		if drone_shoot_timer <= 0:
			drone_shoot_timer = DRONE_SHOOT_RATE
			var p1 = position + Vector2(cos(drone_angle), sin(drone_angle)) * 60.0
			var p2 = position + Vector2(cos(drone_angle + PI), sin(drone_angle + PI)) * 60.0
			var drone_color := Color(1.0, 0.5, 3.0)
			main.spawn_drone_bullet(p1, drone_color)
			main.spawn_drone_bullet(p2, drone_color)
		
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
			var target_pos = get_global_mouse_position() - main.main_camera.offset
			# Clamp del target alla playable area (gli stessi bound del clamp di
			# `position` poco sotto). Senza questo, un cursore tenuto fuori
			# schermo (web fullscreen, mouse drag oltre il bordo) lascia
			# `target_pos` molto distante: la nave si clamperebbe al bordo
			# (position.x = screen_size.x - 80) ma la dead-zone resterebbe
			# violata (distance² ≫ 225) → input_dir continua a spingere verso
			# il bordo all'infinito, e la silhouette resta banked al massimo
			# in roll. Clampando il target, la dead-zone si disengage non
			# appena la nave raggiunge il bordo: roll torna a 0, niente input
			# fantasma.
			target_pos.x = clamp(target_pos.x, 80.0, screen_size.x - 80.0)
			target_pos.y = clamp(target_pos.y, 80.0, screen_size.y - 80.0)
			if position.distance_squared_to(target_pos) > 225.0:  # 15² — dead-zone
				input_dir += (target_pos - position).normalized()

		shoot_timer -= delta
		if (Input.is_action_pressed("fire") or is_touching) and shoot_timer <= 0:
			if weapon_type == 1:
				shoot_timer = SHOOT_RATE_RAILGUN
				main.spawn_railgun(position + Vector2(0, -30))
				# Railgun SFX è già emesso da RailgunSystem.spawn() — non duplicare.
			elif drone_active:
				shoot_timer = SHOOT_RATE_BUFFED  # Più veloce e 4 cannoni!
				main.spawn_player_bullet(position + Vector2(-30, -10))
				main.spawn_player_bullet(position + Vector2(-15, -20))
				main.spawn_player_bullet(position + Vector2(15, -20))
				main.spawn_player_bullet(position + Vector2(30, -10))
				_play_shoot_sfx()
			else:
				shoot_timer = SHOOT_RATE_NORMAL
				main.spawn_player_bullet(position + Vector2(-22, -10))
				main.spawn_player_bullet(position + Vector2(22, -10))
				_play_shoot_sfx()
	
	if dash_cooldown > 0:
		dash_cooldown -= delta
		
	# Tick i-frame timer post-damage; consuma indipendentemente dal dash.
	if hit_iframe_timer > 0.0:
		hit_iframe_timer = max(hit_iframe_timer - delta, 0.0)
	# Hit flash decay (timer ~80ms, fast).
	if hit_flash_timer > 0.0:
		hit_flash_timer = max(hit_flash_timer - delta, 0.0)

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

	# Modulate combinato: alpha flicker per i-frame + RGB brightness boost
	# per hit flash. modulate è moltiplicativo: a 3× brightness il cockpit HDR
	# saturatissimo esplode di bloom = "lampo da impatto" istantaneo.
	if ship_renderer:
		var iframe_alpha: float = 1.0
		if hit_iframe_timer > 0.0:
			iframe_alpha = 0.35 + 0.65 * abs(sin(hit_iframe_timer * 30.0))
		var flash_b: float = 1.0
		if hit_flash_timer > 0.0:
			flash_b = 1.0 + (hit_flash_timer / HIT_FLASH_DURATION) * 2.5
		ship_renderer.modulate = Color(flash_b, flash_b, flash_b, iframe_alpha)
	
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
	# Tier-2: vector thrust → i flame ruotano in opposto al roll, simulando
	# motori che orientano la spinta in curva. Roll +0.25 (right banking) →
	# flame ruotano di -0.18 rad (verso sinistra) come reazione fisica.
	var flame_thrust_rot: float = -roll * 0.7
	for i in flames.size():
		flames[i].position.y = flame_base_y[i] + ship_bob
		flames[i].rotation = flame_thrust_rot

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
