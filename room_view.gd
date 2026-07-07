class_name RoomView
extends Control
## 房间俯视图（极简线条 + 暖色调）：左侧是一只更大的俯视水族箱，
## 右侧用日式门分隔后打开成私家庭院外景（砂砾、踏石、竹/枫、小水钵），让 home 与户外景观并置。

const ROOM_SIZE := Vector2(560, 280)
const TANK_SIZE := Vector2(380, 218)   # 左侧主视觉：明显放大，鱼和水体细节更清楚

# —— 房间透视几何（后续主要调这里）——
# 地板四角：蓝色内框，必须保持矩形。四面墙会自动连接这些点。
const ROOM_FLOOR_TL := Vector2(44.0, 42.0)
const ROOM_FLOOR_TR := Vector2(392.0, 42.0)
const ROOM_FLOOR_BR := Vector2(392.0, 238.0)
const ROOM_FLOOR_BL := Vector2(44.0, 238.0)
# 外框四角：红色外框，必须保持矩形。四面墙是外矩形到内矩形之间的四个梯形。
const ROOM_OUTER_TL := Vector2(0.0, 0.0)
const ROOM_OUTER_TR := Vector2(452.0, 0.0)
const ROOM_OUTER_BR := Vector2(452.0, 280.0)
const ROOM_OUTER_BL := Vector2(0.0, 280.0)
const DEBUG_ROOM_POINTS := true          # 临时调点用：高亮显示地板/外框 8 个透视点

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


func setup(host) -> void:
	g = host
	custom_minimum_size = ROOM_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 左侧大缸：右侧留给日系庭院
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


func _position_tank() -> void:
	if not is_instance_valid(_aq):
		return
	_aq.size = TANK_SIZE
	_aq.position = _tank_position()


