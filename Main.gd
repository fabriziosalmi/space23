extends Node2D
class_name Main

# Orchestratore di SPACE23. Tiene lo stato di alto livello (game state machine,
# punteggio, hp, distance), pilota la camera (shake + hit-stop), gestisce
# transizioni traccia/boss, e instrada le chiamate cross-system. La logica
# specifica vive nei sotto-sistemi in `systems/`.

# ========== TUNING CONSTANTS ==========
# Cambiando questi valori si tara il gioco senza cercare numeri sparsi nel codice.

# Pooling
const ENEMY_BULLET_POOL_SIZE: int = 2500

# Combat / collisioni
const PLAYER_BULLET_DAMAGE: int = 1
const ENEMY_BODY_COLLISION_DAMAGE: float = 30.0
const ENEMY_BULLET_DAMAGE: float = 15.0
const PLAYER_BULLET_HIT_RADIUS: float = 35.0   # player bullet → enemy
const GRAZE_RADIUS: float = 35.0               # bullet → player

# Score
const SCORE_PER_KILL: int = 250
const SCORE_PER_BOSS: int = 5000
const SCORE_PER_GRAZE: int = 50

# Powerup drop
const POWERUP_DROP_CHANCE: float = 0.20

# Bomb
const STARTING_BOMBS: int = 3
const BOMB_SHAKE: float = 80.0
const BOMB_ENEMY_DAMAGE: int = 50

# Difficulty curve (sigmoidale: cresce ma satura a DIFF_MAX, evita ingiocabilità a 30k+).
# diff(d) = 1 + (DIFF_MAX-1) * (1 - exp(-d / DIFF_DISTANCE_DIVISOR))
const DIFF_DISTANCE_DIVISOR: float = 4000.0
const DIFF_MAX: float = 4.0

# Boss
const BOSS_SPAWN_BEFORE_TRACK_END: float = 30.0
const BOSS_TYPE_INDEX: int = 5

# Player HP / Camera
const PLAYER_HP_MAX: float = 100.0
const PLAYER_HEAL: float = 40.0
const CAMERA_SHAKE_MAX: float = 10.0  # 80→45→22→10: il radial blur ora porta tutto il "punch", il movimento camera è solo un sussulto leggero
const INTRO_ZOOM: float = 4.0
const GAMEOVER_ZOOM: float = 2.5

# Black holes
const BH_PULL_RADIUS: float = 250.0
const BH_PULL_FORCE_PROJECTILE: float = 800.0
const BH_PULL_FORCE_PLAYER_BULLET: float = 1200.0
const BH_LIFE: float = 6.0
const BH_ABSORB_RADIUS: float = 20.0
const BH_GRAVITY_RADIUS: float = 500.0

# Flow
const FLOW_GAIN_PER_SEC: float = 0.08
const FLOW_DECAY_PER_SEC: float = 0.05
const FLOW_GAIN_PER_KILL: float = 0.05
const FLOW_GAIN_PER_GRAZE: float = 0.10
const FLOW_TOP_HALF_THRESHOLD: float = 0.5

# Time-dilation / scrolling
const BASE_SCROLL_SPEED: float = 100.0
const TITLE_SPEED_MULT: float = 0.05
const INTRO_SPEED_MULT: float = 0.1
const TRANSITION_SPEED_MULT: float = 0.5
const DROP_SPEED_MULT: float = 4.0
const FLOW_SPEED_BONUS: float = 0.8

# ========== STATO GAMEPLAY ==========

var distance: float = 0.0
var is_playing: bool = false
var global_speed_multiplier: float = 1.0
var target_speed_multiplier: float = 1.0
var score_points: int = 0
var player_hp: float = PLAYER_HP_MAX
var flow_state: float = 0.0
var player_bombs: int = STARTING_BOMBS
var has_boss_spawned: bool = false
var drop_event_triggered: bool = false  # one-shot per traccia
var is_paused: bool = false

# Camera FX (trauma model, Squirrel Eiserloh GDC 2016).
# `shake_intensity` resta come "trauma input" cumulativo (0..CAMERA_SHAKE_MAX), così
# i call-site esistenti (add_shake) non cambiano. Internamente lo normalizziamo a
# trauma ∈ [0,1] e l'offset è trauma² · MAX · noise — risposta non-lineare che
# punta forte sui peak e si calma rapido. Il noise è 3 sin a freq decorrelate
# (cheap Perlin-1D) per evitare il dither bianco di randf_range.
var shake_intensity: float = 0.0
var shake_time: float = 0.0  # accumulator per la phase del noise
var hit_stop_timer: float = 0.0

# Boss-explosion lensing: riusa lo shader del black hole (post.gdshader bh_*) per
# bendare brevemente il viewport quando salta un super-explosion (boss kill o
# smart bomb). Più espressivo di un semplice flash. Sovrascrive temporaneamente
# il lensing del BH reale (priorità massima per ~0.4s).
const BOSS_LENS_DURATION: float = 0.4
var boss_lens_timer: float = 0.0
var boss_lens_pos: Vector2 = Vector2.ZERO

# Damage edge glow. Triggerato da damage_player (~200ms decay), letto dal post
# shader come `damage_flash` uniform. Tinta rossa solo ai bordi → "ho preso
# danno" leggibile in periferia senza ostruire il combattimento al centro.
const DAMAGE_FLASH_DURATION: float = 0.20
var damage_flash_timer: float = 0.0

# Heartbeat di basso HP. Quando hp < 25 spara una micro-SFX a ~70 bpm. Pitch
# basso (0.4) e volume basso (-15dB): "il tuo cuore batte, sei ferito" non
# urla ma è presente. Si stacca quando guarisci o muori.
const HEARTBEAT_HP_THRESHOLD: float = 25.0
const HEARTBEAT_PERIOD: float = 0.857  # 60/70 bpm
var heartbeat_timer: float = 0.0

