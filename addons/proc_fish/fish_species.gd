class_name ProcFishSpecies
extends RefCounted
## 物种蓝图（纯数据）：描述「一条鱼长什么样」——体型剖面 / 关节参数 / 配色 / 花纹。
## 与「怎么让脊椎动 / 怎么画」（ProcFishSpine + ProcFish）解耦：加新种类 / 花纹 = 只动这里。
##
## 扩展指引：
##   · 加体型 → 在 PROFILES 里加一条归一化半宽剖面，并在 _pick_profile 里给出选择条件。
##   · 加花纹 → 在 Pattern 枚举加一项，并在 ProcFish._draw_pattern 里加一个绘制分支。
##   · 定制某条鱼 → 在 from_catch 末尾按 id 覆盖字段即可（具名特例）。

enum Pattern { NONE, STRIPES, SPOTS }

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
}

# 已知细长 / 高身体型的鱼种（其余走 standard）。列表即扩展点，加 id 立即生效。
const SLENDER_IDS := ["swampeel", "conger", "hairtail", "halfbeak", "sandlance",
	"icefish", "ricefish", "loach", "spined_loach", "bigscale_loach"]
const DEEP_IDS := ["crucian", "bream", "fangbream", "wuchang", "blackbream",
	"pufferfish", "mandarin", "bluegill", "paradisefish", "tilapia"]

var body_width: PackedFloat32Array = PackedFloat32Array()  # 每个身体关节的像素半宽（已缩放）
var link_size: float = 5.0                                  # 关节间距（px）→ 决定总长
var angle_constraint: float = PI / 8.0                      # 摆动柔度
var body_color: Color = Color(0.23, 0.49, 0.65)
var fin_color: Color = Color(0.51, 0.76, 0.84)
var belly_color: Color = Color(0.72, 0.86, 0.90)
var pattern: int = Pattern.NONE
var pattern_color: Color = Color(1, 1, 1, 0.25)
var variant: int = 0                                        # 0 普通 / 1 斑斓 / 2 鎏金 / 3 七彩
var body_len: float = 50.0                                  # 头→尾大致像素长度（命中判定 / 布局用）


## 从一条渔获（id + 变体 + 体重）派生物种蓝图。weight<0 时取该鱼种体重区间中点。
static func from_catch(id: String, var_index: int = 0, weight: float = -1.0) -> ProcFishSpecies:
	var sp := new()
	sp.variant = var_index
	var tier := FishData.tier_of(id)
	var f: Dictionary = FishData.FISH.get(id, {})
	var wmin := float(f.get("wmin", 0.1))
	var wmax := float(f.get("wmax", 1.0))
	if weight < 0.0:
		weight = (wmin + wmax) * 0.5

	# ① 体型模板
	var key := "standard"
	if SLENDER_IDS.has(id):
		key = "slender"
	elif DEEP_IDS.has(id):
		key = "deep"
	var profile: Array = PROFILES[key]

	# ② 尺寸：体重按对数映射到像素半宽，钳进缸内友好区间；细长体略瘦、高身体略胖。
	var wr: float = 0.0
	if wmax > wmin:
		wr = clampf((weight - wmin) / (wmax - wmin), 0.0, 1.0)
	# 跨鱼种基准：对数压缩体重（0.005kg 小鱼 → 大鱼 15kg+），再叠本鱼种内的相对大小。
	var log_scale := clampf((log(weight + 0.05) - log(0.05)) / (log(15.0) - log(0.05)), 0.0, 1.0)
	var base_width := lerpf(6.0, 15.0, log_scale) * lerpf(0.85, 1.12, wr)
	if key == "slender":
		base_width *= 0.7
	elif key == "deep":
		base_width *= 1.05

	sp.body_width = PackedFloat32Array()
	for i in profile.size():
		sp.body_width.append(float(profile[i]) * base_width)
	sp.link_size = base_width * lerpf(0.62, 0.5, log_scale)   # 大鱼相对更修长
	sp.body_len = sp.link_size * float(TOTAL_JOINTS - 1)

	# ③ 柔度：小/细长鱼灵活，大/高身鱼僵硬
	match key:
		"slender": sp.angle_constraint = PI / 6.0
		"deep":    sp.angle_constraint = PI / 10.0
		_:         sp.angle_constraint = PI / 8.0

	# ④ 配色：以品阶色为基调，保留「中身 / 浅鳍 / 更浅腹」的层次（参考蓝鱼配色的明度结构）。
	var tier_col: Color = FishData.TIER_COLORS[clampi(tier, 0, FishData.TIER_COLORS.size() - 1)]
	var base := tier_col.lerp(Color(0.23, 0.49, 0.65), 0.42)
	sp.body_color = base.darkened(0.08)
	sp.fin_color = base.lightened(0.30)
	sp.belly_color = base.lightened(0.52)

	# ⑤ 变体：把变体色混入身/鳍（程序化鱼直接调色，比 PNG 外部 tint 更自然）；七彩另由 ProcFish 加流光。
	if var_index >= 1:
		var vc := FishData.variant_color(var_index)
		var mix: float = [0.0, 0.28, 0.55, 0.40][clampi(var_index, 0, 3)]
		sp.body_color = sp.body_color.lerp(vc, mix * 0.65)
		sp.fin_color = sp.fin_color.lerp(vc, mix)
		sp.belly_color = sp.belly_color.lerp(vc, mix * 0.5)

	# ⑥ 花纹（MVP）：按 id 稳定分配，让同缸的鱼看着各不相同。低干扰、半透明叠在鱼身上。
	var h := absi(int(id.hash()))
	match h % 3:
		0:
			sp.pattern = Pattern.NONE
		1:
			sp.pattern = Pattern.STRIPES
			sp.pattern_color = sp.body_color.darkened(0.32)
			sp.pattern_color.a = 0.5
		2:
			sp.pattern = Pattern.SPOTS
			sp.pattern_color = sp.belly_color.lightened(0.1)
			sp.pattern_color.a = 0.4

	return sp
