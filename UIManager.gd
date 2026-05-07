extends CanvasLayer
class_name UIManager

signal start_pressed
signal name_submitted(new_text: String)
signal retry_pressed

var hud_score: Label
var hp_bar: ProgressBar
var title_label: Label
var leaderboard_label: Label
var flow_label: Label
var bomb_label: Label

var game_over_container: VBoxContainer
var final_score_label: Label
var name_input: LineEdit
var retry_button: Button

var highscores = []
const SAVE_PATH = "user://space23_highscores.json"
var current_final_score = 0
var start_button: Button
var boss_hp_bar: ProgressBar
var arcade_font

func _ready():
	arcade_font = preload("res://PressStart2P.ttf")
	layer = 101
	var screen_size = get_viewport().get_visible_rect().size
	
	hud_score = Label.new()
	hud_score.position = Vector2(20, 20)
	hud_score.text = "SCORE: 0"
	hud_score.add_theme_font_override("font", arcade_font)
	hud_score.add_theme_font_size_override("font_size", 16)
	hud_score.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))
	hud_score.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.2))
	hud_score.add_theme_constant_override("outline_size", 6)
	add_child(hud_score)
	
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(20, 60)
	hp_bar.size = Vector2(200, 20)
	hp_bar.max_value = 100
	hp_bar.value = 100
	add_child(hp_bar)
	
	title_label = Label.new()
	
	var game_version = "v0.1.0"
	var vfile = FileAccess.open("res://version.txt", FileAccess.READ)
	if vfile:
		game_version = vfile.get_as_text().strip_edges()
		
	title_label.text = "S P A C E 2 3\n\nPRESS ENTER TO START\n\n" + game_version
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", arcade_font)
	title_label.add_theme_font_size_override("font_size", 52)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.6))
	title_label.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.4))
	title_label.add_theme_constant_override("outline_size", 16)
	title_label.add_theme_constant_override("shadow_offset_x", 8)
	title_label.add_theme_constant_override("shadow_offset_y", 8)
	title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0))
	title_label.position = Vector2(screen_size.x / 2.0 - 500, screen_size.y / 2.0 - 200)
	title_label.size = Vector2(1000, 400)
	add_child(title_label)
	
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
	
	hud_score.hide()
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
	bomb_label.position = Vector2(20, 90)
	bomb_label.add_theme_font_override("font", arcade_font)
	bomb_label.add_theme_font_size_override("font_size", 16)
	bomb_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	bomb_label.add_theme_color_override("font_outline_color", Color(0.4, 0.0, 0.0))
	bomb_label.add_theme_constant_override("outline_size", 6)
	bomb_label.hide()
	add_child(bomb_label)
	
	# Game Over UI
	game_over_container = VBoxContainer.new()
	game_over_container.alignment = BoxContainer.ALIGNMENT_CENTER
	game_over_container.size = Vector2(600, 400)
	game_over_container.position = Vector2(screen_size.x / 2.0 - 300, screen_size.y / 2.0 - 200)
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
	
	load_highscores()

func _process(delta):
	if title_label.visible:
		var time = Time.get_ticks_msec() / 1000.0
		# Blink effettivo su "PRESS ENTER TO START" se volessimo,
		# ma facciamo pulsare dolcemente i colori
		var pulse = (sin(time * 5.0) + 1.0) * 0.5
		title_label.add_theme_color_override("font_color", Color(1.0, 0.2 + pulse * 0.6, 0.6 + pulse * 0.4))

func _input(event):
	if title_label.visible and (event is InputEventKey or event is InputEventMouseButton):
		if event.is_pressed() and not event.is_echo():
			title_label.text = "S P A C E 2 3\n\nPRESS ANY KEY TO START\n\n" + title_label.text.split("\n\n")[-1] # Fallback just in case
			title_label.hide()
			leaderboard_label.hide()
			hud_score.show()
			hp_bar.show()
			flow_label.show()
			bomb_label.show()
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

func show_game_over(final_score: int):
	current_final_score = int(final_score)
	hud_score.hide()
	hp_bar.hide()
	flow_label.hide()
	bomb_label.hide()
	final_score_label.text = "FINAL SCORE: " + str(current_final_score)
	game_over_container.show()
	name_input.show()
	name_input.text = ""
	name_input.grab_focus()
	retry_button.hide()

func hide_game_over():
	game_over_container.hide()
	hud_score.show()
	hp_bar.show()
	flow_label.show()
	bomb_label.show()

func update_hud(hp: float, score: int, flow: float = 0.0, bombs: int = 0):
	hp_bar.value = hp
	hud_score.text = "SCORE: " + str(int(score))
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
