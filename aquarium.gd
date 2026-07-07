class_name Aquarium
extends Control
## 活水族箱（Task 1）：把放进缸里的收藏鱼（g.display）渲染成沿平滑路径游动的小鱼缸。
## 兑现 Chillquarium 式收集深度——鎏金/七彩变体带光晕粒子，点鱼弹出它的纪录卡。
## 自管动画（_process 推进、_draw 合成），不依赖 tween，避免面板重建时残留。
## 字段沿用主节点的 display（不另起炉灶）；纪录取自 g.dex（首捕日期为 v11 新增）。
## 缸景：竖向水体渐变 + 斜射光柱/焦散 + 砂砾/石头/水草/沉木 + 悬浮微粒 + 气泡 + 景深柔影。

var g                                   # CornerFishing 主节点（弱类型避免循环依赖）
var swimmers: Array = []                # Array[ProcFish]：程序化脊椎链鱼（替代原 PNG 正弦游动）
var _rng := RandomNumberGenerator.new()
var bubbles: Array = []                 # 缸底升起的气泡 {x, y, r, spd, sway, phase}
var plants: Array = []                  # 缸底水草丛 {x, base_y, blades, back}
var rocks: Array = []                   # 缸底石头 {x, w, h, col}
var driftwood: Dictionary = {}          # 斜插沉木 {x, y, len, ang, w}
var motes: Array = []                   # 悬浮浮游微粒（marine snow），填充空旷水域 {x, y, r, vx, vy, a}
var _t := 0.0
var _glow_tex: Texture2D
var _water_tex: Texture2D               # 上亮下深的水体竖向渐变（替代纯色矩形）
var _card: Control = null               # 当前打开的纪录卡（点空白处关闭）

const VIEW_SIZE := Vector2(472, 260)
const MARGIN := 22.0                     # 鱼游动的四周留白（俯视：上下左右都要留）
const TOP_COL := Color(0.13, 0.36, 0.42) # 俯视水体：从上方看进水里的青绿（平涂，无上亮下深渐变）
const WATER_ALPHA := 0.95


func setup(host) -> void:
	g = host
	custom_minimum_size = VIEW_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_glow_tex = _make_glow()
	_water_tex = _make_water_tex()
	_build_swimmers()
	_build_decor()
	if swimmers.is_empty():
		var hint := Label.new()
		hint.text = "缸里还空着——从下面把心爱的鱼放进来，让它们游起来～"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", Color(0.62, 0.70, 0.74))
		hint.set_anchors_preset(Control.PRESET_FULL_RECT)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hint)


func _build_swimmers() -> void:
	swimmers.clear()
	if g == null:
		return
	_rng.randomize()
	var bounds := _swim_bounds()
	for i in g.display.size():
		var c: Dictionary = g.display[i]
		var id := str(c["id"])
		var vr := int(c.get("var", 0))
		var sp := ProcFishSpecies.from_catch(id, vr, float(c.get("w", -1.0)))
		var origin := Vector2(
			_rng.randf_range(bounds.position.x + 20.0, bounds.end.x - 20.0),
			_rng.randf_range(bounds.position.y + 20.0, bounds.end.y - 20.0))
		var pf := ProcFish.new()
		pf.setup(sp, origin, bounds, _rng)
		pf.idx = i
		pf.catch_data = c
		swimmers.append(pf)


## 鱼可游动的矩形范围（俯视：整片缸内，留四周边距即可）。
func _swim_bounds() -> Rect2:
	var sz := size if size.x > 1.0 else VIEW_SIZE
	return Rect2(MARGIN, 24.0, sz.x - MARGIN * 2.0, sz.y - 48.0)


