extends Node2D
class_name EnemySystem

# Owns:
#   - definizioni statiche dei tipi nemico (poligono, hp, speed, ai-id)
#   - array `enemies` runtime
#   - logica AI (5 tipi: fighter, scout, tank, spinner, invader, mothership)
#   - rendering nemici + radar HUD per nemici fuori schermo

# Refs (settate da Main in _ready)
var main: Node
var player: Node2D
var projectile_system: Node      # ProjectileSystem
var explosion_system: ExplosionSystem
var audio_manager: Node
var screen_size: Vector2 = Vector2.ZERO

var enemies: Array = []

const ENEMY_TYPES := [
	{ # 0: SCOUT (small triangle, fast)
		"hp": 2, "speed": [150.0, 250.0], "color": Color(0.1, 0.8, 0.3),
		"pts": [Vector2(0, 15), Vector2(-15, -10), Vector2(15, -10)],
		"ai": 1, "shoot": [2.0, 4.0]
	},
	{ # 1: FIGHTER (arrowhead, charges)
		"hp": 5, "speed": [80.0, 150.0], "color": Color(0.8, 0.1, 0.2),
		"pts": [Vector2(0, 20), Vector2(-25, -15), Vector2(-10, -5), Vector2(10, -5), Vector2(25, -15)],
		"ai": 0, "shoot": [1.5, 3.0]
	},
	{ # 2: TANK (pentagon, slow + homing)
		"hp": 15, "speed": [40.0, 70.0], "color": Color(0.8, 0.6, 0.1),
		"pts": [Vector2(0, 30), Vector2(-35, 5), Vector2(-25, -20), Vector2(25, -20), Vector2(35, 5)],
		"ai": 2, "shoot": [1.5, 3.0]
	},
	{ # 3: SPINNER / BULLET HELL BOSS
		"hp": 30, "speed": [30.0, 50.0], "color": Color(0.9, 0.2, 0.9),
		"pts": [Vector2(0, 30), Vector2(-30, 0), Vector2(0, -30), Vector2(30, 0)],
		"ai": 3, "shoot": [0.05, 0.05]
	},
	{ # 4: SPACE INVADER (square, side-to-side)
		"hp": 8, "speed": [120.0, 180.0], "color": Color(0.1, 1.0, 0.5),
		"pts": [Vector2(-15, -10), Vector2(15, -10), Vector2(15, 10), Vector2(-15, 10)],
		"ai": 4, "shoot": [1.5, 2.5]
	},
	{ # 5: MOTHER SHIP BOSS
		"hp": 250, "speed": [20.0, 30.0], "color": Color(2.0, 0.2, 0.2),
		"pts": [Vector2(0, 80), Vector2(-150, -40), Vector2(-80, -80), Vector2(80, -80), Vector2(150, -40)],
		"ai": 5, "shoot": [0.05, 0.05]
	},
	{ # 6: OCTOPUS — squat dome with four tentacles (invader pattern)
		"hp": 6, "speed": [100.0, 150.0], "color": Color(0.2, 0.9, 1.2),
		"pts": [
			Vector2(-18, -14), Vector2(-10, -22), Vector2(10, -22), Vector2(18, -14),
			Vector2(22, 4), Vector2(14, 12), Vector2(8, 4), Vector2(2, 14),
			Vector2(-2, 14), Vector2(-8, 4), Vector2(-14, 12), Vector2(-22, 4)
		],
		"ai": 4, "shoot": [1.8, 2.8]
	},
	{ # 7: CRAB — wide silhouette with claws (invader pattern, slower)
		"hp": 10, "speed": [80.0, 120.0], "color": Color(1.4, 0.4, 0.2),
		"pts": [
			Vector2(-28, 0), Vector2(-22, -10), Vector2(-12, -8), Vector2(-6, -16),
			Vector2(6, -16), Vector2(12, -8), Vector2(22, -10), Vector2(28, 0),
			Vector2(20, 8), Vector2(8, 4), Vector2(-8, 4), Vector2(-20, 8)
		],
		"ai": 4, "shoot": [1.2, 2.2]
	},
	{ # 8: SQUID — bullet body with three tails (scout pattern, very fast)
		"hp": 4, "speed": [200.0, 300.0], "color": Color(1.4, 0.2, 1.0),
		"pts": [
			Vector2(0, -20), Vector2(-12, -8), Vector2(-14, 8),
			Vector2(-7, 6), Vector2(-3, 14), Vector2(0, 8),
			Vector2(3, 14), Vector2(7, 6), Vector2(14, 8), Vector2(12, -8)
		],
		"ai": 1, "shoot": [3.0, 4.5]
	},
	{ # 9: MANTIS — diamond core with sharp wings (fighter pattern)
		"hp": 8, "speed": [150.0, 200.0], "color": Color(0.6, 1.5, 0.3),
		"pts": [
			Vector2(0, -22), Vector2(-8, -8), Vector2(-30, -2), Vector2(-10, 4),
			Vector2(0, 18), Vector2(10, 4), Vector2(30, -2), Vector2(8, -8)
		],
		"ai": 0, "shoot": [1.0, 2.0]
	},
	{ # 10: DREAD — heavy rectangle with four horns (tank pattern)
		"hp": 25, "speed": [30.0, 50.0], "color": Color(1.5, 0.5, 0.0),
		"pts": [
			Vector2(-26, -16), Vector2(-18, -22), Vector2(-12, -16),
			Vector2(-4, -22), Vector2(4, -22), Vector2(12, -16),
			Vector2(18, -22), Vector2(26, -16),
			Vector2(28, 4), Vector2(20, 14), Vector2(-20, 14), Vector2(-28, 4)
		],
		"ai": 2, "shoot": [1.0, 2.5]
	},
	{ # 11: SENTINEL — inverted triangle + cyclop eye (fighter pattern, slow)
		"hp": 12, "speed": [60.0, 90.0], "color": Color(1.6, 1.4, 0.2),
		"pts": [
			Vector2(-22, -16), Vector2(22, -16),
			Vector2(16, -2), Vector2(8, 8), Vector2(0, 18),
			Vector2(-8, 8), Vector2(-16, -2)
		],
		"ai": 0, "shoot": [1.6, 2.6]
	}
]

