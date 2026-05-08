extends Node2D
class_name PowerupSystem

# Powerup floating verso il basso. Pickup applica effetti via le `refs` settate da Main.
# Tipi: 0=heal, 1=railgun, 2=drones, 3=blackhole.

const POWERUP_FALL_SPEED: float = 80.0
const PICKUP_RADIUS: float = 30.0

var powerups: Array = []

# Refs (settate da Main in _ready)
var main: Node
var player: Node2D
var audio_manager: Node
var explosion_system: ExplosionSystem
var bh_system: Node  # BlackHoleSystem (forward ref)
var screen_size: Vector2 = Vector2.ZERO

func spawn(pos: Vector2, type_idx: int) -> void:
	powerups.append({ "pos": pos, "type": type_idx })

func tick(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var gsm: float = main.global_speed_multiplier if main else 1.0
	for i in range(powerups.size() - 1, -1, -1):
		var p: Dictionary = powerups[i]
		p.pos.y += POWERUP_FALL_SPEED * gsm * delta
		if p.pos.distance_squared_to(player.position) < PICKUP_RADIUS * PICKUP_RADIUS:
			_apply_pickup(p)
			powerups.remove_at(i)
		elif p.pos.y > screen_size.y + 100:
			powerups.remove_at(i)
	queue_redraw()

func clear() -> void:
	powerups.clear()
	queue_redraw()

func _apply_pickup(p: Dictionary) -> void:
	match p.type:
		0:  # Heal (Medkit)
			audio_manager.play_sfx(2.5, 5.0, player.position)
			if main:
				main.heal(main.PLAYER_HEAL)
			explosion_system.spawn(player.position, Color(0.2, 3.0, 0.5), 0.5)
		1:  # Railgun
			audio_manager.play_sfx(3.5, 5.0, player.position)
			player.fire_buff_timer = 10.0
			player.weapon_type = 1
			explosion_system.spawn(player.position, Color(3.0, 0.5, 3.0), 0.5)
		2:  # Drones
			audio_manager.play_sfx(2.0, 5.0, player.position)
			player.fire_buff_timer = 15.0
			player.drone_active = true
			explosion_system.spawn(player.position, Color(0.5, 3.0, 3.0), 0.5)
		3:  # Black Hole
			audio_manager.play_sfx(0.1, 10.0, player.position)
			explosion_system.spawn(player.position, Color(0.0, 0.0, 0.0), 2.0)
			if main:
				main.add_shake(40.0)
			if bh_system:
				bh_system.spawn(p.pos)

func _draw() -> void:
	for p in powerups:
		match p.type:
			0:  # Medkit
				draw_circle(p.pos, 8.0, Color(0.2, 2.5, 0.5))
				draw_circle(p.pos, 4.0, Color(1.0, 1.0, 1.0))
			1:  # Railgun viola
				draw_circle(p.pos, 8.0, Color(3.0, 0.5, 3.0))
				draw_circle(p.pos, 4.0, Color(1.0, 1.0, 1.0))
			2:  # Drones azzurro
				draw_circle(p.pos, 8.0, Color(0.5, 3.0, 3.0))
				draw_circle(p.pos, 4.0, Color(1.0, 1.0, 1.0))
			3:  # Black Hole nero con bordo viola HDR
				draw_circle(p.pos, 8.0, Color(0.0, 0.0, 0.0))
				draw_circle(p.pos, 4.0, Color(4.0, 0.5, 4.0))