## 缸景：水草丛 + 石头 + 沉木 + 浮游微粒 + 气泡。一次性随机生成，之后靠 _t 做确定性动画。
func _build_decor() -> void:
	bubbles.clear()
	plants.clear()
	rocks.clear()
	motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# 水草：多丛散布全缸（俯视：从缸内任一点冒出的草丛，不再贴缸底）
	var spots := [0.08, 0.18, 0.3, 0.42, 0.55, 0.68, 0.8, 0.9]
	for si in spots.size():
		var s: float = spots[si]
		var back := (si % 2 == 0)               # 隔丛靠后，前后两层更密
		var blades := []
		var n := rng.randi_range(4, 7)
		for b in n:
			blades.append({
				"h": rng.randf_range(20.0, 46.0) * (0.85 if back else 1.0),  # 俯视草丛：较短的放射叶
				"w": rng.randf_range(3.0, 6.0),
				"ph": rng.randf() * TAU,
				"bend": rng.randf_range(0.6, 1.4),
			})
		plants.append({
			"x": VIEW_SIZE.x * s + rng.randf_range(-10.0, 10.0),
			"base_y": rng.randf_range(24.0, VIEW_SIZE.y - 24.0),
			"blades": blades,
			"back": back,
		})
	# 石头：3~4 块，散布全缸
	for k in rng.randi_range(3, 4):
		var w := rng.randf_range(22.0, 50.0)
		rocks.append({
			"x": rng.randf_range(28.0, VIEW_SIZE.x - 28.0),
			"y": rng.randf_range(24.0, VIEW_SIZE.y - 24.0),
			"w": w,
			"h": w * rng.randf_range(0.6, 0.85),
			"col": Color(0.12, 0.14, 0.16).lerp(Color(0.19, 0.20, 0.21), rng.randf()),
		})
	# 沉木：一根横躺枯木，散布缸中（俯视：任意朝向）
	driftwood = {
		"x": VIEW_SIZE.x * rng.randf_range(0.3, 0.6),
		"y": VIEW_SIZE.y * rng.randf_range(0.3, 0.7),
		"len": rng.randf_range(80.0, 120.0),
		"ang": rng.randf_range(0.0, TAU),
		"w": rng.randf_range(8.0, 12.0),
	}
	# 悬浮浮游微粒：散布全缸，缓慢下沉横移，填充空旷水域
	for k in 34:
		motes.append({
			"x": rng.randf_range(0.0, VIEW_SIZE.x),
			"y": rng.randf_range(0.0, VIEW_SIZE.y),
			"r": rng.randf_range(0.6, 1.6),
			"vx": rng.randf_range(-3.0, 3.0),
			"vy": rng.randf_range(2.0, 7.0),
			"a": rng.randf_range(0.06, 0.18),
		})
	# 气泡：从缸底零散升起
	for k in 16:
		bubbles.append({
			"x": rng.randf_range(MARGIN, VIEW_SIZE.x - MARGIN),
			"y": rng.randf_range(0.0, VIEW_SIZE.y),
			"r": rng.randf_range(1.2, 3.0),
			"spd": rng.randf_range(10.0, 22.0),
			"sway": rng.randf_range(3.0, 7.0),
			"phase": rng.randf() * TAU,
		})


## 俯视水体：平涂水色纹理（1px 宽、拉伸填充），不再有上亮下深竖向渐变。
func _make_water_tex() -> ImageTexture:
	var h := 4
	var img := Image.create(1, h, false, Image.FORMAT_RGBA8)
	for y in h:
		img.set_pixel(0, y, Color(TOP_COL.r, TOP_COL.g, TOP_COL.b, WATER_ALPHA))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if swimmers.is_empty() and bubbles.is_empty():
		return
	_t += delta
	var bounds := _swim_bounds()
	for pf in swimmers:
		pf.update(delta, bounds, _rng)
	# 气泡上升 + 横向轻摆；越顶则回到缸底重生
	for bb in bubbles:
		bb["y"] -= bb["spd"] * delta
		if bb["y"] <= 6.0:
			bb["y"] = VIEW_SIZE.y - 6.0
			bb["x"] = clampf(bb["x"] + (bb["phase"] - PI) * 2.0, MARGIN, VIEW_SIZE.x - MARGIN)
	# 浮游微粒：缓慢下沉 + 横移，落到缸底回到顶部
	for m in motes:
		m["x"] = fposmod(m["x"] + m["vx"] * delta, VIEW_SIZE.x)
		m["y"] += m["vy"] * delta
		if m["y"] > VIEW_SIZE.y:
			m["y"] = 0.0
	queue_redraw()


# ============================ 绘制 ============================

