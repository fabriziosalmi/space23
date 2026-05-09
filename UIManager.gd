extends CanvasLayer
class_name UIManager

signal start_pressed
signal name_submitted(new_text: String)
signal retry_pressed
signal bomb_pressed
signal pause_toggle_requested

# HUD: split DIST + KILLS invece di SCORE unico (la distance dominava il totale).
var dist_label: Label
var kill_label: Label
var hp_bar: ProgressBar
var title_label: Label
var version_label: Label  # piccolo, basso-destra, visibile solo durante TITLE
var leaderboard_label: Label
var flow_label: Label
var bomb_label: Label

# Pause overlay
var pause_dim: ColorRect
var pause_label: Label

# Mobile BOMB button
var bomb_button: Button

# Control hints visibili sul TITLE (sotto leaderboard). Onboarding minimo:
# il giocatore vede le keybind senza dover indovinare WASD / Space / Shift / X.
# Hidden insieme a title_label/leaderboard quando il game inizia.
var controls_label: Label

var game_over_container: VBoxContainer
var final_score_label: Label
var name_input: LineEdit
var retry_button: Button

var highscores = []
const SAVE_PATH = "user://space23_highscores.json"
var current_final_score = 0
var start_button: Button
var boss_hp_bar: ProgressBar
var boss_hp_label: Label
var arcade_font

# HUD pulse-on-increment: brevissimo bump di luminosità (modulate brightness)
# quando KILLS / BOMBS cambiano. Sells "questa cifra è viva, è appena cambiata"
# senza rumore visivo. DIST cresce ogni frame → niente pulse (sarebbe constant).
# Modulate è moltiplicativo sul font_color: 1.6× pulse + decay 100ms triggera
# bloom HDR sui label colorati (yellow KILLS, orange BOMBS) per ~1 frame.
var _prev_kill_score: int = -1
var _prev_bombs: int = -1
const HUD_PULSE_DURATION: float = 0.10
var _kill_pulse_t: float = 0.0
var _bomb_pulse_t: float = 0.0

