class_name ProcFishSpecies
extends RefCounted
## 物种蓝图（纯数据）：描述「一条鱼长什么样」——体型剖面 / 关节参数 / 配色 / 花纹。
## 与「怎么让脊椎动 / 怎么画」（ProcFishSpine + ProcFish）解耦：加新种类 / 花纹 = 只动这里。
##
## 扩展指引：
##   · 加体型 → 在 PROFILES 里加一条归一化半宽剖面，并在 _pick_profile 里给出选择条件。
##   · 加花纹 → 在 Pattern 枚举加一项，并在 ProcFish._draw_pattern 里加一个绘制分支。
##   · 定制某条鱼 → 在 from_catch 末尾按 id 覆盖字段即可（具名特例）。

enum Pattern { NONE, STRIPES, SPOTS, BLOTCHES, LATERAL_LINE, RINGS, BIOLUMEN }
enum SwimMode { CRUISE, DART, EEL, HOVER, GLIDE, DEEP_DRIFT }

# 身体关节数固定为 10（尾鳍另占 2 节，合计 12），与参考 Fish.pde 的索引约定一致。
const BODY_JOINTS := 10
const TOTAL_JOINTS := 12

# —— 归一化半宽剖面（10 个身体关节，最大值≈1.0，乘以 base_width 得像素半宽）——
const PROFILES := {
	# 标准流线体（参考 Fish.pde 的 bodyWidth 归一化）
	"standard": [0.810, 0.964, 1.000, 0.988, 0.917, 0.762, 0.607, 0.452, 0.381, 0.226],
	# 细长体（鳗 / 带鱼 / 溪流小鱼）：整体偏瘦、匀称
	"slender":  [0.520, 0.600, 0.640, 0.660, 0.640, 0.600, 0.540, 0.460, 0.360, 0.220],
	# 高身圆体（鲫 / 鳊 / 河豚）：中段鼓起
	"deep":     [0.820, 1.060, 1.220, 1.240, 1.120, 0.920, 0.680, 0.470, 0.340, 0.200],
	# 扁宽体（鲆 / 鳐 / 鲳）：头身宽、尾柄短，俯视更像一片宽身体
	"flat":     [0.980, 1.180, 1.260, 1.180, 0.980, 0.760, 0.520, 0.340, 0.240, 0.160],
	# 巨物/鲟鲨体：前段厚重，后段拉长
	"heavy":    [0.900, 1.060, 1.120, 1.060, 0.940, 0.780, 0.610, 0.450, 0.310, 0.180],
}

# 已知细长 / 高身体型的鱼种（其余走 standard）。列表即扩展点，加 id 立即生效。
const SLENDER_IDS := ["swampeel", "conger", "hairtail", "halfbeak", "sandlance",
	"icefish", "ricefish", "loach", "spined_loach", "bigscale_loach", "eel",
	"marbled_eel", "oarfish", "lancetfish", "dragonfish", "rattail", "cave_eel",
	"olm", "moray", "pipefish", "needlefish"]
const DEEP_IDS := ["crucian", "bream", "fangbream", "wuchang", "blackbream",
	"pufferfish", "mandarin", "bluegill", "paradisefish", "tilapia", "pomfret",
	"butterflyfish", "angelfish", "spotted_puffer", "boxfish", "filefish"]
const FLAT_IDS := ["flounder", "estuary_stingray", "manta_ray", "sawfish", "stingray"]
const HEAVY_IDS := ["sturgeon", "chinese_sturgeon", "kaluga", "paddlefish",
	"whale_shark", "wels_catfish", "giant_grouper", "arapaima", "bull_shark"]
static var _palette_cache: Dictionary = {}

