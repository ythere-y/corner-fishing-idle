class_name RoomView
extends Control
## 房间俯视图（极简线条 + 暖色调）：鱼缸直接落在地板中央，
## 当前默认只展示一个初始房间 + 一个鱼缸；后续可扩展不同房间/鱼缸模块。

const ROOM_SIZE := Vector2(560, 280)
const TANK_SIZE := Vector2(210, 132)   # 鱼缸直接落在地板中央，保留鱼和水体细节
const ENABLE_GARDEN_MODULE := false    # 当前阶段先隐藏右侧 garden，保留函数给后续房间拓展用

# ============================ 元素设计索引 ============================
# 这里先写“为什么这样画”，下面每个 _draw_* 只负责一个元素，方便手调。
const ELEMENT_DESIGN := {
	"room_unit": "RoomView 先作为可拓展房间单元：默认一个房间、一个鱼缸；后续再挂多房间/多鱼缸模块。",
	"room_shell": "四面墙由外矩形连接到地板矩形，墙面都是梯形，用来提示俯视房间盒子。",
	"floor": "中央暖木地板是鱼缸的承载面；不再画地毯或桌子，鱼缸直接放在地板上。",
	"window": "上方窗户跟随后墙透视，远端更宽、靠室内一侧更窄，窗光投向鱼缸。",
	"aquarium": "鱼缸是房间主物件，居中摆放；RoomView 只画贴地柔影，缸框由 Aquarium 自己绘制。",
	"pendants": "角落吊灯用连线和圆形灯罩提示这是从上往下看的房间。",
	"future_shoji": "预留：后续若房间接 garden，可打开 ENABLE_GARDEN_MODULE 并恢复可点击日式推拉门。",
	"future_garden": "预留：garden 模块暂不显示，后续可作为可拓展房间外景/鱼缸环境。",
}

# ============================ 房间透视几何 ============================
# 地板四角：蓝色内框，代表室内可用地板区域。四面墙会自动连接这些点。
const ROOM_FLOOR_TL := Vector2(44.0, 42.0)
const ROOM_FLOOR_TR := Vector2(516.0, 42.0)
const ROOM_FLOOR_BR := Vector2(516.0, 238.0)
const ROOM_FLOOR_BL := Vector2(44.0, 238.0)
# 外框四角：红色外框，代表房间外边界。四面墙是外矩形到内矩形之间的四个梯形。
const ROOM_OUTER_TL := Vector2(0.0, 0.0)
const ROOM_OUTER_TR := Vector2(560.0, 0.0)
const ROOM_OUTER_BR := Vector2(560.0, 280.0)
const ROOM_OUTER_BL := Vector2(0.0, 280.0)
const DEBUG_ROOM_POINTS := false         # 临时调点用：蓝色框代表地板区域，红色框代表房间外框

# ============================ 可调元素参数 ============================
const DOOR_W := 68.0                     # 推拉门总宽；越大越像门，越小越像分隔柱
const DOOR_TOP := 12.0                   # 门框顶端贴近后墙
const DOOR_BOTTOM := 266.0               # 门框底端贴近前墙
const DOOR_OPEN_OFFSET := 28.0           # 开门时两扇门向两侧滑开的距离
const DOOR_SKEW := 11.0                  # 梯形斜切量：门扇上/下边错位，提示透视

# —— 暖色调极简线条配色 ——
const C_FLOOR := Color(0.96, 0.88, 0.73)      # 暖奶油地板
const C_PLANK := Color(0.82, 0.65, 0.47)      # 木纹线（暖棕）
const C_WALL  := Color(0.54, 0.39, 0.28)      # 墙描边（暖棕）
const C_BASE  := Color(0.72, 0.53, 0.38)      # 踢脚线
const C_SHADOW := Color(0.32, 0.22, 0.14)     # 缸在地板上的投影（暖暗）
const C_DOOR  := Color(0.91, 0.80, 0.63)      # 门洞（浅）
const C_WIN   := Color(0.78, 0.87, 0.90)      # 窗（暖天光）
const C_CABINET := Color(0.70, 0.48, 0.31)    # 小木柜
const C_FABRIC := Color(0.74, 0.42, 0.36)     # 坐垫/布艺
const C_PLANT := Color(0.20, 0.45, 0.28)      # 植物
const C_LAMP := Color(1.00, 0.78, 0.42)       # 暖灯
const C_GARDEN_SAND := Color(0.82, 0.79, 0.69)
const C_GARDEN_MOSS := Color(0.42, 0.55, 0.33)
const C_GARDEN_STONE := Color(0.43, 0.45, 0.42)
const C_BAMBOO := Color(0.30, 0.52, 0.31)
const C_MAPLE := Color(0.74, 0.30, 0.22)