func _ready():
	arcade_font = preload("res://PressStart2P.ttf")
	layer = 101
	var screen_size = get_viewport().get_visible_rect().size

	dist_label = _make_hud_label(Vector2(20, 20), Color(0.4, 1.0, 0.6), Color(0.0, 0.2, 0.1))
	dist_label.text = "DIST  0m"
	add_child(dist_label)

	kill_label = _make_hud_label(Vector2(20, 42), Color(1.0, 1.0, 0.2), Color(0.1, 0.0, 0.2))
	kill_label.text = "SCORE  0"
	add_child(kill_label)

	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(20, 70)
	hp_bar.size = Vector2(200, 20)
	hp_bar.max_value = 100
	hp_bar.value = 100
	_apply_neon_progressbar_theme(hp_bar, Color(0.2, 1.0, 0.5), Color(0.6, 1.0, 0.8))
	add_child(hp_bar)

	title_label = Label.new()

	var game_version = "v0.1.0"
	var vfile = FileAccess.open("res://version.txt", FileAccess.READ)
	if vfile:
		game_version = vfile.get_as_text().strip_edges()

	# Testo accorciato + box piu' largo: "TAP OR PRESS ANY KEY TO START" col font
	# PressStart2P a size 52 superava i 1000px del box → veniva clippato a destra.
	title_label.text = "S P A C E 2 3\n\nPRESS ANY KEY  /  TAP"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_override("font", arcade_font)
	title_label.add_theme_font_size_override("font_size", 52)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.6))
	title_label.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.4))
	title_label.add_theme_constant_override("outline_size", 16)
	title_label.add_theme_constant_override("shadow_offset_x", 8)
	title_label.add_theme_constant_override("shadow_offset_y", 8)
	title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0))
	title_label.position = Vector2(20, screen_size.y / 2.0 - 220)
	title_label.size = Vector2(screen_size.x - 40, 420)
	add_child(title_label)

	# Versione + credit, piccolo angolo basso-destra. Stesso font arcade, alpha
	# basso per restare unobtrusive. Mostrato solo durante TITLE (hide insieme
	# al title_label nell'_input handler), il bottom-right durante gameplay è
	# occupato dal bomb_button.
	version_label = Label.new()
	version_label.text = game_version + "  ·  MADE BY FAB23"
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	version_label.add_theme_font_override("font", arcade_font)
	version_label.add_theme_font_size_override("font_size", 12)
	version_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.6, 0.55))
	version_label.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.4, 0.55))
	version_label.add_theme_constant_override("outline_size", 4)
	version_label.position = Vector2(0, screen_size.y - 28)
	version_label.size = Vector2(screen_size.x - 14, 20)
	add_child(version_label)
	
	leaderboard_label = Label.new()
	leaderboard_label.position = Vector2(screen_size.x / 2.0 - 200, screen_size.y / 2.0 + 80)
	leaderboard_label.size = Vector2(400, 200)
	leaderboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leaderboard_label.add_theme_font_override("font", arcade_font)
	leaderboard_label.add_theme_font_size_override("font_size", 16)
	leaderboard_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8))
	leaderboard_label.add_theme_color_override("font_outline_color", Color(0.0, 0.2, 0.4))
	leaderboard_label.add_theme_constant_override("outline_size", 6)
	add_child(leaderboard_label)

	# Control hints — sotto al leaderboard sul TITLE. Pre-fix il giocatore
	# nuovo doveva indovinare le keybind o leggere il README. Hide insieme
	# al title_label nell'_input handler.
	controls_label = Label.new()
	controls_label.size = Vector2(screen_size.x - 40, 40)
	controls_label.position = Vector2(20, screen_size.y - 70)
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.text = "WASD / STICK  MOVE   •   SPACE / A  FIRE   •   SHIFT / B  DASH   •   X / Y  BOMB   •   ESC / START  PAUSE"
	controls_label.add_theme_font_override("font", arcade_font)
	controls_label.add_theme_font_size_override("font_size", 11)
	controls_label.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0, 0.7))
	controls_label.add_theme_color_override("font_outline_color", Color(0.0, 0.2, 0.4, 0.7))
	controls_label.add_theme_constant_override("outline_size", 4)
	add_child(controls_label)
	
	dist_label.hide()
	kill_label.hide()
	hp_bar.hide()

	flow_label = Label.new()
	flow_label.position = Vector2(screen_size.x - 250, 20)
	flow_label.add_theme_font_override("font", arcade_font)
	flow_label.add_theme_font_size_override("font_size", 16)
	flow_label.add_theme_color_override("font_color", Color(0.2, 1.0, 1.0))
	flow_label.add_theme_color_override("font_outline_color", Color(0.0, 0.2, 0.4))
	flow_label.add_theme_constant_override("outline_size", 6)
	flow_label.hide()
	add_child(flow_label)
	
	bomb_label = Label.new()
	bomb_label.position = Vector2(20, 100)
	bomb_label.add_theme_font_override("font", arcade_font)
	bomb_label.add_theme_font_size_override("font_size", 16)
	bomb_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	bomb_label.add_theme_color_override("font_outline_color", Color(0.4, 0.0, 0.0))
	bomb_label.add_theme_constant_override("outline_size", 6)
	bomb_label.hide()
	add_child(bomb_label)

	# Boss HP UI (centrato in alto)
	boss_hp_label = Label.new()
	boss_hp_label.text = "WARNING — MOTHER SHIP"
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_hp_label.size = Vector2(600, 24)
	boss_hp_label.position = Vector2(screen_size.x / 2.0 - 300, 18)
	boss_hp_label.add_theme_font_override("font", arcade_font)
	boss_hp_label.add_theme_font_size_override("font_size", 14)
	boss_hp_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.3))
	boss_hp_label.add_theme_color_override("font_outline_color", Color(0.4, 0.0, 0.0))
	boss_hp_label.add_theme_constant_override("outline_size", 6)
	boss_hp_label.hide()
	add_child(boss_hp_label)

	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.size = Vector2(600, 14)
	boss_hp_bar.position = Vector2(screen_size.x / 2.0 - 300, 46)
	boss_hp_bar.max_value = 100
	boss_hp_bar.value = 0
	boss_hp_bar.show_percentage = false
	_apply_neon_progressbar_theme(boss_hp_bar, Color(1.0, 0.2, 0.3), Color(1.4, 0.5, 0.6))
	boss_hp_bar.hide()
	add_child(boss_hp_bar)

	# --- MOBILE BOMB BUTTON (visibile solo su touch / web) ---
	bomb_button = Button.new()
	bomb_button.text = "BOMB"
	bomb_button.size = Vector2(96, 96)
	bomb_button.position = Vector2(screen_size.x - 116, screen_size.y - 116)
	bomb_button.add_theme_font_override("font", arcade_font)
	bomb_button.add_theme_font_size_override("font_size", 18)
	bomb_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	bomb_button.modulate = Color(1.0, 1.0, 1.0, 0.85)
	bomb_button.pressed.connect(func(): bomb_pressed.emit())
	bomb_button.hide()  # mostrato all'inizio partita su mobile/web (vedi _show_play_ui)
	add_child(bomb_button)

	# Game Over UI.
	# Bias verticale: "GAME OVER" (48pt rosso) è il primo figlio e l'ancora
	# visiva pesante. Con un VBoxContainer matematicamente centrato, il blocco
	# è geometricamente al centro ma il *baricentro percepito* finisce sotto
	# (perché GAME OVER è la massa). Scostiamo il container 30 logical px in
	# alto per spostare il GAME OVER vicino al centro schermo dove l'occhio se
	# l'aspetta.
	game_over_container = VBoxContainer.new()
	game_over_container.alignment = BoxContainer.ALIGNMENT_CENTER
	game_over_container.size = Vector2(600, 400)
	game_over_container.position = Vector2(screen_size.x / 2.0 - 300, screen_size.y / 2.0 - 230)
	game_over_container.hide()
	
	var go_label = Label.new()
	go_label.text = "GAME OVER"
	go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_label.add_theme_font_override("font", arcade_font)
	go_label.add_theme_font_size_override("font_size", 48)
	go_label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1))
	go_label.add_theme_color_override("font_outline_color", Color(0.4, 0.0, 0.0))
	go_label.add_theme_constant_override("outline_size", 16)
	go_label.add_theme_constant_override("shadow_offset_x", 5)
	go_label.add_theme_constant_override("shadow_offset_y", 5)
	go_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0))
	game_over_container.add_child(go_label)
	
	final_score_label = Label.new()
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score_label.add_theme_font_override("font", arcade_font)
	final_score_label.add_theme_font_size_override("font_size", 24)
	final_score_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	final_score_label.add_theme_color_override("font_outline_color", Color(0.4, 0.2, 0.0))
	final_score_label.add_theme_constant_override("outline_size", 8)
	game_over_container.add_child(final_score_label)
	
	name_input = LineEdit.new()
	name_input.custom_minimum_size = Vector2(300, 50)
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.placeholder_text = "ENTER PILOT NAME"
	name_input.max_length = 8
	name_input.add_theme_font_override("font", arcade_font)
	name_input.add_theme_font_size_override("font_size", 16)
	name_input.text_submitted.connect(_on_name_submitted)
	game_over_container.add_child(name_input)
	
	retry_button = Button.new()
	retry_button.text = "R E T R Y"
	retry_button.add_theme_font_override("font", arcade_font)
	retry_button.add_theme_font_size_override("font_size", 24)
	retry_button.pressed.connect(func(): retry_pressed.emit())
	retry_button.hide()
	game_over_container.add_child(retry_button)
	
	add_child(game_over_container)

	# --- PAUSE OVERLAY (aggiunto per ULTIMO → top of canvas layer) ---
	pause_dim = ColorRect.new()
	pause_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	pause_dim.size = screen_size
	pause_dim.mouse_filter = Control.MOUSE_FILTER_STOP  # blocca click sui bottoni sotto
	# Tap sull'overlay = togliere pausa (utile su mobile, dove ESC non c'è).
	pause_dim.gui_input.connect(_on_pause_overlay_input)
	pause_dim.hide()
	add_child(pause_dim)

	pause_label = Label.new()
	pause_label.text = "P A U S E\n\nTAP  /  ESC  /  START"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.size = screen_size
	pause_label.add_theme_font_override("font", arcade_font)
	pause_label.add_theme_font_size_override("font_size", 48)
	pause_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	pause_label.add_theme_color_override("font_outline_color", Color(0.0, 0.2, 0.4))
	pause_label.add_theme_constant_override("outline_size", 12)
	pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # i click li gestisce pause_dim
	pause_label.hide()
	add_child(pause_label)

	load_highscores()

	# Resize handler: Window/viewport resize → ricomputiamo le posizioni
	# screen-dependent. Senza questo:
	#   - pause_dim.size restava al size iniziale → overlay non copriva il
	#     viewport ridimensionato (visibile gameplay sotto angoli)
	#   - bomb_button restava all'angolo del vecchio screen (off-canvas o
	#     fluttuante in mezzo)
	#   - title_label / version_label / leaderboard_label / boss_hp / game
	#     over container fissi alle vecchie coordinate
	# I label HUD top-left (dist/score/hp/bomb) sono già anchored a (20, ...)
	# → safe sotto resize. flow_label.position viene ricomputato ogni frame
	# in update_hud (già responsivo).
	get_tree().root.size_changed.connect(_on_viewport_resized)