var body_width: PackedFloat32Array = PackedFloat32Array()  # 每个身体关节的像素半宽（已缩放）
var link_size: float = 5.0                                  # 关节间距（px）→ 决定总长
var angle_constraint: float = PI / 8.0                      # 摆动柔度
var body_color: Color = Color(0.23, 0.49, 0.65)
var fin_color: Color = Color(0.51, 0.76, 0.84)
var belly_color: Color = Color(0.72, 0.86, 0.90)
var pattern: int = Pattern.NONE
var pattern_color: Color = Color(1, 1, 1, 0.25)
var pattern_density: float = 1.0
var pattern_scale: float = 1.0
var variant: int = 0                                        # 0 普通 / 1 斑斓 / 2 鎏金 / 3 七彩
var quality: int = 0                                        # 0..3 星级；控制高光/细节，不覆盖变体识别
var swim_mode: int = SwimMode.CRUISE
var body_len: float = 50.0                                  # 头→尾大致像素长度（命中判定 / 布局用）
var speed_mult: float = 1.0                                  # 运动性格：速度倍率
var turn_rate_mult: float = 1.0                              # 运动性格：转向角速度倍率
var wiggle_mult: float = 1.0                                 # 运动性格：摆动幅度倍率
var tail_freq_mult: float = 1.0                              # 运动性格：摆尾频率倍率
var pectoral_mult: float = 1.0                                # 部位特征：胸鳍/腹鳍大小
var dorsal_mult: float = 1.0                                  # 部位特征：背鳍高度
var tail_mult: float = 1.0                                    # 部位特征：尾鳍展开
var eye_mult: float = 1.0                                     # 部位特征：眼睛大小
var glow_mult: float = 0.0                                    # 星级/深海/变体带来的柔光强度
var sparkle_mult: float = 0.0                                 # 高品质/高变体粒子强度


