class_name WorldMap
extends Control
## 旅行地图（v1：完全离线）——背包客手记里的那一页世界地图。
##
## 三样东西叠在一张水彩纸上：
##   ① 简笔海岸线（缺水彩底图时的程序化回退；有 assets/art/ui/world_map.png 就直接贴图）
##   ② **晨昏线**：按 NOAA 太阳位置公式实时算，随真实 UTC 每分钟西移约 2px。
##      这是整页唯一"会动、活着"的东西，且零联网、零后端——断网它照样走。
##   ③ 旅程：走过的站点点亮成灯、按到访顺序用手绘针脚线连起来；当前站多一圈呼吸光晕。
##
## ⚠️ 地图上的点是**钓点**，不是玩家的现实位置。将来加"别人的渔火"时，上行也只有 spot_key
##    这一个枚举——因此不处理任何位置数据（见 BACKLOG 决策日志 2026-07-08）。
##
## 语义提醒（有意为之，不是 bug）：weather.gd 的昼夜取**本机本地时钟**，晨昏线用 UTC 天文真实。
## 所以你深夜打开地图，可能看到自己正在钓的新西兰处于白昼半球。面板底下那句话就是在说这件事。
##
## 渲染范式照 aquarium.gd（自管动画 + _draw 一次性合成 + _gui_input 命中测试），
## 但**不逐帧重绘**：挂件默认 120fps，地图按 REDRAW_HZ 节流，晨昏线每 SUN_REFRESH 秒才重算。

var g                                    # CornerFishing 主节点（弱类型，避免循环依赖）
var _t := 0.0                            # 动画时钟
var _redraw_acc := 0.0                   # 重绘节流累加器
var _sun_acc := 999.0                    # 太阳参数刷新累加器（首帧立即算）
var _sun := {"decl": 0.0, "lam": 0.0}    # 当前太阳赤纬(弧度) 与 直射点经度(度)
var _term: PackedVector2Array = []       # 晨昏线折线（屏幕坐标）
var _night: PackedVector2Array = []      # 夜半球多边形（屏幕坐标）
var _nodes := {}                         # spot_id -> 屏幕坐标（含防重叠微调）
var _hover := ""                         # 当前悬停的站点 id
var _glow: ImageTexture
var _map_tex: Texture2D = null           # 水彩底图（缺图则程序化画海岸线，仓库惯例）

# —— 视窗：只画旅程覆盖的半个地球（欧亚—大洋洲），美洲不在这条路线上 ——
# 等距圆柱投影（plate carrée）：经纬度 → 像素是纯线性映射。
const LON0 := -35.0
const LON1 := 180.0
const LAT0 := 72.0      # 上边界（北）
const LAT1 := -50.0     # 下边界（南）
const VIEW := Vector2(472, 268)

const REDRAW_HZ := 20.0        # 重绘频率上限（挂件默认跑 120fps，地图没必要跟）
const SUN_REFRESH := 20.0      # 晨昏线重算间隔（地球每 4 分钟才转 1 经度 ≈ 2px）
const NODE_MIN_SEP := 10.0     # 站点最小像素间距（4 个中国站会挤成一坨，做微量分离）
const NODE_MAX_PUSH := 12.0    # 分离位移上限：超过就不再推，宁可挤也不撒谎

# —— 纸上配色（暖纸 + 去饱和海）——
const SEA      := Color(0.760, 0.792, 0.784)
const LAND     := Color(0.878, 0.847, 0.741)
const COAST    := Color(0.404, 0.396, 0.345, 0.75)
const GRID     := Color(0.416, 0.427, 0.400, 0.16)
const NIGHT    := Color(0.180, 0.216, 0.360, 0.34)   # 夜半球暗罩（软边另画）
const TERM     := Color(0.400, 0.470, 0.720, 0.55)   # 晨昏线本身
const LAMP     := Color(0.949, 0.757, 0.306)         # 渔火琥珀
const LAMP_HI  := Color(1.000, 0.914, 0.690)
const STITCH   := Color(0.404, 0.322, 0.243, 0.70)   # 旅程针脚线
const PENCIL   := Color(0.478, 0.467, 0.416, 0.55)   # 未解锁站点的铅笔淡描


func setup(host) -> void:
	g = host
	custom_minimum_size = VIEW
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_glow = _make_glow()
	var p := "res://assets/art/ui/world_map.png"
	if ResourceLoader.exists(p):
		_map_tex = load(p) as Texture2D   # 水彩底图到位后自动接管，程序化海岸线降级为回退
	_nodes = layout_nodes()


