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

func _ready():
	arcade_font = preload("res://PressStart2P.ttf")
	layer = 101
	var screen_size = get_viewport().get_visible_rect().size
	
	dist_label = _make_hud_label(Vector2(20, 20), Color(0.4, 1.0, 0.6), Color(0.0, 0.2, 0.1))
	dist_label.text = "DIST  0m"
	add_child(dist_label)

	kill_label = _make_hud_label(Vector2(20, 42), Color(1.0, 1.0, 0.2), Color(0.1, 0.0, 0.2))
	kill_label.text = "KILLS  0"
	add_child(kill_label)

	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(20, 70)
	hp_bar.size = Vector2(200, 20)
	hp_bar.max_value = 100
	hp_bar.value = 100
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
	pause_label.text = "P A U S E\n\nTAP / ESC TO RESUME"
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

func _process(_delta):
	if title_label.visible:
		var time = Time.get_ticks_msec() / 1000.0
		# Blink effettivo su "PRESS ENTER TO START" se volessimo,
		# ma facciamo pulsare dolcemente i colori
		var pulse = (sin(time * 5.0) + 1.0) * 0.5
		title_label.add_theme_color_override("font_color", Color(1.0, 0.2 + pulse * 0.6, 0.6 + pulse * 0.4))

func _input(event):
	if title_label.visible and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch):
		if not event.is_pressed() and not event.is_echo():
			title_label.hide()
			leaderboard_label.hide()
			if version_label: version_label.hide()
			_show_play_ui()
			start_pressed.emit()

func _on_name_submitted(new_text: String):
	new_text = new_text.strip_edges().to_upper()
	if new_text == "":
		new_text = "ANON"
	name_input.hide()
	save_highscore(new_text, current_final_score)
	retry_button.show()
	retry_button.grab_focus()
	name_submitted.emit(new_text)

func show_game_over(distance_m: int, kill_score: int):
	var total: int = distance_m + kill_score
	current_final_score = total
	_hide_play_ui()
	if boss_hp_bar: boss_hp_bar.hide()
	if boss_hp_label: boss_hp_label.hide()
	final_score_label.text = "FINAL SCORE: %d\n\nDIST  %d m   +   KILLS  %d" % [total, distance_m, kill_score]
	game_over_container.show()
	name_input.show()
	name_input.text = ""
	name_input.grab_focus()
	retry_button.hide()

func update_boss_hp(hp: float, max_hp: float):
	if not boss_hp_bar:
		return
	if max_hp <= 0.0 or hp <= 0.0:
		boss_hp_bar.hide()
		if boss_hp_label: boss_hp_label.hide()
		return
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = hp
	boss_hp_bar.show()
	if boss_hp_label: boss_hp_label.show()

func hide_game_over():
	game_over_container.hide()
	_show_play_ui()

func update_hud(hp: float, distance_m: int, kill_score: int, flow: float = 0.0, bombs: int = 0):
	hp_bar.value = hp
	dist_label.text = "DIST  %dm" % distance_m
	kill_label.text = "KILLS  %d" % kill_score
	bomb_label.text = "BOMBS: " + str(bombs)

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
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			var data = json.get_data()
			if typeof(data) == TYPE_ARRAY:
				highscores = data
				
	_update_leaderboard_display()

func save_highscore(player_name: String, score: int):
	highscores.append({"name": player_name, "score": score})
	highscores.sort_custom(func(a, b): return a["score"] > b["score"])
	if highscores.size() > 5:
		highscores.resize(5)
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
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
