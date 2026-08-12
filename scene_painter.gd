extends Node2D
## 角落垂钓 · 场景绘制
## 优先用 Codex 产出的真实美术；缺失时回退程序化绘制。
## 动态效果层按 docs/dynamic_art_plan.md 接入（全部透明叠加，只播放不修改资源）：
##   雾气微风 / 水流高光循环 / 雪粒漂移 / 小动物低频事件 / 浮漂涟漪 / 灯光呼吸
## 最上层另叠程序化「水彩纸纹」（见 _build_paper_texture / _draw_paper_layer），统一全画面气质。
## main.gd 钓鱼状态机通过 dip / add_ripple() 驱动浮标与水花。

const W := 520.0
const H := 400.0
const HORIZON := 206.0

# 合成主图模式下的咬钩点（= 主图里画的小浮漂/钓线落水处），涟漪/飘字以此为锚。
# 默认值按当前主图实测；main.gd 可从 ui_layout.json 覆盖（Codex 美术更新时同步）。
var bite_point := Vector2(384, 344)

# 浮漂精灵缩放：资源 128×128 水彩浮漂（idle/bite 同画幅），按场景比例缩小到 ~15px。
const BOBBER_SCALE := 0.12
# 灯光呼吸锚点回退值（dynamic_art_plan.md 给定的近似位置；
# 实际锚点在 _ready 里扫描主图暖色像素质心自动定位，主图更新也不会错位）
const LANTERN_POS := Vector2(438, 274)

# —— 程序化回退配色 ——
const C_GLOW := Color(0.97, 0.91, 0.80)
const C_MT_FAR := Color(0.64, 0.69, 0.75)
const C_SNOW := Color(0.94, 0.96, 0.97)
const C_PINE := Color(0.34, 0.46, 0.43)
const C_PINE_HI := Color(0.45, 0.55, 0.50)
const C_WATER_TOP := Color(0.69, 0.80, 0.82)
const C_WATER_BOT := Color(0.50, 0.64, 0.71)
const C_SHIMMER := Color(0.96, 0.98, 0.98)
const C_SNOWBANK := Color(0.89, 0.91, 0.91)
const C_ROCK := Color(0.55, 0.56, 0.57)
const C_COAT := Color(0.44, 0.47, 0.39)
const C_DARK := Color(0.28, 0.28, 0.26)
const C_SKIN := Color(0.80, 0.72, 0.62)
const C_LANTERN := Color(1.0, 0.84, 0.48)

# 昼夜底图慢交叉淡入秒数（背景按时段切换时不硬切，缓慢 crossfade）。
const SPOT_FADE_DUR := 90.0

var t := 0.0
var dip := 0.0
var use_composite := false
var _base: Texture2D
var _spot_base: Texture2D = null   # 当前钓点底图（缺图回退到 _base，不崩）
var _spot_prev: Texture2D = null   # crossfade 中正在淡出的上一张底图
var _spot_fade := 1.0              # crossfade 进度 0→1（1=完成，无活动淡入）
var _spot_key := ""                # 当前钓点 bg_key（决定底图族）
var _spot_phase := ""              # 当前昼夜阶段 dawn/day/dusk/night（决定时段图）
var _fisher: Texture2D             # 独立渔夫精灵（含鱼竿），叠加到所有干净底图上
var _lantern_tex: Texture2D        # 独立灯笼精灵，叠加到所有干净底图上

# 统一叠加层锚点（art 空间）。所有钓场底图都是纯风景，渔夫/灯笼/钓线/浮漂都由代码叠加。
const FISHER_SCALE := 0.30   # 渔夫精灵原 192px → ~58px，坐右岸
var fisher_anchor := Vector2(430, 300)   # 渔夫脚底中心
var fisher_flip := false
const LANTERN_SCALE := 0.34  # 灯笼精灵原 96px → ~33px，立在渔夫旁
var lantern_anchor := Vector2(462, 286)  # 灯笼底部中心（渔夫右侧岸上）
var rod_tip_off := Vector2(-24, -47)     # 竿尖相对 fisher_anchor 的偏移（钓线起点，对准精灵里画的竿尖）
var phase_tint := Color(0, 0, 0, 0)  # 昼夜时段染色（A=0 不染色），main 经 set_phase_tint 设置

# —— 连续昼夜调色（新）：随真实时钟连续推移的竖向渐变 wash，取代旧的全屏平涂染色 ——
# use_grade=true 走新调色；false 回退旧 _draw_phase_tint（供 A/B 对比 / 截图）。
var use_grade := true
var debug_tod := -1.0                 # ≥0 强制该时刻（小时 0..24），供截图；<0 用真实时钟
var _tod := 12.0                      # 当前连续时刻 0..24
var _spot_has_phase_art := false      # 当前底图是否分时段手绘（true→调色只做轻统一，避免双重染色）
var _gp: Dictionary = {"sky": Color(1, 1, 1), "horizon": Color(1, 1, 1), "water": Color(1, 1, 1), "alpha": 0.0, "glow": 0.0}

# 昼夜调色关键帧（按真实小时 h 排序，0..24 环绕插值）：
# sky/horizon/water = 天空/地平线/水面三段色；alpha = 叠加强度；glow = 灯光增益。
# 正午 alpha=0（不叠加），黎明/黄昏暖、夜晚冷而暗；地平线在绘制时更通透，让暖光"透出来"。
const _GRADE_KEYS := [
	{"h": 0.0,  "sky": Color(0.06, 0.08, 0.20), "horizon": Color(0.12, 0.14, 0.30), "water": Color(0.03, 0.05, 0.15), "alpha": 0.66, "glow": 1.00},
	{"h": 5.0,  "sky": Color(0.20, 0.20, 0.38), "horizon": Color(0.46, 0.36, 0.46), "water": Color(0.12, 0.14, 0.28), "alpha": 0.52, "glow": 0.72},
	{"h": 6.5,  "sky": Color(0.56, 0.56, 0.74), "horizon": Color(0.99, 0.72, 0.55), "water": Color(0.50, 0.52, 0.62), "alpha": 0.32, "glow": 0.44},
	{"h": 9.0,  "sky": Color(0.93, 0.96, 1.00), "horizon": Color(1.00, 0.98, 0.95), "water": Color(0.90, 0.94, 0.97), "alpha": 0.06, "glow": 0.06},
	{"h": 12.0, "sky": Color(1.00, 1.00, 1.00), "horizon": Color(1.00, 1.00, 1.00), "water": Color(1.00, 1.00, 1.00), "alpha": 0.00, "glow": 0.00},
	{"h": 15.5, "sky": Color(1.00, 0.98, 0.92), "horizon": Color(1.00, 0.95, 0.86), "water": Color(0.96, 0.95, 0.92), "alpha": 0.07, "glow": 0.10},
	{"h": 17.5, "sky": Color(0.80, 0.66, 0.70), "horizon": Color(1.00, 0.74, 0.46), "water": Color(0.70, 0.60, 0.62), "alpha": 0.30, "glow": 0.48},
	{"h": 18.8, "sky": Color(0.28, 0.26, 0.50), "horizon": Color(0.98, 0.48, 0.38), "water": Color(0.24, 0.24, 0.46), "alpha": 0.50, "glow": 0.78},
	{"h": 20.5, "sky": Color(0.09, 0.11, 0.26), "horizon": Color(0.22, 0.18, 0.36), "water": Color(0.05, 0.07, 0.20), "alpha": 0.62, "glow": 0.96},
]
var _water_overlay: Texture2D     # 旧版波光叠层（无新版帧动画时的回退）
var _bobber_idle: Texture2D
var _bobber_bite: Texture2D
var _bobber := Vector2(296, HORIZON + 80)
var _rod_tip := Vector2(338, 244)
var _ripples: Array = []

# —— 动态效果层（Codex 资源，缺失自动跳过对应效果）——
var _shimmer_tex: Array = []      # 6 帧水流高光
var _mist_tex: Array = []         # 3 层雾气
var _snow_tex: Array = []         # 3 层雪粒
var _ripple_tex: Array = []       # 4 帧浮漂涟漪
var _glow_tex: Array = []         # 4 帧灯光呼吸
var _wild_tex: Dictionary = {}    # 小动物事件精灵（bird=帧数组，其余=单帧）
var _wild_alt: Dictionary = {}    # 可选副帧：bird_glide/rabbit_alert/fox_retreat/fish_jump_02（缺则忽略）

var _mist_par: Array = []         # 每层 {period, amp, phase, alpha}
var _snow_par: Array = []         # 每层 {period, dist, phase, alpha}
var _shimmer_period := 6.0
var _glow_period := 4.5
var _pulse_t := 8.0               # 浮漂待机涟漪计时

# 小动物事件状态
var quiet := false      # 专注模式：停小动物低频事件
var _wild_kind := ""
var _wild_t := 0.0
var _wild_dur := 0.0
var _wild_from := Vector2.ZERO
var _wild_to := Vector2.ZERO
var _wild_scale := 0.25
var _wild_timer := 60.0
var _lantern := LANTERN_POS
var _prng := RandomNumberGenerator.new()

# —— 上鱼庆祝闪光：仅稀有时触发，柔和暖色脉冲，走场景羽化层（不铺满整窗、不染桌面）——
const FLASH_DUR := 0.6
var _flash_t := 0.0