## 从一条渔获（id + 变体 + 体重）派生物种蓝图。weight<0 时取该鱼种体重区间中点。
static func from_catch(id: String, var_index: int = 0, weight: float = -1.0, quality_index: int = 0) -> ProcFishSpecies:
	var sp := new()
	sp.variant = var_index
	sp.quality = clampi(quality_index, 0, 3)
	var tier := FishData.tier_of(id)
	var f: Dictionary = FishData.FISH.get(id, {})
	var wmin := float(f.get("wmin", 0.1))
	var wmax := float(f.get("wmax", 1.0))
	var tags: Array = f.get("tags", []) as Array
	var name := str(f.get("name", id))
	if weight < 0.0:
		weight = (wmin + wmax) * 0.5

	# ① 体型模板
	var key := _pick_profile(id, name, tags, wmax)
	sp.swim_mode = _pick_swim_mode(id, name, tags, key, wmax)
	if key == "slender":
		sp.wiggle_mult = 1.18
		sp.turn_rate_mult = 1.18
	elif key == "deep":
		sp.wiggle_mult = 0.88
		sp.turn_rate_mult = 0.86
	elif key == "flat":
		sp.wiggle_mult = 0.62
		sp.turn_rate_mult = 0.74
	elif key == "heavy":
		sp.wiggle_mult = 0.76
		sp.turn_rate_mult = 0.68
	if tags.has("deep") or tags.has("protected") or wmax >= 40.0:
		sp.speed_mult *= 0.82
		sp.tail_freq_mult *= 0.82
	elif tags.has("stream") or tags.has("reef"):
		sp.speed_mult *= 1.12
		sp.tail_freq_mult *= 1.10
	if tags.has("night"):
		sp.speed_mult *= 0.92
	if tags.has("cold") or tags.has("polar"):
		sp.tail_freq_mult *= 0.88
	match sp.swim_mode:
		SwimMode.DART:
			sp.speed_mult *= 1.18
			sp.turn_rate_mult *= 1.20
			sp.tail_freq_mult *= 1.16
		SwimMode.EEL:
			sp.wiggle_mult *= 1.32
			sp.turn_rate_mult *= 1.08
			sp.tail_freq_mult *= 0.94
		SwimMode.HOVER:
			sp.speed_mult *= 0.78
			sp.wiggle_mult *= 0.82
			sp.turn_rate_mult *= 1.12
		SwimMode.GLIDE:
			sp.speed_mult *= 0.86
			sp.wiggle_mult *= 0.56
			sp.turn_rate_mult *= 0.72
			sp.tail_freq_mult *= 0.72
		SwimMode.DEEP_DRIFT:
			sp.speed_mult *= 0.72
			sp.wiggle_mult *= 0.70
			sp.turn_rate_mult *= 0.62
			sp.tail_freq_mult *= 0.70
	_apply_part_traits(sp, id, name, tags, key)
	var profile: Array = PROFILES[key]

	# ② 尺寸：体重按对数映射到像素半宽，钳进缸内友好区间；细长体略瘦、高身体略胖。
	var wr: float = 0.0
	if wmax > wmin:
		wr = clampf((weight - wmin) / (wmax - wmin), 0.0, 1.0)
	# 跨鱼种基准：对数压缩体重（0.005kg 小鱼 → 巨物），再叠本鱼种内的相对大小。
	var log_scale := clampf((log(weight + 0.05) - log(0.05)) / (log(80.0) - log(0.05)), 0.0, 1.0)
	var species_scale := clampf((log(wmax + 0.05) - log(0.05)) / (log(120.0) - log(0.05)), 0.0, 1.0)
	var base_width := lerpf(5.4, 17.0, log_scale) * lerpf(0.88, 1.16, wr)
	base_width *= lerpf(0.92, 1.12, species_scale)
	if key == "slender":
		base_width *= 0.68
	elif key == "deep":
		base_width *= 1.08
	elif key == "flat":
		base_width *= 1.18
	elif key == "heavy":
		base_width *= 1.05

	sp.body_width = PackedFloat32Array()
	for i in profile.size():
		sp.body_width.append(float(profile[i]) * base_width)
	var length_mult := 1.0
	if key == "slender":
		length_mult = 1.38
	elif key == "flat":
		length_mult = 0.72
	elif key == "heavy":
		length_mult = 1.18
	sp.link_size = base_width * lerpf(0.62, 0.5, log_scale) * length_mult   # 大鱼相对更修长
	sp.body_len = sp.link_size * float(TOTAL_JOINTS - 1)

	# ③ 柔度：小/细长鱼灵活，大/高身鱼僵硬
	match key:
		"slender": sp.angle_constraint = PI / 6.0
		"deep":    sp.angle_constraint = PI / 10.0
		"flat":    sp.angle_constraint = PI / 11.0
		"heavy":   sp.angle_constraint = PI / 12.0
		_:         sp.angle_constraint = PI / 8.0

	# ④ 配色：生态标签定主色，品阶色定稀有度气质；鱼缸里同生态读得出一类，但不会全靠 tier 染色。
	var tier_col: Color = FishData.TIER_COLORS[clampi(tier, 0, FishData.TIER_COLORS.size() - 1)]
	var habitat_col := _habitat_color(id, name, tags)
	var base := habitat_col.lerp(tier_col, clampf(0.16 + float(tier) * 0.035, 0.16, 0.34))
	sp.body_color = base.darkened(0.06)
	sp.fin_color = base.lightened(0.24).lerp(tier_col.lightened(0.10), 0.18)
	sp.belly_color = base.lightened(0.48)
	var palette := _icon_palette(id)
	if not palette.is_empty():
		sp.body_color = (palette["body"] as Color).darkened(0.04)
		sp.fin_color = (palette["accent"] as Color).lightened(0.12)
		sp.belly_color = (palette["belly"] as Color).lightened(0.18)
	if key == "flat":
		sp.belly_color = sp.belly_color.darkened(0.08)
	if tags.has("deep") or tags.has("night"):
		sp.body_color = sp.body_color.darkened(0.16)
		sp.fin_color = sp.fin_color.darkened(0.06)
	if tags.has("protected"):
		sp.fin_color = sp.fin_color.lerp(Color(0.86, 0.78, 0.52), 0.22)

	# ⑤ 变体：把变体色混入身/鳍（程序化鱼直接调色，比 PNG 外部 tint 更自然）；七彩另由 ProcFish 加流光。
	if var_index >= 1:
		var vc := FishData.variant_color(var_index)
		var mix: float = [0.0, 0.28, 0.55, 0.40][clampi(var_index, 0, 3)]
		sp.body_color = sp.body_color.lerp(vc, mix * 0.65)
		sp.fin_color = sp.fin_color.lerp(vc, mix)
		sp.belly_color = sp.belly_color.lerp(vc, mix * 0.5)
	if sp.quality >= 2:
		var qmix := 0.08 * float(sp.quality - 1)
		sp.belly_color = sp.belly_color.lightened(qmix)
		sp.fin_color = sp.fin_color.lightened(qmix * 0.7)

	# ⑥ 花纹：优先从生态/名称取意，再用 id 稳定补足，让同缸的鱼看着各不相同。
	var h := absi(int(id.hash()))
	var stripe_hint := _text_has_any(id + name, ["stripe", "bar", "tiger", "斑", "鲈", "鲭"])
	var spot_hint := _text_has_any(id + name, ["spot", "dot", "puffer", "grouper", "星", "点", "鳜"])
	var line_hint := _text_has_any(id + name, ["salmon", "trout", "taimen", "tuna", "mackerel", "鲑", "鳟", "金枪", "鲭", "鲹"])
	var ring_hint := _text_has_any(id + name, ["koi", "goldfish", "clownfish", "锦鲤", "金鱼", "小丑"])
	var bio_hint := tags.has("deep") or tags.has("cavern") or _text_has_any(id + name,
		["lanternfish", "bristlemouth", "dragonfish", "anglerfish", "hatchetfish", "blind", "cave", "灯笼", "钻光", "巨口", "鮟鱇", "盲", "洞"])
	if bio_hint:
		sp.pattern = Pattern.BIOLUMEN
		sp.pattern_color = sp.belly_color.lightened(0.35).lerp(Color(0.55, 0.88, 1.0), 0.35)
		sp.pattern_color.a = 0.54
		sp.glow_mult += 0.32
	elif ring_hint:
		sp.pattern = Pattern.RINGS
		sp.pattern_color = sp.fin_color.lightened(0.2)
		sp.pattern_color.a = 0.46
	elif tags.has("reef") or spot_hint:
		sp.pattern = Pattern.SPOTS
		sp.pattern_color = sp.belly_color.lightened(0.1)
		sp.pattern_color.a = 0.42
	elif tags.has("stream") or stripe_hint:
		sp.pattern = Pattern.STRIPES
		sp.pattern_color = sp.body_color.darkened(0.32)
		sp.pattern_color.a = 0.50
	elif line_hint:
		sp.pattern = Pattern.LATERAL_LINE
		sp.pattern_color = sp.fin_color.lightened(0.12)
		sp.pattern_color.a = 0.50
	else:
		match h % 3:
			0:
				sp.pattern = Pattern.NONE
			1:
				sp.pattern = Pattern.STRIPES
				sp.pattern_color = sp.body_color.darkened(0.32)
				sp.pattern_color.a = 0.46
			2:
				sp.pattern = Pattern.BLOTCHES
				sp.pattern_color = sp.body_color.darkened(0.20).lerp(sp.fin_color, 0.25)
				sp.pattern_color.a = 0.34
	sp.pattern_density = clampf(0.80 + float(tier) * 0.08 + float(var_index) * 0.18 + float(sp.quality) * 0.05, 0.75, 1.75)
	sp.pattern_scale = clampf(0.92 + float(h % 7) * 0.035, 0.90, 1.16)
	if var_index >= 1:
		sp.pattern_color = sp.pattern_color.lerp(FishData.variant_color(var_index), 0.18 + 0.08 * float(var_index))
		sp.pattern_color.a = clampf(sp.pattern_color.a + 0.08 * float(var_index), 0.25, 0.72)
	sp.glow_mult += 0.08 * float(sp.quality)
	if var_index >= 2:
		sp.glow_mult += 0.28 + 0.12 * float(var_index - 2)
	sp.sparkle_mult = 0.10 * float(maxi(sp.quality - 1, 0)) + 0.18 * float(var_index)

	return sp


