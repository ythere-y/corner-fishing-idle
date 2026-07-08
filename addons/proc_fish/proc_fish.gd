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
var _vel: Vector2 = Vector2.ZERO          # 带惯性的头部速度，避免直线追点的呆板感
var _speed: float = 22.0
var _heading: float = 0.0                 # 当前航向。只按角速度渐变，避免突然掉头。
var _swim_t: float = 0.0
var _swim_freq: float = 2.2               # 摆尾频率
var _wiggle: float = 3.0                  # 侧向摆动幅度(px)
var _pulse_ph: float = 0.0                # 变体光晕脉动相位(各鱼错开)
var _turn_rate: float = 1.65              # 最大转向角速度(rad/s)：限制大角度转身


func setup(sp: ProcFishSpecies, origin: Vector2, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	species = sp
	_bounds = bounds
	spine = ProcFishSpine.new(origin, ProcFishSpecies.TOTAL_JOINTS, sp.link_size, sp.angle_constraint)
	_speed = rng.randf_range(16.0, 30.0) * sp.speed_mult
	_swim_freq = rng.randf_range(1.8, 2.8) * sp.tail_freq_mult
	_wiggle = sp.link_size * rng.randf_range(0.35, 0.6) * sp.wiggle_mult
	_turn_rate = rng.randf_range(1.25, 2.1) * sp.turn_rate_mult
	_swim_t = rng.randf() * TAU
	_pulse_ph = rng.randf() * TAU
	_pick_target(rng)
	var initial_dir := (_target - origin).normalized()
	if initial_dir.length() <= 0.01:
		initial_dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
	_heading = initial_dir.angle()
	_vel = Vector2.from_angle(_heading) * _speed


func head() -> Vector2:
	return spine.joints[0]


## 命中判定：点到任一关节的距离 < 该处半宽 * 松弛系数。
func hit(p: Vector2) -> bool:
	for i in spine.joints.size():
		var w: float = species.body_width[i] if i < species.body_width.size() else species.link_size
		if p.distance_to(spine.joints[i]) < maxf(10.0, w * 1.4):
			return true
	return false


func _pick_target(rng: RandomNumberGenerator, center_bias: bool = false) -> void:
	var max_margin := maxf(4.0, minf(_bounds.size.x, _bounds.size.y) * 0.42)
	var m := minf(maxf(22.0, species.body_len * 0.35), max_margin)
	var min_x := _bounds.position.x + m
	var max_x := _bounds.end.x - m
	var min_y := _bounds.position.y + m
	var max_y := _bounds.end.y - m
	if center_bias:
		var center := _bounds.get_center()
		var half := _bounds.size * 0.28
		if species.swim_mode == ProcFishSpecies.SwimMode.HOVER:
			half = _bounds.size * 0.18
		elif species.swim_mode == ProcFishSpecies.SwimMode.DEEP_DRIFT:
			half = _bounds.size * 0.22
		min_x = maxf(min_x, center.x - half.x)
		max_x = minf(max_x, center.x + half.x)
		min_y = maxf(min_y, center.y - half.y)
		max_y = minf(max_y, center.y + half.y)
	if min_x > max_x:
		min_x = _bounds.get_center().x
		max_x = min_x
	if min_y > max_y:
		min_y = _bounds.get_center().y
		max_y = min_y
	_target = Vector2(
		rng.randf_range(min_x, max_x),
		rng.randf_range(min_y, max_y))


func update(delta: float, bounds: Rect2, rng: RandomNumberGenerator) -> void:
	_bounds = bounds
	_swim_t += delta * _swim_freq
	var h := spine.joints[0]
	var to_t := _target - h
	if to_t.length() < maxf(18.0, species.body_len * 0.42):
		_pick_target(rng)
		to_t = _target - h
	var dist := maxf(to_t.length(), 0.001)
	var dir := to_t / dist
	# 边界不再反弹速度，而是持续给一个回到缸内的航向偏置，避免贴边时突然掉头。
	var edge := maxf(14.0, species.body_len * 0.20)
	var avoid := Vector2.ZERO
	if h.x < bounds.position.x + edge:
		avoid.x += 1.0 - clampf((h.x - bounds.position.x) / edge, 0.0, 1.0)
	elif h.x > bounds.end.x - edge:
		avoid.x -= 1.0 - clampf((bounds.end.x - h.x) / edge, 0.0, 1.0)
	if h.y < bounds.position.y + edge:
		avoid.y += 1.0 - clampf((h.y - bounds.position.y) / edge, 0.0, 1.0)
	elif h.y > bounds.end.y - edge:
		avoid.y -= 1.0 - clampf((bounds.end.y - h.y) / edge, 0.0, 1.0)
	if avoid.length() > 0.01:
		dir = (dir + avoid.normalized() * 1.8).normalized()
		if h.distance_to(_target) < edge * 1.4:
			_pick_target(rng, true)
	# 航向按最大角速度旋过去，大角度转身会走弧线，不会一帧翻面。
	_heading = _rotate_toward_angle(_heading, dir.angle(), _turn_rate * delta)
	var cruise := _speed * lerpf(0.72, 1.10, clampf(dist / maxf(bounds.size.length() * 0.35, 1.0), 0.0, 1.0))
	var mode_wave := 1.0
	match species.swim_mode:
		ProcFishSpecies.SwimMode.DART:
			mode_wave = 0.78 + 0.52 * pow(maxf(0.0, sin(_swim_t * 0.9 + _pulse_ph)), 4.0)
			cruise *= mode_wave
		ProcFishSpecies.SwimMode.HOVER:
			cruise *= 0.72 + 0.18 * sin(_swim_t * 0.55 + _pulse_ph)
		ProcFishSpecies.SwimMode.EEL:
			cruise *= 0.86 + 0.20 * sin(_swim_t * 0.45 + _pulse_ph)
		ProcFishSpecies.SwimMode.GLIDE:
			cruise *= 0.76 + 0.10 * sin(_swim_t * 0.35 + _pulse_ph)
		ProcFishSpecies.SwimMode.DEEP_DRIFT:
			cruise *= 0.66 + 0.08 * sin(_swim_t * 0.30 + _pulse_ph)
	var desired_vel := Vector2.from_angle(_heading) * cruise
	_vel = _vel.lerp(desired_vel, clampf(delta * 3.0, 0.0, 1.0))
	var move_dir := Vector2.from_angle(_heading)
	var perp := Vector2(-move_dir.y, move_dir.x)
	var wander_amp := 0.55
	match species.swim_mode:
		ProcFishSpecies.SwimMode.EEL:
			wander_amp = 0.92
		ProcFishSpecies.SwimMode.HOVER:
			wander_amp = 0.32
		ProcFishSpecies.SwimMode.GLIDE:
			wander_amp = 0.22
		ProcFishSpecies.SwimMode.DEEP_DRIFT:
			wander_amp = 0.28
	var wander := perp * sin(_swim_t * 0.72 + _pulse_ph) * _wiggle * wander_amp
	var desired := h + (_vel + wander) * delta
	var min_x := bounds.position.x + edge
	var max_x := bounds.end.x - edge
	var min_y := bounds.position.y + edge
	var max_y := bounds.end.y - edge
	if min_x > max_x:
		min_x = bounds.get_center().x
		max_x = min_x
	if min_y > max_y:
		min_y = bounds.get_center().y
		max_y = min_y
	var clamped := Vector2(clampf(desired.x, min_x, max_x), clampf(desired.y, min_y, max_y))
	if clamped.distance_squared_to(h) < 0.01 and avoid.length() > 0.01:
		_heading = avoid.angle()
		_vel = avoid.normalized() * _speed * 0.65
		clamped = Vector2(clampf(h.x + _vel.x * delta, min_x, max_x), clampf(h.y + _vel.y * delta, min_y, max_y))
	desired = clamped
	spine.resolve(desired)


static func _rotate_toward_angle(from_angle: float, to_angle: float, max_step: float) -> float:
	var diff := fposmod(to_angle - from_angle + PI, TAU) - PI
	if absf(diff) <= max_step:
		return ProcFishSpine._simplify_angle(to_angle)
	return ProcFishSpine._simplify_angle(from_angle + signf(diff) * max_step)


# ============================ 绘制 ============================

## 在 canvas 上绘制本鱼。t=全局时间(变体脉动),glow_tex=软光晕图(复用 aquarium 的)。
func draw(ci: CanvasItem, t: float, glow_tex: Texture2D) -> void:
	var j := spine.joints
	var a := spine.angles
	var bw := species.body_width
	var r := _fin_scale()

	# 变体光晕(鎏金/七彩):鱼身中心脉动软光
	var vr := species.variant
	if (vr >= 2 or species.glow_mult > 0.05) and glow_tex != null:
		var mid := j[3]
		var pulse := 0.5 + 0.5 * sin(t * 2.4 + _pulse_ph)
		var vc := FishData.variant_color(vr) if vr >= 1 else species.pattern_color
		var gs := species.body_len * (0.78 + species.glow_mult + 0.20 * pulse)
		ci.draw_texture_rect(glow_tex, Rect2(mid - Vector2(gs, gs) * 0.5, Vector2(gs, gs)),
			false, Color(vc.r, vc.g, vc.b, clampf(0.07 + species.glow_mult * 0.16 + 0.12 * pulse, 0.06, 0.36)))

	var head_to_mid1 := clampf(ProcFishSpine._relative_angle_diff(a[0], a[6]), -0.95, 0.95)
	var head_to_mid2 := clampf(ProcFishSpine._relative_angle_diff(a[0], a[7]), -0.95, 0.95)
	var head_to_tail: float = clampf(head_to_mid1 + ProcFishSpine._relative_angle_diff(a[6], a[11]), -1.15, 1.15)

	# —— 胸鳍(joint 3)——
	ci.draw_colored_polygon(_oval(_bp(3, PI / 3.0, 0.0), 80.0 * r * species.pectoral_mult,
		32.0 * r * species.pectoral_mult, a[2] - PI / 4.0), species.fin_color)
	ci.draw_colored_polygon(_oval(_bp(3, -PI / 3.0, 0.0), 80.0 * r * species.pectoral_mult,
		32.0 * r * species.pectoral_mult, a[2] + PI / 4.0), species.fin_color)
	# —— 腹鳍(joint 7)——
	ci.draw_colored_polygon(_oval(_bp(7, PI / 2.0, 0.0), 48.0 * r * species.pectoral_mult,
		16.0 * r * species.pectoral_mult, a[6] - PI / 4.0), species.belly_color)
	ci.draw_colored_polygon(_oval(_bp(7, -PI / 2.0, 0.0), 48.0 * r * species.pectoral_mult,
		16.0 * r * species.pectoral_mult, a[6] + PI / 4.0), species.belly_color)

	# —— 尾鳍(joints 8..11)——
	var tail := PackedVector2Array()
	for i in range(8, 12):
		var tw := clampf(1.5 * head_to_tail * float(i - 8) * float(i - 8) * species.tail_mult, -18.0, 18.0)
		tail.append(j[i] + Vector2.from_angle(a[i] - PI / 2.0) * tw)
	for i in range(11, 7, -1):
		var tw := clampf(head_to_tail * 6.0 * species.tail_mult, -16.0, 16.0)
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

	# —— 背鳍(joints 4..7)：用粗曲线代替闭合多边形，避免急转时自交导致三角剖分闪烁。
	var dorsal := _dorsal_curve(head_to_mid1, head_to_mid2)
	if dorsal.size() >= 2:
		var dcol := species.fin_color
		dcol.a *= 0.82
		ci.draw_polyline(dorsal, dcol, maxf(1.4, r * 8.0 * species.dorsal_mult), true)

	# —— 眼 ——
	var eye_r := maxf(2.0, 12.0 * r * species.eye_mult)
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
	elif species.sparkle_mult > 0.16:
		var c := j[4]
		var count := 2 + int(round(species.sparkle_mult * 3.0))
		for k in count:
			var ph := t * (1.5 + 0.12 * k) + _pulse_ph + float(k) * 1.9
			var rp := species.body_len * (0.22 + 0.04 * float(k % 3))
			var sp := c + Vector2(cos(ph), sin(ph * 1.17)) * rp
			var sa := 0.18 + 0.18 * sin(t * 3.3 + k)
			ci.draw_circle(sp, maxf(1.0, r * 4.8), Color(species.pattern_color.r, species.pattern_color.g, species.pattern_color.b, sa))


## 花纹绘制分支(扩展点:加 Pattern 枚举 → 加一个分支)。
func _draw_pattern(ci: CanvasItem, head_to_tail: float) -> void:
	match species.pattern:
		ProcFishSpecies.Pattern.STRIPES:
			for i in [2, 4, 6]:
				var top := _bp(i, -PI / 2.0, 0.0)
				var bot := _bp(i, PI / 2.0, 0.0)
				ci.draw_line(top, bot, species.pattern_color, maxf(1.5, species.link_size * 0.4), true)
		ProcFishSpecies.Pattern.SPOTS:
			var spots := [2, 4, 5, 7]
			if species.pattern_density > 1.25:
				spots = [1, 2, 4, 5, 6, 7]
			for i in spots:
				var c := spine.joints[i]
				var rad: float = species.body_width[i] * 0.28 * species.pattern_scale if i < species.body_width.size() else 2.0
				ci.draw_circle(c, maxf(1.5, rad), species.pattern_color)
		ProcFishSpecies.Pattern.BLOTCHES:
			for i in [2, 4, 6]:
				var c := spine.joints[i]
				var rad: float = species.body_width[i] * 0.42 * species.pattern_scale if i < species.body_width.size() else 3.0
				ci.draw_colored_polygon(_oval(c, maxf(2.0, rad * 1.25), maxf(1.4, rad * 0.72),
					spine.angles[i] + sin(float(i) * 1.7) * 0.65, 10), species.pattern_color)
		ProcFishSpecies.Pattern.LATERAL_LINE:
			var pts := PackedVector2Array()
			for i in range(1, ProcFishSpecies.BODY_JOINTS - 1):
				pts.append(spine.joints[i] + Vector2.from_angle(spine.angles[i] - PI / 2.0) * species.body_width[i] * 0.18)
			if pts.size() >= 2:
				ci.draw_polyline(pts, species.pattern_color, maxf(1.2, species.link_size * 0.22), true)
		ProcFishSpecies.Pattern.RINGS:
			for i in [2, 4, 6]:
				var c := spine.joints[i]
				var rad: float = species.body_width[i] * 0.55 * species.pattern_scale if i < species.body_width.size() else 3.0
				ci.draw_arc(c, maxf(2.0, rad), 0.0, TAU, 18, species.pattern_color, maxf(1.0, species.link_size * 0.16), true)
		ProcFishSpecies.Pattern.BIOLUMEN:
			for i in [1, 3, 5, 7]:
				var side := -1.0 if i % 2 == 0 else 1.0
				var p := _bp(i, side * PI / 2.0, -species.body_width[i] * 0.45)
				ci.draw_circle(p, maxf(1.1, species.link_size * 0.14 * species.pattern_scale), species.pattern_color)
		_:
			pass


## 背鳍：joints 4→7 上缘的一条稳定曲线。早期闭合多边形在急转时可能自交，触发 triangulation failed。
func _dorsal_curve(h2m1: float, h2m2: float) -> PackedVector2Array:
	var j := spine.joints
	var a := spine.angles
	var p0 := j[4] + Vector2.from_angle(a[4] + PI / 2.0) * h2m1 * 4.0
	var p3 := j[7] + Vector2.from_angle(a[7] + PI / 2.0) * h2m2 * 4.0
	var c1 := j[5] + Vector2.from_angle(a[5] + PI / 2.0) * h2m1 * 13.0 * species.dorsal_mult
	var c2 := j[6] + Vector2.from_angle(a[6] + PI / 2.0) * h2m2 * 13.0 * species.dorsal_mult
	var pts := PackedVector2Array()
	var segs := 8
	for s in segs + 1:
		pts.append(_bezier(p0, c1, c2, p3, float(s) / float(segs)))
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