# ============================ 投影与太阳（纯函数，可无头测试）============================

## 等距圆柱投影：经纬度 → 视窗像素。x 随经度线性、y 随纬度线性（南向下）。
static func project(lon: float, lat: float) -> Vector2:
	return Vector2((lon - LON0) / (LON1 - LON0) * VIEW.x,
		(LAT0 - lat) / (LAT0 - LAT1) * VIEW.y)


const MONTH_CUM := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]   # 各月起始累计日


static func _day_of_year(y: int, m: int, d: int) -> int:
	var doy: int = int(MONTH_CUM[clampi(m, 1, 12) - 1]) + d
	if m > 2 and ((y % 4 == 0 and y % 100 != 0) or y % 400 == 0):
		doy += 1
	return doy


## NOAA General Solar Position：返回 {decl: 太阳赤纬(弧度), lam: 直射点经度(度, [-180,180])}。
## 直射点每小时西移 15°——这就是地图上晨昏线移动的全部来源。
static func sun_params(unix: float) -> Dictionary:
	var d := Time.get_datetime_dict_from_unix_time(int(unix))   # 总是 UTC
	var doy := _day_of_year(int(d["year"]), int(d["month"]), int(d["day"]))
	var hf := float(d["hour"]) + float(d["minute"]) / 60.0 + float(d["second"]) / 3600.0
	var y := TAU / 365.0 * (float(doy) - 1.0 + (hf - 12.0) / 24.0)
	var eqtime := 229.18 * (0.000075 + 0.001868 * cos(y) - 0.032077 * sin(y) \
		- 0.014615 * cos(2.0 * y) - 0.040849 * sin(2.0 * y))
	var decl := 0.006918 - 0.399912 * cos(y) + 0.070257 * sin(y) - 0.006758 * cos(2.0 * y) \
		+ 0.000907 * sin(2.0 * y) - 0.002697 * cos(3.0 * y) + 0.00148 * sin(3.0 * y)
	var lam := -15.0 * (hf + eqtime / 60.0 - 12.0)
	lam = fposmod(lam + 180.0, 360.0) - 180.0
	return {"decl": decl, "lam": lam}


## 该点此刻是否在夜半球（太阳天顶角 > 90°）。
static func is_night(lon: float, lat: float, decl: float, lam: float) -> bool:
	var p := deg_to_rad(lat)
	return sin(p) * sin(decl) + cos(p) * cos(decl) * cos(deg_to_rad(lon - lam)) < 0.0


## 晨昏线纬度：tanφ = -cos(λ-λs)/tanδ。分点日 δ→0 时退化成经线（物理正确），clamp 防 NaN。
static func terminator_lat(lon: float, decl: float, lam: float) -> float:
	var td := tan(decl)
	if absf(td) < 1e-4:
		td = 1e-4 * signf(td) if td != 0.0 else 1e-4
	return clampf(rad_to_deg(atan(-cos(deg_to_rad(lon - lam)) / td)), -89.0, 89.0)


## 10 个站点的屏幕坐标：先按真实经纬度投影，再做**微量分离**——
## 4 个中国站在 2px 内挤成一坨，点不中也数不清。分离位移封顶 NODE_MAX_PUSH，
## 确定性迭代（无随机）：宁可挤，也不把站点搬到别的国家去。
static func layout_nodes() -> Dictionary:
	var order: Array = SpotData.SPOT_ORDER
	var truth := {}
	var pos := {}
	for sid in order:
		var geo: Vector2 = SpotData.geo_of(sid)
		if geo == Vector2.ZERO:
			continue
		truth[sid] = project(geo.x, geo.y)
		pos[sid] = truth[sid]
	for _i in 24:
		for a in pos:
			for b in pos:
				if a == b:
					continue
				var delta: Vector2 = pos[a] - pos[b]
				var dist := delta.length()
				if dist >= NODE_MIN_SEP:
					continue
				var dir := delta / dist if dist > 0.001 else Vector2(1, 0)
				var push := dir * (NODE_MIN_SEP - dist) * 0.5
				pos[a] = pos[a] + push
				pos[b] = pos[b] - push
		for sid in pos:   # 每轮都把位移拉回真实位置附近，防止漂到别的国家
			var off: Vector2 = pos[sid] - truth[sid]
			if off.length() > NODE_MAX_PUSH:
				pos[sid] = truth[sid] + off.normalized() * NODE_MAX_PUSH
	return pos


# ============================ 生命周期 ============================