static func _apply_part_traits(sp: ProcFishSpecies, id: String, name: String, tags: Array, profile_key: String) -> void:
	var key_text := id + name
	if profile_key == "flat":
		sp.pectoral_mult *= 1.45
		sp.dorsal_mult *= 0.55
		sp.tail_mult *= 0.82
	elif profile_key == "heavy":
		sp.pectoral_mult *= 0.92
		sp.dorsal_mult *= 0.85
		sp.tail_mult *= 1.08
	elif profile_key == "slender":
		sp.pectoral_mult *= 0.82
		sp.tail_mult *= 1.16
	elif profile_key == "deep":
		sp.dorsal_mult *= 1.08
		sp.tail_mult *= 0.92
	if _text_has_any(key_text, ["grayling", "lancetfish", "sailfish", "lionfish", "帆", "茴鱼", "狮子鱼"]):
		sp.dorsal_mult *= 1.75
	if _text_has_any(key_text, ["hillstream", "torrent_catfish", "sculpin", "ray", "manta", "skate", "平鳍", "石爬", "杜父", "鳐", "鲼"]):
		sp.pectoral_mult *= 1.55
		sp.dorsal_mult *= 0.75
	if _text_has_any(key_text, ["tuna", "mackerel", "salmon", "taimen", "trevally", "鲑", "金枪", "鲭", "鲹"]):
		sp.tail_mult *= 1.22
	if _text_has_any(key_text, ["hatchetfish", "lanternfish", "dragonfish", "anglerfish", "bristlemouth", "cave", "blind", "灯笼", "巨口", "鮟鱇", "斧", "盲"]):
		sp.eye_mult *= 1.22
	if tags.has("deep") or tags.has("night") or tags.has("cavern"):
		sp.eye_mult *= 1.10
	if tags.has("reef"):
		sp.dorsal_mult *= 1.08
		sp.tail_mult *= 1.08