func spawn(type_idx: int, pos: Vector2, diff: float, speed_mult: float = 1.0, color_mod: Color = Color(1, 1, 1, 1)) -> void:
	var e_type: Dictionary = ENEMY_TYPES[type_idx]
	var hp_value: int = int(e_type.hp * diff)
	enemies.append({
		"pos": pos,
		"hp": hp_value,
		"max_hp": hp_value,
		# base_hp = HP del tipo prima del moltiplicatore di difficulty. Usato dal
		# hit-stop scaler in ProjectileSystem per restare diff-invariante (un
		# fighter è sempre "fighter-class" anche a diff 4).
		"base_hp": int(e_type.hp),
		"speed": randf_range(e_type.speed[0], e_type.speed[1]) * diff * speed_mult,
		"ai_type": e_type.ai,
		"ai_timer": 0.0,
		"ai_state": "ENTER",
		"charge_timer": 0.0,
		"shoot_timer": randf_range(e_type.shoot[0], e_type.shoot[1]),
		"color": e_type.color * color_mod,
		"pts": PackedVector2Array(e_type.pts),
		"hit_flash": 0.0,
		"invader_dir": 1.0 if randf() > 0.5 else -1.0
	})

func clear() -> void:
	enemies.clear()
	queue_redraw()

func tick(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var gsm: float = main.global_speed_multiplier if main else 1.0

	for i in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[i]
		e.ai_timer += delta
		if e.hit_flash > 0:
			e.hit_flash -= delta

		match int(e.ai_type):
			0:  _ai_fighter(e, delta, gsm)
			1:  _ai_scout(e, delta, gsm)
			2:  _ai_tank(e, delta, gsm)
			3:  _ai_spinner(e, delta, gsm)
			4:  _ai_invader(e, delta, gsm)
			5:  _ai_mothership(e, delta, gsm)

		# Aggiorna boss HP UI ogni frame (solo per boss)
		if e.ai_type == Main.BOSS_TYPE_INDEX and main and is_instance_valid(main.ui_manager):
			main.ui_manager.update_boss_hp(e.hp, e.max_hp)

		# Collisione corpo nave-nemico (squared distance: niente sqrt nell'hot path).
		# Check sia su is_invincible (stato dal frame precedente) che su
		# hit_iframe_timer (stato corrente in-frame): blocca lo stack di N body
		# collision sullo stesso frame che altrimenti rimuovono N nemici "free"
		# (HP è protetto da damage_player ma le rimozioni e i side-FX no).
		var hb: float = player.HITBOX_RADIUS_BODY
		if e.pos.distance_squared_to(player.position) < hb * hb and not player.is_invincible and player.hit_iframe_timer <= 0.0:
			explosion_system.spawn(player.position, Color(3.0, 0.5, 0.5), 0.8)
			main.add_shake(25.0)
			main.trigger_hit_stop(0.05)
			enemies.remove_at(i)
			main.damage_player(Main.ENEMY_BODY_COLLISION_DAMAGE)
		elif e.pos.y > screen_size.y + 100:
			enemies.remove_at(i)

	queue_redraw()

# ========== AI ROUTINES ==========

func _ai_fighter(e: Dictionary, delta: float, gsm: float) -> void:
	# Scende, ferma e carica, spara spread di 3, fugge.
	if e.ai_state == "ENTER":
		e.pos.y += e.speed * gsm * delta
		if e.pos.y > 150:
			e.ai_state = "CHARGE"
			e.charge_timer = 1.0
	elif e.ai_state == "CHARGE":
		e.pos.x += randf_range(-2, 2)
		e.charge_timer -= delta
		if e.charge_timer <= 0:
			e.ai_state = "LEAVE"
			audio_manager.play_sfx(0.5, 0.0, e.pos)
			for a in [-0.2, 0.0, 0.2]:
				var dir: Vector2 = (player.position - e.pos).rotated(a).normalized()
				projectile_system.spawn_enemy_bullet(e.pos, dir, 400.0)
	elif e.ai_state == "LEAVE":
		e.pos.y -= e.speed * gsm * delta
		if e.pos.y < -100:
			e.hp = 0

func _ai_scout(e: Dictionary, delta: float, gsm: float) -> void:
	# Curva dolce; swarm verso il player se vicino.
	e.pos.y += e.speed * gsm * delta
	if e.pos.distance_squared_to(player.position) < 90000.0:  # 300² — swarm radius
		e.pos = e.pos.move_toward(player.position, e.speed * 0.9 * gsm * delta)
	else:
		e.pos.x += sin(e.ai_timer * 3.0) * 80.0 * delta

func _ai_tank(e: Dictionary, delta: float, gsm: float) -> void:
	# Lento; insegue X del player; missili traccianti.
	e.pos.y += e.speed * 0.5 * gsm * delta
	e.pos.x = lerp(e.pos.x, player.position.x, 0.5 * delta)
	e.shoot_timer -= delta
	if e.shoot_timer <= 0:
		e.shoot_timer = randf_range(2.5, 4.0)
		var dir: Vector2 = (player.position - e.pos).normalized()
		projectile_system.spawn_enemy_bullet(e.pos, dir, 250.0, true)

func _ai_spinner(e: Dictionary, delta: float, gsm: float) -> void:
	# Bullet hell rotante.
	if e.ai_state == "ENTER":
		e.pos.y += e.speed * gsm * delta
		if e.pos.y > 200:
			e.ai_state = "SPIN"
	elif e.ai_state == "SPIN":
		e.pos.y += sin(e.ai_timer * 2.0) * 20.0 * delta
		e.pos.x += cos(e.ai_timer * 1.5) * 50.0 * delta
		e.shoot_timer -= delta
		if e.shoot_timer <= 0:
			e.shoot_timer = 0.08
			var a: float = e.ai_timer * 6.0
			projectile_system.spawn_enemy_bullet(e.pos, Vector2(cos(a), sin(a)), 300.0, false)
			projectile_system.spawn_enemy_bullet(e.pos, Vector2(cos(a + PI), sin(a + PI)), 300.0, false)
			# Barriere più lente perpendicolari
			projectile_system.spawn_enemy_bullet(e.pos, Vector2(cos(a + PI / 2.0), sin(a + PI / 2.0)), 150.0, false)
			projectile_system.spawn_enemy_bullet(e.pos, Vector2(cos(a - PI / 2.0), sin(a - PI / 2.0)), 150.0, false)
	if e.pos.y > screen_size.y + 100:
		e.hp = 0

func _ai_invader(e: Dictionary, delta: float, gsm: float) -> void:
	e.pos.x += e.speed * e.invader_dir * gsm * delta
	if e.pos.x < 100 or e.pos.x > screen_size.x - 100:
		e.invader_dir *= -1.0
		e.pos.y += 60.0
		e.pos.x += e.speed * e.invader_dir * gsm * delta
	if e.shoot_timer <= 0:
		e.shoot_timer = randf_range(1.5, 2.5)
		projectile_system.spawn_enemy_bullet(e.pos, Vector2.DOWN, 250.0, false)
	if e.pos.y > screen_size.y + 100:
		e.hp = 0

func _ai_mothership(e: Dictionary, delta: float, gsm: float) -> void:
	if e.ai_state == "ENTER":
		e.pos.y += e.speed * gsm * delta
		if e.pos.y > 150:
			e.ai_state = "ATTACK"
	elif e.ai_state == "ATTACK":
		e.pos.x += sin(e.ai_timer * 1.5) * 80.0 * delta
		e.shoot_timer -= delta
		# Telegraph DMC: flash bianco 100ms prima di sparare.
		if e.shoot_timer < 0.3 and e.shoot_timer > 0.2:
			e.hit_flash = 1.0
		if e.shoot_timer <= 0:
			e.shoot_timer = 2.0
			audio_manager.play_sfx(0.8, 2.0, e.pos)
			var a: float = e.ai_timer * 3.0
			for j in range(16):
				var dir: Vector2 = Vector2(cos(a + j * PI / 8.0), sin(a + j * PI / 8.0))
				projectile_system.spawn_enemy_bullet(e.pos + Vector2(0, 40), dir, 200.0, false)
			if randf() > 0.5:
				var dir_p: Vector2 = (player.position - e.pos).normalized()
				projectile_system.spawn_enemy_bullet(e.pos, dir_p, 400.0, true)

# ========== RENDER ==========

func _draw() -> void:
	var audio_low: float = audio_manager.audio_low if audio_manager else 0.0

	# Nemici (poligono + core glow audio-reattivo + edge glow al hit)
	for e in enemies:
		# Fill: tinta originale, brighter (non bianco) durante hit_flash.
		var fill: Color = e.color
		if e.hit_flash > 0:
			fill = e.color * (1.0 + 4.0 * e.hit_flash)

		var c_arr := PackedColorArray()
		c_arr.resize(e.pts.size())
		c_arr.fill(fill)
		var beat_scale: float = 1.0 + (audio_low * 0.3)
		draw_set_transform(e.pos, 0.0, Vector2(beat_scale, beat_scale))
		draw_polygon(e.pts, c_arr)

		# Edge glow ring: attivo solo quando colpito; preserva la silhouette
		# invece di sostituirla con un bianco invadente.
		if e.hit_flash > 0:
			var glow: Color = e.color * 4.0
			glow.a = e.hit_flash
			var loop := PackedVector2Array(e.pts)
			loop.append(e.pts[0])
			draw_polyline(loop, glow, 2.0 + 4.0 * e.hit_flash, true)

		draw_circle(Vector2.ZERO, 6.0, Color(2.5 + audio_low * 2.0, 0.5, 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Radar HUD: indicatori per nemici sopra il bordo superiore della camera
	if main and main.game_state != "TITLE" and is_instance_valid(main.main_camera):
		var cam_tl: Vector2 = main.main_camera.position - screen_size / 2.0
		for e in enemies:
			if e.pos.y < cam_tl.y:
				var indicator_x: float = clamp(e.pos.x, cam_tl.x + 20, cam_tl.x + screen_size.x - 20)
				var pts := PackedVector2Array([
					Vector2(indicator_x, cam_tl.y + 30),
					Vector2(indicator_x - 10, cam_tl.y + 15),
					Vector2(indicator_x + 10, cam_tl.y + 15)
				])
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_polygon(pts, PackedColorArray([
					Color(1.0, 0.0, 0.0, 0.8),
					Color(1.0, 0.0, 0.0, 0.8),
					Color(1.0, 0.0, 0.0, 0.8)
				]))
