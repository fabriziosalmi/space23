extends Node2D
class_name PowerupSystem

# Powerup floating verso il basso. Pickup applica effetti via le `refs` settate da Main.
# Tipi: 0=heal, 1=railgun, 2=drones, 3=blackhole.

const POWERUP_FALL_SPEED: float = 80.0
const PICKUP_RADIUS: float = 32.0
const MAGNET_RADIUS: float = 135.0
const MAGNET_PULL_SPEED: float = 420.0

var powerups: Array = []
var _had_powerups: bool = false

# Refs (settate da Main in _ready)
var main: Node
var player: Node2D
var audio_manager: Node
var explosion_system: ExplosionSystem
var bh_system: Node  # BlackHoleSystem (forward ref)
var screen_size: Vector2 = Vector2.ZERO

func spawn(pos: Vector2, type_idx: int) -> void:
	powerups.append({ "pos": pos, "type": type_idx })
	# "Qualcosa è apparso" tell: anello in espansione di colore matchato al
	# tipo, 0.4s, 50px raggio target. Subliminale — il giocatore non lo nota
	# coscientemente, ma se manca la scena sembra "morta" (powerup pop in
	# silenzio in mezzo al caos). Colore × 0.6 per tenerlo soft (gli HDR
	# pieni dei tipi sarebbero invadenti come anello).
	if explosion_system:
		var c: Color = _color_for_type(type_idx) * 0.6
		explosion_system.spawn_ring(pos, c, 50.0)

func tick(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if powerups.is_empty():
		if _had_powerups:
			_had_powerups = false
			queue_redraw()
		return
	_had_powerups = true
	# Cap caduta nei Drop così i powerup restano raccoglibili anche a 4x warp.
	var fall_gsm: float = min(main.global_speed_multiplier if main else 1.0, 1.8)
	for i in range(powerups.size() - 1, -1, -1):
		var p: Dictionary = powerups[i]
		p.pos.y += POWERUP_FALL_SPEED * fall_gsm * delta
		var dist_sq: float = p.pos.distance_squared_to(player.position)
		if dist_sq < MAGNET_RADIUS * MAGNET_RADIUS and dist_sq > 1.0:
			var dist: float = sqrt(dist_sq)
			var pull_t: float = 1.0 - (dist / MAGNET_RADIUS)
			p.pos = p.pos.move_toward(player.position, MAGNET_PULL_SPEED * (0.35 + pull_t * 0.65) * delta)
			dist_sq = p.pos.distance_squared_to(player.position)
		if dist_sq < PICKUP_RADIUS * PICKUP_RADIUS:
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
				main.spawn_floating_text(player.position, "+%d HP" % int(main.PLAYER_HEAL), Color(0.3, 1.0, 0.5), 13, 0.85)
			explosion_system.spawn(player.position, Color(0.2, 3.0, 0.5), 0.5)
		1:  # Railgun
			audio_manager.play_sfx(3.5, 5.0, player.position)
			player.railgun_timer = max(player.railgun_timer, 10.0)
			player.weapon_type = 1
			if main:
				main.spawn_floating_text(player.position, "RAILGUN!", Color(1.0, 0.4, 1.0), 14, 0.9)
			explosion_system.spawn(player.position, Color(3.0, 0.5, 3.0), 0.5)
		2:  # Drones
			audio_manager.play_sfx(2.0, 5.0, player.position)
			player.drone_timer = max(player.drone_timer, 15.0)
			player.drone_active = true
			if main:
				main.spawn_floating_text(player.position, "DRONES!", Color(0.4, 1.0, 1.0), 14, 0.9)
			explosion_system.spawn(player.position, Color(0.5, 3.0, 3.0), 0.5)
		3:  # Black Hole
			audio_manager.play_sfx(0.1, 10.0, player.position)
			explosion_system.spawn(player.position, Color(0.0, 0.0, 0.0), 2.0)
			if main:
				main.add_shake(40.0)
				main.spawn_floating_text(player.position, "BLACK HOLE!", Color(0.8, 0.5, 1.0), 14, 0.95)
			if bh_system:
				bh_system.spawn(p.pos)

func _color_for_type(type_idx: int) -> Color:
	# Single source of truth per i colori powerup — usato sia dal _draw che
	# dallo spawn-ring tell. Match con type_idx: 0=heal, 1=railgun, 2=drones,
	# 3=blackhole.
	match type_idx:
		0: return Color(0.2, 2.5, 0.5)   # Medkit verde
		1: return Color(3.0, 0.4, 2.2)   # Railgun magenta
		2: return Color(0.3, 2.8, 3.0)   # Drones cyan
		3: return Color(1.6, 0.6, 3.8)   # Black Hole viola profondo (distinto da Railgun)
		_: return Color(1.0, 1.0, 1.0)

func _draw() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var ring_pulse: float = 1.0 + 0.12 * sin(t * 7.0)
	for p in powerups:
		var c: Color = _color_for_type(p.type)
		var pos: Vector2 = p.pos
		if p.type == 3:
			# Black Hole: nucleo nero + doppio anello viola HDR pulsante
			draw_circle(pos, 10.0, Color(0.0, 0.0, 0.0, 0.95))
			draw_arc(pos, 11.0 * ring_pulse, 0.0, TAU, 24, c, 2.5, true)
			draw_arc(pos, 5.5, 0.0, TAU, 16, Color(2.5, 1.8, 4.0), 1.5, true)
		else:
			draw_circle(pos, 10.0, Color(0.05, 0.05, 0.1, 0.85))
			draw_arc(pos, 10.5 * ring_pulse, 0.0, TAU, 24, c, 2.5, true)
			var glyph_col := Color(2.2, 2.2, 2.2)
			match p.type:
				0:  # Heal: croce '+'
					draw_line(pos + Vector2(-4.5, 0), pos + Vector2(4.5, 0), glyph_col, 2.0, true)
					draw_line(pos + Vector2(0, -4.5), pos + Vector2(0, 4.5), glyph_col, 2.0, true)
				1:  # Railgun: fascio verticale con punta 'I'
					draw_line(pos + Vector2(0, -5.5), pos + Vector2(0, 5.5), glyph_col, 2.5, true)
					draw_line(pos + Vector2(-4.0, -2.0), pos + Vector2(0, -5.5), glyph_col, 1.8, true)
					draw_line(pos + Vector2(4.0, -2.0), pos + Vector2(0, -5.5), glyph_col, 1.8, true)
				2:  # Drones: due satelliti laterali + core
					draw_circle(pos, 2.0, glyph_col)
					draw_circle(pos + Vector2(-5.0, 0), 2.2, c)
					draw_circle(pos + Vector2(5.0, 0), 2.2, c)