var g                                   # CornerFishing 主节点
var _aq: Control = null                 # 左侧大水族箱
var _t := 0.0                           # 房间轻微动态时间；当前用于吊灯/预留植物模块
var _door_open := true                  # 点击日式推拉门开/关 garden，默认打开看见右侧庭院


func setup(host) -> void:
	g = host
	custom_minimum_size = ROOM_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_aq = Aquarium.new()
	_aq.name = "Aquarium"
	_aq.setup(g)
	_aq.custom_minimum_size = TANK_SIZE
	add_child(_aq)
	_position_tank()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_position_tank()
		queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _position_tank() -> void:
	if not is_instance_valid(_aq):
		return
	_aq.size = TANK_SIZE
	_aq.position = _tank_position()


func _gui_input(event: InputEvent) -> void:
	if not ENABLE_GARDEN_MODULE:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _door_hit_rect().has_point(mb.position):
			_door_open = not _door_open
			accept_event()
			queue_redraw()


func _draw() -> void:
	var sz := size
	_draw_indoor_room(sz)
	_draw_window_light(sz)
	_draw_room_props(sz)
	_draw_corner_pendants(sz)
	if ENABLE_GARDEN_MODULE:
		_draw_japanese_garden(sz)
		_draw_shoji_divider(sz)
	if DEBUG_ROOM_POINTS:
		_draw_debug_room_points()
	_draw_tank_floor_shadow()


func _draw_tank_floor_shadow() -> void:
	# 设计意图：鱼缸直接落在木地板上；这里只画很薄的贴地柔影，不再暗示桌子/地毯。
	var tr := _tank_rect()
	for i in 4:
		var inset := float(i) * 3.0
		draw_rect(Rect2(tr.position.x + 3.0 + inset, tr.position.y + 5.0 + inset,
			tr.size.x - 6.0 - inset * 2.0, tr.size.y - 2.0 - inset * 2.0),
			Color(C_SHADOW.r, C_SHADOW.g, C_SHADOW.b, 0.09 - i * 0.018))


func _draw_indoor_room(sz: Vector2) -> void:
	# 轻透视房间盒子：四面墙都由“外框四角”连接到“地板四角”，保证墙面和地板严格相接。
	var outer_tl := ROOM_OUTER_TL
	var outer_tr := ROOM_OUTER_TR
	var outer_br := ROOM_OUTER_BR
	var outer_bl := ROOM_OUTER_BL
	var inner_tl := ROOM_FLOOR_TL
	var inner_tr := ROOM_FLOOR_TR
	var inner_br := ROOM_FLOOR_BR
	var inner_bl := ROOM_FLOOR_BL
	# 后墙（远处，最窄）
	draw_polygon(PackedVector2Array([
		outer_tl, outer_tr, inner_tr, inner_tl
	]), [Color(0.76, 0.57, 0.39)])
	# 左墙（向远处收束）
	draw_polygon(PackedVector2Array([
		outer_tl, inner_tl, inner_bl, outer_bl
	]), [Color(0.62, 0.43, 0.28)])
	# 右墙（靠门，向远处收束；保持四边梯形）
	draw_polygon(PackedVector2Array([
		outer_tr, outer_br, inner_br, inner_tr
	]), [Color(0.43, 0.26, 0.16)])
	# 前墙（近处，最宽）
	draw_polygon(PackedVector2Array([
		inner_bl, inner_br, outer_br, outer_bl
	]), [Color(0.48, 0.30, 0.18)])
	# 中央地板同样用梯形，和四面墙形成盒子感。
	var floor_tl := inner_tl
	var floor_tr := inner_tr
	var floor_bl := inner_bl
	var floor_br := inner_br
	var floor_poly := PackedVector2Array([floor_tl, floor_tr, floor_br, floor_bl])
	draw_polygon(floor_poly, [C_FLOOR])
	for i in 9:
		var f0 := float(i) / 9.0
		var f1 := float(i + 1) / 9.0
		var l0 := floor_tl.lerp(floor_bl, f0)
		var r0 := floor_tr.lerp(floor_br, f0)
		var l1 := floor_tl.lerp(floor_bl, f1)
		var r1 := floor_tr.lerp(floor_br, f1)
		var band_col := Color(0.95, 0.84, 0.66, 0.20) if i % 2 == 0 else Color(1.0, 0.92, 0.76, 0.16)
		draw_polygon(PackedVector2Array([l0, r0, r1, l1]), [band_col])
		draw_line(l0, r0, Color(C_PLANK.r, C_PLANK.g, C_PLANK.b, 0.30), 1.0)
		for k in 3:
			var ff := clampf(f0 + 0.12 + k * 0.035, 0.0, 1.0)
			var ll := floor_tl.lerp(floor_bl, ff)
			var rr := floor_tr.lerp(floor_br, ff)
			var a := 0.18 + 0.18 * k + fmod(float(i * 7), 13.0) / 60.0
			var b := minf(a + 0.16, 0.92)
			draw_line(ll.lerp(rr, a), ll.lerp(rr, b),
				Color(C_PLANK.r, C_PLANK.g, C_PLANK.b, 0.10), 1.0)
	# 内轮廓和墙脚线，强化可见四面墙。
	draw_polyline(PackedVector2Array([floor_tl, floor_tr, floor_br, floor_bl, floor_tl]),
		Color(C_BASE.r, C_BASE.g, C_BASE.b, 0.58), 2.0, true)
	draw_line(outer_tl, outer_tr, Color(0.96, 0.76, 0.48, 0.24), 1.0)
	draw_line(floor_bl, floor_br, Color(0.16, 0.09, 0.05, 0.24), 1.0)


