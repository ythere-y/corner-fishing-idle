class_name ProcFish
extends RefCounted

var spine: ProcFishSpine
var species: ProcFishSpecies

## 一条程序化动画的鱼：持有脊椎链(ProcFishSpine)+ 物种蓝图(ProcFishSpecies),自主游动 + 自绘。
## 运动：头部追一个虚拟目标点(自主游荡 + 侧向正弦摆尾),身体经脊椎链柔性跟随 → 真「游」。
## 绘制：忠实移植 .reference/animal-proc-anim 的 Fish.display(鳍→尾→身→背鳍→眼),
##       但所有体型 / 配色 / 花纹常量改读 species → 加种类 / 花纹只动 ProcFishSpecies。
## 变体特效 MVP：配色已在 species 混入;这里叠脉动光晕(鎏金/七彩)+ 七彩环绕流光星点。

var catch_data: Dictionary = {}          # 关联渔获 {id,w,q,var};背景装饰鱼可为空(不可点击)
var idx: int = -1                         # 在 g.display 中的下标(捞回鱼篓用),背景鱼 = -1

var _target: Vector2 = Vector2.ZERO       # 当前游向目标
var _bounds: Rect2 = Rect2()
var _speed: float = 22.0
var _swim_t: float = 0.0
var _swim_freq: float = 2.2               # 摆尾频率
var _wiggle: float = 3.0                  # 侧向摆动幅度(px)
var _pulse_ph: float = 0.0                # 变体光晕脉动相位(各鱼错开)


