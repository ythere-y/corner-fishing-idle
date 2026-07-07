class_name RoomView
extends Control
## 房间俯视图（极简线条 + 暖色调）：把缩小的活水族箱摆进一只俯视的房间里，
## 让“这是一个俯视图”更直观——地板木纹线、四壁描边、门洞、窗、缸下软地毯与投影。
## 缸本身仍是 Aquarium（鱼的程序化动画/点鱼看纪录不变），只是缩小居中放在房间中央。

const ROOM_SIZE := Vector2(420, 280)
const TANK_SIZE := Vector2(196, 128)   # 缩小后的缸（相对原 472×260 约 0.42）

# —— 暖色调极简线条配色 ——
const C_FLOOR := Color(0.96, 0.88, 0.73)    # 暖奶油地板
const C_PLANK := Color(0.82, 0.65, 0.47)    # 木纹线（暖棕）
const C_WALL  := Color(0.56, 0.41, 0.29)    # 墙描边（暖棕）
const C_RUG   := Color(0.88, 0.66, 0.50)    # 缸下软地毯（暖陶）
const C_SHADOW := Color(0.32, 0.22, 0.14)   # 缸在地板上的投影（暖暗）
const C_DOOR  := Color(0.90, 0.80, 0.64)    # 门洞（浅）
const C_WIN   := Color(0.78, 0.86, 0.90)    # 窗（暖天光）

var g                                   # CornerFishing 主节点
var _aq: Control = null                 # 居中的缩小水族箱
var _rng := RandomNumberGenerator.new()


func setup(host) -> void:
	g = host
	custom_minimum_size = ROOM_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	# 缩小的缸：居中放在房间中央
	_aq = Aquarium.new()
	_aq.name = "Aquarium"
	_aq.setup(g)
	_aq.custom_minimum_size = TANK_SIZE
	add_child(_aq)
	_aq.set_anchors_preset(Control.PRESET_CENTER)   # 不论房间尺寸都居中


func _draw() -> void:
	var sz := size
	# ① 地板（暖奶油底）
	draw_rect(Rect2(0, 0, sz.x, sz.y), C_FLOOR)
	# ② 木地板条纹（俯视：横向木板，极简线条）
	for i in int(sz.y / 28.0) + 1:
		var y := i * 28.0
		draw_line(Vector2(0, y), Vector2(sz.x, y), Color(C_PLANK.r, C_PLANK.g, C_PLANK.b, 0.35), 1.0)
	# ③ 缸下软地毯（暖色椭圆，柔和收住缸脚）
	var tr := _tank_rect()
	var cx := tr.position.x + tr.size.x * 0.5
	var cy := tr.position.y + tr.size.y * 0.5
	var rw := tr.size.x * 0.78
	var rh := tr.size.y * 0.78
	var rug := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		rug.append(Vector2(cx + cos(a) * rw, cy + sin(a) * rh))
	draw_polygon(rug, [Color(C_RUG.r, C_RUG.g, C_RUG.b, 0.35)])
	draw_polyline(rug, Color(C_RUG.r, C_RUG.g, C_RUG.b, 0.5), 1.0, true)
	# ④ 缸在地板上的投影（俯视：缸像落在地毯上的物件，柔影偏下）
	draw_rect(Rect2(tr.position.x, tr.position.y + 5.0, tr.size.x, tr.size.y),
		Color(C_SHADOW.r, C_SHADOW.g, C_SHADOW.b, 0.18))
	# ⑤ 四壁描边（俯视房间轮廓，极简线条）
	var ww := 3.0
	draw_rect(Rect2(0, 0, sz.x, ww), C_WALL)
	draw_rect(Rect2(0, sz.y - ww, sz.x, ww), C_WALL)
	draw_rect(Rect2(0, 0, ww, sz.y), C_WALL)
	draw_rect(Rect2(sz.x - ww, 0, ww, sz.y), C_WALL)
	# ⑥ 门洞（右墙留缺口 + 浅色门扇 + 描边）
	var dh := 70.0
	var dy := (sz.y - dh) * 0.5
	draw_rect(Rect2(sz.x - ww, dy, ww + 1.0, dh), C_DOOR)
	draw_rect(Rect2(sz.x - ww, dy, ww, dh), C_WALL, false, 1.0)   # 门框线
	draw_line(Vector2(sz.x - ww, dy + dh * 0.5), Vector2(sz.x, dy + dh * 0.5),
		Color(C_WALL.r, C_WALL.g, C_WALL.b, 0.6), 1.0)            # 门中缝
	# ⑦ 窗（上墙一小扇，暖天光 + 十字格）
	var ww_w := 54.0
	var wx := (sz.x - ww_w) * 0.5
	var wy := -ww * 0.5
	draw_rect(Rect2(wx, 0, ww_w, ww + 2.0), C_WIN)
	draw_rect(Rect2(wx, 0, ww_w, ww + 2.0), C_WALL, false, 1.0)
	draw_line(Vector2(wx + ww_w * 0.5, 0), Vector2(wx + ww_w * 0.5, ww + 2.0), C_WALL, 1.0)
	draw_line(Vector2(wx, (ww + 2.0) * 0.5), Vector2(wx + ww_w, (ww + 2.0) * 0.5), C_WALL, 1.0)


## 缸在房间局部坐标里的矩形（用于投影/地毯定位）：缸恒为 TANK_SIZE 且居中。
func _tank_rect() -> Rect2:
	return Rect2((size - TANK_SIZE) * 0.5, TANK_SIZE)
