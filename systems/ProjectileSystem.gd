extends Node2D
class_name ProjectileSystem

# Owns:
#   - player_bullets[]               (rettangoli blu, sparati dalla nave)
#   - active_enemy_bullets[]         (cerchi neon, dai nemici)
#   - pool_enemy_bullets[]           (pre-allocato, riusato per evitare allocazioni in hot-path)
#
# Gestisce gravità da BH, movimento (con time-dilation per i proiettili nemici),
# rimbalzi sui bordi (player bullet con `bounces > 0`), homing nemico, collisioni
# vs nemici e player, grazing.

const PLAYER_BULLET_SPEED: float = 1200.0
const HOMING_TURN_RATE: float = 1.2
const COL_ENEMY_PINK := Color(3.0, 0.2, 1.5)
const CORE_ENEMY_PINK := Color(4.0, 1.0, 3.0)
const COL_ENEMY_HOMING := Color(3.0, 1.0, 0.1)
const CORE_ENEMY_HOMING := Color(4.0, 3.0, 1.0)

var player_bullets: Array = []
var active_enemy_bullets: Array = []
var pool_enemy_bullets: Array = []
var _had_bullets: bool = false

# Refs (settate da Main in _ready)
var main: Node
var player: Node2D
var enemy_system: EnemySystem
var bh_system: Node              # BlackHoleSystem
var explosion_system: ExplosionSystem
var audio_manager: Node
var screen_size: Vector2 = Vector2.ZERO

func _init_pool() -> void:
	pool_enemy_bullets.clear()
	for i in range(Main.ENEMY_BULLET_POOL_SIZE):
		pool_enemy_bullets.append({ "pos": Vector2.ZERO, "dir": Vector2.ZERO, "speed": 0.0, "homing": false, "grazed": false })

func setup_pool() -> void:
	# Chiamata dopo che screen_size è disponibile.
	_init_pool()

# ========== SPAWN ==========

func spawn_player_bullet(pos: Vector2, dir: Vector2 = Vector2.UP, color: Color = Color(0.2, 1.5, 3.0), bounces: int = 0) -> void:
	player_bullets.append({ "pos": pos, "dir": dir, "speed": PLAYER_BULLET_SPEED, "color": color, "bounces": bounces })

func spawn_enemy_bullet(pos: Vector2, dir: Vector2, speed: float, homing: bool = false) -> void:
	if pool_enemy_bullets.size() == 0:
		return  # Pool esaurito (estrema bullet hell): drop silente
	var b: Dictionary = pool_enemy_bullets.pop_back()
	b.pos = pos
	b.dir = dir
	b.speed = speed
	b.homing = homing
	b.grazed = false
	active_enemy_bullets.append(b)

func _remove_enemy_bullet_at(idx: int) -> void:
	# Swap-and-pop verso il pool.
	var b: Dictionary = active_enemy_bullets[idx]
	pool_enemy_bullets.append(b)
	active_enemy_bullets[idx] = active_enemy_bullets[active_enemy_bullets.size() - 1]
	active_enemy_bullets.pop_back()

func clear_enemy_bullets_with_fx() -> void:
	# Usato dalla smart bomb: ring leggero campionato (max ~30) per evitare
	# lag spike su WebGL quando ci sono centinaia di proiettili a schermo.
	var total: int = active_enemy_bullets.size()
	var stride: int = max(1, int(float(total) / 30.0))
	for i in range(total):
		var b: Dictionary = active_enemy_bullets[i]
		if i % stride == 0:
			explosion_system.spawn_ring(b.pos, Color(1.0, 0.5, 0.5), 24.0, 0.25)
		pool_enemy_bullets.append(b)
	active_enemy_bullets.clear()

func clear_all() -> void:
	player_bullets.clear()
	active_enemy_bullets.clear()
	_init_pool()
	queue_redraw()

# ========== TICK ==========