func _on_viewport_resized() -> void:
	_layout_for_size(get_viewport().get_visible_rect().size)

# Idempotente: chiamabile sul mount o ad ogni resize, riposiziona/ridimensiona
# tutto quel che dipende da `screen_size`. Le label HUD a (20, ...) restano
# anchored top-left e non sono qui.
func _layout_for_size(s: Vector2) -> void:
	if title_label:
		title_label.position = Vector2(20, s.y / 2.0 - 220)
		title_label.size = Vector2(s.x - 40, 420)
	if version_label:
		version_label.position = Vector2(0, s.y - 28)
		version_label.size = Vector2(s.x - 14, 20)
	if leaderboard_label:
		leaderboard_label.position = Vector2(s.x / 2.0 - 200, s.y / 2.0 + 80)
	if controls_label:
		controls_label.size = Vector2(s.x - 40, 40)
		controls_label.position = Vector2(20, s.y - 70)
	if bomb_button:
		bomb_button.position = Vector2(s.x - 116, s.y - 116)
	if boss_hp_label:
		boss_hp_label.position = Vector2(s.x / 2.0 - 300, 18)
	if boss_hp_bar:
		boss_hp_bar.position = Vector2(s.x / 2.0 - 300, 46)
	if pause_dim:
		pause_dim.size = s
	if pause_label:
		pause_label.size = s
	if game_over_container:
		game_over_container.position = Vector2(s.x / 2.0 - 300, s.y / 2.0 - 230)