func _draw_window_light(sz: Vector2) -> void:
	var tr := _tank_rect()
	var cx := tr.position.x + tr.size.x * 0.50
	var win_top := 252.0
	var win_bot := 206.0
	var win_y0 := 4.0
	var win_y1 := 34.0
	var win_pts := PackedVector2Array([
		Vector2(cx - win_top * 0.5, win_y0),
		Vector2(cx + win_top * 0.5, win_y0),
		Vector2(cx + win_bot * 0.5, win_y1),
		Vector2(cx - win_bot * 0.5, win_y1),
	])
	draw_polygon(win_pts, [Color(0.88, 0.95, 0.96, 0.96)])
	draw_polyline(PackedVector2Array([win_pts[0], win_pts[1], win_pts[2], win_pts[3], win_pts[0]]),
		Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.82), 1.4, true)
	for i in 3:
		var f := float(i + 1) / 4.0
		draw_line(win_pts[0].lerp(win_pts[1], f), win_pts[3].lerp(win_pts[2], f),
			Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.50), 1.0)
	draw_line(win_pts[0].lerp(win_pts[3], 0.54), win_pts[1].lerp(win_pts[2], 0.54),
		Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.40), 1.0)
	var pts := PackedVector2Array([
		Vector2(cx - 88.0, win_y1),
		Vector2(cx + 90.0, win_y1),
		Vector2(cx + 146.0, tr.end.y - 10.0),
		Vector2(cx - 132.0, tr.end.y - 4.0),
	])
	draw_polygon(pts, [Color(1.0, 0.93, 0.70, 0.09)])
	for i in 4:
		var x := cx - 58.0 + i * 38.0
		draw_line(Vector2(x, 13.0), Vector2(x + 78.0, tr.end.y - 18.0),
			Color(1.0, 0.96, 0.78, 0.08), 1.0)