func _draw() -> void:
	var sz := size
	_draw_indoor_room(sz)
	_draw_japanese_garden(sz)
	_draw_window_light(sz)
	_draw_room_props(sz)
	_draw_shoji_divider(sz)
	if DEBUG_ROOM_POINTS:
		_draw_debug_room_points()
	# 缸在地板上的投影（俯视：只保留柔影，去掉旧版圆形背景垫）
	var tr := _tank_rect()
	for i in 4:
		var inset := float(i) * 3.0
		draw_rect(Rect2(tr.position.x - 2.0 + inset, tr.position.y + 7.0 + inset,
			tr.size.x + 4.0 - inset * 2.0, tr.size.y + 4.0 - inset * 2.0),
			Color(C_SHADOW.r, C_SHADOW.g, C_SHADOW.b, 0.14 - i * 0.025))


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
	var win := Rect2(cx - 82.0, 5.0, 164.0, 19.0)
	draw_rect(win, Color(0.88, 0.93, 0.92, 0.95))
	draw_rect(win, Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.78), false, 1.0)
	for i in 3:
		var x := win.position.x + win.size.x * (float(i + 1) / 4.0)
		draw_line(Vector2(x, win.position.y), Vector2(x, win.end.y), Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.55), 1.0)
	draw_line(Vector2(win.position.x, win.position.y + win.size.y * 0.52), Vector2(win.end.x, win.position.y + win.size.y * 0.52),
		Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.42), 1.0)
	var pts := PackedVector2Array([
		Vector2(cx - 72.0, win.end.y),
		Vector2(cx + 72.0, win.end.y),
		Vector2(cx + 144.0, tr.end.y - 8.0),
		Vector2(cx - 126.0, tr.end.y - 2.0),
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


func _draw_japanese_garden(sz: Vector2) -> void:
	var gx := _door_x() + 24.0
	var gr := Rect2(gx, 0.0, maxf(sz.x - gx, 1.0), sz.y)
	# 右侧明确是外景：不透明苔地直接铺满，不画黄色底和外边框。
	draw_rect(gr, Color(0.45, 0.61, 0.36))
	var sand := Rect2(gr.position + Vector2(10.0, 26.0), gr.size - Vector2(20.0, 48.0))
	draw_rect(sand, C_GARDEN_SAND)
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
	# 苔藓边角，不再像室内地毯。
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
	# 竹与枫：左右高低错开，形成日系庭院符号。
	var bamboo_base := Vector2(gr.end.x - 28.0, gr.position.y + 62.0)
	for i in 4:
		var x := bamboo_base.x - i * 9.0
		draw_line(Vector2(x, bamboo_base.y + 50.0), Vector2(x + 4.0, bamboo_base.y - 8.0),
			Color(C_BAMBOO.r, C_BAMBOO.g, C_BAMBOO.b, 0.80), 3.0, true)
		for k in 3:
			var y := bamboo_base.y + 6.0 + k * 16.0
			draw_line(Vector2(x + 1.0, y), Vector2(x + 17.0, y - 7.0),
				Color(C_BAMBOO.r + 0.08, C_BAMBOO.g + 0.10, C_BAMBOO.b, 0.58), 2.0, true)
	var maple := Vector2(gr.position.x + 38.0, gr.end.y - 42.0)
	draw_line(maple + Vector2(0.0, 22.0), maple, Color(0.34, 0.20, 0.12, 0.74), 3.0, true)
	for i in 9:
		var a := TAU * float(i) / 9.0
		var p := maple + Vector2(cos(a) * 22.0, sin(a) * 14.0)
		draw_circle(p, 4.0, Color(C_MAPLE.r, C_MAPLE.g + 0.08 * sin(i), C_MAPLE.b, 0.62))


func _draw_shoji_divider(sz: Vector2) -> void:
	var x := _door_x()
	var top := 16.0
	var h := sz.y - 32.0
	# 日式门框：厚木门槛 + 两扇半开的障子门；右侧加暗面，给一点侧视厚度。
	var side := PackedVector2Array([
		Vector2(x + 8.0, top - 5.0),
		Vector2(x + 22.0, top + 3.0),
		Vector2(x + 22.0, top + h - 3.0),
		Vector2(x + 8.0, top + h + 5.0),
	])
	draw_polygon(side, [Color(0.28, 0.17, 0.10, 0.76)])
	draw_rect(Rect2(x - 10.0, top - 6.0, 20.0, h + 12.0), Color(0.40, 0.24, 0.14, 0.90))
	draw_rect(Rect2(x - 4.0, top, 8.0, h), Color(0.78, 0.62, 0.42, 0.92))
	draw_rect(Rect2(x - 22.0, top + 10.0, 18.0, h - 20.0), Color(0.96, 0.91, 0.78, 0.58))
	draw_rect(Rect2(x + 4.0, top + 10.0, 18.0, h - 20.0), Color(0.96, 0.91, 0.78, 0.42))
	for yy in 4:
		var y := top + 24.0 + yy * 38.0
		draw_line(Vector2(x - 22.0, y), Vector2(x - 4.0, y), Color(0.50, 0.32, 0.20, 0.52), 1.0)
		draw_line(Vector2(x + 4.0, y), Vector2(x + 22.0, y), Color(0.50, 0.32, 0.20, 0.42), 1.0)
	draw_line(Vector2(x - 13.0, top + 10.0), Vector2(x - 13.0, top + h - 10.0), Color(0.50, 0.32, 0.20, 0.45), 1.0)
	draw_line(Vector2(x + 13.0, top + 10.0), Vector2(x + 13.0, top + h - 10.0), Color(0.50, 0.32, 0.20, 0.34), 1.0)
	draw_rect(Rect2(x - 30.0, top - 9.0, 58.0, 6.0), Color(0.32, 0.19, 0.11, 0.92))
	draw_rect(Rect2(x - 30.0, top + h + 3.0, 58.0, 6.0), Color(0.32, 0.19, 0.11, 0.92))


func _draw_flat_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polygon(pts, [col])


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


## 缸在房间局部坐标里的矩形（用于投影/地毯定位）：左侧固定摆放。
func _tank_rect() -> Rect2:
	return Rect2(_tank_position(), TANK_SIZE)


func _door_x() -> float:
	return _tank_rect().end.x + 12.0


func _tank_position() -> Vector2:
	return ROOM_FLOOR_TL + Vector2(-10.0, 2.0)
