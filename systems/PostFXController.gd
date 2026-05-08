extends CanvasLayer
class_name PostFXController

# Wrapper del pass post-processing. Sta su una propria CanvasLayer (sopra il
# mondo, sotto la UI). Ospita un BackBufferCopy + ColorRect con il material
# post.gdshader. Espone setter idiomatici invece di obbligare il caller a
# parlare il dialetto `set_shader_parameter("audio_bass", ...)`.

var rect: ColorRect

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

# ===== Setters idiomatici =====

func set_flow(v: float) -> void:
	if rect and rect.material:
		rect.material.set_shader_parameter("flow_state", v)

func set_audio_bass(v: float) -> void:
	if rect and rect.material:
		rect.material.set_shader_parameter("audio_bass", v)

func set_bh(uv: Vector2, intensity: float) -> void:
	if rect and rect.material:
		rect.material.set_shader_parameter("bh_pos", uv)
		rect.material.set_shader_parameter("bh_intensity", intensity)

func clear_bh() -> void:
	if rect and rect.material:
		rect.material.set_shader_parameter("bh_intensity", 0.0)

func set_zoom_blur(v: float) -> void:
	if rect and rect.material:
		rect.material.set_shader_parameter("zoom_blur", v)

func set_grayscale(v: float) -> void:
	if rect and rect.material:
		rect.material.set_shader_parameter("grayscale", v)

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
