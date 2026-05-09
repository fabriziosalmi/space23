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

# AABB half-extents per tipo, calcolate lazy dai `pts`. Cache: la prima call
# a `_aabb_half_for_type` riempie l'array, mai più mutata. Usata da:
#   - ProjectileSystem._tick_player_bullets (player_bullet vs enemy)
#   - EnemySystem.tick (body collision)
# Sostituisce i precedenti hit_radius=35 (bullet) e hb=15 (body) trattati come
# distanze contro `e.pos` come punto. Erano corretti per scout/fighter
# (AABB ≤ 25) ma sui boss/dread/mothership (AABB 28-150) l'85%+ della
# silhouette era "phantom": i player bullet attraversavano le ali del boss
# senza danno, e il player poteva parcheggiarsi *dentro* il mothership senza
# beccare body damage. AABB risolve entrambi.
var _aabb_cache: Array = []

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
		"invader_dir": 1.0 if randf() > 0.5 else -1.0,
		# AABB half-extents per collision (point-in-box) — vedi _aabb_cache.
		"hit_aabb": _aabb_half_for_type(type_idx)
	})

# Calcola le half-extents (hw, hh) della bounding box dei `pts` per tipo, e
# le cacha per subsequent call. Usa `max(abs(min), abs(max))` per gestire
# i casi non-simmetrici (es. squid pts: y va da -20 a +14 → hh = 20).
func _aabb_half_for_type(idx: int) -> Vector2:
	if _aabb_cache.is_empty():
		for t in ENEMY_TYPES:
			var min_x: float = INF
			var max_x: float = -INF
			var min_y: float = INF
			var max_y: float = -INF
			for p in t.pts:
				min_x = min(min_x, p.x)
				max_x = max(max_x, p.x)
				min_y = min(min_y, p.y)
				max_y = max(max_y, p.y)
			var hw: float = max(abs(min_x), abs(max_x))
			var hh: float = max(abs(min_y), abs(max_y))
			_aabb_cache.append(Vector2(hw, hh))
	return _aabb_cache[idx]

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

		# Collisione corpo nave-nemico — point-in-box (player center inside
		# enemy_AABB expanded by player body radius). Sostituisce il vecchio
		# distance_squared < 15² che trattava il nemico come punto: un boss
		# da 300×180 era hittable solo entro 15px dal centro, quindi il
		# player poteva *parcheggiarsi dentro la silhouette visibile* senza
		# beccare body damage.
		# Check sia su is_invincible (stato dal frame precedente) che su
		# hit_iframe_timer (stato corrente in-frame): blocca lo stack di N body
		# collision sullo stesso frame che altrimenti rimuovono N nemici "free"
		# (HP è protetto da damage_player ma le rimozioni e i side-FX no).
		var hb: float = player.HITBOX_RADIUS_BODY
		var aabb: Vector2 = e.hit_aabb
		var dx: float = abs(e.pos.x - player.position.x)
		var dy: float = abs(e.pos.y - player.position.y)
		if dx < aabb.x + hb and dy < aabb.y + hb and not player.is_invincible and player.hit_iframe_timer <= 0.0:
			explosion_system.spawn(player.position, Color(3.0, 0.5, 0.5), 0.8)
			main.add_shake(25.0)
			main.trigger_hit_stop(0.05)
			enemies.remove_at(i)
			main.damage_player(Main.ENEMY_BODY_COLLISION_DAMAGE)
		elif e.pos.y > screen_size.y + 100 or e.hp <= 0 or e.pos.y < -300:
			# Cleanup unificato:
			# - sotto schermo (cleanup naturale per scout/invader/spinner)
			# - hp <= 0 (es. fighter in LEAVE che si auto-segna, plus catch-all
			#   per qualsiasi caso edge in cui un nemico è "morto" ma non
			#   rimosso da un kill collision)
			# - sopra schermo (fighter LEAVES verso l'alto, prima rimaneva
			#   bloccato per sempre nell'array perché il check guardava solo
			#   il bottom)
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
	# BUGFIX: il decremento mancava → shoot_timer congelato al valore iniziale
	# (1.5..2.5) e gli invader non sparavano MAI dopo lo spawn. Tutte le altre
	# AI fanno `e.shoot_timer -= delta` prima del check, qui era saltato.
	e.shoot_timer -= delta
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
		# Telegraph 350ms (era 100ms — leggibile solo con conoscenza pregressa
		# del pattern). Window 0.45 → 0.10 = 350ms di flash bianco prima del
		# 16-bullet ring fan. All'ingresso del window, parte una "carica" SFX
		# pitch alto (2.5) che annuncia l'imminente fan — il giocatore ha tempo
		# di posizionarsi, e il mancato dodge è skill-based, non caos.
		if e.shoot_timer <= 0.45 and e.shoot_timer > 0.10:
			e.hit_flash = 1.0
			if not e.get("telegraph_charging", false):
				e.telegraph_charging = true
				audio_manager.play_sfx(2.5, 0.0, e.pos)
		if e.shoot_timer <= 0:
			e.shoot_timer = 2.0
			e.telegraph_charging = false
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
