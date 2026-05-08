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

var player_bullets: Array = []
var active_enemy_bullets: Array = []
var pool_enemy_bullets: Array = []

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
	# Usato dalla smart bomb: piccola esplosione su ogni proiettile prima di tornare al pool.
	for b in active_enemy_bullets:
		explosion_system.spawn(b.pos, Color(1.0, 0.5, 0.5), 0.2)
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
	var black_holes: Array = bh_system.black_holes if bh_system else []
	var gsm: float = main.global_speed_multiplier if main else 1.0

	_tick_player_bullets(delta, black_holes)
	_tick_enemy_bullets(delta, gsm, black_holes)
	queue_redraw()

func _tick_player_bullets(delta: float, black_holes: Array) -> void:
	for i in range(player_bullets.size() - 1, -1, -1):
		var b: Dictionary = player_bullets[i]

		# Gravità BH
		for bh in black_holes:
			var d: float = b.pos.distance_to(bh.pos)
			if d < Main.BH_PULL_RADIUS:
				var pull: Vector2 = (bh.pos - b.pos).normalized() * (1.0 - d / Main.BH_PULL_RADIUS) * Main.BH_PULL_FORCE_PLAYER_BULLET * delta
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
		if b.pos.y < -50 or b.pos.y > screen_size.y + 50 or b.pos.x < -50 or b.pos.x > screen_size.x + 50:
			player_bullets.remove_at(i)
			continue

		# Collisione con nemici (squared distance: hot inner loop, ~6K check/frame
		# nel worst case → uno sqrt risparmiato per ogni iter).
		var hit: bool = false
		var enemies: Array = enemy_system.enemies if enemy_system else []
		var hr_sq: float = Main.PLAYER_BULLET_HIT_RADIUS * Main.PLAYER_BULLET_HIT_RADIUS
		for j in range(enemies.size() - 1, -1, -1):
			var e: Dictionary = enemies[j]
			if b.pos.distance_squared_to(e.pos) < hr_sq:
				e.hp -= Main.PLAYER_BULLET_DAMAGE
				hit = true
				e.hit_flash = 0.1
				explosion_system.spawn(b.pos, Color(0.5, 1.0, 2.0), 0.3)
				if e.hp <= 0:
					_kill_enemy_at(j, e)
				break
		if hit:
			player_bullets.remove_at(i)

func _tick_enemy_bullets(delta: float, gsm: float, black_holes: Array) -> void:
	for i in range(active_enemy_bullets.size() - 1, -1, -1):
		var b: Dictionary = active_enemy_bullets[i]

		# Gravità BH
		for bh in black_holes:
			var d: float = b.pos.distance_to(bh.pos)
			if d < Main.BH_PULL_RADIUS:
				var pull: Vector2 = (bh.pos - b.pos).normalized() * (1.0 - d / Main.BH_PULL_RADIUS) * Main.BH_PULL_FORCE_PROJECTILE * delta
				b.dir = (b.dir * b.speed + pull).normalized()

		# Homing
		if b.has("homing") and b.homing and is_instance_valid(player):
			var desired_dir: Vector2 = (player.position - b.pos).normalized()
			b.dir = b.dir.lerp(desired_dir, HOMING_TURN_RATE * delta).normalized()

		# Movimento (rallentato dal time-dilation — Superhot)
		b.pos += b.dir * b.speed * delta * gsm

		# Player hit / graze (squared distance, ~2500 check/frame nel worst case).
		# Check sia is_invincible (stale dal frame precedente) che hit_iframe_timer
		# (in-frame fresh): blocca stack di N bullet hit nello stesso frame.
		var dist_sq: float = b.pos.distance_squared_to(player.position)
		var hb: float = player.HITBOX_RADIUS_BULLET
		var hb_sq: float = hb * hb
		var graze_sq: float = Main.GRAZE_RADIUS * Main.GRAZE_RADIUS
		var iframed: bool = player.is_invincible or player.hit_iframe_timer > 0.0
		if dist_sq < hb_sq and not iframed:
			explosion_system.spawn(player.position, Color(3.0, 0.2, 0.2), 0.5)
			main.add_shake(10.0)
			main.trigger_hit_stop(0.02)
			_remove_enemy_bullet_at(i)
			main.damage_player(Main.ENEMY_BULLET_DAMAGE)
		elif dist_sq < graze_sq and not b.has("grazed") and not iframed:
			b["grazed"] = true
			main.add_score(Main.SCORE_PER_GRAZE)
			main.gain_flow(Main.FLOW_GAIN_PER_GRAZE)
			explosion_system.spawn(b.pos, Color(1.0, 1.0, 1.0, 0.5), 0.2)
			audio_manager.play_sfx(3.0, -10.0, b.pos)  # graze: pan dalla pos del bullet
		elif b.pos.y > screen_size.y + 100 or b.pos.x < -100 or b.pos.x > screen_size.x + 100:
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

	# Enemy bullets (cerchio + core; arancio per homing, rosa per dritti)
	for b in active_enemy_bullets:
		var col: Color = Color(3.0, 0.2, 1.5)         # Neon Pink
		var core: Color = Color(4.0, 1.0, 3.0)
		if b.has("homing") and b.homing:
			col = Color(3.0, 1.0, 0.1)                # Neon Orange
			core = Color(4.0, 3.0, 1.0)
		draw_circle(b.pos, 5.0, col)
		draw_circle(b.pos, 2.0, core)