# Input buffer per la bomb: se la pressione cade in uno stato non-PLAYING
# (intro, transition, hit-stop, gameover prima del retry), la "memorizziamo"
# per un breve window e la consumiamo al primo frame di PLAYING valido.
# Standard fighting/rhythm games: 6-10 frame ≈ 0.10-0.17s.
const BOMB_INPUT_BUFFER: float = 0.18
var bomb_buffer_timer: float = 0.0

# Game state machine
var game_state: String = "TITLE"  # TITLE / INTRO / PLAYING / GAMEOVER
var is_intro: bool = false
var intro_timer: float = 2.0  # da 5.0: era troppo lungo per un prototipo web (8s totali al primo wave incluso wave_timer)
var game_over_timer: float = 0.0
var player_name: String = "PLAYER 1"

# Color transitions per nebula (palette di partenza = track 1, allineato al
# bumping 3x della playlist in AudioManager.gd)
var current_c_bg: Color = Color(0.015, 0.0, 0.045)
var current_c_neb1: Color = Color(0.15, 0.03, 0.3)
var current_c_neb2: Color = Color(0.0, 0.15, 0.45)
var target_c_bg: Color = current_c_bg
var target_c_neb1: Color = current_c_neb1
var target_c_neb2: Color = current_c_neb2

# Riferimenti scena
var screen_size: Vector2
var main_camera: Camera2D
var world_env: WorldEnvironment
var audio_manager
var bg_renderer
var ui_manager

# Sistemi
var enemy_system: EnemySystem
var projectile_system: ProjectileSystem
var explosion_system: ExplosionSystem
var powerup_system: PowerupSystem
var railgun_system: RailgunSystem
var bh_system: BlackHoleSystem
var wave_director: WaveDirector
var post_fx: PostFXController

@onready var player = preload("res://Player.tscn").instantiate()

# ============================================================
# SETUP
# ============================================================

func _ready() -> void:
	screen_size = get_viewport_rect().size

	# --- INPUT MAP (registriamo qui per non dover editare project.godot) ---
	_setup_input_actions()

	# --- AUDIO ---
	audio_manager = load("res://AudioManager.gd").new()
	add_child(audio_manager)

	# --- BACKGROUND (z=-10, sotto a tutto) ---
	bg_renderer = load("res://BackgroundRenderer.gd").new()
	add_child(bg_renderer)

	# --- WORLD ENV: ACES + bloom HDR ---
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 1.8
	env.glow_bloom = 0.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# --- UI (CanvasLayer 101, sopra tutto) ---
	ui_manager = load("res://UIManager.gd").new()
	add_child(ui_manager)
	ui_manager.start_pressed.connect(_on_start_pressed)
	ui_manager.name_submitted.connect(_on_name_submitted)
	ui_manager.retry_pressed.connect(_on_retry_pressed)
	ui_manager.bomb_pressed.connect(_on_bomb_button_pressed)
	ui_manager.pause_toggle_requested.connect(toggle_pause)

	# --- POST-PROCESSING (CanvasLayer 100, sopra il mondo / sotto la UI) ---
	post_fx = preload("res://systems/PostFXController.gd").new()
	add_child(post_fx)
	post_fx.setup(screen_size)

	# --- SISTEMI DI GIOCO ---
	# Z-index espliciti per garantire la gerarchia visibilità "threat-first" (regola
	# SOTA Cave/Crimzon Clover): i bullet nemici — l'unica cosa che ti uccide —
	# devono essere SEMPRE leggibili anche dentro un'esplosione. L'occlusione di
	# un bullet da parte di detriti estetici = death-by-confusion.
	#
	#   railgun (-3) → enemy/powerup (-2) → explosion (-1) → bullet (0) → player (1)
	enemy_system = preload("res://systems/EnemySystem.gd").new()
	enemy_system.z_index = -2
	add_child(enemy_system)

	powerup_system = preload("res://systems/PowerupSystem.gd").new()
	powerup_system.z_index = -2
	add_child(powerup_system)

	railgun_system = preload("res://systems/RailgunSystem.gd").new()
	railgun_system.z_index = -3  # fascio luminoso "di fondale", sotto a tutto il gameplay
	add_child(railgun_system)

	bh_system = preload("res://systems/BlackHoleSystem.gd").new()
	bh_system.z_index = -1
	add_child(bh_system)

	explosion_system = preload("res://systems/ExplosionSystem.gd").new()
	explosion_system.z_index = -1  # eye-candy: sotto i proiettili (non li deve coprire)
	add_child(explosion_system)

	projectile_system = preload("res://systems/ProjectileSystem.gd").new()
	projectile_system.z_index = 0  # threat layer
	add_child(projectile_system)

	wave_director = preload("res://systems/WaveDirector.gd").new()
	add_child(wave_director)

	# --- PLAYER (sopra tutto il gameplay) ---
	add_child(player)
	player.main = self  # wired before first _process / draw signal fires
	player.z_index = 1
	player.position = Vector2(screen_size.x / 2, screen_size.y - 160)

	# --- CAMERA ---
	main_camera = Camera2D.new()
	main_camera.position = screen_size / 2.0
	main_camera.zoom = Vector2(1.0, 1.0)
	add_child(main_camera)

	# AudioManager usa la camera come listener 2D per il pan stereo degli SFX.
	audio_manager.camera_ref = main_camera

	# --- WIRING DEI RIFERIMENTI ---
	enemy_system.main = self
	enemy_system.player = player
	enemy_system.projectile_system = projectile_system
	enemy_system.explosion_system = explosion_system
	enemy_system.audio_manager = audio_manager
	enemy_system.screen_size = screen_size

	projectile_system.main = self
	projectile_system.player = player
	projectile_system.enemy_system = enemy_system
	projectile_system.bh_system = bh_system
	projectile_system.explosion_system = explosion_system
	projectile_system.audio_manager = audio_manager
	projectile_system.screen_size = screen_size
	projectile_system.setup_pool()

	powerup_system.main = self
	powerup_system.player = player
	powerup_system.audio_manager = audio_manager
	powerup_system.explosion_system = explosion_system
	powerup_system.bh_system = bh_system
	powerup_system.screen_size = screen_size

	railgun_system.main = self
	railgun_system.audio_manager = audio_manager
	railgun_system.enemy_system = enemy_system
	railgun_system.explosion_system = explosion_system

	bh_system.main = self
	bh_system.enemy_system = enemy_system
	bh_system.projectile_system = projectile_system

	wave_director.enemy_system = enemy_system
	wave_director.audio_manager = audio_manager  # phase coupling con la traccia
	wave_director.load_from_json("res://waves.json")

	# --- STATO INIZIALE ---
	player.can_move = false
	game_state = "TITLE"