static func _pick_profile(id: String, name: String, tags: Array, wmax: float) -> String:
	var key_text := id + name
	if FLAT_IDS.has(id) or _text_has_any(key_text, ["ray", "skate", "flounder", "halibut", "pomfret", "鲆", "鳐", "鲳", "鲼"]):
		return "flat"
	if HEAVY_IDS.has(id) or wmax >= 80.0 or _text_has_any(key_text, ["sturgeon", "shark", "gar", "grouper", "catfish", "鲟", "鳇", "鲨", "鲇", "鲶", "鳄雀鳝"]):
		return "heavy"
	if SLENDER_IDS.has(id) or _text_has_any(key_text, ["eel", "loach", "hairtail", "oarfish", "lance", "rattail", "鳗", "鳝", "鳅", "带鱼", "皇带", "蛇", "鱵"]):
		return "slender"
	if DEEP_IDS.has(id) or _text_has_any(key_text, ["bream", "puffer", "boxfish", "butterfly", "angelfish", "鲂", "鳊", "鲫", "鲀", "鲳", "蝶", "箱"]):
		return "deep"
	if tags.has("deep") and wmax >= 15.0:
		return "heavy"
	return "standard"


static func _pick_swim_mode(id: String, name: String, tags: Array, profile_key: String, wmax: float) -> int:
	var key_text := id + name
	if profile_key == "slender" and _text_has_any(key_text, ["eel", "loach", "oarfish", "hairtail", "鳗", "鳝", "鳅", "皇带", "带鱼"]):
		return SwimMode.EEL
	if profile_key == "flat" or _text_has_any(key_text, ["ray", "skate", "flounder", "halibut", "鳐", "鲼", "鲆", "庸鲽"]):
		return SwimMode.GLIDE
	if tags.has("deep") or tags.has("cavern") or tags.has("protected") or wmax >= 80.0:
		return SwimMode.DEEP_DRIFT
	if tags.has("reef") or _text_has_any(key_text, ["puffer", "boxfish", "butterfly", "angelfish", "鲀", "箱", "蝶", "神仙"]):
		return SwimMode.HOVER
	if tags.has("stream") or _text_has_any(key_text, ["minnow", "zacco", "dace", "马口", "鱲", "雅罗"]):
		return SwimMode.DART
	return SwimMode.CRUISE