# Helper per creare label HUD con stile coerente (font arcade + outline scuro).
func _make_hud_label(pos: Vector2, font_color: Color, outline_color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", arcade_font)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", font_color)
	l.add_theme_color_override("font_outline_color", outline_color)
	l.add_theme_constant_override("outline_size", 6)
	return l

# StyleBox neon per ProgressBar (HP, boss HP). Sostituisce il theme default
# Godot (gray flat) con un look coerente al resto della UI: bg scuro semi-
# trasparente bordato dal colore della barra, fill HDR con leggera bordura
# luminosa. Senza questo lo HUD aveva un visibile "rettangolo Godot grigio"
# che stonava col resto neon.
func _apply_neon_progressbar_theme(pb: ProgressBar, bar_color: Color, edge_color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.04, 0.08, 0.75)
	bg.border_color = Color(bar_color.r * 0.4, bar_color.g * 0.4, bar_color.b * 0.4, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	pb.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = bar_color
	fill.border_color = edge_color
	fill.set_border_width_all(1)
	fill.set_corner_radius_all(2)
	pb.add_theme_stylebox_override("fill", fill)

# Mostra/nasconde il cluster di HUD in-game (chiamato da _input title-hide e hide_game_over).
func _show_play_ui() -> void:
	dist_label.show()
	kill_label.show()
	hp_bar.show()
	flow_label.show()
	bomb_label.show()
	if OS.has_feature("mobile") or OS.has_feature("web"):
		bomb_button.show()

func _hide_play_ui() -> void:
	dist_label.hide()
	kill_label.hide()
	hp_bar.hide()
	flow_label.hide()
	bomb_label.hide()
	# Gate sullo stesso check di _show_play_ui (mobile/web): asimmetrico prima,
	# il show-side era gated mentre l'hide-side hidava sempre — funzionalmente
	# equivalente (su desktop bomb_button è già hidden dall'init), ma il pair
	# letto in coppia dava l'idea che il bomb_button potesse comparire su
	# desktop in un certo path. Ora i due metodi sono speculari.
	if OS.has_feature("mobile") or OS.has_feature("web"):
		bomb_button.hide()

func set_pause_visible(visible_state: bool) -> void:
	pause_dim.visible = visible_state
	pause_label.visible = visible_state

func _on_pause_overlay_input(event: InputEvent) -> void:
	# Click / tap sull'overlay = richiesta unpause.
	if event is InputEventMouseButton and event.pressed:
		pause_toggle_requested.emit()
	elif event is InputEventScreenTouch and event.pressed:
		pause_toggle_requested.emit()

func _process(delta):
	if title_label.visible:
		var time = Time.get_ticks_msec() / 1000.0
		# Blink effettivo su "PRESS ENTER TO START" se volessimo,
		# ma facciamo pulsare dolcemente i colori
		var pulse = (sin(time * 5.0) + 1.0) * 0.5
		title_label.add_theme_color_override("font_color", Color(1.0, 0.2 + pulse * 0.6, 0.6 + pulse * 0.4))

	# HUD pulse decay. Curva: brightness picco 1.6× al frame del set (k=1.0
	# subito dopo `_kill_pulse_t = HUD_PULSE_DURATION`), poi decay LINEARE
	# verso 1.0 nei 100ms successivi (no ramp-up). Triggera il bloom HDR
	# del font color saturo per ~1 frame.
	if _kill_pulse_t > 0.0:
		_kill_pulse_t = max(_kill_pulse_t - delta, 0.0)
		var k: float = _kill_pulse_t / HUD_PULSE_DURATION  # 1.0 → 0.0
		var b: float = 1.0 + 0.6 * k
		kill_label.modulate = Color(b, b, b)
	elif kill_label.modulate != Color.WHITE:
		kill_label.modulate = Color.WHITE

	if _bomb_pulse_t > 0.0:
		_bomb_pulse_t = max(_bomb_pulse_t - delta, 0.0)
		var k: float = _bomb_pulse_t / HUD_PULSE_DURATION
		var b: float = 1.0 + 0.6 * k
		bomb_label.modulate = Color(b, b, b)
	elif bomb_label.modulate != Color.WHITE:
		bomb_label.modulate = Color.WHITE

func _input(event):
	if title_label.visible and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton):
		if not event.is_pressed() and not event.is_echo():
			title_label.hide()
			leaderboard_label.hide()
			if version_label: version_label.hide()
			if controls_label: controls_label.hide()
			_show_play_ui()
			start_pressed.emit()