func _process(delta: float) -> void:
	_t += delta
	_sun_acc += delta
	if _sun_acc >= SUN_REFRESH:
		_sun_acc = 0.0
		_recalc_sun()
	_redraw_acc += delta
	if _redraw_acc >= 1.0 / REDRAW_HZ:
		_redraw_acc = 0.0
		queue_redraw()


func _recalc_sun() -> void:
	_sun = sun_params(Time.get_unix_time_from_system())
	var decl: float = _sun["decl"]
	var lam: float = _sun["lam"]
	_term = PackedVector2Array()
	var lon := LON0
	while lon <= LON1 + 0.01:
		_term.append(project(lon, terminator_lat(lon, decl, lam)))
		lon += 1.5
	# 夜半球在晨昏线的哪一侧由赤纬符号决定：北半球夏天(δ>0) → 南极圈在夜里 → 夜在线下方。
	# 闭合边必须推到视窗**之外**：夏至前后晨昏线会深入到南纬 68°（y≈307 > VIEW.y），
	# 若用视窗底边闭合，闭合边会与晨昏线相交 → 自相交多边形三角化失败 → 整块夜色不画。
	_night = _term.duplicate()
	var edge_y := (VIEW.y + 400.0) if decl > 0.0 else -400.0
	_night.append(Vector2(VIEW.x, edge_y))
	_night.append(Vector2(0.0, edge_y))


# ============================ 绘制 ============================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), SEA)
	if _map_tex != null:
		_draw_map_tex()
	else:
		_draw_graticule()
		_draw_landmasses()
	_draw_night()
	_draw_journey()
	_draw_stations()
	_draw_caption()


## 底图贴图：约定 assets/art/ui/world_map.png 是**标准全球等距圆柱图**（经度 -180~180、
## 纬度 90~-90，宽高比 2:1），由本函数按视窗经纬度范围裁出对应区域——美术只需交一张
## 通用世界地图，不必知道我们裁的是哪半个地球。
## 兼容：若交来的图宽高比明显不是 2:1，视为"已按视窗裁好"，整图铺满。
func _draw_map_tex() -> void:
	var ts := _map_tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	if absf(ts.x / ts.y - 2.0) > 0.15:
		draw_texture_rect(_map_tex, Rect2(Vector2.ZERO, VIEW), false)
		return
	var x0 := (LON0 + 180.0) / 360.0 * ts.x
	var x1 := (LON1 + 180.0) / 360.0 * ts.x
	var y0 := (90.0 - LAT0) / 180.0 * ts.y
	var y1 := (90.0 - LAT1) / 180.0 * ts.y
	draw_texture_rect_region(_map_tex, Rect2(Vector2.ZERO, VIEW),
		Rect2(x0, y0, x1 - x0, y1 - y0))


func _draw_graticule() -> void:
	var lon := -30.0
	while lon <= LON1:
		draw_line(project(lon, LAT0), project(lon, LAT1), GRID, 1.0)
		lon += 30.0
	var lat := 60.0
	while lat >= LAT1:
		draw_line(project(LON0, lat), project(LON1, lat), GRID, 1.0)
		lat -= 20.0


## 程序化简笔海岸线（水彩底图到位前的回退）：粗到只求"认得出是哪块大陆"。
func _draw_landmasses() -> void:
	for poly in LAND_POLYS:
		var pts := PackedVector2Array()
		for v in poly:
			pts.append(project(v.x, v.y))
		if pts.size() >= 3:
			draw_colored_polygon(pts, LAND)
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, COAST, 1.0, true)


func _draw_night() -> void:
	if _night.size() < 3:
		return
	draw_colored_polygon(_night, NIGHT)
	if _term.size() >= 2:
		draw_polyline(_term, TERM, 1.4, true)


## 旅程针脚线：按 SPOT_ORDER 串起已造访的站点，短横线一段段"缝"过去（手账装订感）。
func _draw_journey() -> void:
	var seen: Array = []
	for sid in SpotData.SPOT_ORDER:
		if sid in g.seen_spots and _nodes.has(sid):
			seen.append(sid)
	for i in range(seen.size() - 1):
		_stitch(_nodes[seen[i]], _nodes[seen[i + 1]])


func _stitch(a: Vector2, b: Vector2) -> void:
	var total := a.distance_to(b)
	if total < 1.0:
		return
	var dir := (b - a) / total
	var nrm := Vector2(-dir.y, dir.x)
	var seg := 5.0
	var gap := 3.5
	var d := 0.0
	var k := 0
	while d < total:
		var e: float = minf(d + seg, total)
		# 手绘感：每一针在法向上抖一点点（确定性，不随帧闪）
		var wob := sin(float(k) * 1.7) * 0.7
		draw_line(a + dir * d + nrm * wob, a + dir * e + nrm * wob, STITCH, 1.2, true)
		d = e + gap
		k += 1