# —— 稀有仪式三件套（P0 好玩补丁）：咬钩驻留金环 / 入手金光粒子 / 水面号外纸条。
# 全部纯程序绘制、零外部资源、零存档；main 侧一律经 has_method 守卫调用。
var _bite_glow_t := 0.0                       # 稀有咬钩驻留剩余秒数（>0 时浮漂处画脉动金环）
var _bite_glow_col := Color(1.0, 0.86, 0.45)  # 金环颜色（随变体色）
var _sparks: Array = []                       # 金光粒子 {pos, vel, life, max, size, col}
var _news_text := ""                          # 号外纸条文字（空=不显示）
var _news_t := 0.0
const NEWS_DUR := 9.0                         # 号外漂过水面的总时长（秒）

# —— 水彩纸纹层：程序化生成的极淡冷压纸颗粒，铺满整幅场景、叠在所有内容之上。
# 走 painter 自身的羽化材质，会和场景一起向左上消散；把"干净插画"统一成"隔着一层手工纸"的水彩气质。
# 整幅一次性生成（与场景同尺寸，无平铺缝），零外部资源、零存档；带框/沉浸两态通用。
const PAPER_ALPHA := 0.055   # 颗粒峰值透明度（极淡，只做质感不夺画面）
var paper_grain := true
var _paper_tex: Texture2D = null

# —— 渔夫情绪 / 桌面宠物（Task 4）：尽量零存档、瞬态，用变换驱动 ——
var _fisher_pull: Array = []        # 收竿/上鱼姿势帧（咬钩时切换，给渔夫加动作）
var _fisher_mood_tex: Dictionary = {}  # 可选情绪帧 idle_breath/shiver/doze/cheer（缺则回退 idle+变换）
var fisher_mood := "idle"           # idle / cheer / yawn / shiver / doze
var _fisher_pull_pose := 0.0         # Smoothed 0..1 pull pose, driven by dip.
var _mood_t := 0.0                  # 当前非 idle 情绪剩余时长
var _mood_dur := 1.0
var _mood_gap := 10.0               # 距下一次环境小情绪
var ctx_night := false              # 由 main 喂入：夜间时段
var ctx_idle := false              # 由 main 喂入：久未操作
var pet_anchor := Vector2(410, 305) # 小馋猫坐处（脚底中心，渔夫左前的雪岸上）
var pet_action := ""                # "" idle / paw / steal
var _pet_action_t := 0.0
var _pet_action_dur := 1.0
var _pet_blink_t := 3.0

# —— 小馋猫正式 sprite（Codex 96x96 透明帧；缺失自动回退程序化猫）——
const PET_SPRITE_SCALE := 0.30   # 比渔夫(~58px)明显小，退成环境配角，不压主体/背景
const PET_MODULATE := Color(0.95, 0.96, 1.0, 0.90)  # 冷灰已烤进贴图，这里只极轻偏冷 + 略降透明使其后退
const PET_STATE_BLEND_DUR := 0.24
var _pet_tex: Dictionary = {}
var _pet_shadow_tex: Texture2D = null   # 烘焙柔和接触阴影（缺图回退淡椭圆，杜绝悬浮感）
var _pet_paths := {
	"idle": "res://assets/art/pets/cat_idle.png",
	"blink": "res://assets/art/pets/cat_blink.png",
	"paw": "res://assets/art/pets/cat_paw.png",
	"steal": "res://assets/art/pets/cat_steal.png",
	"sleep": "res://assets/art/pets/cat_sleep.png",
	"tail_01": "res://assets/art/pets/cat_tail_01.png",
	"tail_02": "res://assets/art/pets/cat_tail_02.png",
}
var _pet_tail_t := 8.0       # 距下次轻摆尾（idle 低频小事件）
var _pet_tail_active := 0.0  # 当前摆尾剩余时长
var _pet_draw_key := "idle"
var _pet_prev_key := "idle"
var _pet_blend_t := PET_STATE_BLEND_DUR


func _ready() -> void:
	_prng.randomize()
	# 默认/回退底图用干净河湾（不再用烤死渔夫的旧图）；正常情况 set_spot 会按钓点覆盖
	_base = _tex("res://assets/art/background/spot_river_bend.png")
	_water_overlay = _tex("res://assets/art/background/water_highlight_overlay.png")
	_bobber_idle = _tex("res://assets/art/props/bobber_idle.png")
	_bobber_bite = _tex("res://assets/art/props/bobber_bite.png")
	_fisher = _tex("res://assets/art/character/fisher_idle.png")
	_fisher_pull = _frames("res://assets/art/character/fisher_pull_%02d.png", 2)
	_lantern_tex = _tex("res://assets/art/props/lantern.png")
	use_composite = _base != null
	# 动态效果层
	_shimmer_tex = _frames("res://assets/art/effects/water/water_shimmer_%02d.png", 6)
	_mist_tex = _frames("res://assets/art/effects/mist/mist_drift_%02d.png", 3)
	_snow_tex = _frames("res://assets/art/effects/snow/snow_drift_%02d.png", 3)
	_ripple_tex = _frames("res://assets/art/effects/ripple/bobber_ripple_%02d.png", 4)
	_glow_tex = _frames("res://assets/art/effects/light/lantern_glow_%02d.png", 4)
	# 渔夫情绪帧（可选，缺则回退 fisher_idle + 变换驱动）
	for k in ["idle_breath", "shiver", "doze", "cheer"]:
		var ftx := _tex("res://assets/art/character/fisher_%s.png" % k)
		if ftx != null:
			_fisher_mood_tex[k] = ftx
	# 飞鸟：优先多帧扇翅循环（bird_fly_01..03），缺则回退单帧 bird_fly_01（仍可代码扇翅）
	var bird_frames := _frames("res://assets/art/wildlife/bird_fly_%02d.png", 3)
	if bird_frames.is_empty():
		var b1 := _tex("res://assets/art/wildlife/bird_fly_01.png")
		if b1 != null:
			bird_frames = [b1]
	if not bird_frames.is_empty():
		_wild_tex["bird"] = bird_frames
	for k in ["rabbit_idle_01", "fox_peek_01", "fish_jump_01"]:
		var tx := _tex("res://assets/art/wildlife/%s.png" % k)
		if tx != null:
			_wild_tex[k.get_slice("_", 0)] = tx
	# 可选副帧（缺则该效果优雅跳过，事件仍用主帧正常播放）
	for pair in [["bird_glide", "bird_glide_01"], ["rabbit_alert", "rabbit_alert_01"],
			["fox_retreat", "fox_retreat_01"], ["fish_jump_02", "fish_jump_02"]]:
		var atx := _tex("res://assets/art/wildlife/%s.png" % pair[1])
		if atx != null:
			_wild_alt[pair[0]] = atx
	# 小馋猫正式 sprite（缺任一帧则该帧回退程序化猫）
	for k in _pet_paths.keys():
		var ptx := _tex(_pet_paths[k])
		if ptx != null:
			_pet_tex[k] = ptx
	_pet_shadow_tex = _tex("res://assets/art/pets/cat_shadow_soft.png")
	# 每层随机参数 + 随机相位（避免所有循环同步重启，plan 的 Motion Rules）
	_shimmer_period = _prng.randf_range(4.2, 5.5)
	_glow_period = _prng.randf_range(3.5, 5.5)
	for i in _mist_tex.size():
		_mist_par.append({
			"period": _prng.randf_range(18.0, 35.0),
			"amp": _prng.randf_range(8.0, 18.0),
			"phase": _prng.randf() * TAU,
			"alpha": _prng.randf_range(0.25, 0.55),
		})
	for i in _snow_tex.size():
		_snow_par.append({
			"speed": _prng.randf_range(7.0, 15.0),   # px/s 连续下落
			"sway": _prng.randf_range(6.0, 16.0),    # 横向摆动幅度
			"phase": _prng.randf(),
			"alpha": _prng.randf_range(0.22, 0.38),
		})
	# 首次小动物事件提前到 12~25s（让玩家尽快看到一次），之后恢复 45~120s 低频
	_wild_timer = _prng.randf_range(12.0, 25.0)
	# 灯笼为独立叠加精灵，光晕锚点取灯笼火焰处（不再从底图扫描暖色像素）
	_lantern = lantern_anchor + Vector2(0, -16)
	_build_paper_texture()


## 程序化冷压纸颗粒：两层异频 Perlin 叠加（细纤维 + 大斑驳），整幅一次性烤进一张纹理。
## alpha 由"偏离中灰的程度"驱动——平滑处近乎透明，纤维峰谷处才轻微显色，得到细而不糊的颗粒。
func _build_paper_texture() -> void:
	var fiber := FastNoiseLite.new()
	fiber.seed = _prng.randi()
	fiber.noise_type = FastNoiseLite.TYPE_PERLIN
	fiber.frequency = 0.22                       # 高频 → 细密纸纤维
	var mottle := FastNoiseLite.new()
	mottle.seed = _prng.randi()
	mottle.noise_type = FastNoiseLite.TYPE_PERLIN
	mottle.frequency = 0.035                      # 低频 → 手工纸厚薄斑驳
	var iw := int(W)
	var ih := int(H)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	for y in ih:
		for x in iw:
			var f := 0.5 + 0.5 * fiber.get_noise_2d(float(x), float(y))
			var m := 0.5 + 0.5 * mottle.get_noise_2d(float(x), float(y))
			var g := clampf(0.7 * f + 0.3 * m, 0.0, 1.0)
			var tone := lerpf(0.60, 0.97, g)        # 暗纤维↔纸白
			var a := absf(g - 0.5) * 2.0 * PAPER_ALPHA
			img.set_pixel(x, y, Color(tone * 1.03, tone, tone * 0.94, a))  # 极轻暖偏
	_paper_tex = ImageTexture.create_from_image(img)


