extends Node2D
class_name ExplosionSystem

# Particelle "frantumi" + onde d'urto. Self-contained: nessuna dipendenza,
# altri sistemi chiamano semplicemente spawn().

var explosions: Array = []

func spawn(pos: Vector2, color: Color, scale_mod: float, is_super: bool = false) -> void:
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

		ex.shards.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"rot": randf() * PI * 2.0,
			"rot_speed": randf_range(-8.0, 8.0),
			"pts": pts
		})
	explosions.append(ex)

# Ring-only spawn (zero shards): usato per "tell" cues — powerup drop, future
# spawn anticipations. Sfrutta il pipeline di shockwave esistente con shards
# vuoti, niente codice di rendering nuovo. Vita più corta (0.4s vs 0.4-1.5s)
# e radius target esplicito così l'animazione finisce dove vogliamo.
func spawn_ring(pos: Vector2, color: Color, max_radius: float, life: float = 0.4) -> void:
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
	for i in range(explosions.size() - 1, -1, -1):
		var ex: Dictionary = explosions[i]
		ex.life -= delta
		for j in range(ex.shards.size()):
			ex.shards[j].pos += ex.shards[j].vel * delta
			ex.shards[j].vel *= 0.92
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

		for s in ex.shards:
			draw_set_transform(s.pos, s.rot, Vector2.ONE)
			draw_polygon(s.pts, PackedColorArray([c, c, c]))
			draw_polyline(s.pts + PackedVector2Array([s.pts[0]]), Color(3.0, 3.0, 3.0, alpha), 1.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
