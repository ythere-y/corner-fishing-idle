extends SceneTree
## Development visual lab for procedural fish.
## Run:
##   godot --path . -s tools/proc_fish_aquarium_lab.gd
##   godot --path . -s tools/proc_fish_aquarium_lab.gd -- --screenshot
##   godot --path . -s tools/proc_fish_aquarium_lab.gd -- --debug-bones --stress 80 --seed 7

const OUT_DIR := "res://docs/img"
const OUT_FILE := "proc_fish_aquarium_lab.png"
const CELL := Vector2(222, 158)
const GAP := 14

var _screenshot := false
var _debug_bones := false
var _stress := 0
var _seed := 20260708
var _root_control: Control
var _content: Control
var _scroll: ScrollContainer


func _init() -> void:
	_parse_args()
	_run()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match str(args[i]):
			"--screenshot":
				_screenshot = true
			"--debug-bones":
				_debug_bones = true
			"--stress":
				if i + 1 < args.size():
					_stress = int(args[i + 1])
					i += 1
			"--seed":
				if i + 1 < args.size():
					_seed = int(args[i + 1])
					i += 1
		i += 1


func _run() -> void:
	await process_frame
	_build_scene()
	for i in 90:
		await process_frame
	if _screenshot:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png(OUT_DIR + "/" + OUT_FILE)
		print("SNAP %s size=%s cases=%d" % [OUT_FILE, str(img.get_size()), _content.get_child_count()])
		quit()


func _build_scene() -> void:
	var cases := _cases()
	if _stress > 0:
		cases = _stress_cases(_stress)
	var cols := 5 if cases.size() <= 30 else 6
	var rows := int(ceil(float(cases.size()) / float(cols)))
	var stage_size := Vector2(
		float(cols) * CELL.x + float(cols + 1) * GAP,
		float(rows) * CELL.y + float(rows + 1) * GAP + 52.0)
	if _screenshot:
		root.size = Vector2i(int(stage_size.x), int(stage_size.y))
		root.content_scale_size = Vector2i(int(stage_size.x), int(stage_size.y))

	_root_control = Control.new()
	_root_control.name = "ProcFishAquariumLab"
	_root_control.size = stage_size if _screenshot else Vector2(1040, 720)
	if not _screenshot:
		_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_root_control)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.085)
	bg.size = _root_control.size
	if not _screenshot:
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.add_child(bg)

	var title := Label.new()
	title.text = "Proc Fish Aquarium Lab · cases %d · seed %d%s" % [
		cases.size(), _seed, " · debug bones" if _debug_bones else ""]
	title.position = Vector2(GAP, 10)
	title.size = Vector2(1012, 28)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	_root_control.add_child(title)

	_content = Control.new()
	_content.custom_minimum_size = stage_size - Vector2(0, 44)
	_content.size = stage_size - Vector2(0, 44)
	if _screenshot:
		_content.position = Vector2(0, 44)
		_root_control.add_child(_content)
	else:
		_scroll = ScrollContainer.new()
		_scroll.position = Vector2(0, 44)
		_scroll.size = Vector2(1040, 676)
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_root_control.add_child(_scroll)
		_scroll.add_child(_content)

	for idx in cases.size():
		var c: Dictionary = cases[idx]
		var col := idx % cols
		var row := idx / cols
		var tank := ProcFishTank.new()
		tank.position = Vector2(GAP + float(col) * (CELL.x + GAP), GAP + float(row) * (CELL.y + GAP))
		tank.size = CELL
		tank.custom_minimum_size = CELL
		_content.add_child(tank)
		tank.set_case(c["catch"], str(c["label"]), _seed + idx * 97, _debug_bones)


func _cases() -> Array:
	return [
		_case("体型 standard", "carp", 3.0, 0, 0),
		_case("体型 slender/eel", "eel", 1.2, 0, 0),
		_case("体型 deep", "bream", 1.4, 0, 0),
		_case("体型 flat/glide", "manta_ray", 90.0, 0, 0),
		_case("体型 heavy", "kaluga", 160.0, 0, 0),

		_case("重量 small", "carp", 1.0, 0, 0),
		_case("重量 medium", "carp", 4.0, 0, 0),
		_case("重量 large", "carp", 8.0, 0, 0),
		_case("巨物 whale", "whale_shark", 600.0, 1, 1),
		_case("长条 oarfish", "oarfish", 120.0, 2, 2),

		_case("运动 cruise", "salmon", 8.0, 0, 0),
		_case("运动 dart", "minnow", 0.10, 0, 0),
		_case("运动 eel", "marbled_eel", 8.0, 0, 0),
		_case("运动 hover", "angelfish", 0.8, 0, 0),
		_case("运动 deep", "lanternfish", 0.02, 0, 0),

		_case("花纹 stripes", "trout", 2.0, 0, 0),
		_case("花纹 spots", "spotted_puffer", 1.0, 0, 0),
		_case("花纹 blotches", "catfish", 2.0, 0, 0),
		_case("花纹 line", "tuna", 80.0, 0, 0),
		_case("花纹 rings", "koi", 5.0, 1, 0),

		_case("发光 deep", "dragonfish", 0.2, 1, 0),
		_case("发光 cavern", "blind_cavefish", 0.04, 1, 0),
		_case("变体 normal", "mandarin", 1.4, 0, 0),
		_case("变体 斑斓", "mandarin", 1.4, 1, 1),
		_case("变体 鎏金", "mandarin", 1.4, 2, 2),

		_case("变体 七彩", "mandarin", 1.4, 3, 3),
		_case("星级 q0", "bass", 1.4, 0, 0),
		_case("星级 q1", "bass", 1.4, 1, 0),
		_case("星级 q2", "bass", 1.4, 2, 0),
		_case("星级 q3", "bass", 1.4, 3, 0),
	]


func _stress_cases(n: int) -> Array:
	var ids := FishData.FISH.keys()
	ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var out := []
	for i in n:
		var id := str(ids[i % ids.size()])
		var f: Dictionary = FishData.FISH[id]
		var w := lerpf(float(f["wmin"]), float(f["wmax"]), rng.randf())
		out.append(_case("stress %03d" % i, id, w, rng.randi_range(0, 3), rng.randi_range(0, 3)))
	return out


func _case(label: String, id: String, weight: float, q: int, variant: int) -> Dictionary:
	return {
		"label": label,
		"catch": {
			"id": id,
			"w": weight,
			"v": 0,
			"q": q,
			"var": variant,
			"lock": false,
		},
	}