func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _frames(pattern: String, count: int) -> Array:
	var out: Array = []
	for i in count:
		var tx := _tex(pattern % (i + 1))
		if tx == null:
			return []  # 帧不全则整组禁用，避免播放残缺动画
		out.append(tx)
	return out


## 上鱼庆祝：稀有时由 main 触发一次柔和暖色脉冲（限场景内、随羽化淡出）。
func catch_flash() -> void:
	_flash_t = FLASH_DUR


## 稀有咬钩驻留：真·稀有在水下多挣扎几秒，浮漂处亮起脉动金环等玩家亲手起钩。
func bite_glow(dur: float, col: Color) -> void:
	_bite_glow_t = dur
	_bite_glow_col = col


## 咬钩结束（上鱼/起竿）时由 main 熄灭金环。
func bite_glow_off() -> void:
	_bite_glow_t = 0.0


## 稀有入手金光粒子：一簇火花从浮漂处迸出、缓慢上飘消散（约 1.5 秒）。
func celebrate(pos: Vector2, col: Color) -> void:
	for i in 22:
		var a := randf() * TAU
		var sp := randf_range(22.0, 88.0)
		_sparks.append({"pos": pos, "vel": Vector2(cos(a), sin(a)) * sp + Vector2(0, -34.0),
			"life": randf_range(0.8, 1.6), "max": 1.6,
			"size": randf_range(1.4, 3.2), "col": col})


## 水面号外：一张米纸小条从右往左漂过水面（稀有捕获的挂件内播报，不出窗、不推系统通知）。
func newsflash(text: String) -> void:
	_news_text = text
	_news_t = NEWS_DUR


func _process(delta: float) -> void:
	t += delta
	if debug_tod >= 0.0:
		_tod = debug_tod
	else:
		var _td := Time.get_time_dict_from_system()
		_tod = float(_td["hour"]) + float(_td["minute"]) / 60.0 + float(_td["second"]) / 3600.0
	_gp = _grade_params(_tod)
	if _flash_t > 0.0:
		_flash_t -= delta
	if _bite_glow_t > 0.0:
		_bite_glow_t -= delta
	if _news_t > 0.0:
		_news_t -= delta
	for s in _sparks:
		s["pos"] += s["vel"] * delta
		s["vel"] -= s["vel"] * minf(1.0, delta * 2.4)   # 阻尼减速
		s["vel"].y += 20.0 * delta                       # 轻微回落
		s["life"] -= delta
	if not _sparks.is_empty():
		_sparks = _sparks.filter(func(x): return x["life"] > 0.0)
	if _spot_fade < 1.0:
		_spot_fade = minf(1.0, _spot_fade + delta / SPOT_FADE_DUR)
		if _spot_fade >= 1.0:
			_spot_prev = null   # 淡入完成，释放上一张底图引用
	for r in _ripples:
		r["r"] += delta * 40.0
		r["life"] -= delta * 1.1
	_ripples = _ripples.filter(func(x): return x["life"] > 0.0)
	if use_composite:
		_tick_idle_pulse(delta)
		_tick_wildlife(delta)
		_tick_fisher(delta)
		_tick_pet(delta)
	queue_redraw()


## 浮漂待机时偶发的轻涟漪（钓鱼暂停/等待间隙画面不至于完全静止）
func _tick_idle_pulse(delta: float) -> void:
	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = _prng.randf_range(5.0, 9.0)
		if _ripples.is_empty():
			add_ripple(bobber_pos(), 18.0)


func set_quiet(q: bool) -> void:
	quiet = q
	if q:
		_wild_kind = ""


func _tick_wildlife(delta: float) -> void:
	if _wild_tex.is_empty() or quiet:
		return
	if _wild_kind == "":
		_wild_timer -= delta
		if _wild_timer <= 0.0:
			_start_wild()
	else:
		_wild_t += delta
		if _wild_t >= _wild_dur:
			_wild_kind = ""
			_wild_timer = _prng.randf_range(75.0, 120.0)  # 首次预览后更稀疏，像环境细节而非常驻


## 启动一次小动物事件；kind 为空时随机挑选（dynamic_art_plan.md 的出场参数）。
func _start_wild(kind := "") -> void:
	if _wild_tex.is_empty():
		return
	if kind == "" or not _wild_tex.has(kind):
		var keys := _wild_tex.keys()
		kind = keys[_prng.randi() % keys.size()]
	_wild_kind = kind
	_wild_t = 0.0
	match kind:
		"bird":
			_wild_dur = _prng.randf_range(6.0, 10.0)
			_wild_scale = _prng.randf_range(0.16, 0.24)   # 更小，别像贴纸从画面飞过
			var y0 := _prng.randf_range(105.0, 145.0)
			_wild_from = Vector2(W + 30.0, y0)
			_wild_to = Vector2(150.0, y0 - _prng.randf_range(10.0, 30.0))
		"rabbit":
			_wild_dur = _prng.randf_range(4.0, 8.0)
			_wild_scale = _prng.randf_range(0.18, 0.28)
			_wild_from = Vector2(_prng.randf_range(395.0, 430.0), 330.0)
			_wild_to = _wild_from
		"fox":
			_wild_dur = _prng.randf_range(3.0, 6.0)
			_wild_scale = _prng.randf_range(0.18, 0.28)
			_wild_from = Vector2(_prng.randf_range(488.0, 504.0), 296.0)
			_wild_to = _wild_from
		"fish":
			_wild_dur = _prng.randf_range(0.7, 1.1)
			_wild_scale = _prng.randf_range(0.22, 0.35)
			var fx := bite_point.x + _prng.randf_range(-34.0, 30.0)
			_wild_from = Vector2(fx, bite_point.y + 4.0)
			_wild_to = _wild_from
			add_ripple(_wild_from, 24.0)


func bobber_pos() -> Vector2:
	if use_composite:
		return bite_point
	return Vector2(_bobber.x, _bobber.y + sin(t * 2.0) * 1.5 + dip * 9.0)


func add_ripple(pos: Vector2, max_r := 28.0) -> void:
	_ripples.append({"pos": pos, "r": 4.0, "max_r": max_r, "life": 1.0})


# ============================ 绘制 ============================

func _draw() -> void:
	if use_composite:
		_draw_composite()
	else:
		_draw_procedural()


func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


func _smooth01(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## 解析钓点底图：优先时段图 spot_<key>_<phase>.png，回退 spot_<key>.png；
## 二者都缺（或 bg_key 为空）返回 null，由绘制层回退到 _base（spot_river_bend.png）。
func _resolve_spot_tex(bg_key: String, phase: String) -> Texture2D:
	if bg_key == "":
		_spot_has_phase_art = false
		return null
	if phase != "":
		var tx := _tex("res://assets/art/background/spot_%s_%s.png" % [bg_key, phase])
		if tx != null:
			_spot_has_phase_art = true
			return tx
	_spot_has_phase_art = false
	return _tex("res://assets/art/background/spot_%s.png" % bg_key)


## 应用底图。animate=true 时与当前底图做慢 crossfade（昼夜切换）；false 直接换（切钓点地点跳转）。
func _apply_background(target: Texture2D, animate: bool) -> void:
	var old_drawn := _spot_base if _spot_base != null else _base
	var new_drawn := target if target != null else _base
	_spot_base = target
	if animate and old_drawn != null and new_drawn != null and old_drawn != new_drawn:
		_spot_prev = old_drawn
		_spot_fade = 0.0
	else:
		_spot_prev = null
		_spot_fade = 1.0
	queue_redraw()


## 切换钓点底图：按 bg_key + 当前时段解析；缺时段图回退 spot_<key>.png，再缺回退现有主图（不崩）。
## 切钓点是地点跳转，直接换（不 crossfade）；昼夜切换的慢淡入走 set_phase_tint。
func set_spot(bg_key: String) -> void:
	_spot_key = bg_key
	_apply_background(_resolve_spot_tex(bg_key, _spot_phase), false)


## 当前是否用干净 spot 底图（渔夫/按钮需由代码补上）；river 回退 _base 时为 false。
func uses_clean_bg() -> bool:
	return _spot_base != null


## 渔夫情绪状态机（Task 4）：cheer/yawn/shiver/doze 为瞬态小情绪，零存档。
## cheer 由 main 在高星/七彩上鱼时触发；其余按 main 喂入的夜间/久坐上下文低频自发。
func _tick_fisher(delta: float) -> void:
	var target_pull := clampf((dip - 0.12) / 0.88, 0.0, 1.0)
	var pull_speed := 3.8 if target_pull > _fisher_pull_pose else 2.4
	_fisher_pull_pose = move_toward(_fisher_pull_pose, target_pull, delta * pull_speed)
	if _mood_t > 0.0:
		_mood_t -= delta
		if _mood_t <= 0.0:
			fisher_mood = "idle"
		return
	_mood_gap -= delta
	if _mood_gap <= 0.0:
		_mood_gap = _prng.randf_range(14.0, 26.0)
		_start_ambient_mood()


func _start_ambient_mood() -> void:
	if quiet:
		return  # 安静模式不主动演小情绪
	var pool := ["shiver"]    # 冬日钓场总有点冷
	if ctx_night:
		pool.append("yawn")
	if ctx_idle:
		pool.append("doze")
		pool.append("doze")   # 久坐更容易打盹
	fisher_mood = pool[_prng.randi() % pool.size()]
	match fisher_mood:
		"shiver": _mood_dur = 1.8
		"yawn": _mood_dur = 2.4
		"doze": _mood_dur = 3.6
		_: _mood_dur = 1.6
	_mood_t = _mood_dur


## main 喂入昼夜 / 久未操作上下文，决定自发小情绪倾向。
func set_fisher_context(night: bool, idle: bool) -> void:
	ctx_night = night
	ctx_idle = idle


## 钓到高星/七彩 → 举手欢呼（一次性，最高优先）。
func fisher_cheer() -> void:
	fisher_mood = "cheer"
	_mood_dur = 1.6
	_mood_t = _mood_dur


func _draw_fisher_frame(tex: Texture2D, alpha: float) -> void:
	if tex == null or alpha <= 0.001:
		return
	var sz := Vector2(tex.get_size()) * FISHER_SCALE
	draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -sz.y), sz), false, Color(1, 1, 1, alpha))