func _draw() -> void:
	var sz := size if size.x > 1.0 else VIEW_SIZE
	# ① 水体：上亮下深竖向渐变（替代纯色矩形+横线，去掉"表格"廉价感）
	if _water_tex != null:
		draw_texture_rect(_water_tex, Rect2(Vector2.ZERO, sz), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, sz), TOP_COL)
	# ② 底砂/砾石（俯视：铺满整片，不再是底部一条带）
	_draw_substrate(sz)
	# ③ 水面焦散光斑（俯视下读作投在缸底的晃动光斑）
	for i in 4:
		var gx := sz.x * (0.2 + 0.22 * i) + sin(_t * 0.25 + i * 1.7) * 36.0
		var gy := sz.y * (0.18 + 0.09 * i) + cos(_t * 0.2 + i) * 10.0
		var gr := 70.0 + 18.0 * sin(_t * 0.3 + i)
		draw_texture_rect(_glow_tex, Rect2(Vector2(gx - gr, gy - gr), Vector2(gr, gr) * 2.0),
			false, Color(0.55, 0.82, 0.80, 0.05))
	# ④ 石头（俯视卵石）
	for r in rocks:
		_draw_rock(r, sz)
	# ⑤ 沉木（俯视横躺枯枝）
	_draw_driftwood(sz)
	# ⑥ 后景水草（鱼之前画 → 在鱼后面）
	for p in plants:
		if p["back"]:
			_draw_plant(p, true)
	# ⑦ 鱼（程序化脊椎链，各自带柔影）
	for pf in swimmers:
		_draw_swimmer(pf, sz)
	# ⑦b 悬浮浮游微粒（填鱼周空白）
	_draw_motes()
	# ⑧ 前景水草（鱼之后画 → 个别遮住鱼，造穿插）
	for p in plants:
		if not p["back"]:
			_draw_plant(p, false)
	# ⑨ 气泡（最前）
	for bb in bubbles:
		_draw_bubble(bb)
	# ⑩ 暗角：四周轻压，把视线收进缸里
	_draw_vignette(sz)


## 俯视底砂/砾石：铺满整片矩形，无“底部一条带”语义；斑驳 + 亮砂点去平涂感。
func _draw_substrate(sz: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.20, 0.21, 0.20))   # 砂/砾底色
	for i in 5:   # 几片略深斑驳
		var cx := sz.x * (0.15 + 0.18 * i) + sin(i * 2.3) * 14.0
		var cy := sz.y * (0.2 + 0.16 * i)
		draw_circle(Vector2(cx, cy), 50.0 + 20.0 * sin(i), Color(0.23, 0.24, 0.23, 0.5))
	for i in 30:   # 亮砂点 + 小卵石
		var gx := fmod(13.0 * i * 1.7 + 5.0, sz.x)
		var gy := fmod(7.0 * i * 2.3 + 11.0, sz.y)
		draw_circle(Vector2(gx, gy), 0.6 + 0.5 * sin(i * 1.3), Color(0.34, 0.34, 0.30, 0.5))


