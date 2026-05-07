extends CanvasLayer
class_name UIManager

signal start_pressed
signal name_submitted(new_text: String)
signal retry_pressed

var hud_score: Label
var hp_bar: ProgressBar
var title_label: Label
var leaderboard_label: Label

var game_over_container: VBoxContainer
var final_score_label: Label
var name_input: LineEdit
var retry_button: Button

var highscores = []
const SAVE_PATH = "user://space23_highscores.json"
var current_final_score = 0

func _ready():
	layer = 99
	var screen_size = get_viewport().get_visible_rect().size
	
	hud_score = Label.new()
	hud_score.position = Vector2(20, 20)
	hud_score.text = "Score: 0"
	hud_score.add_theme_font_size_override("font_size", 24)
	add_child(hud_score)
	
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(20, 60)
	hp_bar.size = Vector2(200, 20)
	hp_bar.max_value = 100
	hp_bar.value = 100
	add_child(hp_bar)
	
	title_label = Label.new()
	title_label.text = "SPACE23\n\nPRESS ENTER TO START"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	title_label.add_theme_color_override("font_outline_color", Color(0.2, 0.5, 1.0))
	title_label.add_theme_constant_override("outline_size", 8)
	title_label.position = Vector2(screen_size.x / 2.0 - 250, screen_size.y / 2.0 - 150)
	add_child(title_label)
	
	leaderboard_label = Label.new()
	leaderboard_label.position = Vector2(screen_size.x / 2.0 - 200, screen_size.y / 2.0 + 50)
	leaderboard_label.size = Vector2(400, 200)
	leaderboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leaderboard_label.add_theme_font_size_override("font_size", 24)
	add_child(leaderboard_label)
	
	hud_score.hide()
	hp_bar.hide()
	
	# Game Over UI
	game_over_container = VBoxContainer.new()
	game_over_container.alignment = BoxContainer.ALIGNMENT_CENTER
	game_over_container.size = Vector2(600, 400)
	game_over_container.position = Vector2(screen_size.x / 2.0 - 300, screen_size.y / 2.0 - 200)
	game_over_container.hide()
	
	var go_label = Label.new()
	go_label.text = "G A M E   O V E R"
	go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_label.add_theme_font_size_override("font_size", 64)
	go_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	go_label.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.0))
	go_label.add_theme_constant_override("outline_size", 12)
	game_over_container.add_child(go_label)
	
	final_score_label = Label.new()
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score_label.add_theme_font_size_override("font_size", 36)
	final_score_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	final_score_label.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0))
	final_score_label.add_theme_constant_override("outline_size", 8)
	game_over_container.add_child(final_score_label)
	
	name_input = LineEdit.new()
	name_input.custom_minimum_size = Vector2(300, 50)
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.placeholder_text = "ENTER PILOT NAME"
	name_input.text_submitted.connect(_on_name_submitted)
	game_over_container.add_child(name_input)
	
	retry_button = Button.new()
	retry_button.text = "R E T R Y"
	retry_button.add_theme_font_size_override("font_size", 42)
	retry_button.pressed.connect(func(): retry_pressed.emit())
	retry_button.hide()
	game_over_container.add_child(retry_button)
	
	add_child(game_over_container)
	
	load_highscores()

func _input(event):
	if title_label.visible and event.is_action_pressed("ui_accept"):
		title_label.hide()
		leaderboard_label.hide()
		hud_score.show()
		hp_bar.show()
		start_pressed.emit()

func _on_name_submitted(new_text: String):
	if new_text.strip_edges() == "":
		new_text = "ANON"
	name_input.hide()
	save_highscore(new_text, current_final_score)
	retry_button.show()
	retry_button.grab_focus()
	name_submitted.emit(new_text)

func show_game_over(final_score: int):
	current_final_score = final_score
	hud_score.hide()
	hp_bar.hide()
	final_score_label.text = "FINAL SCORE: " + str(final_score)
	game_over_container.show()
	name_input.show()
	name_input.text = ""
	name_input.grab_focus()
	retry_button.hide()

func update_hud(hp: float, score: int):
	hp_bar.value = hp
	hud_score.text = "Score: " + str(score)

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
		text += str(i+1) + ". " + entry.name + " : " + str(entry.score) + "\n"
	leaderboard_label.text = text