func _draw_room_props(sz: Vector2) -> void:
	# 左上矮柜：俯视矩形 + 两个抽屉线，给房间一个生活尺度。
	var cabinet := Rect2(18.0, 20.0, 72.0, 30.0)
	draw_rect(cabinet, Color(C_CABINET.r, C_CABINET.g, C_CABINET.b, 0.80))
	draw_rect(cabinet, C_WALL, false, 1.0)
	draw_line(Vector2(cabinet.position.x, cabinet.position.y + cabinet.size.y * 0.5),
		Vector2(cabinet.end.x, cabinet.position.y + cabinet.size.y * 0.5), Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.45), 1.0)
	for x in [cabinet.position.x + 26.0, cabinet.position.x + 54.0]:
		draw_circle(Vector2(x, cabinet.position.y + cabinet.size.y * 0.5), 1.8, Color(0.96, 0.78, 0.46, 0.75))
	# 左下小坐垫/脚凳。
	var cushion := Rect2(26.0, sz.y - 70.0, 58.0, 34.0)
	draw_rect(cushion, Color(C_FABRIC.r, C_FABRIC.g, C_FABRIC.b, 0.62))
	draw_rect(cushion, Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.34), false, 1.0)
	draw_line(cushion.position + Vector2(10.0, 0.0), cushion.position + Vector2(10.0, cushion.size.y),
		Color(1.0, 0.85, 0.74, 0.22), 1.0)
	# 左侧暖灯：照亮鱼缸，右侧留给庭院。
	var lamp := Vector2(44.0, sz.y - 42.0)
	draw_circle(lamp, 22.0, Color(C_LAMP.r, C_LAMP.g, C_LAMP.b, 0.12))
	draw_circle(lamp, 8.0, Color(C_LAMP.r, C_LAMP.g, C_LAMP.b, 0.72))
	draw_circle(lamp, 3.0, Color(1.0, 0.96, 0.78, 0.90))


func _draw_corner_pendants(sz: Vector2) -> void:
	_draw_pendant(Vector2(78.0, 72.0), Vector2(ROOM_OUTER_TL.x + 16.0, ROOM_OUTER_TL.y + 16.0), 0.78)
	_draw_pendant(Vector2(360.0, 70.0), Vector2(ROOM_OUTER_TR.x - 18.0, ROOM_OUTER_TR.y + 14.0), 0.64)
	_draw_pendant(Vector2(86.0, 218.0), Vector2(ROOM_OUTER_BL.x + 17.0, ROOM_OUTER_BL.y - 18.0), 0.58)


func _draw_pendant(center: Vector2, anchor: Vector2, scale: float) -> void:
	draw_line(anchor, center, Color(0.22, 0.14, 0.09, 0.36), 1.0, true)
	draw_circle(center, 20.0 * scale, Color(C_LAMP.r, C_LAMP.g, C_LAMP.b, 0.10))
	draw_circle(center, 8.8 * scale, Color(0.64, 0.36, 0.18, 0.72))
	draw_circle(center, 6.2 * scale, Color(C_LAMP.r, C_LAMP.g, C_LAMP.b, 0.82))
	draw_circle(center, 2.6 * scale, Color(1.0, 0.94, 0.70, 0.96))
	draw_arc(center, 11.0 * scale, -PI * 0.12, PI * 1.12, 18,
		Color(0.18, 0.11, 0.07, 0.42), 1.0, true)


