class_name RelationshipPortrait
## 河湾人物头像的单一运行时入口：加载、三档尺寸、主题色框与缺图回退。

const MODE_SIZES := {
	"circle": Vector2(40, 40),
	"card": Vector2(72, 72),
	"hero": Vector2(144, 144),
}

static var _circle_shader: Shader = null


static func texture_for(npc: Dictionary) -> Texture2D:
	var path := str(npc.get("portrait", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var resource := load(path)
	return resource as Texture2D if resource is Texture2D else null


static func make(npc: Dictionary, mode: String) -> Control:
	var safe_mode := mode if MODE_SIZES.has(mode) else "card"
	var size: Vector2 = MODE_SIZES[safe_mode]
	var frame := PanelContainer.new()
	frame.custom_minimum_size = size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", _frame_style(npc, safe_mode))

	var texture := texture_for(npc)
	if texture == null:
		var placeholder := Label.new()
		placeholder.name = "RelationshipPortraitPlaceholder"
		var npc_name := str(npc.get("name", "人"))
		placeholder.text = npc_name.substr(0, 1) if npc_name != "" else "人"
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.add_theme_font_size_override("font_size", 18 if safe_mode == "circle" else 28)
		placeholder.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86, 0.96))
		frame.add_child(placeholder)
		return frame
	var image := TextureRect.new()
	image.texture = texture
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if safe_mode == "circle":
		image.material = _circle_material()
	frame.add_child(image)
	return frame


static func _frame_style(npc: Dictionary, mode: String) -> StyleBoxFlat:
	var color: Color = npc.get("color", Color("A98F72"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.92 if mode == "circle" else 0.12)
	style.set_corner_radius_all(999 if mode == "circle" else 10)
	style.set_border_width_all(2 if mode == "circle" else 1)
	style.border_color = Color(color.r, color.g, color.b, 0.95 if mode == "circle" else 0.45)
	return style


static func _circle_material() -> ShaderMaterial:
	if _circle_shader == null:
		_circle_shader = Shader.new()
		_circle_shader.code = """
shader_type canvas_item;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float mask = 1.0 - step(0.5, distance(UV, vec2(0.5)));
	COLOR = vec4(tex.rgb, tex.a * mask);
}
"""
	var material := ShaderMaterial.new()
	material.shader = _circle_shader
	return material