func _draw_fisher_smooth() -> void:
	var tex := _fisher
	var tex_b: Texture2D = null
	var blend := 0.0
	var pull := clampf(_fisher_pull_pose, 0.0, 1.0)
	if pull > 0.01 and not _fisher_pull.is_empty():
		var seg := pull * float(_fisher_pull.size())
		if seg < 1.0 or _fisher_pull.size() == 1:
			tex_b = _fisher_pull[0]
			blend = _smooth01(seg)
		else:
			tex = _fisher_pull[0]
			tex_b = _fisher_pull[mini(1, _fisher_pull.size() - 1)]
			blend = _smooth01(seg - 1.0)
	elif fisher_mood == "cheer" and _fisher_mood_tex.has("cheer"):
		tex = _fisher_mood_tex["cheer"]
	elif fisher_mood == "shiver" and _fisher_mood_tex.has("shiver"):
		tex = _fisher_mood_tex["shiver"]
	elif fisher_mood == "doze" and _fisher_mood_tex.has("doze"):
		tex = _fisher_mood_tex["doze"]
	elif fisher_mood == "idle" and _fisher_mood_tex.has("idle_breath") and sin(t * 1.7) > 0.6:
		tex = _fisher_mood_tex["idle_breath"]
	var off := Vector2.ZERO
	var rot := 0.0
	var sc := Vector2.ONE
	sc.y *= 1.0 + 0.016 * sin(t * 1.7)
	var mood := fisher_mood if pull <= 0.04 else "idle"
	var p := 0.0
	match mood:
		"cheer":
			p = 1.0 - _mood_t / _mood_dur
			off.y = -sin(p * PI) * 6.0
			sc *= 1.0 + 0.04 * sin(p * PI)
			rot = 0.035 * sin(p * TAU * 2.0)
		"yawn":
			p = 1.0 - _mood_t / _mood_dur
			var yy := sin(p * PI)
			sc.y *= 1.0 + 0.05 * yy
			off.y -= 1.6 * yy
			rot = -0.04 * yy
		"shiver":
			off.x = sin(t * 30.0) * 0.8
			off.y += 0.8
			sc.y *= 0.985
		"doze":
			rot = 0.05 * sin(t * 0.8)
			off.y += 1.2 * sin(t * 0.8) + 1.0
	var flip := -1.0 if fisher_flip else 1.0
	draw_set_transform(fisher_anchor + off, rot, Vector2(flip * sc.x, sc.y))
	if tex_b != null:
		_draw_fisher_frame(tex, 1.0 - blend)
		_draw_fisher_frame(tex_b, blend)
	else:
		_draw_fisher_frame(tex, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 叠加独立渔夫精灵（脚底中心对齐 fisher_anchor）。咬钩时切收竿姿势；情绪用变换叠加。
func _draw_fisher() -> void:
	if _fisher == null:
		return
	_draw_fisher_smooth()
	return
	# 选帧：咬钩收竿优先；其次有专属情绪帧就用；idle 呼吸峰值轻切 idle_breath；都缺回退 idle。
	var tex := _fisher
	if dip > 0.5 and not _fisher_pull.is_empty():
		tex = _fisher_pull[int(t * 6.0) % _fisher_pull.size()]  # 咬钩收竿，帧间切换（自然衔接浮漂咬钩）
	elif fisher_mood == "cheer" and _fisher_mood_tex.has("cheer"):
		tex = _fisher_mood_tex["cheer"]
	elif fisher_mood == "shiver" and _fisher_mood_tex.has("shiver"):
		tex = _fisher_mood_tex["shiver"]
	elif fisher_mood == "doze" and _fisher_mood_tex.has("doze"):
		tex = _fisher_mood_tex["doze"]
	elif fisher_mood == "idle" and _fisher_mood_tex.has("idle_breath") and sin(t * 1.7) > 0.6:
		tex = _fisher_mood_tex["idle_breath"]  # 仅在呼气峰值轻切一帧，肉眼几乎察觉不到突变
	var sz := Vector2(tex.get_size()) * FISHER_SCALE
	var off := Vector2.ZERO
	var rot := 0.0
	var sc := Vector2.ONE
	sc.y *= 1.0 + 0.016 * sin(t * 1.7)  # 呼吸：~1px、慢，安静不打扰
	var p := 0.0
	match fisher_mood:
		"cheer":
			p = 1.0 - _mood_t / _mood_dur
			off.y = -sin(p * PI) * 6.0         # 蹦一下（≤6px，不夸张）
			sc *= 1.0 + 0.04 * sin(p * PI)     # 缩放脉冲 ≤1.04
			rot = 0.035 * sin(p * TAU * 2.0)   # 小幅摇摆
		"yawn":
			p = 1.0 - _mood_t / _mood_dur
			var yy := sin(p * PI)
			sc.y *= 1.0 + 0.05 * yy            # 缓慢伸展
			off.y -= 1.6 * yy
			rot = -0.04 * yy                   # 微微后仰
		"shiver":
			off.x = sin(t * 30.0) * 0.8        # 发抖（≤0.8px，细微不剧烈）
			off.y += 0.8                        # 缩脖
			sc.y *= 0.985
		"doze":
			rot = 0.05 * sin(t * 0.8)          # 一点一点打盹
			off.y += 1.2 * sin(t * 0.8) + 1.0
	var flip := -1.0 if fisher_flip else 1.0
	draw_set_transform(fisher_anchor + off, rot, Vector2(flip * sc.x, sc.y))
	draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -sz.y), sz), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ============================ 桌面宠物：小馋猫（Task 4，程序化占位）============================

## 上鱼扒拉 / 偷鱼时由 main 触发，瞬态动作。
func pet_react(kind: String) -> void:
	pet_action = kind
	_pet_action_dur = 0.9 if kind == "paw" else 1.4
	_pet_action_t = _pet_action_dur


func _tick_pet(delta: float) -> void:
	if _pet_action_t > 0.0:
		_pet_action_t -= delta
		if _pet_action_t <= 0.0:
			pet_action = ""
	_pet_blink_t -= delta
	if _pet_blink_t <= 0.0:
		_pet_blink_t = _prng.randf_range(2.6, 6.0)
	# 尾巴轻摆：仅在闲坐(无动作/非睡)时，6~12s 一次、持续 0.8~1.2s，低调有生命感
	if _pet_tail_active > 0.0:
		_pet_tail_active -= delta
	else:
		_pet_tail_t -= delta
		if _pet_tail_t <= 0.0:
			_pet_tail_t = _prng.randf_range(6.0, 12.0)
			if pet_action == "" and not (ctx_night and ctx_idle):
				_pet_tail_active = _prng.randf_range(0.8, 1.2)
	var desired_key := _pet_state_key()
	if desired_key != _pet_draw_key:
		_pet_prev_key = _pet_draw_key
		_pet_draw_key = desired_key
		_pet_blend_t = 0.0
	else:
		_pet_blend_t = minf(_pet_blend_t + delta, PET_STATE_BLEND_DUR)