func _draw_japanese_garden(sz: Vector2) -> void:
	var gx := _door_x() + 24.0
	var gr := Rect2(gx, 0.0, maxf(sz.x - gx, 1.0), sz.y)
	# 右侧明确是外景：不再严格俯视，直接像测试图一样把程序化植物种进画面。
	draw_rect(gr, Color(0.43, 0.58, 0.34))
	var sand := Rect2(gr.position + Vector2(9.0, 22.0), gr.size - Vector2(18.0, 40.0))
	draw_rect(sand, Color(C_GARDEN_SAND.r, C_GARDEN_SAND.g, C_GARDEN_SAND.b, 0.92))
	# 门外台阶：从障子门外延到庭院，形成“入室内园林”的动线。
	var step_y := sz.y * 0.52
	var step := Rect2(gx - 12.0, step_y - 24.0, minf(78.0, gr.size.x * 0.46), 48.0)
	draw_rect(step, Color(0.66, 0.62, 0.54))
	draw_rect(step, Color(0.36, 0.31, 0.25, 0.40), false, 1.0)
	draw_line(step.position + Vector2(7.0, step.size.y * 0.5), step.end - Vector2(7.0, step.size.y * 0.5),
		Color(0.48, 0.44, 0.38, 0.42), 1.0)
	draw_rect(Rect2(step.position.x + 8.0, step.end.y - 8.0, step.size.x - 16.0, 5.0),
		Color(0.30, 0.26, 0.22, 0.28))
	# 顶部竹篱和远处绿篱，强化户外私家庭院。
	draw_rect(Rect2(gr.position.x, gr.position.y, gr.size.x, 16.0), Color(0.33, 0.43, 0.28, 0.60))
	for i in int(gr.size.x / 16.0) + 1:
		var x := gr.position.x + i * 16.0
		draw_line(Vector2(x, gr.position.y + 1.0), Vector2(x + 4.0, gr.position.y + 15.0),
			Color(C_BAMBOO.r, C_BAMBOO.g, C_BAMBOO.b, 0.58), 2.0, true)
	# 苔藓边角。
	for p in [gr.position + Vector2(24.0, gr.size.y - 24.0), gr.end - Vector2(24.0, 28.0), gr.position + Vector2(gr.size.x * 0.58, 34.0)]:
		_draw_flat_ellipse(p, 28.0, 14.0, Color(C_GARDEN_MOSS.r, C_GARDEN_MOSS.g, C_GARDEN_MOSS.b, 0.44))
	# 枯山水砂纹：柔和弧线，避免太抢鱼缸。
	for i in 8:
		var y := sand.position.y + 16.0 + i * 20.0
		var pts := PackedVector2Array()
		for s in 18:
			var f := float(s) / 17.0
			var x := lerpf(sand.position.x + 8.0, sand.end.x - 8.0, f)
			pts.append(Vector2(x, y + sin(f * TAU * 1.2 + i * 0.7) * 3.0))
		draw_polyline(pts, Color(0.55, 0.52, 0.45, 0.24), 1.0, true)
	# 踏石。
	for i in 4:
		var p := Vector2(sand.position.x + 38.0 + i * 34.0, sand.position.y + 56.0 + sin(i * 1.4) * 27.0)
		_draw_flat_ellipse(p, 18.0, 11.0, Color(C_GARDEN_STONE.r, C_GARDEN_STONE.g, C_GARDEN_STONE.b, 0.72))
		_draw_flat_ellipse(p - Vector2(3.0, 2.0), 8.0, 4.5, Color(0.72, 0.73, 0.68, 0.18))
	# 小水钵。
	var bowl := Vector2(sand.end.x - 42.0, sand.end.y - 34.0)
	_draw_flat_ellipse(bowl, 20.0, 14.0, Color(0.34, 0.36, 0.34, 0.86))
	_draw_flat_ellipse(bowl, 13.0, 8.0, Color(0.23, 0.50, 0.58, 0.58))
	draw_circle(bowl + Vector2(3.0, -2.0), 2.4, Color(0.86, 0.96, 1.0, 0.42))
	# L-system 分叉树 + 多类型花簇：参考 procedural-plants 的 F/+/-/[ ] 分叉，
	# 以及 Garten 的多类别小树/花/草组合，但落成 Godot 静态绘制。
	_draw_proc_tree(Vector2(gr.end.x - 33.0, gr.end.y - 42.0), 0.78, 11, Color(0.26, 0.48, 0.26), Color(0.36, 0.22, 0.12))
	_draw_proc_tree(Vector2(gr.position.x + 42.0, gr.end.y - 48.0), 0.62, 31, Color(0.66, 0.25, 0.22), Color(0.32, 0.19, 0.11))
	_draw_proc_tree(Vector2(gr.end.x - 58.0, gr.position.y + 104.0), 0.52, 47, Color(0.22, 0.44, 0.29), Color(0.34, 0.22, 0.14))
	_draw_flower_patch(Vector2(sand.position.x + 25.0, sand.position.y + 38.0), 34.0, 7, Color(0.90, 0.56, 0.70), Color(0.93, 0.78, 0.30))
	_draw_flower_patch(Vector2(sand.end.x - 30.0, sand.position.y + 78.0), 28.0, 19, Color(0.65, 0.55, 0.88), Color(0.96, 0.82, 0.34))
	_draw_tall_grass(Vector2(sand.position.x + 28.0, sand.end.y - 22.0), 42.0, 13)
	_draw_tall_grass(Vector2(sand.end.x - 24.0, sand.end.y - 62.0), 34.0, 23)