## 椭圆多边形（CanvasItem 无 draw_ellipse，自绘）。
func _draw_ellipse(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * float(i) / 18.0
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(pts, col)


## 俯视卵石：从上方看的椭圆 + 暗面 + 高光点。
func _draw_rock(r: Dictionary, sz: Vector2) -> void:
	var cx: float = r["x"]
	var cy: float = r["y"]
	var w: float = r["w"]
	var h: float = r["h"]
	_draw_ellipse(cx, cy, w * 0.5, h * 0.5, r["col"])
	_draw_ellipse(cx + w * 0.08, cy + h * 0.08, w * 0.42, h * 0.42, r["col"].darkened(0.18))
	draw_circle(Vector2(cx - w * 0.12, cy - h * 0.12), w * 0.12, Color(0.32, 0.34, 0.36, 0.4))


## 俯视横躺枯枝：沿底质一截弯曲粗线 + 小枝杈 + 附生苔，作为缸中焦点物。
func _draw_driftwood(sz: Vector2) -> void:
	if driftwood.is_empty():
		return
	var base := Vector2(driftwood["x"], driftwood["y"])
	var ang: float = driftwood["ang"]
	var len: float = driftwood["len"]
	var w: float = driftwood["w"]
	var segs := 10
	var line := PackedVector2Array()
	for i in segs + 1:
		var f := float(i) / float(segs)
		var bend := sin(f * PI) * 14.0           # 中段微弯
		var p := base + Vector2(cos(ang), sin(ang)) * (len * f)
		p += Vector2(-sin(ang), cos(ang)) * bend
		line.append(p)
	draw_polyline(line, Color(0.20, 0.14, 0.10), w, true)                    # 木身
	draw_polyline(line, Color(0.30, 0.22, 0.14), w * 0.5, true)             # 中层
	for k in 2:   # 枝杈
		var f := 0.4 + 0.3 * k
		var bp := base + Vector2(cos(ang), sin(ang)) * (len * f) \
			+ Vector2(-sin(ang), cos(ang)) * sin(f * PI) * 14.0
		var tw := Vector2(-sin(ang), cos(ang)) * (24.0 if k == 0 else -20.0)
		draw_line(bp, bp + tw, Color(0.22, 0.16, 0.11), w * 0.5, true)
	for i in 4:   # 附生苔点
		var f := 0.3 + 0.16 * i
		var mp := base + Vector2(cos(ang), sin(ang)) * (len * f) \
			+ Vector2(-sin(ang), cos(ang)) * sin(f * PI) * 14.0
		draw_circle(mp, 2.2, Color(0.12, 0.30, 0.20, 0.7))


## 俯视水草丛：以 base 为中心的放射状短叶（绕中心数片、轻微摆动），像从上方看一丛。
func _draw_plant(p: Dictionary, back: bool) -> void:
	var base := Vector2(p["x"], p["base_y"])
	var col := Color(0.07, 0.22, 0.18, 0.55) if back else Color(0.10, 0.32, 0.24, 0.78)
	for bl in p["blades"]:
		var n := 7
		var reach: float = bl["h"] * (0.8 if back else 1.0)
		var line := PackedVector2Array()
		for i in n + 1:
			var f := float(i) / float(n)
			var ang := float(bl["ph"]) + (f - 0.5) * 1.6   # 绕中心的放射角，叶尖外展
			var sway := sin(_t * 0.8 + bl["ph"] + f * bl["bend"]) * 3.0
			line.append(base + Vector2(cos(ang), sin(ang)) * (reach * f) + Vector2(sway, 0))
		draw_polyline(line, col, bl["w"] * (0.7 if back else 1.0), true)


## 悬浮浮游微粒（marine snow）：柔白小点，填充空旷水域。
func _draw_motes() -> void:
	for m in motes:
		draw_circle(Vector2(m["x"], m["y"]), m["r"], Color(0.78, 0.86, 0.84, m["a"]))


func _draw_bubble(bb: Dictionary) -> void:
	var x: float = bb["x"] + sin(_t * 1.6 + bb["phase"]) * bb["sway"]
	var pos := Vector2(x, bb["y"])
	var r: float = bb["r"]
	draw_circle(pos, r, Color(0.7, 0.86, 0.9, 0.12))
	draw_arc(pos, r, 0.0, TAU, 12, Color(0.85, 0.95, 0.98, 0.32), 0.9, true)
	draw_circle(pos - Vector2(r * 0.3, r * 0.3), r * 0.28, Color(1, 1, 1, 0.4))


## 四周暗角：各三条递减 alpha 的半透明条，柔化边缘、收拢视线（俯视：四边都压）。
func _draw_vignette(sz: Vector2) -> void:
	for i in 3:
		var a := 0.14 - i * 0.045
		var wdt := 6.0
		draw_rect(Rect2(i * wdt, 0, wdt, sz.y), Color(0.02, 0.05, 0.08, a))
		draw_rect(Rect2(sz.x - (i + 1) * wdt, 0, wdt, sz.y), Color(0.02, 0.05, 0.08, a))
		draw_rect(Rect2(0, i * wdt, sz.x, wdt), Color(0.02, 0.05, 0.08, a))
		draw_rect(Rect2(0, sz.y - (i + 1) * wdt, sz.x, wdt), Color(0.02, 0.05, 0.08, a))


func _draw_swimmer(pf, sz: Vector2) -> void:
	# 俯视顶光：鱼身中心一团极淡柔影（不依赖侧视的“缸底”）
	var mid := Vector2(pf.spine.joints[int(pf.spine.joints.size() * 0.4)])
	if _glow_tex != null:
		var sh := float(pf.species.body_len) * 0.5
		draw_texture_rect(_glow_tex, Rect2(mid - Vector2(sh, sh) * 0.5, Vector2(sh, sh)),
			false, Color(0.0, 0.0, 0.0, 0.10))
	# 鱼身（脊椎链程序化绘制 + 变体特效）
	pf.draw(self, _t, _glow_tex)


## 软光晕径向纹理（白心 → 透明边），变体光晕复用此图按颜色染色。
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


# ============================ 点鱼看纪录 ============================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dismiss_card()
		var hit = _swimmer_at(event.position)
		if hit != null:
			_show_card(hit, event.position)


func _swimmer_at(p: Vector2):
	var best = null
	var best_d := 1e9
	for pf in swimmers:
		var d := p.distance_to(pf.head())
		if pf.hit(p) and d < best_d:
			best_d = d
			best = pf
	return best


func _dismiss_card() -> void:
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null


func _show_card(sw, at: Vector2) -> void:
	var c: Dictionary = sw.catch_data
	var id := str(c["id"])
	var tier := FishData.tier_of(id)
	var vr := int(c.get("var", 0))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIPanels.panel_bg_style())
	card.z_index = 60
	var mg := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		mg.add_theme_constant_override("margin_" + side, 10 if side in ["left", "right"] else 8)
	card.add_child(mg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	mg.add_child(box)
	# 头部：图标 + 名字（含变体宝石/星级）+ 关闭
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(g._fish_icon(id, 44))
	var ni := VBoxContainer.new()
	ni.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ni.add_theme_constant_override("separation", 0)
	var nm := Label.new()
	nm.text = FishData.variant_label(vr) + FishData.quality_label(int(c.get("q", 0))) \
		+ FishData.size_tag(id, float(c["w"])) + FishData.display_name(id)
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color",
		FishData.variant_color(vr) if vr >= 1 else g._ui_tier_color(tier, false))
	ni.add_child(nm)
	var sub := Label.new()
	sub.text = "%s · 这条 %.2fkg" % [FishData.TIER_NAMES[tier], float(c["w"])]
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.72, 0.70, 0.64))
	ni.add_child(sub)
	head.add_child(ni)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(24, 22)
	close.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66))
	close.pressed.connect(_dismiss_card)
	head.add_child(close)
	box.add_child(head)
	# 纪录：图鉴里的该鱼种纪录（最大体重 / 累计 / 首捕日 / 变体）
	var rec: Dictionary = g.dex.get(id, {})
	var maxw := float(rec.get("w", float(c["w"])))
	var fd := str(rec.get("fd", ""))
	var lines := [
		"最大纪录 %.2fkg" % maxw,
		"累计钓获 ×%d" % int(rec.get("n", 1)),
		"首次捕获 %s" % (fd if fd != "" else "很久以前"),
		"变体 %s" % (FishData.variant_label(vr).replace("·", "") if vr >= 1 else "普通"),
	]
	for line in lines:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.80, 0.78, 0.72))
		box.add_child(l)
	# 捞回鱼篓
	var back := Button.new()
	back.text = "捞回鱼篓"
	back.custom_minimum_size = Vector2(0, 30)
	UIPanels.apply_button_skin(back, false)
	back.pressed.connect(func() -> void: Decor.remove_to_inventory(g, int(sw.idx)))
	box.add_child(back)
	card.custom_minimum_size = Vector2(186, 0)   # 定宽，高随内容（按真实高摆放，不再用写死的 168）
	card.top_level = true                         # 脱离鱼缸的 clip_contents：卡片可越过缸底/缸边完整显示，不被裁
	add_child(card)
	_card = card
	# 用内容真实尺寸 + 钳进整张面板可视范围（而非缸内 220 高）：偏下点鱼时卡片向面板下方延伸也能完整显示。
	var csz := card.get_combined_minimum_size()
	csz.x = maxf(csz.x, 186.0)
	var gpt := get_global_transform() * at        # 鱼缸局部点 → 画布全局（top_level 用画布坐标）
	var pos := gpt + Vector2(12.0, -csz.y * 0.5)
	var area: Rect2 = g._panel.get_global_rect() if (g != null and is_instance_valid(g._panel)) else get_global_rect()
	pos.x = clampf(pos.x, area.position.x + 4.0, maxf(area.position.x + 4.0, area.end.x - csz.x - 4.0))
	pos.y = clampf(pos.y, area.position.y + 4.0, maxf(area.position.y + 4.0, area.end.y - csz.y - 4.0))
	card.position = pos