func _pet_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(rx, ry))
	draw_circle(Vector2.ZERO, 1.0, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pet_smooth() -> void:
	var key := _pet_draw_key
	if _pet_tex.has(key) or _pet_tex.has("idle"):
		_draw_pet_shadow()
		var tex = _pet_tex.get(key, _pet_tex.get("idle"))
		var blend := _smooth01(_pet_blend_t / PET_STATE_BLEND_DUR)
		if key != _pet_prev_key and blend < 0.999 and _pet_tex.has(_pet_prev_key):
			_draw_pet_sprite(_pet_tex[_pet_prev_key], _pet_prev_key, 1.0 - blend)
			_draw_pet_sprite(tex, key, blend)
		else:
			_draw_pet_sprite(tex, key, 1.0)
	else:
		_draw_pet_proc()


## 小馋猫入口：有正式 sprite 用 PNG 帧，缺图回退程序化占位猫。
func _draw_pet() -> void:
	_draw_pet_smooth()
	return
	var key := _pet_state_key()
	if _pet_tex.has(key) or _pet_tex.has("idle"):
		_draw_pet_shadow()                       # 接触阴影压在脚底，杜绝悬浮感
		_draw_pet_sprite(_pet_tex.get(key, _pet_tex.get("idle")))
	else:
		_draw_pet_proc()


## 按动作/情境选帧：偷鱼/挥爪优先，其次夜间久坐睡觉，再轻摆尾，再眨眼，否则 idle。
func _pet_state_key() -> String:
	if pet_action == "steal":
		return "steal"
	if pet_action == "paw":
		return "paw"
	if ctx_night and ctx_idle:
		return "sleep"
	if _pet_tail_active > 0.0 and _pet_tex.has("tail_01"):
		if _pet_tex.has("tail_02"):
			return "tail_01" if int(t * 4.0) % 2 == 0 else "tail_02"
		return "tail_01"
	if _pet_blink_t < 0.14:
		return "blink"
	return "idle"


## 接触阴影：优先烘焙 PNG（与猫帧同锚同尺寸，阴影条正落脚底）；缺图回退一枚淡椭圆。
func _draw_pet_shadow() -> void:
	if _pet_shadow_tex != null:
		var sz := Vector2(_pet_shadow_tex.get_size()) * PET_SPRITE_SCALE
		var tl := pet_anchor - Vector2(sz.x * 0.5, sz.y)
		draw_texture_rect(_pet_shadow_tex, Rect2(tl, sz), false, Color(1, 1, 1, 0.9))
	else:
		_pet_ellipse(pet_anchor + Vector2(0, -1), 8.0, 2.4, Color(0.20, 0.22, 0.26, 0.16))


## 绘制 sprite 帧：脚底中心对齐 pet_anchor（变换驱动），极轻呼吸 + 动作位移 + 无尾帧时摆尾错觉。
func _draw_pet_sprite(tex: Texture2D, key := "", alpha := 1.0) -> void:
	var sz := Vector2(tex.get_size()) * PET_SPRITE_SCALE
	var off := Vector2(0, 1.0)                       # 下移1px，脚底压实不悬浮
	var rot := 0.0
	var breath := 1.0 + 0.012 * sin(t * 1.5)         # 呼吸 ~0.3-0.4px，比渔夫更弱
	if key == "sleep":
		breath = 1.0
	if key == "paw" and pet_action == "paw":
		var pp: float = 1.0 - _pet_action_t / maxf(_pet_action_dur, 0.001)
		off.y -= sin(pp * PI) * 1.8
	elif key == "steal" and pet_action == "steal":
		var pp2: float = 1.0 - _pet_action_t / maxf(_pet_action_dur, 0.001)
		off.x += sin(pp2 * PI) * 2.2
	if key == "idle" and _pet_tail_active > 0.0 and not _pet_tex.has("tail_01"):
		rot = sin(t * 6.0) * 0.018                   # 无尾帧时极轻摆错觉（顶端 ~0.5px）
	draw_set_transform(pet_anchor + off, rot, Vector2(1.0, breath))
	# PNG 已做雪景融合；这里再叠偏冷偏灰 modulate，降橘色饱和、压亮度，融入环境
	draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -sz.y), sz), false,
		Color(PET_MODULATE.r, PET_MODULATE.g, PET_MODULATE.b, PET_MODULATE.a * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 程序化橘猫（坐姿）：正式 sprite 缺失时的回退占位（机制可用）。
func _draw_pet_proc() -> void:
	var B := pet_anchor
	var body := Color(0.86, 0.55, 0.28)
	var dark := Color(0.66, 0.40, 0.18)
	var belly := Color(0.96, 0.85, 0.66)
	# 动作进度（抬爪/前倾）
	var lean := 0.0
	var paw_lift := 0.0
	if pet_action != "":
		var pp: float = 1.0 - _pet_action_t / _pet_action_dur
		paw_lift = sin(pp * PI) * 7.0
		if pet_action == "steal":
			lean = sin(pp * PI) * 3.0   # 偷鱼时朝鱼篓前倾
	# 影子
	_pet_ellipse(B + Vector2(1, 1), 12.0, 3.0, Color(0, 0, 0, 0.16))
	# 尾巴（身后，左侧上扬，轻摆）
	var sway := sin(t * 1.6) * 6.0
	var t0 := B + Vector2(-8, -6)
	var t1 := B + Vector2(-14, -14)
	var t2 := B + Vector2(-9 + sway, -24)
	var tail := PackedVector2Array()
	for i in 7:
		var u := float(i) / 6.0
		var a := t0.lerp(t1, u)
		var b := t1.lerp(t2, u)
		tail.append(a.lerp(b, u))
	draw_polyline(tail, dark, 3.4, true)
	# 身体（坐姿臀部 + 前胸）
	_pet_ellipse(B + Vector2(-1 + lean, -9), 9.5, 11.0, body)
	_pet_ellipse(B + Vector2(4 + lean, -9), 6.5, 9.0, body)
	_pet_ellipse(B + Vector2(4 + lean, -6), 3.6, 6.0, belly)
	# 前腿/爪（右爪在动作时抬起扒拉）
	_pet_ellipse(B + Vector2(2 + lean, -3), 2.0, 4.0, body)
	_pet_ellipse(B + Vector2(7 + lean, -3 - paw_lift), 2.0, 4.0, body)
	# 头
	var HC := B + Vector2(7 + lean, -19)
	_pet_ellipse(HC, 6.5, 6.0, body)
	# 耳朵
	draw_colored_polygon(PackedVector2Array([
		HC + Vector2(-5, -4), HC + Vector2(-1, -9), HC + Vector2(0, -3)]), body)
	draw_colored_polygon(PackedVector2Array([
		HC + Vector2(2, -3), HC + Vector2(4, -9), HC + Vector2(6, -3)]), body)
	draw_colored_polygon(PackedVector2Array([
		HC + Vector2(-3, -4), HC + Vector2(-1, -7), HC + Vector2(-0.5, -4)]), dark)
	draw_colored_polygon(PackedVector2Array([
		HC + Vector2(3, -4), HC + Vector2(4, -7), HC + Vector2(5, -4)]), dark)
	# 眼睛（偶尔眨）+ 鼻子
	if _pet_blink_t < 0.14:
		draw_line(HC + Vector2(0, -1), HC + Vector2(2, -1), dark, 1.0)
		draw_line(HC + Vector2(4, -1), HC + Vector2(6, -1), dark, 1.0)
	else:
		draw_circle(HC + Vector2(1, -1), 1.0, dark)
		draw_circle(HC + Vector2(5, -1), 1.0, dark)
	draw_circle(HC + Vector2(3, 1), 0.9, Color(0.5, 0.3, 0.3))


## 叠加独立油灯精灵（底部中心对齐 lantern_anchor）。
func _draw_lantern() -> void:
	if _lantern_tex == null:
		return
	var sz := Vector2(_lantern_tex.get_size()) * LANTERN_SCALE
	var topleft := lantern_anchor - Vector2(sz.x * 0.5, sz.y)
	draw_texture_rect(_lantern_tex, Rect2(topleft, sz), false)


## 钓线：竿尖 → 浮漂，淡白细线（底图不再烤死钓线，统一由此叠加）。
func _current_rod_tip() -> Vector2:
	var idle_tip := fisher_anchor + rod_tip_off
	if _fisher_pull_pose <= 0.01:
		return idle_tip
	var pull_tip_1 := fisher_anchor + Vector2(-16, -57)
	var pull_tip_2 := fisher_anchor + Vector2(-6, -58)
	var first := idle_tip.lerp(pull_tip_1, _smooth01(_fisher_pull_pose * 2.0))
	return first.lerp(pull_tip_2, _smooth01(_fisher_pull_pose * 2.0 - 1.0))


func _draw_fishing_line() -> void:
	var a := _current_rod_tip()
	var off := Vector2(0, sin(t * 2.0) * 1.2 + dip * 5.0)
	# 终点接到浮漂上部系线处（随浮漂一起上下浮动），不插进漂身中心。
	var b := bobber_pos() + off + Vector2(0, -BOBBER_SCALE * 128.0 * 0.30)
	_draw_painterly_fishing_line(a, b, clampf(dip, 0.0, 1.0))


func _quad_bezier(a: Vector2, c: Vector2, b: Vector2, u: float) -> Vector2:
	return a.lerp(c, u).lerp(c.lerp(b, u), u)


func _draw_painterly_fishing_line(a: Vector2, b: Vector2, pull: float) -> void:
	var dist := a.distance_to(b)
	if dist < 2.0:
		return
	var taut := _smooth01(pull)
	var sag := clampf(dist * lerpf(0.042, 0.014, taut), 2.5, 11.0)
	var drift := sin(t * 0.55) * clampf(dist * 0.005, 0.2, 1.0) * (1.0 - taut * 0.65)
	var mid := a.lerp(b, 0.54) + Vector2(drift, sag)
	var pts := PackedVector2Array()
	var seg := 22
	for i in seg + 1:
		var u := float(i) / float(seg)
		pts.append(_quad_bezier(a, mid, b, u))
	for i in seg:
		var u := (float(i) + 0.5) / float(seg)
		var fade := clampf(sin(PI * u) * 1.2, 0.45, 1.0)
		var wash_alpha := (0.045 + 0.025 * fade) * (1.0 + taut * 0.35)
		draw_line(pts[i], pts[i + 1], Color(0.62, 0.65, 0.62, wash_alpha), 1.45, true)
	for i in seg:
		var u := (float(i) + 0.5) / float(seg)
		var paper := 0.74 + 0.18 * sin(float(i) * 1.73 + t * 0.33)
		var alpha := (0.22 + 0.10 * taut) * paper * clampf(sin(PI * u) * 1.15, 0.52, 1.0)
		var col := Color(0.30, 0.30, 0.26, alpha).lerp(Color(0.52, 0.58, 0.56, alpha * 0.85), u)
		draw_line(pts[i], pts[i + 1], col, 0.58, true)
	for j in 3:
		var u := clampf(0.70 + float(j) * 0.075 + 0.012 * sin(t * 0.8 + float(j)), 0.0, 1.0)
		var p := _quad_bezier(a, mid, b, u)
		var q := _quad_bezier(a, mid, b, clampf(u + 0.018, 0.0, 1.0))
		draw_line(p, q, Color(0.82, 0.85, 0.79, 0.085 * (1.0 - taut * 0.25)), 0.50, true)


## 昼夜时段染色 + 底图切换（main 在跨段时调用；A=0 即白昼不染色）。
## phase_id 为空保持旧签名兼容（只改染色不切底图）；非空且与当前时段不同则慢 crossfade 换时段图。
func set_phase_tint(c: Color, phase_id := "") -> void:
	phase_tint = c
	if phase_id != "" and phase_id != _spot_phase:
		_spot_phase = phase_id
		_apply_background(_resolve_spot_tex(_spot_key, _spot_phase), true)
	queue_redraw()


## 时段染色叠层：覆盖整幅场景的淡色，经羽化材质自然向左上渐隐。
func _draw_phase_tint() -> void:
	if phase_tint.a > 0.001:
		draw_rect(Rect2(0.0, 0.0, W, H), phase_tint)


## 连续昼夜调色参数：按当前时刻 tod(0..24) 在关键帧间平滑插值，环绕到次日。
## 返回 {sky, horizon, water, alpha, glow}。
func _grade_params(tod: float) -> Dictionary:
	var n := _GRADE_KEYS.size()
	var hh: float = fposmod(tod, 24.0)
	var i := 0
	while i < n - 1 and hh >= float(_GRADE_KEYS[i + 1]["h"]):
		i += 1
	var a: Dictionary = _GRADE_KEYS[i]
	var b: Dictionary = _GRADE_KEYS[(i + 1) % n]
	var h0: float = float(a["h"])
	var h1: float = float(b["h"])
	if h1 <= h0:
		h1 += 24.0
	var u: float = _smooth01((hh - h0) / maxf(h1 - h0, 0.001))
	return {
		"sky": (a["sky"] as Color).lerp(b["sky"], u),
		"horizon": (a["horizon"] as Color).lerp(b["horizon"], u),
		"water": (a["water"] as Color).lerp(b["water"], u),
		"alpha": lerpf(float(a["alpha"]), float(b["alpha"]), u),
		"glow": lerpf(float(a["glow"]), float(b["glow"]), u),
	}


## 连续昼夜调色叠层：上(天)→地平线→下(水) 的竖向渐变 wash。
## 地平线处更通透，暖光像"透出来"而非盖一层膜；分时段手绘底图已带色则自动减弱，避免双重染色。
func _draw_daynight_grade() -> void:
	var a: float = float(_gp["alpha"])
	if _spot_has_phase_art:
		a *= 0.62   # 时段底图已带色，这里减弱但仍下压，避免双重染色又不至于太弱
	if a <= 0.004:
		return
	var sky: Color = _gp["sky"]
	var hor: Color = _gp["horizon"]
	var wat: Color = _gp["water"]
	var hy := HORIZON - 10.0
	var a_top := a
	var a_hor := a * 0.55   # 地平线更通透
	var a_bot := a * 0.92
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, hy), Vector2(0, hy)]),
		PackedColorArray([_a(sky, a_top), _a(sky, a_top), _a(hor, a_hor), _a(hor, a_hor)]))
	draw_polygon(
		PackedVector2Array([Vector2(0, hy), Vector2(W, hy), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([_a(hor, a_hor), _a(hor, a_hor), _a(wat, a_bot), _a(wat, a_bot)]))


## 夜间灯火：以灯笼为光源的暖光池 + 水面暖光倒影 + 萤火漂动。
## 全部画在右下角可见核心(水/岸/渔夫/灯笼)，按 _gp.glow 随天色启停（白昼≈0，夜里最强）。
func _draw_night_lights() -> void:
	var glow: float = float(_gp["glow"])
	if glow <= 0.02:
		return
	var fc := _lantern
	var warm := Color(1.0, 0.78, 0.42)
	var pool: float = clampf(glow, 0.0, 1.0) * (0.90 + 0.10 * sin(t * TAU / _glow_period))
	# 暖光池：照亮灯周围的水与岸（大而柔，内强外淡）
	for i in 9:
		var f := float(i) / 8.0
		var rad := lerpf(10.0, 110.0, f)
		var aa := pow(1.0 - f, 1.9) * 0.15 * pool
		draw_circle(fc, rad, _a(warm, aa))
	# 灯火核心 + 轻颤 bloom（暖白，越内越亮）
	var pulse := 0.90 + 0.10 * sin(t * 7.3)
	draw_circle(fc, 7.0 * pulse, _a(Color(1.0, 0.90, 0.66), 0.55 * pool))
	draw_circle(fc, 4.0 * pulse, _a(Color(1.0, 0.95, 0.80), 0.85 * pool))
	draw_circle(fc, 2.0 * pulse, _a(Color(1.0, 1.0, 0.95), 0.95 * pool))
	# 水面长倒影：从灯下跌入水中，碎成晃动的光斑（近亮、远碎、随波拉长）
	var rsx := fc.x - 4.0
	var rsy := fc.y + 24.0
	var rlen := 392.0 - rsy
	var segs := 16
	for j in segs:
		var u := float(j) / float(segs - 1)
		var yy := rsy + u * rlen
		var drift := -12.0 * u
		var wob := sin(t * 2.2 + u * 9.0) * (1.5 + u * 6.0)
		var ww := lerpf(7.0, 28.0, u)
		var shim := 0.50 + 0.50 * sin(t * 3.0 + u * 7.0 + float(j))
		var ar := pow(1.0 - u, 0.85) * 0.32 * pool * shim
		draw_rect(Rect2(rsx + drift - ww * 0.5 + wob, yy, ww, lerpf(3.0, 7.0, u)), _a(warm, ar))
	# 萤火（暮/夜）：水岸上空缓慢漂移 + 闪烁（参数化，无需生成/存档）
	if glow > 0.22:
		var fa: float = clampf((glow - 0.22) / 0.6, 0.0, 1.0)
		var fcol := Color(0.95, 0.98, 0.62)
		for k in 8:
			var ph := float(k) * 1.7
			var fx := 296.0 + float(k) * 22.0 + sin(t * 0.5 + ph) * 15.0
			var fy := 318.0 + float(k % 3) * 13.0 + cos(t * 0.36 + ph * 1.3) * 9.0
			var tw := 0.30 + 0.70 * (0.5 + 0.5 * sin(t * 2.4 + ph * 2.0))
			draw_circle(Vector2(fx, fy), 1.7, _a(fcol, tw * fa))


# —— 干净底图 + 统一叠加层（所有钓场同一路径；底图均为纯风景，渔夫/灯笼/钓线/浮漂全代码叠加）——
func _draw_composite() -> void:
	# 底图：昼夜切换时上一张底图淡出、当前底图按 _spot_fade 淡入（缺时段图已在解析层回退，不黑屏）。
	var bg := _spot_base if _spot_base != null else _base
	if _spot_prev != null and _spot_fade < 1.0:
		draw_texture(_spot_prev, Vector2.ZERO)
		if bg != null:
			draw_texture(bg, Vector2.ZERO, Color(1, 1, 1, _spot_fade))
	elif bg != null:
		draw_texture(bg, Vector2.ZERO)
	_draw_fisher()          # 渔夫（含鱼竿）坐右岸
	_draw_pet()             # 渔夫旁的小馋猫
	_draw_lantern()         # 渔夫旁的油灯
	_draw_fishing_line()    # 竿尖 → 浮漂的钓线
	_draw_mist_layer()
	_draw_shimmer_layer()
	_draw_snow_layer()
	if use_grade:
		_draw_daynight_grade()
		_draw_night_lights()
	else:
		_draw_phase_tint()
	_draw_wildlife()
	_draw_ripples()
	_draw_bobber_sprite()
	_draw_bite_ring()       # 稀有咬钩驻留：浮漂脉动金环（P0 好玩补丁）
	_draw_sparks()          # 稀有入手金光粒子
	_draw_glow_layer()      # 灯光呼吸光晕（锚在灯笼火焰处）
	_draw_catch_flash()     # 稀有上鱼柔和暖光脉冲（受羽化遮罩约束）
	_draw_newsflash()       # 水面号外纸条（稀有捕获的挂件内播报）
	_draw_paper_layer()     # 水彩纸纹（最上层介质，随羽化消散，统一全画面气质）


## 水彩纸纹层：把烤好的纸颗粒整幅贴上（最上层）。与场景同尺寸、对齐原点，无平铺缝；
## 经 painter 的羽化材质天然向左上消散。paper_grain=false 可整体关闭。
func _draw_paper_layer() -> void:
	if not paper_grain or _paper_tex == null:
		return
	draw_texture(_paper_tex, Vector2.ZERO)


func _draw_catch_flash() -> void:
	if _flash_t <= 0.0:
		return
	var p: float = _flash_t / FLASH_DUR          # 1 → 0
	var a := sin(p * PI) * 0.16                   # 0 → 峰值0.16 → 0 的柔和脉冲
	draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 0.86, 0.45, a))