func _draw_shoji_divider(sz: Vector2) -> void:
	var x := _door_x()
	var left := x - DOOR_W * 0.5
	var right := x + DOOR_W * 0.5
	var top := DOOR_TOP
	var bottom := DOOR_BOTTOM
	var open := DOOR_OPEN_OFFSET if _door_open else 0.0
	# 设计意图：这是房间和 garden 的“日式推拉门”。门框与门扇都用梯形点位，
	# 而不是普通矩形，让它跟房间墙面透视一致；点击门区可开/关。
	var frame := PackedVector2Array([
		Vector2(left - 6.0, top - 4.0),
		Vector2(right + 6.0, top + DOOR_SKEW * 0.25),
		Vector2(right - 6.0, bottom + 4.0),
		Vector2(left + 6.0, bottom - DOOR_SKEW * 0.25),
	])
	draw_polygon(frame, [Color(0.30, 0.18, 0.10, 0.88)])
	draw_line(Vector2(left - 10.0, top - 6.0), Vector2(right + 10.0, top - 1.0),
		Color(0.20, 0.12, 0.07, 0.95), 5.0, true)
	draw_line(Vector2(left - 10.0, bottom + 4.0), Vector2(right + 10.0, bottom - 1.0),
		Color(0.20, 0.12, 0.07, 0.95), 5.0, true)
	var gap_col := Color(0.14, 0.10, 0.07, 0.50 if _door_open else 0.18)
	draw_polygon(_door_quad(x - 8.0, x + 8.0, 0.0), [gap_col])
	_draw_shoji_panel(_door_quad(left - open, x - open * 0.38, -DOOR_SKEW), true)
	_draw_shoji_panel(_door_quad(x + open * 0.38, right + open, DOOR_SKEW), false)
	var handle_y := lerpf(top, bottom, 0.52)
	draw_circle(Vector2(x - 9.0 - open * 0.38, handle_y), 2.2, Color(0.76, 0.54, 0.32, 0.82))
	draw_circle(Vector2(x + 9.0 + open * 0.38, handle_y), 2.2, Color(0.76, 0.54, 0.32, 0.82))


func _door_quad(left_x: float, right_x: float, skew: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left_x, DOOR_TOP),
		Vector2(right_x, DOOR_TOP + skew * 0.25),
		Vector2(right_x - skew, DOOR_BOTTOM),
		Vector2(left_x - skew, DOOR_BOTTOM - skew * 0.25),
	])


func _draw_shoji_panel(q: PackedVector2Array, left_panel: bool) -> void:
	var paper := Color(0.96, 0.91, 0.78, 0.60 if left_panel else 0.48)
	var wood := Color(0.49, 0.30, 0.18, 0.62)
	draw_polygon(q, [paper])
	draw_polyline(PackedVector2Array([q[0], q[1], q[2], q[3], q[0]]), wood, 1.4, true)
	for i in 1:
		var f := 0.50
		draw_line(q[0].lerp(q[1], f), q[3].lerp(q[2], f), wood, 1.0, true)
	for j in 4:
		var f := float(j + 1) / 5.0
		draw_line(q[0].lerp(q[3], f), q[1].lerp(q[2], f), wood, 1.0, true)


func _door_hit_rect() -> Rect2:
	return Rect2(_door_x() - DOOR_W * 0.85, DOOR_TOP - 10.0,
		DOOR_W * 1.7, DOOR_BOTTOM - DOOR_TOP + 20.0)


func _draw_flat_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polygon(pts, [col])


func _draw_proc_tree(base: Vector2, scale: float, seed: int, leaf_col: Color, branch_col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	draw_circle(base + Vector2(0.0, 3.0), 13.0 * scale, Color(0.14, 0.12, 0.08, 0.14))
	_draw_tree_branch(base, -PI * 0.5 + rng.randf_range(-0.08, 0.08), 40.0 * scale, 5.0 * scale, 4, rng, leaf_col, branch_col)


func _draw_tree_branch(pos: Vector2, angle: float, length: float, width: float, depth: int,
		rng: RandomNumberGenerator, leaf_col: Color, branch_col: Color) -> void:
	var wind := sin(_t * 0.7 + float(depth) * 1.9) * 0.025
	var end := pos + Vector2(cos(angle + wind), sin(angle + wind)) * length
	draw_line(pos, end, Color(branch_col.r, branch_col.g, branch_col.b, 0.82), maxf(width, 1.0), true)
	if depth <= 0:
		for i in 5:
			var a := TAU * float(i) / 5.0 + rng.randf_range(-0.25, 0.25)
			var leaf := end + Vector2(cos(a) * 7.0, sin(a) * 5.0) * rng.randf_range(0.55, 1.0)
			_draw_leaf(leaf, a, 7.0 * rng.randf_range(0.75, 1.15), leaf_col)
		return
	var branches := 3 if rng.randf() > 0.58 else 2
	for i in branches:
		var side := -1.0 if i % 2 == 0 else 1.0
		var spread := rng.randf_range(0.34, 0.62) * side
		var next_angle := angle + spread + rng.randf_range(-0.13, 0.13)
		var next_len := length * rng.randf_range(0.62, 0.76)
		_draw_tree_branch(end, next_angle, next_len, width * 0.68, depth - 1, rng, leaf_col, branch_col)


func _draw_leaf(center: Vector2, angle: float, length: float, col: Color) -> void:
	var n := Vector2(cos(angle), sin(angle))
	var p := Vector2(-n.y, n.x)
	var pts := PackedVector2Array([
		center + n * length,
		center + p * length * 0.36,
		center - n * length * 0.55,
		center - p * length * 0.36,
	])
	draw_polygon(pts, [Color(col.r, col.g, col.b, 0.72)])


func _draw_flower_patch(center: Vector2, radius: float, seed: int, petal_col: Color, core_col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 12:
		var p := center + Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius * 0.55, radius * 0.55))
		var stem_h := rng.randf_range(8.0, 18.0)
		draw_line(p + Vector2(0.0, stem_h), p, Color(0.21, 0.43, 0.24, 0.62), 1.0, true)
		var petals := 6 if rng.randf() > 0.55 else 5
		for k in petals:
			var a := TAU * float(k) / float(petals)
			_draw_flat_ellipse(p + Vector2(cos(a) * 4.0, sin(a) * 3.0), 2.6, 1.7,
				Color(petal_col.r, petal_col.g, petal_col.b, 0.74))
		draw_circle(p, 2.2, Color(core_col.r, core_col.g, core_col.b, 0.82))