func _on_name_submitted(new_text: String):
	new_text = _sanitize_name(new_text)
	if new_text == "":
		new_text = "ANON"
	name_input.hide()
	save_highscore(new_text, current_final_score)
	retry_button.show()
	retry_button.grab_focus()
	name_submitted.emit(new_text)

# Pulisce il nome del pilota: solo A-Z, 0-9, spazio. Cap a 8 chars. Senza
# questo filtro un nome con tab/newline o emoji rompeva il layout fix-width
# del leaderboard (es. "FOO\tBAR" shiftava la colonna score). LineEdit
# permette qualsiasi unicode in input.
func _sanitize_name(raw: String) -> String:
	var upper: String = raw.strip_edges().to_upper()
	var out: String = ""
	for c in upper:
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == " ":
			out += c
		if out.length() >= 8:
			break
	return out

func show_game_over(distance_m: int, kill_score: int):
	var total: int = distance_m + kill_score
	current_final_score = total
	_hide_play_ui()
	if boss_hp_bar: boss_hp_bar.hide()
	if boss_hp_label: boss_hp_label.hide()
	# Label aggiornata: il valore "kill_score" è in realtà score_points
	# (kills + grazes + top-half time bonus), non solo kills. "SCORE" è
	# accurato; il breakdown DIST + SCORE chiarisce la composizione del totale.
	final_score_label.text = "FINAL SCORE: %d\n\nDIST  %d m   +   SCORE  %d" % [total, distance_m, kill_score]
	game_over_container.show()
	# Leaderboard visible durante game over: prima era hidden per sempre dopo
	# il primo TITLE → il giocatore non vedeva mai il proprio nuovo entry
	# salvato. Ora mostra le top 5 sotto il game-over container.
	leaderboard_label.show()
	name_input.show()
	name_input.text = ""
	name_input.grab_focus()
	retry_button.hide()

# Chiamata da Main._on_retry_pressed PRIMA di hide_game_over: se c'è uno score
# pendente (game over con name_input ancora visibile = utente non ha submitato
# il nome), salviamo automaticamente con il testo digitato (o "ANON" se vuoto).
# Senza questo, l'instant retry shortcut (`ui_accept` durante game over)
# scartava lo score senza salvarlo, sorprendendo il giocatore.
func auto_save_pending_score() -> void:
	if not (name_input and name_input.visible):
		return
	if current_final_score <= 0:
		return
	var pending_name: String = name_input.text.strip_edges().to_upper()
	if pending_name == "":
		pending_name = "ANON"
	save_highscore(pending_name, current_final_score)