## 稀有咬钩驻留金环：浮漂外两圈脉动圆弧（水彩淡金），提示「此刻点起钩有惊喜」。
func _draw_bite_ring() -> void:
	if _bite_glow_t <= 0.0:
		return
	var p := bobber_pos()
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	var col := _bite_glow_col
	col.a = 0.34 + 0.26 * pulse
	draw_arc(p, 13.0 + 4.0 * pulse, 0.0, TAU, 40, col, 2.0, true)
	col.a *= 0.45
	draw_arc(p, 21.0 + 6.0 * pulse, 0.0, TAU, 48, col, 1.5, true)


## 稀有入手金光粒子：小圆点随生命值淡出（水彩气质：小、软、稀）。
func _draw_sparks() -> void:
	for s in _sparks:
		var k := clampf(float(s["life"]) / float(s["max"]), 0.0, 1.0)
		var col: Color = s["col"]
		col.a = 0.85 * k
		draw_circle(s["pos"], float(s["size"]) * (0.6 + 0.4 * k), col)


## 号外纸条字体：桌面走全局回退（含系统 CJK 回退链）；web 沙箱无系统字体，
## fallback_font 无 CJK 会画成豆腐块，改用已打包的 Noto Serif SC（懒加载缓存）。
var _news_font_cache: Font = null
func _news_font() -> Font:
	if OS.has_feature("web"):
		if _news_font_cache == null:
			_news_font_cache = load("res://assets/fonts/NotoSerifSC-Bold.woff2")
		if _news_font_cache != null:
			return _news_font_cache
	return ThemeDB.fallback_font