static func _habitat_color(id: String, name: String, tags: Array) -> Color:
	var key_text := id + name
	if tags.has("reef"):
		return Color(0.16, 0.62, 0.72).lerp(Color(0.95, 0.43, 0.28), 0.38)
	if tags.has("brackish"):
		return Color(0.42, 0.52, 0.32)
	if tags.has("polar") or tags.has("cold"):
		return Color(0.56, 0.74, 0.82)
	if tags.has("cavern"):
		return Color(0.34, 0.31, 0.42)
	if tags.has("urban"):
		return Color(0.42, 0.55, 0.46)
	if tags.has("deep"):
		return Color(0.18, 0.28, 0.48)
	if tags.has("coast"):
		return Color(0.22, 0.55, 0.68)
	if tags.has("stream"):
		return Color(0.38, 0.58, 0.64)
	if tags.has("lake"):
		return Color(0.30, 0.55, 0.42)
	if tags.has("river"):
		return Color(0.45, 0.50, 0.34)
	if _text_has_any(key_text, ["koi", "锦鲤"]):
		return Color(0.88, 0.45, 0.30)
	return Color(0.23, 0.49, 0.65)


static func _icon_palette(id: String) -> Dictionary:
	if _palette_cache.has(id):
		return _palette_cache[id]
	var out := {}
	var path := "res://assets/art/fish/%s.png" % id
	if not FileAccess.file_exists(path):
		_palette_cache[id] = out
		return out
	var tex := load(path) as Texture2D
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		img = Image.new()
		if img.load(path) != OK:
			_palette_cache[id] = out
			return out
	if img.is_compressed():
		img.decompress()
	if img.get_width() <= 0 or img.get_height() <= 0:
		_palette_cache[id] = out
		return out
	var avg := Vector3.ZERO
	var bright := Vector3.ZERO
	var accent := Vector3.ZERO
	var avg_w := 0.0
	var bright_w := 0.0
	var accent_w := 0.0
	var step := 2
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a < 0.18:
				continue
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			var sat := 0.0 if mx <= 0.001 else (mx - mn) / mx
			if mx > 0.92 and sat < 0.12:
				continue
			var w := c.a * clampf(0.45 + sat, 0.45, 1.25)
			var v := Vector3(c.r, c.g, c.b) * w
			avg += v
			avg_w += w
			if mx > 0.50:
				var bw := w * mx
				bright += Vector3(c.r, c.g, c.b) * bw
				bright_w += bw
			if sat > 0.16:
				var aw := w * sat
				accent += Vector3(c.r, c.g, c.b) * aw
				accent_w += aw
	if avg_w <= 0.0:
		_palette_cache[id] = out
		return out
	var body := _v3_to_color(avg / avg_w)
	var belly := _v3_to_color(bright / bright_w) if bright_w > 0.0 else body.lightened(0.25)
	var accent_col := _v3_to_color(accent / accent_w) if accent_w > 0.0 else body.lightened(0.18)
	out = {"body": body, "belly": belly, "accent": accent_col}
	_palette_cache[id] = out
	return out


static func _v3_to_color(v: Vector3) -> Color:
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0), 1.0)


static func _text_has_any(text: String, needles: Array) -> bool:
	var lower := text.to_lower()
	for n in needles:
		if lower.find(str(n).to_lower()) >= 0:
			return true
	return false