func update_boss_hp(hp: float, max_hp: float):
	if not boss_hp_bar:
		return
	if max_hp <= 0.0 or hp <= 0.0:
		boss_hp_bar.hide()
		if boss_hp_label: boss_hp_label.hide()
		return
	boss_hp_bar.max_value = max_hp
	# Clamp: railgun DPS continuo o smart bomb (-50 hp/proiettile) può
	# portare hp a valori negativi tra il damage e il successivo
	# handle_enemy_kill cleanup. Senza il clamp la ProgressBar mostrava
	# `value < 0` per 1 frame (Godot non clampa automaticamente fill > 0).
	boss_hp_bar.value = max(hp, 0.0)
	boss_hp_bar.show()
	if boss_hp_label: boss_hp_label.show()

func hide_game_over():
	game_over_container.hide()
	leaderboard_label.hide()
	_show_play_ui()

func update_hud(hp: float, distance_m: int, kill_score: int, flow: float = 0.0, bombs: int = 0):
	hp_bar.value = hp
	dist_label.text = "DIST  %dm" % distance_m
	# "SCORE" anziché "KILLS": il valore include kills (250/5000), graze (50)
	# e top-half time bonus (~14 pt/sec). "KILLS" era misleading — sembrava
	# un counter di nemici uccisi mentre era un punteggio composito.
	kill_label.text = "SCORE  %d" % kill_score
	bomb_label.text = "BOMBS: " + str(bombs)

	# Pulse on increment. Skip the very first frame (when prev = -1) so the
	# initial HUD show non triggera un pulse.
	if _prev_kill_score >= 0 and kill_score > _prev_kill_score:
		_kill_pulse_t = HUD_PULSE_DURATION
	_prev_kill_score = kill_score
	if _prev_bombs >= 0 and bombs != _prev_bombs:
		_bomb_pulse_t = HUD_PULSE_DURATION
	_prev_bombs = bombs

	if flow >= 1.0:
		flow_label.text = "MAX FLOW!"
		flow_label.add_theme_color_override("font_color", Color(1.0, 0.2, 1.0))
		flow_label.position = Vector2(get_viewport().get_visible_rect().size.x - 220, 20) + Vector2(randf_range(-3,3), randf_range(-3,3))
	elif flow > 0.05:
		flow_label.text = "FLOW: " + str(int(flow * 100)) + "%"
		flow_label.add_theme_color_override("font_color", Color(0.2, 1.0, 1.0))
		flow_label.position = Vector2(get_viewport().get_visible_rect().size.x - 220, 20)
	else:
		flow_label.text = ""

func load_highscores():
	highscores.clear()
	if FileAccess.file_exists(SAVE_PATH):
		# `FileAccess.open` può ritornare null anche se file_exists è true
		# (permessi, file lockato, web export con private mode che blocca
		# IndexedDB). Senza il guard, il successivo `file.get_as_text()`
		# crashava il caricamento del leaderboard.
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file != null:
			var json := JSON.new()
			var error: int = json.parse(file.get_as_text())
			if error == OK:
				var data = json.get_data()
				if typeof(data) == TYPE_ARRAY:
					# Validiamo ogni entry: il save format può corrompersi
					# (crash mid-write, edit manuale, vecchio formato dopo
					# uno schema change). Senza validation, una entry
					# malformata crashava _update_leaderboard_display
					# (es. `entry.name.substr(0,8)` se name è null o int).
					for e in data:
						if _is_valid_highscore_entry(e):
							highscores.append(e)

	_update_leaderboard_display()

func _is_valid_highscore_entry(e) -> bool:
	if typeof(e) != TYPE_DICTIONARY:
		return false
	if not e.has("name") or not e.has("score"):
		return false
	if typeof(e.get("name")) != TYPE_STRING:
		return false
	var s_type: int = typeof(e.get("score"))
	if s_type != TYPE_INT and s_type != TYPE_FLOAT:
		return false
	return true

func save_highscore(player_name: String, score: int):
	highscores.append({"name": player_name, "score": score})
	highscores.sort_custom(func(a, b): return a["score"] > b["score"])
	if highscores.size() > 5:
		highscores.resize(5)

	# Guard null: FileAccess.open in WRITE può fallire (disco pieno,
	# permessi negati, web private mode). Senza, il successivo
	# `file.store_string` crashava silenziosamente l'intero submit-name flow.
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(highscores))
	_update_leaderboard_display()

func _update_leaderboard_display():
	if highscores.is_empty():
		leaderboard_label.text = "NO TOP SCORES YET"
		return
		
	var text = "--- TOP 5 PILOTS ---\n\n"
	for i in range(highscores.size()):
		var entry = highscores[i]
		text += str(i+1) + ". " + entry.name.substr(0, 8).rpad(8) + " " + str(int(entry.score)).pad_zeros(6) + "\n"
	leaderboard_label.text = text