## 水面号外纸条：米纸底 + 暖墨字，从右缓缓漂到左、首尾淡入淡出（挂件内自足的「全服播报」平替）。
func _draw_newsflash() -> void:
	if _news_t <= 0.0 or _news_text == "":
		return
	var f: Font = _news_font()
	if f == null:
		return
	var fs := 11
	var k := 1.0 - _news_t / NEWS_DUR            # 0 → 1
	var tw := f.get_string_size(_news_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := W + 24.0 - (W + tw + 72.0) * k       # 右外 → 左外
	var y := 292.0 + sin(t * 1.3) * 2.5           # 浮在水面上方，轻轻晃
	var fade := clampf(minf(k, 1.0 - k) * 7.0, 0.0, 1.0)
	var pad := 8.0
	var rect := Rect2(x - pad, y - 15.0, tw + pad * 2.0, 22.0)
	draw_rect(rect, Color(0.96, 0.93, 0.85, 0.88 * fade))
	draw_rect(rect, Color(0.36, 0.29, 0.21, 0.55 * fade), false, 1.0)
	draw_string(f, Vector2(x, y + 1.0), _news_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(0.25, 0.19, 0.13, 0.95 * fade))


## 雾气微风：每层异周期正弦漂移（约 ±20~40px），透明度做明显的浓淡呼吸。
func _draw_mist_layer() -> void:
	for i in _mist_tex.size():
		var p: Dictionary = _mist_par[i]
		var ph: float = TAU * t / p["period"] + p["phase"]
		var off := Vector2(sin(ph) * p["amp"] * 2.2, cos(ph * 0.7) * p["amp"] * 0.4)
		var a: float = p["alpha"] * (0.62 + 0.38 * sin(ph * 1.7))
		draw_texture(_mist_tex[i], off, Color(1, 1, 1, a))


## 水流高光：6 帧慢循环，相邻帧交叉淡化，整体透明度 0.35~0.65 缓慢起伏。
func _draw_shimmer_layer() -> void:
	if _shimmer_tex.is_empty():
		if _water_overlay != null:  # 回退旧版单张波光
			var a: float = clampf(0.22 + 0.12 * sin(t * 0.8), 0.0, 0.45)
			draw_texture_rect(_water_overlay, Rect2(Vector2(sin(t * 0.4) * 3.0, 0.0), Vector2(W, H)), false, Color(1, 1, 1, a))
		return
	var n := _shimmer_tex.size()
	var f: float = fposmod(t, _shimmer_period) / _shimmer_period * n
	var i0 := int(f) % n
	var i1 := (i0 + 1) % n
	var frac := f - floorf(f)
	var base_a := 0.55 + 0.2 * sin(t * 0.5)  # 0.35 ~ 0.75，呼吸更明显
	draw_texture(_shimmer_tex[i0], Vector2.ZERO, Color(1, 1, 1, base_a * (1.0 - frac)))
	draw_texture(_shimmer_tex[i1], Vector2.ZERO, Color(1, 1, 1, base_a * frac))


## 雪粒漂移：连续向下飘落（7~15 px/s）+ 横向轻摆，纵向 wrap 两次绘制实现无缝循环。
func _draw_snow_layer() -> void:
	for i in _snow_tex.size():
		var p: Dictionary = _snow_par[i]
		var yy: float = fposmod(t * p["speed"] + p["phase"] * H, H)
		var xx: float = sin(t * 0.35 + p["phase"] * TAU) * p["sway"]
		var col := Color(1, 1, 1, p["alpha"])
		draw_texture(_snow_tex[i], Vector2(xx, yy), col)
		draw_texture(_snow_tex[i], Vector2(xx, yy - H), col)


## 小动物低频事件：首尾各 ~18% 时长淡入淡出，绝不抢画面。
func _draw_wildlife() -> void:
	if _wild_kind == "" or not _wild_tex.has(_wild_kind):
		return
	var prog: float = clampf(_wild_t / _wild_dur, 0.0, 1.0)
	var fade: float = clampf(minf(_wild_t, _wild_dur - _wild_t) / maxf(0.18 * _wild_dur, 0.15), 0.0, 1.0)
	var pos := _wild_from.lerp(_wild_to, prog)
	var tex: Texture2D = _wild_frame(prog)
	if tex == null:
		return
	var flap := 1.0
	match _wild_kind:
		"bird":
			pos.y += sin(prog * TAU * 2.0) * 3.0  # 滑翔起伏（更小）
			flap = _bird_wing_squash()            # 单帧时竖向挤压模拟扇翅，非纯平移
		"fish":
			pos.y -= sin(PI * prog) * 24.0        # 跃出水面的弧线
		"rabbit":
			pos.y += sin(t * 2.2) * 1.0           # 原地轻动
	var sz := Vector2(tex.get_size()) * _wild_scale
	# 降亮+偏冷，把小动物压回水彩调（减少"贴上去"的突兀感）
	var tint := Color(0.90, 0.91, 0.93, 0.92 * fade)
	if _wild_kind == "bird":
		tint = Color(0.84, 0.86, 0.88, 0.72 * fade)  # 鸟再降透明，远空里若隐若现
	if _wild_kind == "bird":
		# 朝左飞 → 水平翻转；竖向乘 flap 做扇翅挤压（绕身体中心，含单帧也"扇"起来）
		var fx := -1.0 if _wild_to.x < _wild_from.x else 1.0
		draw_set_transform(pos, 0.0, Vector2(fx, flap))
		draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(tex, Rect2(pos - sz * 0.5, sz), false, tint)
	if _wild_kind == "fish" and prog > 0.85 and _ripples.size() < 2:
		add_ripple(Vector2(_wild_from.x, bite_point.y + 4.0), 20.0)


## 取当前小动物帧：bird 为帧数组（多帧按 ~8fps 循环，单帧返回单图）；按情境替换可选副帧。
func _wild_frame(prog: float) -> Texture2D:
	var entry: Variant = _wild_tex.get(_wild_kind)
	var tex: Texture2D = null
	if entry is Array:
		var frames: Array = entry
		if frames.is_empty():
			return null
		tex = frames[int(_wild_t * 8.0) % frames.size()] if frames.size() > 1 else frames[0]
	else:
		tex = entry
	match _wild_kind:
		"bird":
			if entry is Array and (entry as Array).size() <= 1 \
					and _wild_alt.has("bird_glide") and sin(prog * TAU) < -0.4:
				tex = _wild_alt["bird_glide"]    # 单帧鸟：滑翔段偶尔切滑翔姿
		"rabbit":
			if _wild_alt.has("rabbit_alert") and prog > 0.40 and prog < 0.62:
				tex = _wild_alt["rabbit_alert"]  # 中段竖耳警觉
		"fox":
			if _wild_alt.has("fox_retreat") and prog > 0.70:
				tex = _wild_alt["fox_retreat"]   # 末段缩回草丛
		"fish":
			if _wild_alt.has("fish_jump_02") and prog > 0.50:
				tex = _wild_alt["fish_jump_02"]  # 下落段换姿
	return tex


## 飞鸟扇翅：有多帧时帧本身已表达翅膀（不挤压）；单帧时用竖向轻挤压模拟扇动。
func _bird_wing_squash() -> float:
	var entry: Variant = _wild_tex.get("bird")
	if entry is Array and (entry as Array).size() > 1:
		return 1.0
	return 1.0 - 0.16 * (0.5 + 0.5 * sin(_wild_t * 18.0))


## 涟漪：有 Codex 帧动画时按扩散进度播 4 帧；否则回退程序化圆弧。
func _draw_ripples() -> void:
	for r in _ripples:
		var prog: float = clampf(1.0 - r["life"], 0.0, 1.0)
		if not _ripple_tex.is_empty():
			var idx: int = clampi(int(prog * _ripple_tex.size()), 0, _ripple_tex.size() - 1)
			var tex: Texture2D = _ripple_tex[idx]
			var s: float = (0.7 + 0.6 * prog) * (r["max_r"] / 28.0)
			var sz := Vector2(tex.get_size()) * s
			var a: float = clampf(r["life"], 0.0, 1.0) * 0.8
			draw_texture_rect(tex, Rect2(Vector2(r["pos"]) - sz * 0.5, sz), false, Color(1, 1, 1, a))
		else:
			var k: float = clampf(1.0 - r["r"] / r["max_r"], 0.0, 1.0)
			var a2: float = clampf(r["life"], 0.0, 1.0) * 0.5 * k
			if a2 > 0.02:
				draw_arc(r["pos"], r["r"], 0.0, TAU, 26, _a(C_SHIMMER, a2), 1.5)


## 浮漂：用 Codex 水彩贴图（idle/bite，128×128）。咬钩(dip>0.5)切 bite 帧；
## 轻微上下浮动 + 咬钩下沉。贴图缺失才回退程序绘制 _draw_bobber_proc。
func _draw_bobber_sprite() -> void:
	var p := bobber_pos()
	var tex := _bobber_bite if (dip > 0.5 and _bobber_bite != null) else _bobber_idle
	if tex == null:
		_draw_bobber_proc(p)
		return
	var sz := Vector2(tex.get_size()) * BOBBER_SCALE
	var off := Vector2(0, sin(t * 2.0) * 1.2 + dip * 5.0)
	draw_texture_rect(tex, Rect2(p - sz * 0.5 + off, sz), false)


## 灯光呼吸：4 帧 ping-pong + 相邻帧交叉淡化，慢速脉动。
func _draw_glow_layer() -> void:
	if _glow_tex.is_empty():
		return
	var n := _glow_tex.size()
	var ph: float = fposmod(t, _glow_period * 2.0) / _glow_period
	var k: float = ph if ph <= 1.0 else 2.0 - ph  # 0→1→0
	var f: float = k * float(n - 1)
	var i0 := int(f)
	var i1: int = mini(i0 + 1, n - 1)
	var frac := f - floorf(f)
	var base_a := 0.55 + 0.28 * sin(t * TAU / _glow_period)  # 0.27 ~ 0.83，呼吸更明显
	if use_grade:
		base_a *= 0.30 + 1.05 * float(_gp["glow"])   # 灯光随天色增强：白昼很弱、夜里点亮
	var s: float = 1.0 + 0.10 * sin(t * TAU / _glow_period)  # 光晕随呼吸轻微胀缩
	var sz := Vector2(_glow_tex[0].get_size()) * s
	var rect := Rect2(_lantern - sz * 0.5, sz)
	draw_texture_rect(_glow_tex[i0], rect, false, Color(1, 1, 1, base_a * (1.0 - frac)))
	if i1 != i0:
		draw_texture_rect(_glow_tex[i1], rect, false, Color(1, 1, 1, base_a * frac))


## 水彩浮漂：暖红下身 + 奶白颈 + 细天线，柔晕湿边、哑光低饱和，融进水彩调；
## 那点红是画面唯一暖焦点。dip>0（咬钩）→ 下沉 + 接水涟漪环加强。
func _draw_bobber_proc(p: Vector2) -> void:
	var bite := clampf(dip, 0.0, 1.0)
	var red := Color(0.79, 0.34, 0.30)
	var red_dk := Color(0.58, 0.24, 0.23)
	var cream := Color(0.95, 0.92, 0.84)
	var edge := Color(0.26, 0.17, 0.18, 0.28)
	# 接水涟漪环（咬钩时更明显）
	var ring := 4.6 + sin(t * 2.2) * 0.7 + bite * 3.2
	draw_arc(p + Vector2(0, 3.0), ring, 0.0, TAU, 22, _a(C_SHIMMER, 0.15 + bite * 0.12), 1.0)
	# 水下淡倒影
	draw_circle(p + Vector2(0, 5.0), 2.2, Color(red.r, red.g, red.b, 0.10))
	# 天线 + 顶红珠
	draw_line(p + Vector2(0, -3.2), p + Vector2(0, -6.6), red_dk, 1.0, true)
	draw_circle(p + Vector2(0, -6.7), 0.9, red)
	# 红下身（主体，占大半）：柔晕 + 实心 + 下缘湿边
	draw_circle(p + Vector2(0, 1.1), 4.4, Color(red.r, red.g, red.b, 0.20))
	draw_circle(p + Vector2(0, 1.1), 3.5, red)
	draw_arc(p + Vector2(0, 1.1), 3.5, deg_to_rad(15), deg_to_rad(165), 16, edge, 0.9)
	# 奶白颈（上部细带，红占主、不喧宾）：柔晕 + 实心
	draw_circle(p + Vector2(0, -1.8), 2.3, Color(cream.r, cream.g, cream.b, 0.20))
	draw_circle(p + Vector2(0, -1.8), 1.7, cream)
	# 哑光高光（柔，不塑料）
	draw_circle(p + Vector2(-0.7, -2.1), 0.55, Color(1, 1, 1, 0.5))


# ============================ 程序化回退场景 ============================

func _draw_procedural() -> void:
	_draw_glow_proc()
	_draw_mountains()
	_draw_treeline()
	_draw_water()
	_draw_shimmer_proc()
	_draw_ripples()
	_draw_bank()
	_draw_angler()
	_draw_bobber_proc(bobber_pos())


func _draw_glow_proc() -> void:
	var top := 72.0
	var pts := PackedVector2Array([
		Vector2(150, top), Vector2(W, top), Vector2(W, HORIZON), Vector2(150, HORIZON)])
	var clear := _a(C_GLOW, 0.0)
	draw_polygon(pts, PackedColorArray([clear, clear, _a(C_GLOW, 0.5), _a(C_GLOW, 0.12)]))


func _draw_mountains() -> void:
	var far := PackedVector2Array([
		Vector2(150, HORIZON), Vector2(150, 170), Vector2(208, 142),
		Vector2(252, 160), Vector2(300, 120), Vector2(356, 154),
		Vector2(408, 130), Vector2(468, 152), Vector2(W, 140), Vector2(W, HORIZON)])
	draw_colored_polygon(far, _a(C_MT_FAR, 0.92))
	_snowcap(Vector2(300, 120), 24, 17)
	_snowcap(Vector2(408, 130), 20, 14)
	_snowcap(Vector2(208, 142), 16, 11)


func _snowcap(peak: Vector2, hw: float, h: float) -> void:
	var pts := PackedVector2Array([
		peak, peak + Vector2(hw * 0.55, h), peak + Vector2(hw * 0.18, h * 0.65),
		peak + Vector2(-hw * 0.22, h), peak + Vector2(-hw * 0.55, h * 0.78)])
	draw_colored_polygon(pts, _a(C_SNOW, 0.95))


func _draw_treeline() -> void:
	var x := 150.0
	var i := 0
	while x < W - 4:
		var hh := 15.0 + (3.0 if i % 2 == 0 else 8.0)
		_pine(Vector2(x, HORIZON + 1), hh, hh * 0.5, C_PINE if i % 2 == 0 else C_PINE_HI, 0.85)
		x += 12.5
		i += 1


func _pine(base: Vector2, h: float, hw: float, col: Color, a := 1.0) -> void:
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, -h), base + Vector2(hw, 0), base + Vector2(-hw, 0)]), _a(col, a))
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(0, -h * 1.5), base + Vector2(hw * 0.66, -h * 0.5),
		base + Vector2(-hw * 0.66, -h * 0.5)]), _a(col, a))