func _draw_stations() -> void:
	for sid in SpotData.SPOT_ORDER:
		if not _nodes.has(sid):
			continue
		var p: Vector2 = _nodes[sid]
		var unlocked: bool = sid in g.unlocked_spots
		var visited: bool = sid in g.seen_spots
		var is_cur: bool = sid == g.current_spot
		if not unlocked:
			draw_arc(p, 3.2, 0.0, TAU, 20, PENCIL, 1.0, true)   # 铅笔淡描的空心圈
			continue
		if is_cur:
			# 当前站：呼吸光晕 + 最亮的一盏灯（你自己那盏，永远最大最亮）
			var breath := 0.5 + 0.5 * sin(_t * 1.9)
			_lamp(p, 11.0 + 3.0 * breath, 0.26 + 0.16 * breath)
			draw_circle(p, 3.0, LAMP_HI)
			draw_arc(p, 6.5 + 1.8 * breath, 0.0, TAU, 28, Color(LAMP, 0.50), 1.2, true)
		elif visited:
			_lamp(p, 7.0, 0.16)
			draw_circle(p, 2.2, Color(LAMP, 0.85))
		else:
			draw_circle(p, 2.2, Color(LAMP, 0.45))   # 已解锁但没去过：一盏还没点亮的灯
		if sid == _hover:
			draw_arc(p, 10.0, 0.0, TAU, 28, Color(1, 1, 1, 0.55), 1.0, true)


func _lamp(p: Vector2, r: float, a: float) -> void:
	draw_texture_rect(_glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(LAMP, a))


## 底部一行：悬停某站时报站名与解锁进度；不悬停时报你自己的旅程。
func _draw_caption() -> void:
	var f: Font = g._font if g != null and g._font != null else ThemeDB.fallback_font
	if f == null:
		return
	var txt := ""
	if _hover != "" and SpotData.has(_hover):
		txt = SpotData.display_name(_hover)
		if _hover in g.unlocked_spots:
			txt += "　·　" + ("此刻你在这里" if _hover == g.current_spot
				else ("已造访" if _hover in g.seen_spots else "已解锁，还没去过"))
		else:
			txt += "　·　🔒 " + SpotData.unlock_text(_hover)
	else:
		txt = "你的旅程　·　已走过 %d/%d 站　·　累计 %d 次抛竿" % [
			g.seen_spots.size(), SpotData.SPOT_ORDER.size(), g.lifetime_catches]
	var pos := Vector2(10, VIEW.y - 9)
	draw_string(f, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.10, 0.09, 0.07, 0.45))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.22, 0.19, 0.14, 0.95))


