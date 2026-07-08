class_name ProcFishTank
extends Control
## Reusable single-fish tank for development labs and future room composition.
## It owns one ProcFish instance, draws a compact top-down tank, and can expose
## lightweight debug overlays without depending on the main game state.

const DEFAULT_SIZE := Vector2(220, 156)
const PAD := 12.0

var catch_data: Dictionary = {}
var tank_label := ""
var debug_bones := false
var seed := 1

var _fish: ProcFish
var _rng := RandomNumberGenerator.new()
var _glow_tex: ImageTexture
var _t := 0.0
var _caption: Label


func _ready() -> void:
	custom_minimum_size = DEFAULT_SIZE
	if _caption == null:
		_caption = Label.new()
		_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_caption.add_theme_font_size_override("font_size", 10)
		_caption.add_theme_color_override("font_color", Color(0.86, 0.84, 0.76))
		_caption.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.04, 0.72))
		_caption.add_theme_constant_override("shadow_offset_x", 1)
		_caption.add_theme_constant_override("shadow_offset_y", 1)
		add_child(_caption)
	_caption.position = Vector2(8, 6)
	_caption.size = Vector2(maxf(20.0, size.x - 16.0), 34.0)
	_glow_tex = _make_glow()
	_rebuild()
	set_process(true)


func set_case(data: Dictionary, label := "", case_seed := 1, show_debug := false) -> void:
	catch_data = data.duplicate(true)
	tank_label = label
	seed = case_seed
	debug_bones = show_debug
	if is_inside_tree():
		_rebuild()
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if is_instance_valid(_caption):
			_caption.position = Vector2(8, 6)
			_caption.size = Vector2(maxf(20.0, size.x - 16.0), 34.0)
		if is_inside_tree() and not catch_data.is_empty():
			_rebuild()


func _process(delta: float) -> void:
	_t += delta
	if _fish != null:
		_fish.update(delta, _swim_bounds(), _rng)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	_draw_tank(r)
	if _fish != null:
		_fish.draw(self, _t, _glow_tex)
		if debug_bones:
			_draw_debug()


func _rebuild() -> void:
	if catch_data.is_empty():
		_fish = null
		return
	_rng.seed = seed
	var id := str(catch_data.get("id", "crucian"))
	var sp := ProcFishSpecies.from_catch(id, int(catch_data.get("var", 0)),
		float(catch_data.get("w", -1.0)), int(catch_data.get("q", 0)))
	var bounds := _swim_bounds()
	var origin := bounds.get_center() + Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(-12.0, 12.0))
	_fish = ProcFish.new()
	_fish.setup(sp, origin, bounds, _rng)
	_fish.catch_data = catch_data
	_update_caption(sp)


func _update_caption(sp: ProcFishSpecies) -> void:
	if _caption == null:
		return
	var id := str(catch_data.get("id", ""))
	var name := FishData.display_name(id) if FishData.FISH.has(id) else id
	var pattern_name: String = str(ProcFishSpecies.Pattern.keys()[sp.pattern])
	var mode_name: String = str(ProcFishSpecies.SwimMode.keys()[sp.swim_mode])
	var q := int(catch_data.get("q", 0))
	var vr := int(catch_data.get("var", 0))
	_caption.text = "%s\n%s %.2fkg q%d v%d · %s/%s" % [
		tank_label if tank_label != "" else name,
		name,
		float(catch_data.get("w", 0.0)),
		q,
		vr,
		pattern_name,
		mode_name,
	]


func _swim_bounds() -> Rect2:
	var top := 42.0
	return Rect2(PAD, top, maxf(20.0, size.x - PAD * 2.0), maxf(20.0, size.y - top - PAD))


func _draw_tank(r: Rect2) -> void:
	draw_rect(r, Color(0.12, 0.13, 0.12))
	var water := Rect2(Vector2(PAD, 42.0), Vector2(maxf(20.0, r.size.x - PAD * 2.0), maxf(20.0, r.size.y - 54.0)))
	draw_rect(water.grow(4.0), Color(0.34, 0.24, 0.14))
	draw_rect(water, Color(0.13, 0.38, 0.58))
	draw_rect(water, Color(0.58, 0.82, 0.92, 0.16))
	for i in 4:
		var y := water.position.y + water.size.y * (0.18 + 0.18 * i) + sin(_t * 0.8 + i) * 1.3
		draw_line(Vector2(water.position.x + 5.0, y), Vector2(water.end.x - 5.0, y),
			Color(0.72, 0.90, 0.96, 0.18), 1.0)
	draw_rect(water, Color(0.76, 0.91, 0.96, 0.42), false, 1.0)
	draw_rect(water.grow(4.0), Color(0.62, 0.48, 0.30), false, 2.0)
	var sand := Rect2(water.position.x + 4.0, water.end.y - 15.0, water.size.x - 8.0, 10.0)
	draw_rect(sand, Color(0.72, 0.67, 0.48, 0.32))
	for i in 5:
		var x := water.position.x + 18.0 + float(i) * 7.0
		var y0 := water.end.y - 9.0
		draw_line(Vector2(x, y0), Vector2(x + sin(_t + i) * 3.0, y0 - 20.0 - float(i % 2) * 5.0),
			Color(0.18, 0.44, 0.28, 0.58), 2.0)


func _draw_debug() -> void:
	if _fish == null or _fish.spine == null:
		return
	var joints := _fish.spine.joints
	for i in joints.size():
		draw_circle(joints[i], 2.0, Color(1.0, 0.92, 0.35, 0.85))
		if i > 0:
			draw_line(joints[i - 1], joints[i], Color(1.0, 0.92, 0.35, 0.48), 1.0)
	draw_circle(_fish._target, 3.0, Color(1.0, 0.25, 0.22, 0.9))
	draw_line(joints[0], _fish._target, Color(1.0, 0.25, 0.22, 0.35), 1.0)


func _make_glow() -> ImageTexture:
	var s := 48
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := s * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x - c, y - c).length() / (s * 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