func _draw_tall_grass(base: Vector2, height: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in 13:
		var x := base.x + rng.randf_range(-16.0, 16.0)
		var h := height * rng.randf_range(0.45, 1.05)
		var sway := sin(_t * 0.9 + float(i) * 0.6) * 3.0
		draw_line(Vector2(x, base.y), Vector2(x + rng.randf_range(-9.0, 9.0) + sway, base.y - h),
			Color(0.25, 0.48, 0.25, 0.58), rng.randf_range(1.0, 2.0), true)


func _draw_debug_room_points() -> void:
	var floor_col := Color(0.20, 0.85, 1.0, 0.95)
	var outer_col := Color(1.0, 0.25, 0.20, 0.95)
	var floor_pts := {
		"F_TL": ROOM_FLOOR_TL,
		"F_TR": ROOM_FLOOR_TR,
		"F_BR": ROOM_FLOOR_BR,
		"F_BL": ROOM_FLOOR_BL,
	}
	var outer_pts := {
		"O_TL": ROOM_OUTER_TL,
		"O_TR": ROOM_OUTER_TR,
		"O_BR": ROOM_OUTER_BR,
		"O_BL": ROOM_OUTER_BL,
	}
	draw_polyline(PackedVector2Array([ROOM_FLOOR_TL, ROOM_FLOOR_TR, ROOM_FLOOR_BR, ROOM_FLOOR_BL, ROOM_FLOOR_TL]),
		floor_col, 2.0, true)
	draw_polyline(PackedVector2Array([ROOM_OUTER_TL, ROOM_OUTER_TR, ROOM_OUTER_BR, ROOM_OUTER_BL, ROOM_OUTER_TL]),
		outer_col, 2.0, true)
	for k in floor_pts.keys():
		_draw_debug_point(str(k), floor_pts[k], floor_col)
	for k in outer_pts.keys():
		_draw_debug_point(str(k), outer_pts[k], outer_col)


func _draw_debug_point(label: String, p: Vector2, col: Color) -> void:
	draw_circle(p, 5.5, Color(0.02, 0.02, 0.02, 0.82))
	draw_circle(p, 4.0, col)
	draw_line(p - Vector2(8.0, 0.0), p + Vector2(8.0, 0.0), col, 1.0)
	draw_line(p - Vector2(0.0, 8.0), p + Vector2(0.0, 8.0), col, 1.0)
	draw_string(ThemeDB.fallback_font, p + Vector2(7.0, -7.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 1.0, 1.0, 0.96))


## 缸在房间局部坐标里的矩形（用于贴地阴影）：居中固定摆放。
func _tank_rect() -> Rect2:
	return Rect2(_tank_position(), TANK_SIZE)


func _door_x() -> float:
	return ROOM_FLOOR_TR.x + 12.0


func _tank_position() -> Vector2:
	var center := (ROOM_FLOOR_TL + ROOM_FLOOR_BR) * 0.5
	return center - TANK_SIZE * 0.5
