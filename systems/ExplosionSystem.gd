extends Node2D
class_name ExplosionSystem

# Particelle "frantumi" + onde d'urto. Self-contained: nessuna dipendenza,
# altri sistemi chiamano semplicemente spawn().

const MAX_EXPLOSIONS: int = 80

var explosions: Array = []
var _had_explosions: bool = false

func spawn(pos: Vector2, color: Color, scale_mod: float, is_super: bool = false) -> void:
	if explosions.size() >= MAX_EXPLOSIONS:
		if not is_super:
			return
		# Super-explosions (boss kill / bomb / death) always get through: evict oldest non-super.
		for k in range(explosions.size()):
			if not explosions[k].is_super:
				explosions.remove_at(k)
				break
	var ex: Dictionary = {
		"pos": pos,
		"color": color,
		"life": 1.5 if is_super else 0.4,
		"max_life": 1.5 if is_super else 0.4,
		"is_super": is_super,
		"shards": [],
		"shockwaves": []
	}

	var num_waves: int = 2 if is_super else 1
	for i in range(num_waves):
		ex.shockwaves.append({ "radius": 0.0, "speed": randf_range(300.0, 800.0) * scale_mod })

	var num_shards: int = 40 if is_super else 8
	for i in range(num_shards):
		var angle: float = randf() * PI * 2.0
		var speed: float = randf_range(100.0, 500.0) * scale_mod
		var pts := PackedVector2Array()
		var size: float = randf_range(5.0, 25.0) * scale_mod
		for j in range(3):
			var a: float = (j * (PI * 2.0 / 3.0)) + randf_range(-0.5, 0.5)
			var r: float = size * randf_range(0.3, 1.0)
			pts.append(Vector2(cos(a), sin(a)) * r)

		var pts_loop := PackedVector2Array(pts)
		pts_loop.append(pts[0])
		ex.shards.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"rot": randf() * PI * 2.0,
			"rot_speed": randf_range(-8.0, 8.0),
			"pts": pts,
			"pts_loop": pts_loop
		})
	explosions.append(ex)

# Ring-only spawn (zero shards): usato per "tell" cues — powerup drop, future
# spawn anticipations. Sfrutta il pipeline di shockwave esistente con shards
# vuoti, niente codice di rendering nuovo. Vita più corta (0.4s vs 0.4-1.5s)
# e radius target esplicito così l'animazione finisce dove vogliamo.
func spawn_ring(pos: Vector2, color: Color, max_radius: float, life: float = 0.4) -> void:
	if explosions.size() >= MAX_EXPLOSIONS:
		return
	explosions.append({
		"pos": pos,
		"color": color,
		"life": life,
		"max_life": life,
		"is_super": false,
		"shards": [],  # niente: ring-only
		"shockwaves": [{ "radius": 0.0, "speed": max_radius / life }]
	})

func tick(delta: float) -> void:
	if explosions.is_empty():
		if _had_explosions:
			_had_explosions = false
			queue_redraw()
		return
	_had_explosions = true
	var drag: float = pow(0.92, delta * 60.0)
	for i in range(explosions.size() - 1, -1, -1):
		var ex: Dictionary = explosions[i]
		ex.life -= delta
		for j in range(ex.shards.size()):
			ex.shards[j].pos += ex.shards[j].vel * delta
			ex.shards[j].vel *= drag
			ex.shards[j].rot += ex.shards[j].rot_speed * delta
		for j in range(ex.shockwaves.size()):
			ex.shockwaves[j].radius += ex.shockwaves[j].speed * delta
		if ex.life <= 0:
			explosions.remove_at(i)
	queue_redraw()

func clear() -> void:
	explosions.clear()
	queue_redraw()

func _draw() -> void:
	for ex in explosions:
		var alpha: float = ex.life / ex.max_life
		var c: Color = ex.color
		c.a = alpha

		for sw in ex.shockwaves:
			draw_arc(ex.pos, sw.radius, 0, PI * 2, 32, c * 1.5, 2.0 + (alpha * 5.0), true)
			if ex.is_super:
				draw_arc(ex.pos, sw.radius * 0.9, 0, PI * 2, 32, Color(1, 1, 1, alpha), 1.0, true)

		if ex.is_super:
			draw_circle(ex.pos, (1.0 - alpha) * 150.0, c * 0.5)  # Core implosivo

		var edge_col := Color(3.0, 3.0, 3.0, alpha)
		for s in ex.shards:
			draw_set_transform(s.pos, s.rot, Vector2.ONE)
			draw_colored_polygon(s.pts, c)
			draw_polyline(s.pts_loop, edge_col, 1.0, true)
		if not ex.shards.is_empty():
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