func tick(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var has_any: bool = not player_bullets.is_empty() or not active_enemy_bullets.is_empty()
	if not has_any:
		if _had_bullets:
			_had_bullets = false
			queue_redraw()
		return
	_had_bullets = true
	var black_holes: Array = bh_system.black_holes if bh_system else []
	# Cap velocità bullet nemici nei Drop a 2.2x per mantenere schivabilità
	# anche durante i peak 4.8x del warp visivo.
	var gsm: float = min(main.global_speed_multiplier if main else 1.0, 2.2)

	_tick_player_bullets(delta, black_holes)
	_tick_enemy_bullets(delta, gsm, black_holes)
	queue_redraw()

func _tick_player_bullets(delta: float, black_holes: Array) -> void:
	if player_bullets.is_empty():
		return
	var has_bh: bool = not black_holes.is_empty()
	var bh_r: float = Main.BH_PULL_RADIUS
	var bh_r_sq: float = bh_r * bh_r
	var bh_force_dt: float = Main.BH_PULL_FORCE_PLAYER_BULLET * delta
	var max_x: float = screen_size.x + 50.0
	var max_y: float = screen_size.y + 50.0
	var enemies: Array = enemy_system.enemies if enemy_system else []
	var pad: float = Main.PLAYER_BULLET_HIT_PADDING

	for i in range(player_bullets.size() - 1, -1, -1):
		var b: Dictionary = player_bullets[i]

		# Gravità BH (squared distance check prima di sqrt)
		if has_bh:
			for bh in black_holes:
				var d_sq: float = b.pos.distance_squared_to(bh.pos)
				if d_sq < bh_r_sq and d_sq > 0.0001:
					var d: float = sqrt(d_sq)
					var pull: Vector2 = ((bh.pos - b.pos) / d) * (1.0 - d / bh_r) * bh_force_dt
					b.dir = (b.dir * b.speed + pull).normalized()

		# Movimento (real-time, ignora time-dilation)
		b.pos += b.dir * b.speed * delta

		# Rimbalzo su bordi (mirror-laser style)
		if b.bounces > 0:
			if b.pos.x < 0 or b.pos.x > screen_size.x:
				b.dir.x *= -1.0
				b.bounces -= 1
				b.pos.x = clamp(b.pos.x, 0, screen_size.x)

		# Cull off-screen
		if b.pos.y < -50.0 or b.pos.y > max_y or b.pos.x < -50.0 or b.pos.x > max_x:
			player_bullets.remove_at(i)
			continue

		var hit: bool = false
		for j in range(enemies.size() - 1, -1, -1):
			var e: Dictionary = enemies[j]
			var aabb: Vector2 = e.hit_aabb
			if abs(b.pos.x - e.pos.x) < aabb.x + pad and abs(b.pos.y - e.pos.y) < aabb.y + pad:
				e.hp -= Main.PLAYER_BULLET_DAMAGE
				hit = true
				e.hit_flash = 0.1
				if e.hp <= 0:
					_kill_enemy_at(j, e)
				else:
					explosion_system.spawn(b.pos, Color(0.5, 1.0, 2.0), 0.15)
				break
		if hit:
			player_bullets.remove_at(i)

func _tick_enemy_bullets(delta: float, gsm: float, black_holes: Array) -> void:
	if active_enemy_bullets.is_empty():
		return
	var has_bh: bool = not black_holes.is_empty()
	var bh_r: float = Main.BH_PULL_RADIUS
	var bh_r_sq: float = bh_r * bh_r
	var bh_force_dt: float = Main.BH_PULL_FORCE_PROJECTILE * delta
	var move_dt: float = delta * gsm
	var homing_t: float = HOMING_TURN_RATE * delta
	var player_pos: Vector2 = player.position
	var hb: float = player.HITBOX_RADIUS_BULLET
	var hb_sq: float = hb * hb
	var graze_sq: float = Main.GRAZE_RADIUS * Main.GRAZE_RADIUS
	var iframed: bool = player.is_invincible or player.hit_iframe_timer > 0.0
	var max_y: float = screen_size.y + 100.0
	var max_x: float = screen_size.x + 100.0

	for i in range(active_enemy_bullets.size() - 1, -1, -1):
		var b: Dictionary = active_enemy_bullets[i]

		# Gravità BH (squared distance check prima di sqrt)
		if has_bh:
			for bh in black_holes:
				var d_sq: float = b.pos.distance_squared_to(bh.pos)
				if d_sq < bh_r_sq and d_sq > 0.0001:
					var d: float = sqrt(d_sq)
					var pull: Vector2 = ((bh.pos - b.pos) / d) * (1.0 - d / bh_r) * bh_force_dt
					b.dir = (b.dir * b.speed + pull).normalized()

		# Homing
		if b.homing:
			var desired_dir: Vector2 = (player_pos - b.pos).normalized()
			b.dir = b.dir.lerp(desired_dir, homing_t).normalized()

		# Movimento
		b.pos += b.dir * (b.speed * move_dt)

		# Player hit / graze (hoisted invariants)
		var dist_sq: float = b.pos.distance_squared_to(player_pos)
		if dist_sq < hb_sq and not iframed:
			explosion_system.spawn(player_pos, Color(3.0, 0.2, 0.2), 0.5)
			main.add_shake(10.0)
			main.trigger_hit_stop(0.02)
			_remove_enemy_bullet_at(i)
			main.damage_player(Main.ENEMY_BULLET_DAMAGE)
			iframed = true
		elif dist_sq < graze_sq and not b.grazed and not iframed:
			b.grazed = true
			var graze_pts: int = main.add_scaled_score(Main.SCORE_PER_GRAZE)
			main.gain_flow(Main.FLOW_GAIN_PER_GRAZE)
			main.spawn_floating_text(b.pos, "GRAZE +%d" % graze_pts, Color(0.6, 1.0, 1.0), 10, 0.55)
			explosion_system.spawn(b.pos, Color(1.0, 1.0, 1.0, 0.5), 0.2)
			audio_manager.play_sfx(3.0, -10.0, b.pos)
		elif b.pos.y > max_y or b.pos.y < -100.0 or b.pos.x < -100.0 or b.pos.x > max_x:
			_remove_enemy_bullet_at(i)

# Kill side-effect (FX, score, hit-stop) lives in Main.handle_enemy_kill — same
# logic now reused by RailgunSystem and BlackHoleSystem so a boss killed by any
# damage source gets the dramatic finish.
func _kill_enemy_at(j: int, e: Dictionary) -> void:
	main.handle_enemy_kill(e)
	enemy_system.enemies.remove_at(j)

# ========== RENDER ==========

func _draw() -> void:
	# Player bullets — anisotropic stretch along direction of motion. The
	# rectangle base is 4×24; we stretch the long axis (Y in local space) by
	# ~speed/600 so high-speed shots leave a longer streak. Rotated to match
	# `dir`. Default `dir` is Vector2.UP, which has angle = -PI/2 — adding
	# +PI/2 keeps the rectangle aligned with motion.
	for b in player_bullets:
		var stretch_y: float = 1.0 + b.speed / 600.0
		draw_set_transform(b.pos, b.dir.angle() + PI / 2.0, Vector2(1.0, stretch_y))
		draw_rect(Rect2(Vector2(-2, -12), Vector2(4, 24)), b.color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Enemy bullets (cerchio + core; colori const per zero allocazioni nel hot-path)
	for b in active_enemy_bullets:
		if b.homing:
			draw_circle(b.pos, 5.0, COL_ENEMY_HOMING)
			draw_circle(b.pos, 2.0, CORE_ENEMY_HOMING)
		else:
			draw_circle(b.pos, 5.0, COL_ENEMY_PINK)
			draw_circle(b.pos, 2.0, CORE_ENEMY_PINK)
