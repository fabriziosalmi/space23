extends CanvasLayer
class_name PostFXController

# Wrapper del pass post-processing. Sta su una propria CanvasLayer (sopra il
# mondo, sotto la UI). Ospita un BackBufferCopy + ColorRect con il material
# post.gdshader. Espone setter idiomatici invece di obbligare il caller a
# parlare il dialetto `set_shader_parameter("audio_bass", ...)`.

var rect: ColorRect
var _uniform_cache: Dictionary = {}

func _set_uniform(param: StringName, val) -> void:
	if not (rect and rect.material):
		return
	if _uniform_cache.has(param) and _uniform_cache[param] == val:
		return
	_uniform_cache[param] = val
	rect.material.set_shader_parameter(param, val)

func setup(screen_size: Vector2) -> void:
	layer = 100  # Sopra il mondo (z<100), sotto la UI (UIManager.layer=101)

	var bbc := BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bbc)

	rect = ColorRect.new()
	rect.size = screen_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/post.gdshader")
	rect.material = mat
	add_child(rect)
	_apply_aspect(screen_size)
	# Resize: BH lens / radial blur mask vogliono restare circolari su qualsiasi
	# aspect. Senza questo, su mobile portrait (~0.56) o schermi quadrati il
	# vecchio valore hardcoded 1.77 deformava le mask in ellissi orizzontali.
	get_tree().root.size_changed.connect(func():
		var s: Vector2 = get_viewport().get_visible_rect().size
		rect.size = s
		_apply_aspect(s)
	)

func _apply_aspect(s: Vector2) -> void:
	if s.y > 0.0:
		_set_uniform(&"aspect", s.x / s.y)

# ===== Setters idiomatici (dirty-checked per evitare uniform upload ridondanti) =====

func set_flow(v: float) -> void:
	_set_uniform(&"flow_state", v)

func set_audio_bass(v: float) -> void:
	_set_uniform(&"audio_bass", v)

func set_bh(uv: Vector2, intensity: float) -> void:
	_set_uniform(&"bh_pos", uv)
	_set_uniform(&"bh_intensity", intensity)

func clear_bh() -> void:
	_set_uniform(&"bh_intensity", 0.0)

func set_zoom_blur(v: float) -> void:
	_set_uniform(&"zoom_blur", v)

func set_grayscale(v: float) -> void:
	_set_uniform(&"grayscale", v)

func set_radial_blur(v: float) -> void:
	_set_uniform(&"radial_blur", v)

func set_ship_uv(uv: Vector2) -> void:
	_set_uniform(&"ship_uv", uv)

func set_damage_flash(v: float) -> void:
	_set_uniform(&"damage_flash", v)

func get_zoom_blur() -> float:
	if rect and rect.material:
		var v = rect.material.get_shader_parameter("zoom_blur")
		return 0.0 if v == null else float(v)
	return 0.0

func get_grayscale() -> float:
	if rect and rect.material:
		var v = rect.material.get_shader_parameter("grayscale")
		return 0.0 if v == null else float(v)
	return 0.0
