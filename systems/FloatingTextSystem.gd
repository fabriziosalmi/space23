extends Node2D
class_name FloatingTextSystem

# Popup flottanti leggeri in world-space (+250, GRAZE!, DROP!, PHASE 2!).
# Pool/cap fisso per evitare allocazioni o cali FPS in bullet hell.

const MAX_TEXTS: int = 32
const RISE_SPEED: float = 55.0

var texts: Array = []
var font: Font

func _ready() -> void:
	font = preload("res://PressStart2P.ttf")
	z_index = 5

func spawn(pos: Vector2, label: String, color: Color = Color(1.0, 1.0, 0.4), font_size: int = 12, life: float = 0.75) -> void:
	if texts.size() >= MAX_TEXTS:
		texts.remove_at(0)
	texts.append({
		"pos": pos + Vector2(randf_range(-10.0, 10.0), -12.0),
		"text": label,
		"color": color,
		"size": font_size,
		"life": life,
		"max_life": life,
	})

func tick(delta: float) -> void:
	if texts.is_empty():
		return
	for i in range(texts.size() - 1, -1, -1):
		var t: Dictionary = texts[i]
		t.life -= delta
		t.pos.y -= RISE_SPEED * delta
		if t.life <= 0.0:
			texts.remove_at(i)
	queue_redraw()

func clear() -> void:
	texts.clear()
	queue_redraw()

func _draw() -> void:
	if font == null or texts.is_empty():
		return
	for t in texts:
		var alpha: float = clamp(t.life / t.max_life, 0.0, 1.0)
		var col: Color = t.color
		col.a = alpha
		var outline := Color(0.0, 0.0, 0.0, alpha * 0.85)
		var sz: int = int(t.size)
		var w: float = font.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var draw_pos: Vector2 = t.pos - Vector2(w * 0.5, 0.0)
		draw_string_outline(font, draw_pos, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, outline)
		draw_string(font, draw_pos, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