func _make_glow() -> ImageTexture:
	var s := 48
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := s * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x - c, y - c).length() / (s * 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


# ============================ 交互（只到站点，永不到"人"）============================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit := _station_at(event.position)
		if hit != _hover:
			_hover = hit
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sid := _station_at(event.position)
		# 点已解锁的站 = 直接前往（地图顺带成了钓点切换器）；锁定站只看不动。
		# 注意：本文件**不得静态引用 Audio 等 autoload**——validate 直接调 WorldMap.project()
		# 会在 autoload 注册前编译本脚本，引用即报 "Identifier not found: Audio"。
		# 切钓点的音效由 Spots.switch_to → _apply_spot_visuals 负责。
		if sid != "" and sid in g.unlocked_spots and sid != g.current_spot:
			g._switch_spot(sid)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != "":
		_hover = ""
		queue_redraw()


## 最近命中：站点会挤在一起（4 个中国站），取最近的那个而不是第一个碰到的。
func _station_at(p: Vector2) -> String:
	var best := ""
	var best_d := 14.0
	for sid in _nodes:
		var d: float = p.distance_to(_nodes[sid])
		if d < best_d:
			best_d = d
			best = sid
	return best


# ============================ 简笔大陆轮廓（经度, 纬度）============================
# 粗略到只保证"认得出"，误差数度；水彩底图 assets/art/ui/world_map.png 一到位就不再使用。

const LAND_POLYS := [
	# 欧亚大陆（含阿拉伯半岛与印度次大陆）
	[Vector2(-9, 39), Vector2(-9, 44), Vector2(-1, 49), Vector2(3, 51), Vector2(8, 54),
	 Vector2(10, 58), Vector2(5, 60), Vector2(12, 66), Vector2(26, 71), Vector2(40, 68),
	 Vector2(55, 69), Vector2(70, 73), Vector2(90, 76), Vector2(110, 76), Vector2(130, 73),
	 Vector2(150, 71), Vector2(170, 68), Vector2(180, 66), Vector2(170, 60), Vector2(160, 55),
	 Vector2(150, 59), Vector2(140, 53), Vector2(133, 44), Vector2(126, 37), Vector2(122, 31),
	 Vector2(112, 22), Vector2(105, 10), Vector2(100, 6), Vector2(97, 17), Vector2(90, 22),
	 Vector2(80, 15), Vector2(77, 8), Vector2(72, 20), Vector2(64, 25), Vector2(57, 25),
	 Vector2(50, 29), Vector2(43, 13), Vector2(35, 28), Vector2(30, 36), Vector2(24, 40),
	 Vector2(15, 38), Vector2(12, 45), Vector2(3, 43), Vector2(-2, 36)],
	# 非洲
	[Vector2(-6, 36), Vector2(10, 37), Vector2(20, 33), Vector2(32, 31), Vector2(36, 22),
	 Vector2(43, 11), Vector2(51, 12), Vector2(41, -2), Vector2(40, -11), Vector2(35, -24),
	 Vector2(25, -34), Vector2(18, -34), Vector2(13, -23), Vector2(12, -6), Vector2(9, 4),
	 Vector2(-1, 5), Vector2(-8, 4), Vector2(-14, 10), Vector2(-17, 15), Vector2(-16, 22),
	 Vector2(-10, 30)],
	# 澳大利亚
	[Vector2(113, -22), Vector2(114, -27), Vector2(118, -34), Vector2(129, -32), Vector2(138, -35),
	 Vector2(146, -39), Vector2(150, -37), Vector2(153, -28), Vector2(146, -19), Vector2(142, -11),
	 Vector2(136, -12), Vector2(130, -11), Vector2(124, -14), Vector2(115, -20)],
	# 格陵兰（大部分在视窗外，靠 clip_contents 裁掉）
	[Vector2(-45, 60), Vector2(-25, 68), Vector2(-20, 76), Vector2(-30, 83), Vector2(-58, 82),
	 Vector2(-55, 70)],
	# 冰岛（第9站在这儿）
	[Vector2(-24, 65), Vector2(-18, 66.5), Vector2(-14, 65.5), Vector2(-16, 63.5), Vector2(-22, 63.8)],
	# 不列颠
	[Vector2(-5, 50), Vector2(0, 52), Vector2(-1, 55), Vector2(-3, 58), Vector2(-6, 56), Vector2(-5, 53)],
	# 日本
	[Vector2(130, 32), Vector2(135, 34), Vector2(140, 36), Vector2(141, 41), Vector2(145, 44),
	 Vector2(142, 42), Vector2(139, 37), Vector2(135, 35), Vector2(131, 33)],
	# 菲律宾（第5站）
	[Vector2(120, 18), Vector2(122, 15), Vector2(125, 10), Vector2(126, 7), Vector2(123, 6),
	 Vector2(120, 12)],
	# 婆罗洲（第6站在其东北岸）
	[Vector2(109, 2), Vector2(114, 7), Vector2(118, 6), Vector2(117, 1), Vector2(111, -3),
	 Vector2(109, -1)],
	# 苏门答腊
	[Vector2(95, 5), Vector2(98, 2), Vector2(104, -2), Vector2(106, -6), Vector2(103, -5),
	 Vector2(98, 0)],
	# 爪哇
	[Vector2(105, -6), Vector2(114, -8), Vector2(115, -8.6), Vector2(106, -7.2)],
	# 新几内亚
	[Vector2(131, -1), Vector2(140, -3), Vector2(147, -8), Vector2(143, -9), Vector2(134, -5)],
	# 新西兰 北岛（第7站在其东岸外海）
	[Vector2(173, -35), Vector2(176, -37), Vector2(178, -38), Vector2(175, -41), Vector2(173, -38)],
	# 新西兰 南岛
	[Vector2(171, -41), Vector2(174, -42), Vector2(173, -45), Vector2(168, -47), Vector2(166, -44),
	 Vector2(170, -42)],
	# 马达加斯加
	[Vector2(49, -12), Vector2(50, -16), Vector2(47, -25), Vector2(44, -21), Vector2(44, -16)],
]
