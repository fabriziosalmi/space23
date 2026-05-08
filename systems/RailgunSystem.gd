extends Node2D
class_name RailgunSystem

# Railgun = beam verticale che parte dalla nave verso l'alto, dura ~0.2s,
# infligge danno continuo a tutti i nemici che attraversano la colonna.

const RAILGUN_LIFE: float = 0.2
const RAILGUN_HALF_WIDTH: float = 15.0
const RAILGUN_DPS: float = 30.0

var railguns: Array = []

# Refs (settate da Main in _ready)
var main: Node
var audio_manager: Node
var enemy_system: EnemySystem
var explosion_system: ExplosionSystem

func spawn(pos: Vector2) -> void:
	railguns.append({ "pos": pos, "life": RAILGUN_LIFE })
	audio_manager.play_sfx(0.2, 5.0, pos)
	if main:
		main.add_shake(15.0)

func tick(delta: float) -> void:
	for i in range(railguns.size() - 1, -1, -1):
		var r: Dictionary = railguns[i]
		r.life -= delta
		if r.life <= 0:
			railguns.remove_at(i)
			continue
		if not enemy_system:
			continue
		var rect := Rect2(r.pos.x - RAILGUN_HALF_WIDTH, -1000, RAILGUN_HALF_WIDTH * 2.0, r.pos.y + 1000)
		var enemies: Array = enemy_system.enemies
		for j in range(enemies.size() - 1, -1, -1):
			var e: Dictionary = enemies[j]
			if rect.has_point(e.pos):
				e.hp -= RAILGUN_DPS * delta
				e.hit_flash = 0.1
				if e.hp <= 0:
					_kill_enemy(j, e)
	queue_redraw()

func clear() -> void:
	railguns.clear()
	queue_redraw()

func _kill_enemy(j: int, e: Dictionary) -> void:
	# Kill FX/score centralized in Main.handle_enemy_kill: boss killed via
	# railgun now gets the same dramatic treatment (lensing, big shake, +5000
	# score, 1.2s freeze) instead of the previous silent-ish 0.05s + 250 score
	# bug. We layer the railgun-flavor kill SFX on top so the "high-pitch zap"
	# cue specific to railgun kills survives the refactor.
	main.handle_enemy_kill(e)
	audio_manager.play_sfx(1.5, -5.0, e.pos)
	enemy_system.enemies.remove_at(j)

func _draw() -> void:
	for r in railguns:
		var alpha: float = r.life * 5.0  # 0 → 1 nel tempo di vita
		draw_rect(Rect2(r.pos.x - RAILGUN_HALF_WIDTH, 0, RAILGUN_HALF_WIDTH * 2.0, r.pos.y), Color(3.0, 0.5, 3.0, alpha))
		draw_rect(Rect2(r.pos.x - 5, 0, 10, r.pos.y), Color(4.0, 3.0, 4.0, alpha))