# ============================================================
# INPUT MAP
# ============================================================

# Mapping default. Gli utenti possono sovrascriverli runtime tramite InputMap
# (es. menu rebind futuro). Usiamo `physical_keycode` per essere indipendenti
# dal layout (W su QWERTY = stesso tasto su AZERTY).
const _DEFAULT_KEY_BINDINGS := {
	"move_up":    [KEY_W, KEY_UP],
	"move_down":  [KEY_S, KEY_DOWN],
	"move_left":  [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"fire":       [KEY_SPACE],
	"dash":       [KEY_SHIFT],
	"bomb":       [KEY_X],
	"pause":      [KEY_ESCAPE, KEY_P],
}

# Joypad button bindings (Xbox layout — PS controllers map identically via
# Godot's gamepad DB). D-pad per il movimento digitale; face button A/X per
# fire (+ RB), B/O per dash (+ LB), X/□ per bomb (+ Y/△ come secondario),
# Start per pause. Stick analogico aggiunto sotto via InputEventJoypadMotion.
const _DEFAULT_JOY_BUTTONS := {
	"move_up":    [JOY_BUTTON_DPAD_UP],
	"move_down":  [JOY_BUTTON_DPAD_DOWN],
	"move_left":  [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"fire":       [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER],
	"dash":       [JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER],
	"bomb":       [JOY_BUTTON_X, JOY_BUTTON_Y],
	"pause":      [JOY_BUTTON_START],
}

# Stick analogico (left). Formato: [axis_index, sign]. Sign -1 = direzione
# negativa dell'asse (su / sinistra), +1 = positiva (giù / destra). Godot
# usa una deadzone di 0.5 per is_action_pressed → lo stick fa effetto solo
# oltre il 50% di inclinazione (Livello A: digitale). Il Livello B userebbe
# get_action_strength per analogico graduato — non incluso qui.
const _DEFAULT_JOY_AXES := {
	"move_up":    [JOY_AXIS_LEFT_Y, -1.0],
	"move_down":  [JOY_AXIS_LEFT_Y,  1.0],
	"move_left":  [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X,  1.0],
}

func _setup_input_actions() -> void:
	for action_name in _DEFAULT_KEY_BINDINGS.keys():
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)
		InputMap.add_action(action_name)
		# Keyboard bindings
		for k in _DEFAULT_KEY_BINDINGS[action_name]:
			var key_ev := InputEventKey.new()
			key_ev.physical_keycode = k
			InputMap.action_add_event(action_name, key_ev)
		# Joypad button bindings (D-pad + face buttons + shoulders)
		if _DEFAULT_JOY_BUTTONS.has(action_name):
			for btn in _DEFAULT_JOY_BUTTONS[action_name]:
				var btn_ev := InputEventJoypadButton.new()
				btn_ev.button_index = btn
				InputMap.action_add_event(action_name, btn_ev)
		# Joypad analog axis bindings (left stick)
		if _DEFAULT_JOY_AXES.has(action_name):
			var ai: Array = _DEFAULT_JOY_AXES[action_name]
			var axis_ev := InputEventJoypadMotion.new()
			axis_ev.axis = ai[0]
			axis_ev.axis_value = ai[1]
			InputMap.action_add_event(action_name, axis_ev)

# ============================================================
# STATE TRANSITIONS
# ============================================================

func _on_start_pressed() -> void:
	game_state = "INTRO"
	is_intro = true
	is_playing = true
	audio_manager.load_and_play_track(0)
	main_camera.position = Vector2(screen_size.x / 2, screen_size.y - 160)
	main_camera.zoom = Vector2(INTRO_ZOOM, INTRO_ZOOM)
	_set_cursor_hidden(true)

# Cursore di sistema nascosto durante gameplay (TITLE/GAMEOVER/PAUSE → visible
# perché serve per click su menu/leaderboard/retry/name input). La nave segue
# comunque la mouse position anche con cursore nascosto — Godot tracka mouse
# pos a prescindere. Su touch/mobile la chiamata è no-op (nessun cursore).
func _set_cursor_hidden(hidden: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if hidden else Input.MOUSE_MODE_VISIBLE

func _on_name_submitted(new_text: String) -> void:
	player_name = new_text

func trigger_game_over() -> void:
	game_state = "GAMEOVER"
	game_over_timer = 0.0
	player_hp = 0
	player.can_move = false
	player.visible = false
	add_shake(60.0)
	_set_cursor_hidden(false)  # name input + retry button cliccabili
	explosion_system.spawn(player.position, Color(4.0, 1.0, 0.5), 3.0, true)
	target_speed_multiplier = 0.0

func _on_retry_pressed() -> void:
	# Reset FX accumulati dal _tick_gameover_fx (zoom, blur, grayscale, pitch).
	# Senza questi reset il viewport resta nero/zoomato/silenzioso anche dopo
	# che lo stato logico è tornato a PLAYING — bug osservato: schermo nero
	# fuorché player ghost, audio muto.
	post_fx.set_zoom_blur(0.0)
	post_fx.set_grayscale(0.0)
	post_fx.clear_bh()
	main_camera.zoom = Vector2(1.0, 1.0)
	main_camera.position = screen_size / 2.0
	main_camera.offset = Vector2.ZERO
	audio_manager.audio_stream_player.pitch_scale = 1.0
	audio_manager.audio_stream_player.stream_paused = false
	audio_manager.is_transitioning = false
	audio_manager.transition_timer = 0.0

	# Reset transient timers gameplay (shake, hit-stop, lensing, input buffer):
	# se erano attivi nel momento del game-over, sopravviverebbero al retry.
	shake_intensity = 0.0
	hit_stop_timer = 0.0
	boss_lens_timer = 0.0
	bomb_buffer_timer = 0.0

	# Restore tempo gameplay (target_speed era 0.0 dal trigger_game_over).
	global_speed_multiplier = 1.0
	target_speed_multiplier = 1.0

	# Instant Restart (QoL SOTA): un piccolo punch al respawn.
	add_shake(150.0)
	trigger_hit_stop(0.5)

	player_hp = PLAYER_HP_MAX
	player_bombs = STARTING_BOMBS
	score_points = 0
	flow_state = 0.0
	distance = 0.0

	wave_director.reset()

	player.position = Vector2(screen_size.x / 2.0, screen_size.y - 100)
	player.velocity = Vector2.ZERO
	# Grace period più generoso del normal hit i-frame: 1s per dare al player
	# il tempo di orientarsi al respawn.
	player.hit_iframe_timer = 1.0
	player.is_dashing = false
	player.dash_timer = 0.0
	player.dash_cooldown = 0.0
	player.dash_dir = Vector2.ZERO
	# Reset dei powerup attivi: se il player muore col railgun o coi drones
	# attivi, non vogliamo che li conservi al respawn (sarebbe inconsistente
	# col reset di score/distance/bombs).
	player.fire_buff_timer = 0.0
	player.weapon_type = 0
	player.drone_active = false
	player.trail_history.clear()
	player.visible = true
	player.can_move = true

	enemy_system.clear()
	projectile_system.clear_all()
	powerup_system.clear()
	railgun_system.clear()
	bh_system.clear()
	explosion_system.clear()
	if bg_renderer:
		bg_renderer.clear_landmarks()

	game_state = "PLAYING"
	game_over_timer = 0.0
	is_intro = false
	has_boss_spawned = false
	drop_event_triggered = false
	is_paused = false
	if ui_manager: ui_manager.set_pause_visible(false)
	_set_cursor_hidden(true)

	audio_manager.load_and_play_track(0)

	if is_instance_valid(ui_manager):
		ui_manager.hide_game_over()
		ui_manager.update_boss_hp(0, 100)

# ============================================================
# API ESPOSTA AI SOTTO-SISTEMI / PLAYER
# ============================================================

func add_shake(amount: float) -> void:
	shake_intensity = min(shake_intensity + amount, CAMERA_SHAKE_MAX)

func trigger_hit_stop(duration: float) -> void:
	hit_stop_timer = max(hit_stop_timer, duration)

# Difficolta sigmoidale: cresce dolcemente, satura a DIFF_MAX (evita 7×+ a 30k m).
static func diff_for_distance(d: float) -> float:
	return 1.0 + (DIFF_MAX - 1.0) * (1.0 - exp(-d / DIFF_DISTANCE_DIVISOR))

func difficulty() -> float:
	return diff_for_distance(distance)

func toggle_pause() -> void:
	if game_state != "PLAYING":
		return
	is_paused = not is_paused
	if audio_manager and audio_manager.audio_stream_player:
		audio_manager.audio_stream_player.stream_paused = is_paused
	if ui_manager:
		ui_manager.set_pause_visible(is_paused)
	# Cursor visibile in pausa (tap overlay = unpause), nascosto al resume.
	_set_cursor_hidden(not is_paused)

func _on_bomb_button_pressed() -> void:
	# Pressione dal bomb button mobile/UI: la riportiamo al buffer in modo che
	# segua lo stesso path del press da tastiera (consumato in _tick_playing).
	bomb_buffer_timer = BOMB_INPUT_BUFFER

# Drop event one-shot: arriva la cassa potente, spawna bonus wave + powerup garantito.
func _on_drop_event() -> void:
	# Bonus wave: tre invader ravvicinati che entrano dall'alto
	var diff: float = difficulty()
	enemy_system.spawn(4, Vector2(screen_size.x * 0.30, -100), diff)
	enemy_system.spawn(4, Vector2(screen_size.x * 0.50, -120), diff)
	enemy_system.spawn(4, Vector2(screen_size.x * 0.70, -100), diff)
	# Powerup garantito (random tra i 4 tipi)
	powerup_system.spawn(Vector2(screen_size.x / 2.0, -50), randi() % 4)
	# Cue audio + shake leggero come "qui parte la goduria" — pan centrato (default).
	audio_manager.play_sfx(0.3, 8.0)
	add_shake(20.0)

func add_score(n: int) -> void:
	score_points += n

func gain_flow(amount: float) -> void:
	flow_state = min(flow_state + amount, 1.0)

func try_drop_powerup(pos: Vector2) -> void:
	if randf() < POWERUP_DROP_CHANCE:
		powerup_system.spawn(pos, randi() % 4)

func handle_enemy_kill(e: Dictionary) -> void:
	# Centralised kill FX + scoring. Called by every system that can bring an
	# enemy's HP to 0 — player bullets (ProjectileSystem), railgun beam
	# (RailgunSystem), black-hole absorption (BlackHoleSystem). The caller is
	# responsible for removing the enemy from the enemies array (it has the
	# index; we don't). Centralising here fixes two bugs from before:
	#   - boss killed by railgun got no boss FX (no lensing, +250 score
	#     instead of +5250, 0.05s hit-stop instead of 1.2s)
	#   - boss/anything killed by BH absorb was silently removed by
	#     EnemySystem's hp<=0 cleanup → no score, no SFX, no FX at all
	# Boss kill is the dramatic finish (super explosion, lens warp, +5000
	# score). Normal kill gets hit-stop bracketed by base_hp so a "scout-class"
	# kill stays scout-class even at diff 4.
	if e.ai_type == BOSS_TYPE_INDEX:
		if is_instance_valid(ui_manager):
			ui_manager.update_boss_hp(0, 100)
		add_score(SCORE_PER_BOSS)
		explosion_system.spawn(e.pos, Color(3.0, 1.0, 0.2), 3.0, true)
		audio_manager.play_sfx(0.2, 10.0, e.pos)  # boss kill: pan dalla pos del boss
		add_shake(100.0)
		trigger_hit_stop(1.2)
		trigger_boss_lens(e.pos)
	else:
		explosion_system.spawn(e.pos, Color(3.0, 1.0, 0.2), 1.0)
		# Hit-stop bracket su base_hp (pre-difficulty), così uno scout resta
		# scout-class anche a diff 4. Buckets calibrati sui base_hp dei tipi:
		# 2-4 (scout/squid)=0.02; 5-10 (fighter/crab/octopus/mantis/sentinel)=0.04;
		# 12-30 (tank/dread/spinner)=0.07.
		var bhp: int = int(e.get("base_hp", e.get("max_hp", 1)))
		var stop_dur: float
		if bhp <= 4:
			stop_dur = 0.02
		elif bhp <= 10:
			stop_dur = 0.04
		else:
			stop_dur = 0.07
		trigger_hit_stop(stop_dur)

	gain_flow(FLOW_GAIN_PER_KILL)
	try_drop_powerup(e.pos)
	add_score(SCORE_PER_KILL)

func damage_player(amount: float) -> void:
	# Guard: se i-frame ancora attivi, ignoriamo il danno. Necessario perché
	# alcuni call site (es. body collision) bypassano il check di is_invincible
	# o lo controllano prima dell'incremento del timer di un altro hit nello
	# stesso frame.
	if player.hit_iframe_timer > 0.0:
		return
	player_hp -= amount
	flow_state = 0.0
	# I-frame post-damage: blocca lo stacking di più bullet sullo stesso frame
	# (il check `not player.is_invincible` nei collision detector vedrà true
	# dal prossimo proiettile in poi finché il timer non scade).
	player.hit_iframe_timer = player.HIT_IFRAME_DURATION
	# Brief white-flash pulse sul body (~80ms) = feedback istantaneo "hit!"
	player.trigger_hit_flash()
	# Damage SFX: pitch basso (0.4) + volume medio. Suona "grave" e impatta
	# audio l'evento più importante del gameplay (player perso HP). Pan dalla
	# pos del player. Distinto dai SFX kill nemico (pitch 0.5/0.8).
	audio_manager.play_sfx(0.4, 0.0, player.position)
	# Edge red glow: 200ms in periferia. Letto dal post shader.
	damage_flash_timer = DAMAGE_FLASH_DURATION
	if player_hp <= 0 and game_state != "GAMEOVER":
		trigger_game_over()

func heal(amount: float) -> void:
	player_hp = min(player_hp + amount, PLAYER_HP_MAX)

# Delegano alle API dei sistemi — Player chiama queste via get_parent().
func spawn_player_bullet(pos: Vector2, dir: Vector2 = Vector2.UP, color: Color = Color(0.2, 1.5, 3.0), bounces: int = 0) -> void:
	projectile_system.spawn_player_bullet(pos, dir, color, bounces)

# Wrapper tipato per i drone shot. Esiste per blindare la call-site contro
# refactor della firma di spawn_player_bullet: i drone sparano sempre dritti
# verso l'alto, il colore è il solo parametro variabile. Senza wrapper, il
# Player passava color come argomento posizionale al posto di dir → bug
# silenzioso se la firma cambia.
func spawn_drone_bullet(pos: Vector2, color: Color) -> void:
	projectile_system.spawn_player_bullet(pos, Vector2.UP, color, 0)

func spawn_railgun(pos: Vector2) -> void:
	railgun_system.spawn(pos)

# ============================================================
# SMART BOMB
# ============================================================

func trigger_smart_bomb() -> void:
	player_bombs -= 1
	audio_manager.play_sfx(0.2, 5.0, player.position)
	add_shake(BOMB_SHAKE)

	# Super esplosione bianca + pulizia bullet hell + lensing del viewport.
	explosion_system.spawn(player.position, Color(10.0, 10.0, 10.0), 3.0, true)
	trigger_boss_lens(player.position)
	projectile_system.clear_enemy_bullets_with_fx()

	# Danno globale ai nemici
	for i in range(enemy_system.enemies.size() - 1, -1, -1):
		var e: Dictionary = enemy_system.enemies[i]
		e.hp -= BOMB_ENEMY_DAMAGE
		e.hit_flash = 1.0
		if e.hp <= 0:
			explosion_system.spawn(e.pos, Color(3.0, 1.0, 0.2), 1.0)
			score_points += 100
			enemy_system.enemies.remove_at(i)

# ============================================================
# MAIN LOOP
# ============================================================

func _process(delta: float) -> void:
	# Pause toggle: sempre processato (ESC/P sblocca anche se in pausa).
	if Input.is_action_just_pressed("pause"):
		toggle_pause()

	# Pausa: freeze totale e immediato. Shake, bomb buffer, hit-stop e tutti i
	# sistemi mantengono lo stato esatto al momento del press → l'unpause
	# riprende seamless. Senza questo early-return, lo shake decadeva in
	# real-time durante la pausa e all'unpause il momento era perso (es. pausi
	# su un peak hit, attendi 1s, sblocchi → camera già a riposo).
	if is_paused:
		return

	# Bomb input buffer: registriamo il press indipendentemente dallo stato di
	# gioco, così non perdiamo l'input durante intro/transition/hit-stop. Il
	# consumo avviene in _tick_playing al primo frame valido.
	if Input.is_action_just_pressed("bomb"):
		bomb_buffer_timer = BOMB_INPUT_BUFFER
	if bomb_buffer_timer > 0.0:
		bomb_buffer_timer = max(bomb_buffer_timer - delta, 0.0)

	# Camera shake. trauma² · MAX · smooth_noise: i peak sentono fortissimo,
	# il decay è rapido. Skippato in pausa (early-return sopra).
	if shake_intensity > 0.0:
		shake_time += delta
		var trauma: float = shake_intensity / CAMERA_SHAKE_MAX
		var t2: float = trauma * trauma
		# Tre sin a freq decorrelate (golden ratio gap) → noise pseudo-Perlin,
		# decorrelato tra X e Y così non si inclina sempre sulla diagonale.
		var nx: float = sin(shake_time * 47.0) * 0.6 + sin(shake_time * 23.7) * 0.4
		var ny: float = sin(shake_time * 38.3 + 1.7) * 0.6 + sin(shake_time * 19.1 + 0.9) * 0.4
		main_camera.offset = Vector2(nx, ny) * (t2 * CAMERA_SHAKE_MAX)
		# Decay lineare di trauma (= decay quadratico dell'offset visivo).
		# 1.6 unità trauma/sec ⇒ uno shake al massimo (trauma=1) si esaurisce in ~0.6s.
		shake_intensity = max(shake_intensity - 1.6 * CAMERA_SHAKE_MAX * delta, 0.0)
	else:
		main_camera.offset = Vector2.ZERO

	# Hit-stop globale: tutto il gameplay si ferma (la camera è già stata aggiornata sopra).
	if hit_stop_timer > 0:
		hit_stop_timer -= delta
		return

	# TITLE: niente gameplay, ma facciamo "respirare" la nebula:
	#  - fake_pulse simula la cassa (lo strobe del nebula shader resta vivo
	#    anche senza musica)
	#  - cicliamo lentamente attraverso i colori delle 3 tracce della playlist
	#    (mood-shift ogni ~8s) così l'universo non resta sempre uguale.
	if game_state == "TITLE":
		global_speed_multiplier = TITLE_SPEED_MULT
		var t: float = Time.get_ticks_msec() / 1000.0
		var fake_pulse: float = 0.45 + 0.25 * sin(t * 0.7)  # 0.20 → 0.70

		if audio_manager and audio_manager.playlist.size() > 0:
			var pl: Array = audio_manager.playlist
			var period: float = 8.0
			var idx: int = int(t / period) % pl.size()
			var next_idx: int = (idx + 1) % pl.size()
			var phase: float = fmod(t, period) / period
			var ca = pl[idx].colors
			var cb = pl[next_idx].colors
			current_c_bg   = ca[0].lerp(cb[0], phase)
			current_c_neb1 = ca[1].lerp(cb[1], phase)
			current_c_neb2 = ca[2].lerp(cb[2], phase)

		bg_renderer.update_background(delta, global_speed_multiplier, current_c_bg, current_c_neb1, current_c_neb2, fake_pulse, audio_manager.audio_mid, audio_manager.audio_high)
		return

	if not is_playing:
		return

	# Retry da gameover (Enter / R)
	if Input.is_action_just_pressed("ui_accept") and game_state == "GAMEOVER" and game_over_timer > 0.5:
		_on_retry_pressed()
		return

	# Sub-state dispatch ESCLUSIVO. Prima era una catena spuria:
	#   if GAMEOVER: _tick_gameover_fx(...)
	#   if is_intro: _tick_intro
	#   elif transitioning: _tick_track_transition
	#   else: _tick_playing
	# Risultato: in GAMEOVER giravano sia _tick_gameover_fx che _tick_playing,
	# con _tick_playing a sovrascrivere target_speed, far crescere flow/score
	# dal y_ratio, lerpare la camera verso target_cam_x in conflitto col lerp
	# verso player.position di _tick_gameover_fx, e consumare il bomb_buffer.
	if game_state == "GAMEOVER":
		_tick_gameover_fx(delta)
	elif is_intro:
		_tick_intro(delta)
	elif audio_manager.is_transitioning:
		_tick_track_transition(delta)
	else:
		_tick_playing(delta)

	# Tempo globale (smooth verso target). Lerp rate 4.0/s ⇒ settling ~0.5s.
	# Prima era 1.5/s (settling 1.5s) e con clamp floor SUPERHOT 0.05 le
	# transizioni stop↔move duravano abbastanza da percepirsi come stutter
	# sincrono su tutti gli elementi gsm-multiplied (bullets, enemies, scroll).
	global_speed_multiplier = lerp(global_speed_multiplier, target_speed_multiplier, 4.0 * delta)

	# Boss spawn + wave director SOLO in PLAYING reale. Il vecchio gate
	# (not is_intro and not transitioning) lasciava passare il GAMEOVER → boss
	# poteva spawnare a fine traccia dopo la morte, e il wave director
	# continuava a sfornare nemici sul cadavere.
	if game_state == "PLAYING" and not audio_manager.is_transitioning:
		_check_boss_spawn()
		wave_director.tick(delta, distance, screen_size)

	# Damage edge-glow decay (post shader uniform). 200ms da hit a zero.
	if damage_flash_timer > 0.0:
		damage_flash_timer = max(damage_flash_timer - delta, 0.0)

	# Heartbeat di basso HP. Solo durante PLAYING reale (non during transition,
	# non during gameover). Periodo 70 bpm. SFX pitch 0.4 + vol -15dB → grave
	# e quieto, percepito come pulsazione di tensione.
	if game_state == "PLAYING" and player_hp > 0.0 and player_hp < HEARTBEAT_HP_THRESHOLD:
		heartbeat_timer -= delta
		if heartbeat_timer <= 0.0:
			heartbeat_timer = HEARTBEAT_PERIOD
			audio_manager.play_sfx(0.4, -15.0, player.position)
	else:
		heartbeat_timer = 0.0  # reset quando guarisci / muori / non in playing

	# Sistemi di gioco
	projectile_system.tick(delta)
	enemy_system.tick(delta)
	bh_system.tick(delta)
	railgun_system.tick(delta)
	powerup_system.tick(delta)
	explosion_system.tick(delta)

	# Post-FX uniforms
	_update_post_fx()

	# Track-change palette tease: negli ultimi 5s di una traccia, drift molto
	# soft della palette target verso la palette della prossima traccia. Peak
	# ~30% blend nell'ultimo frame, quindi current_c_* (lerp 0.8/s) raggiunge
	# ~24% di blend prima del fade-to-black di _tick_track_transition. Sells
	# continuità musicale↔visiva — l'universo "sente" il cambio in arrivo.
	# Skippato durante transition (le palette target sono già nere lì) e in
	# stati non-PLAYING.
	if game_state == "PLAYING" and not audio_manager.is_transitioning:
		var stream = audio_manager.audio_stream_player.stream
		if stream:
			var time_left: float = stream.get_length() - audio_manager.get_playback_position()
			if time_left > 0.0 and time_left < 5.0:
				var tease: float = (5.0 - time_left) / 5.0 * 0.3
				var pl: Array = audio_manager.playlist
				var cur_idx: int = audio_manager.current_track_idx
				var next_idx: int = (cur_idx + 1) % pl.size()
				var cur_colors = pl[cur_idx].colors
				var next_colors = pl[next_idx].colors
				target_c_bg = cur_colors[0].lerp(next_colors[0], tease)
				target_c_neb1 = cur_colors[1].lerp(next_colors[1], tease)
				target_c_neb2 = cur_colors[2].lerp(next_colors[2], tease)

	# Transizione colori nebula
	current_c_bg = current_c_bg.lerp(target_c_bg, 0.8 * delta)
	current_c_neb1 = current_c_neb1.lerp(target_c_neb1, 0.8 * delta)
	current_c_neb2 = current_c_neb2.lerp(target_c_neb2, 0.8 * delta)

	# Audio reactive shake (solo sui beat forti)
	if audio_manager.audio_low > 0.75:
		add_shake(audio_manager.audio_low * 3.0)

	# Glow stabile
	if world_env and world_env.environment:
		world_env.environment.glow_intensity = 1.8

	# Background scroll (con kick→parallasse boost interno a BackgroundRenderer).
	# Passiamo player.position.x: il BackgroundRenderer calcola un viewport
	# offset position-keyed (smoothato + clampato) e ogni layer shifta in base
	# al proprio depth factor → parallasse vero (non più velocity-driven).
	bg_renderer.update_background(delta, global_speed_multiplier, current_c_bg, current_c_neb1, current_c_neb2, audio_manager.audio_low, audio_manager.audio_mid, audio_manager.audio_high, player.position.x)

	# Distance + HUD (DIST + KILLS separati così il punteggio kill non viene
	# sommerso dalla distance dopo 1 minuto di gioco).
	distance += BASE_SCROLL_SPEED * global_speed_multiplier * delta
	ui_manager.update_hud(player_hp, int(distance), score_points, flow_state, player_bombs)

# ============================================================
# SUB-STATE TICKS
# ============================================================

func _tick_intro(delta: float) -> void:
	intro_timer -= delta
	main_camera.zoom = main_camera.zoom.lerp(Vector2(1.0, 1.0), 0.8 * delta)
	main_camera.position = main_camera.position.lerp(screen_size / 2.0, 0.8 * delta)
	target_speed_multiplier = INTRO_SPEED_MULT
	if intro_timer <= 0:
		is_intro = false
		# La state machine deve riflettere PLAYING qui o toggle_pause() resta
		# bloccato al primo playthrough (gate `game_state != "PLAYING"` → ESC
		# non pausa finché non muori e fai retry).
		game_state = "PLAYING"
		player.can_move = true
		main_camera.zoom = Vector2(1.0, 1.0)
		main_camera.position = screen_size / 2.0

func _tick_track_transition(delta: float) -> void:
	audio_manager.transition_timer -= delta
	# Effetto: buio totale e slow motion
	target_c_bg = Color(0, 0, 0)
	target_c_neb1 = Color(0, 0, 0)
	target_c_neb2 = Color(0, 0, 0)
	target_speed_multiplier = TRANSITION_SPEED_MULT

	if audio_manager.transition_timer <= 0:
		audio_manager.is_transitioning = false
		audio_manager.current_track_idx = (audio_manager.current_track_idx + 1) % audio_manager.playlist.size()
		audio_manager.load_and_play_track(audio_manager.current_track_idx)
		# Nuova traccia → boss e drop event della prossima traccia devono ri-armarsi.
		has_boss_spawned = false
		drop_event_triggered = false
		var t_colors = audio_manager.playlist[audio_manager.current_track_idx].colors
		target_c_bg = t_colors[0]
		target_c_neb1 = t_colors[1]
		target_c_neb2 = t_colors[2]

func _tick_playing(delta: float) -> void:
	# Velocità base: warp dopo il drop della traccia.
	var base_target_speed: float = 1.0
	var pos: float = audio_manager.get_playback_position()
	var drop: float = audio_manager.get_current_drop_time()
	if pos >= drop:
		base_target_speed = DROP_SPEED_MULT
		# One-shot: spawna bonus wave + powerup garantito al primo crossing.
		if not drop_event_triggered:
			drop_event_triggered = true
			_on_drop_event()

	# SUPERHOT: time dilation legata alla velocità del player. Floor 0.9
	# (prima 0.5, prima ancora 0.05). Il floor 0.5 toglieva lo stutter
	# discreto del 0.05 ma lasciava un'oscillazione *continua* sincrona:
	# tutti gli elementi gsm-scaled (bullets, enemies, scroll, comete)
	# pulsavano insieme al ritmo dei cambi di velocità del player. Anche
	# smooth, il sync era leggibile come "il mondo cambia velocità con me"
	# = artificial. A 0.9 l'ampiezza scende dal 50% al 10% — sotto la
	# soglia percettiva. SuperHot vive ancora come *feeling* sottile
	# ("il mondo ha leggero peso quando ti fermi") senza il sync visibile.
	# Se ulteriormente eccessivo, escalation: disaccoppiare il bg dal gsm.
	var speed_ratio: float = clamp(player.velocity.length() / player.max_speed, 0.9, 1.0)
	if player.is_dashing:
		speed_ratio = 1.0  # Dash forza il tempo reale
	target_speed_multiplier = base_target_speed * speed_ratio * (1.0 + flow_state * FLOW_SPEED_BONUS)

	# Smart bomb: consuma dal buffer (vedi _process) — copre i casi in cui il
	# press è caduto durante intro/transition/hit-stop, evitando "il gioco mi ha
	# mangiato la bomb".
	if bomb_buffer_timer > 0.0 and player_bombs > 0:
		bomb_buffer_timer = 0.0
		trigger_smart_bomb()

	# DMC Risk/Reward: nel mezzo schermo alto si guadagna flow + bonus score.
	var player_y_ratio: float = player.position.y / screen_size.y
	if player_y_ratio < FLOW_TOP_HALF_THRESHOLD:
		flow_state = min(flow_state + delta * FLOW_GAIN_PER_SEC, 1.0)
		score_points += int(15 * delta * (1.0 - player_y_ratio))
	else:
		flow_state = max(flow_state - delta * FLOW_DECAY_PER_SEC, 0.0)

	# Parallasse camera (segue dolcemente il player sull'asse X)
	var target_cam_x: float = (screen_size.x / 2.0) + (player.position.x - (screen_size.x / 2.0)) * 0.15
	main_camera.position.x = lerp(main_camera.position.x, target_cam_x, 3.0 * delta)

func _tick_gameover_fx(delta: float) -> void:
	game_over_timer += delta
	# Fotofinish: slow-mo estremo, zoom + blur + grayscale.
	main_camera.zoom = main_camera.zoom.lerp(Vector2(GAMEOVER_ZOOM, GAMEOVER_ZOOM), 0.8 * delta)
	main_camera.position = main_camera.position.lerp(player.position, 1.5 * delta)
	audio_manager.audio_stream_player.pitch_scale = lerp(audio_manager.audio_stream_player.pitch_scale, 0.01, 1.0 * delta)

	post_fx.set_zoom_blur(lerp(post_fx.get_zoom_blur(), 0.4, 1.5 * delta))
	post_fx.set_grayscale(lerp(post_fx.get_grayscale(), 1.0, 1.5 * delta))

	if game_over_timer > 3.0 and not ui_manager.game_over_container.visible:
		ui_manager.show_game_over(int(distance), score_points)

func _check_boss_spawn() -> void:
	if not audio_manager.audio_stream_player.stream:
		return
	var track_len: float = audio_manager.audio_stream_player.stream.get_length()
	var pos: float = audio_manager.get_playback_position()
	if pos > track_len - BOSS_SPAWN_BEFORE_TRACK_END and not has_boss_spawned:
		has_boss_spawned = true
		enemy_system.spawn(BOSS_TYPE_INDEX, Vector2(screen_size.x / 2.0, -200), difficulty())
		audio_manager.play_sfx(0.5, 10.0)
		add_shake(50.0)

func _update_post_fx() -> void:
	post_fx.set_flow(flow_state)
	post_fx.set_audio_bass(audio_manager.audio_low)
	post_fx.set_damage_flash(damage_flash_timer / DAMAGE_FLASH_DURATION)

	# Radial blur driven by shake_intensity — same trauma signal that does the
	# physical shake. Net effect: small physical shake + bigger visual blur
	# pulse around the ship. Replaces the brute "shake everything" feel.
	post_fx.set_radial_blur(shake_intensity / CAMERA_SHAKE_MAX)
	# Ship's rendered UV (camera-relative). Used as the calm centre of the
	# blur mask. We don't compensate for camera.offset here — the slight
	# off-centre during shake is invisible.
	if player and is_instance_valid(player):
		var ship_screen: Vector2 = player.position - main_camera.position + (screen_size / 2.0)
		post_fx.set_ship_uv(ship_screen / screen_size)

	# Boss-explosion lensing ha priorità sul BH reale finché il timer è attivo.
	if boss_lens_timer > 0.0:
		boss_lens_timer -= get_process_delta_time()
		var t: float = clamp(boss_lens_timer / BOSS_LENS_DURATION, 0.0, 1.0)
		# Curva di intensity: parte forte (1.6) e decade quadraticamente. >1.0
		# spinge il bend oltre il range del BH classico per avere quella "punta"
		# cinematografica all'inizio.
		var intensity: float = t * t * 1.6
		var lens_uv: Vector2 = (boss_lens_pos - main_camera.position + (screen_size / 2.0)) / screen_size
		post_fx.set_bh(lens_uv, intensity)
		return

	var primary = bh_system.primary()
	if primary != null:
		var bh_uv: Vector2 = (primary.pos - main_camera.position + (screen_size / 2.0)) / screen_size
		var intensity: float = min(primary.life, 2.0) / 2.0
		post_fx.set_bh(bh_uv, intensity)
	else:
		post_fx.clear_bh()

func trigger_boss_lens(pos: Vector2) -> void:
	boss_lens_timer = BOSS_LENS_DURATION
	boss_lens_pos = pos
