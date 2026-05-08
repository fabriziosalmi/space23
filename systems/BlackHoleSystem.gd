extends Node2D
class_name BlackHoleSystem

# Buchi neri: vita finita, gravità sui nemici e proiettili nemici, assorbimento
# entro un raggio molto piccolo. La posizione del primo BH viene letta dal
# PostFXController per applicare il gravitational lensing.

var black_holes: Array = []

# Refs (settate da Main in _ready)
var main: Node                   # Main, per centralizzare gli FX di kill
var enemy_system: EnemySystem
var projectile_system: Node  # ProjectileSystem (forward ref)

func spawn(pos: Vector2) -> void:
	black_holes.append({ "pos": pos, "life": Main.BH_LIFE })

func tick(delta: float) -> void:
	for i in range(black_holes.size() - 1, -1, -1):
		var bh: Dictionary = black_holes[i]
		bh.life -= delta
		if bh.life <= 0:
			black_holes.remove_at(i)
			continue

		var pull_force: float = 400.0 * min(bh.life, 1.0)

		if enemy_system:
			# Reverse iter: absorb damage that brings hp ≤ 0 must remove the
			# enemy in-place with the proper kill FX. Without this path, the
			# enemy would just be silently culled by EnemySystem's hp ≤ 0
			# cleanup branch on the next frame — no score, no SFX, no boss
			# lensing if the absorbed enemy was the boss.
			for ei in range(enemy_system.enemies.size() - 1, -1, -1):
				var e: Dictionary = enemy_system.enemies[ei]
				var dist: float = e.pos.distance_to(bh.pos)
				if dist < Main.BH_GRAVITY_RADIUS:
					e.pos = e.pos.move_toward(bh.pos, (pull_force / max(dist, 10.0)) * 200.0 * delta)
				if dist < Main.BH_ABSORB_RADIUS:
					e.hp -= 100
					if e.hp <= 0 and main:
						main.handle_enemy_kill(e)
						enemy_system.enemies.remove_at(ei)

		if projectile_system:
			for b in projectile_system.active_enemy_bullets:
				var dist: float = b.pos.distance_to(bh.pos)
				if dist < Main.BH_GRAVITY_RADIUS:
					b.pos = b.pos.move_toward(bh.pos, (pull_force / max(dist, 10.0)) * 300.0 * delta)
				if dist < Main.BH_ABSORB_RADIUS:
					b.pos.y = 9999  # marker per pulizia in ProjectileSystem
	queue_redraw()

func clear() -> void:
	black_holes.clear()
	queue_redraw()

# Per il PostFX: ritorna il primo BH attivo o null.
func primary() -> Variant:
	return black_holes[0] if not black_holes.is_empty() else null

func _draw() -> void:
	var time: float = Time.get_ticks_msec() / 1000.0
	for bh in black_holes:
		var alpha: float = min(bh.life, 1.0)
		draw_circle(bh.pos, 15.0, Color(0, 0, 0, alpha))  # Event horizon
		draw_arc(bh.pos, 25.0 + sin(time * 20.0) * 5.0, 0, PI * 2, 32, Color(2.0, 0.5, 3.0, alpha), 3.0, true)
		draw_arc(bh.pos, 35.0 + cos(time * 15.0) * 10.0, 0, PI * 2, 32, Color(4.0, 1.0, 1.0, alpha * 0.5), 1.0, true)