func setup(sp: ProcFishSpecies, origin: Vector2, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	species = sp
	_bounds = bounds
	spine = ProcFishSpine.new(origin, ProcFishSpecies.TOTAL_JOINTS, sp.link_size, sp.angle_constraint)
	_speed = rng.randf_range(16.0, 30.0)
	_swim_freq = rng.randf_range(1.8, 2.8)
	_wiggle = sp.link_size * rng.randf_range(0.35, 0.6)
	_swim_t = rng.randf() * TAU
	_pulse_ph = rng.randf() * TAU
	_pick_target(rng)


func head() -> Vector2:
	return spine.joints[0]


## 命中判定：点到任一关节的距离 < 该处半宽 * 松弛系数。
func hit(p: Vector2) -> bool:
	for i in spine.joints.size():
		var w: float = species.body_width[i] if i < species.body_width.size() else species.link_size
		if p.distance_to(spine.joints[i]) < maxf(10.0, w * 1.4):
			return true
	return false


func _pick_target(rng: RandomNumberGenerator) -> void:
	var m := 20.0
	_target = Vector2(
		rng.randf_range(_bounds.position.x + m, _bounds.end.x - m),
		rng.randf_range(_bounds.position.y + m, _bounds.end.y - m))


func update(delta: float, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	_bounds = bounds
	_swim_t += delta * _swim_freq
	var h := spine.joints[0]
	var to_t := _target - h
	if to_t.length() < 14.0:
		_pick_target(rng)
		to_t = _target - h
	var dir := to_t.normalized()
	# 侧向正弦摆动 → 头左右微摆 → 身体 S 形跟随(尾巴自然摆)
	var perp := Vector2(-dir.y, dir.x)
	var desired := h + dir * _speed * delta + perp * sin(_swim_t) * _wiggle * delta * 6.0
	# 软边界：贴边则把目标重选到中心侧,避免卡边
	desired.x = clampf(desired.x, bounds.position.x + 6.0, bounds.end.x - 6.0)
	desired.y = clampf(desired.y, bounds.position.y + 6.0, bounds.end.y - 6.0)
	spine.resolve(desired)


# ============================ 绘制 ============================

## 在 canvas 上绘制本鱼。t=全局时间(变体脉动),glow_tex=软光晕图(复用 aquarium 的)。
func draw(ci: CanvasItem, t: float, glow_tex: Texture2D) -> void:
	var j := spine.joints
	var a := spine.angles
	var bw := species.body_width
	var r := _fin_scale()

	# 变体光晕(鎏金/七彩):鱼身中心脉动软光
	var vr := species.variant
	if vr >= 2 and glow_tex != null:
		var mid := j[3]
		var pulse := 0.5 + 0.5 * sin(t * 2.4 + _pulse_ph)
		var vc := FishData.variant_color(vr)
		var gs := species.body_len * (1.1 + 0.25 * pulse)
		ci.draw_texture_rect(glow_tex, Rect2(mid - Vector2(gs, gs) * 0.5, Vector2(gs, gs)),
			false, Color(vc.r, vc.g, vc.b, 0.16 + 0.18 * pulse))

	var head_to_mid1 := ProcFishSpine._relative_angle_diff(a[0], a[6])
	var head_to_mid2 := ProcFishSpine._relative_angle_diff(a[0], a[7])
	var head_to_tail: float = head_to_mid1 + ProcFishSpine._relative_angle_diff(a[6], a[11])

	# —— 胸鳍(joint 3)——
	ci.draw_colored_polygon(_oval(_bp(3, PI / 3.0, 0.0), 80.0 * r, 32.0 * r, a[2] - PI / 4.0), species.fin_color)
	ci.draw_colored_polygon(_oval(_bp(3, -PI / 3.0, 0.0), 80.0 * r, 32.0 * r, a[2] + PI / 4.0), species.fin_color)
	# —— 腹鳍(joint 7)——
	ci.draw_colored_polygon(_oval(_bp(7, PI / 2.0, 0.0), 48.0 * r, 16.0 * r, a[6] - PI / 4.0), species.belly_color)
	ci.draw_colored_polygon(_oval(_bp(7, -PI / 2.0, 0.0), 48.0 * r, 16.0 * r, a[6] + PI / 4.0), species.belly_color)

	# —— 尾鳍(joints 8..11)——
	var tail := PackedVector2Array()
	for i in range(8, 12):
		var tw := 1.5 * head_to_tail * float(i - 8) * float(i - 8)
		tail.append(j[i] + Vector2.from_angle(a[i] - PI / 2.0) * tw)
	for i in range(11, 7, -1):
		var tw := clampf(head_to_tail * 6.0, -13.0, 13.0)
		tail.append(j[i] + Vector2.from_angle(a[i] + PI / 2.0) * tw)
	if tail.size() >= 3:
		ci.draw_colored_polygon(tail, species.fin_color)

	# —— 鱼身 ——
	var body := PackedVector2Array()
	for i in range(0, ProcFishSpecies.BODY_JOINTS):        # 右半
		body.append(_bp(i, PI / 2.0, 0.0))
	body.append(_bp(ProcFishSpecies.BODY_JOINTS - 1, PI, 0.0))   # 尾端
	for i in range(ProcFishSpecies.BODY_JOINTS - 1, -1, -1):     # 左半
		body.append(_bp(i, -PI / 2.0, 0.0))
	body.append(_bp(0, -PI / 6.0, 0.0))                      # 头顶收口
	body.append(_bp(0, 0.0, bw[0] * 0.06))
	body.append(_bp(0, PI / 6.0, 0.0))
	if body.size() >= 3:
		ci.draw_colored_polygon(body, species.body_color)
		# 顶部一抹高光,给体积(克制)
		var hi := PackedVector2Array()
		for i in range(0, ProcFishSpecies.BODY_JOINTS):
			hi.append(_bp(i, -PI / 2.0, 0.0))
		var hcol := species.fin_color.lightened(0.15)
		hcol.a = 0.35
		ci.draw_polyline(hi, hcol, maxf(1.0, r * 6.0), true)

	# —— 花纹(MVP:叠在鱼身上,半透明)——
	_draw_pattern(ci, head_to_tail)

	# —— 背鳍(joints 4..7,贝塞尔近似 → 采样多边形)——
	var dorsal := _dorsal_shape(head_to_mid1, head_to_mid2)
	if dorsal.size() >= 3:
		ci.draw_colored_polygon(dorsal, species.fin_color)

	# —— 眼 ——
	var eye_r := maxf(2.0, 12.0 * r)
	var el := _bp(0, PI / 2.0, -18.0 * r)
	var er := _bp(0, -PI / 2.0, -18.0 * r)
	ci.draw_circle(el, eye_r, Color(1, 1, 1, 0.95))
	ci.draw_circle(er, eye_r, Color(1, 1, 1, 0.95))
	ci.draw_circle(el, eye_r * 0.5, Color(0.08, 0.09, 0.11))
	ci.draw_circle(er, eye_r * 0.5, Color(0.08, 0.09, 0.11))

	# —— 七彩:环绕流光星点 ——
	if vr >= 3:
		var c := j[3]
		for k in 3:
			var ang := t * 2.0 + k * TAU / 3.0
			var rp := species.body_len * 0.4
			var sp := c + Vector2(cos(ang), sin(ang) * 0.6) * rp
			var sa := 0.4 + 0.4 * sin(t * 4.0 + k)
			ci.draw_circle(sp, maxf(1.2, r * 8.0), Color(0.98, 0.92, 1.0, sa))


## 花纹绘制分支(扩展点:加 Pattern 枚举 → 加一个分支)。
func _draw_pattern(ci: CanvasItem, head_to_tail: float) -> void:
	match species.pattern:
		ProcFishSpecies.Pattern.STRIPES:
			for i in [2, 4, 6]:
				var top := _bp(i, -PI / 2.0, 0.0)
				var bot := _bp(i, PI / 2.0, 0.0)
				ci.draw_line(top, bot, species.pattern_color, maxf(1.5, species.link_size * 0.4), true)
		ProcFishSpecies.Pattern.SPOTS:
			for i in [2, 4, 5, 7]:
				var c := spine.joints[i]
				var rad: float = species.body_width[i] * 0.28 if i < species.body_width.size() else 2.0
				ci.draw_circle(c, maxf(1.5, rad), species.pattern_color)
		_:
			pass


## 背鳍：joints 4→7 上缘,一条三次贝塞尔回到 4(参考 Fish.pde 的 bezierVertex);采样成多边形。
func _dorsal_shape(h2m1: float, h2m2: float) -> PackedVector2Array:
	var j := spine.joints
	var a := spine.angles
	var p0 := j[4]
	var p3 := j[7]
	# 去程曲线(沿脊背)控制点 = j5,j6;回程控制点把鳍鼓起来
	var c1 := j[5]
	var c2 := j[6]
	var back_c1 := Vector2(j[6].x + cos(a[6] + PI / 2.0) * h2m2 * 16.0, j[6].y + sin(a[6] + PI / 2.0) * h2m2 * 16.0)
	var back_c2 := Vector2(j[5].x + cos(a[5] + PI / 2.0) * h2m1 * 16.0, j[5].y + sin(a[5] + PI / 2.0) * h2m1 * 16.0)
	var pts := PackedVector2Array()
	var segs := 8
	for s in segs + 1:                     # p0 → p3 沿脊背
		pts.append(_bezier(p0, c1, c2, p3, float(s) / float(segs)))
	for s in segs + 1:                     # p3 → p0 鼓起的外缘
		pts.append(_bezier(p3, back_c1, back_c2, p0, float(s) / float(segs)))
	return pts


static func _bezier(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, tt: float) -> Vector2:
	var u := 1.0 - tt
	return u * u * u * p0 + 3.0 * u * u * tt * c1 + 3.0 * u * tt * tt * c2 + tt * tt * tt * p1


## 鱼鳍 / 眼相对参考(head half-width≈84px)的等比缩放系数。
func _fin_scale() -> float:
	var actual := 0.0
	for w in species.body_width:
		actual = maxf(actual, w)
	return actual / 84.0   # 84 = 参考 Fish.pde 头部半宽基准


## body-space 取点：joint i 沿其法向偏 angle_offset、外扩 (body_width[i] + len_offset)。移植 getPosX/Y。
func _bp(i: int, angle_offset: float, len_offset: float) -> Vector2:
	var w: float = species.body_width[i] if i < species.body_width.size() else species.link_size
	return spine.joints[i] + Vector2.from_angle(spine.angles[i] + angle_offset) * (w + len_offset)


## 椭圆 → 多边形(旋转 rot)。draw_colored_polygon 用。
static func _oval(center: Vector2, rx: float, ry: float, rot: float, segs: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var ang := TAU * float(i) / float(segs)
		pts.append(center + Vector2(cos(ang) * rx, sin(ang) * ry).rotated(rot))
	return pts