func _draw_water() -> void:
	var pts := PackedVector2Array([
		Vector2(0, HORIZON), Vector2(W, HORIZON), Vector2(W, H), Vector2(0, H)])
	draw_polygon(pts, PackedColorArray([
		_a(C_WATER_TOP, 0.0), _a(C_WATER_TOP, 0.9),
		_a(C_WATER_BOT, 0.9), _a(C_WATER_BOT, 0.0)]))


func _draw_shimmer_proc() -> void:
	for i in 7:
		var yy := HORIZON + 16.0 + i * 23.0
		if yy > H - 6.0:
			continue
		var phase := t * 0.6 + i * 1.3
		var cx := 308.0 + sin(phase) * 12.0
		var hw := 58.0 + 22.0 * cos(phase * 0.7)
		var a: float = max(0.05, 0.11 + 0.06 * sin(phase * 1.3))
		a *= clampf((cx - 60.0) / 180.0, 0.15, 1.0)
		draw_line(Vector2(cx - hw, yy), Vector2(cx + hw, yy), _a(C_SHIMMER, a), 2.0)


func _draw_bank() -> void:
	var bank := PackedVector2Array([
		Vector2(W, 248), Vector2(372, 300), Vector2(404, 332), Vector2(W, H)])
	draw_colored_polygon(bank, _a(C_SNOWBANK, 0.95))
	draw_circle(Vector2(372, 304), 9.0, _a(C_ROCK, 0.9))
	draw_circle(Vector2(398, 318), 7.0, _a(C_ROCK, 0.9))
	draw_circle(Vector2(150, HORIZON + 14), 6.0, _a(C_ROCK, 0.55))
	draw_circle(Vector2(166, HORIZON + 18), 4.0, _a(C_ROCK, 0.5))
	_pine(Vector2(502, 252), 42.0, 18.0, C_PINE)
	_pine(Vector2(516, 276), 32.0, 14.0, C_PINE)


func _draw_angler() -> void:
	var hip := Vector2(430, 294)
	draw_line(hip + Vector2(-10, 4), hip + Vector2(-12, 20), C_DARK, 2.0)
	draw_line(hip + Vector2(10, 4), hip + Vector2(12, 20), C_DARK, 2.0)
	draw_line(hip + Vector2(-13, 4), hip + Vector2(13, 4), C_DARK, 3.0)
	var lp := hip + Vector2(28, -4)
	draw_circle(lp, 11.0, _a(C_LANTERN, 0.22))
	draw_circle(lp, 4.0, C_LANTERN)
	draw_line(lp + Vector2(0, 4), lp + Vector2(0, 18), C_DARK, 1.5)
	draw_colored_polygon(PackedVector2Array([
		hip + Vector2(-13, 2), hip + Vector2(13, 4),
		hip + Vector2(9, -30), hip + Vector2(-9, -32)]), C_COAT)
	draw_circle(hip + Vector2(-3, -42), 7.5, C_SKIN)
	draw_colored_polygon(PackedVector2Array([
		hip + Vector2(-12, -43), hip + Vector2(5, -45),
		hip + Vector2(3, -53), hip + Vector2(-9, -51)]), C_DARK)
	var hands := hip + Vector2(-9, -18)
	draw_line(hands, _rod_tip, Color(0.32, 0.25, 0.18), 2.0)
	draw_line(_rod_tip, bobber_pos(), _a(Color(0.95, 0.95, 0.95), 0.5), 1.0)
