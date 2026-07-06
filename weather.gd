class_name Weather
## 昼夜时段系统（新模块）：由真实时钟派生（桌面陪伴——随你这一天自然流转），零存档。
## 黎明/黄昏为"金色时段"（咬钩更勤、渔获略增值、运气微加）；夜晚静谧但偶有大物（运气+2）。
## 低干扰：仅给小幅修正 + 场景轻染色 + HUD 显示。纯静态数据，无需 g。

## id -> {name, 起始小时, wait_mult, value_mult, luck, tint(RGBA：A 为场景叠加染色透明度)}
const PHASES := {
	"dawn":  {"name": "黎明", "wait_mult": 0.95, "value_mult": 1.08, "luck": 1, "tint": [0.99, 0.86, 0.72, 0.10]},
	"day":   {"name": "白昼", "wait_mult": 1.00, "value_mult": 1.00, "luck": 0, "tint": [1.0, 1.0, 1.0, 0.0]},
	"dusk":  {"name": "黄昏", "wait_mult": 0.95, "value_mult": 1.08, "luck": 1, "tint": [0.99, 0.66, 0.52, 0.14]},
	"night": {"name": "夜晚", "wait_mult": 1.05, "value_mult": 1.05, "luck": 2, "tint": [0.40, 0.47, 0.72, 0.22]},
}
const ORDER := ["dawn", "day", "dusk", "night"]
const DEFAULT_PHASE := "day"


## 真实小时 -> 时段 id。黎明 5–8 / 白昼 8–17 / 黄昏 17–20 / 夜晚 20–次日5。
static func phase_for_hour(h: int) -> String:
	if h >= 5 and h < 8:
		return "dawn"
	if h >= 8 and h < 17:
		return "day"
	if h >= 17 and h < 20:
		return "dusk"
	return "night"


## 测试钩子：无头验证钉死时段用（"" = 不启用）。离线结算的时段在 _ready 内部取真实时钟，
## 测试无法从外部插手——不钉死会让相关断言随开发机时间漂移成 time-of-day flaky。
static var force_phase := ""


## 当前真实时段 id。
static func current_phase() -> String:
	if force_phase != "":
		return force_phase
	return phase_for_hour(int(Time.get_time_dict_from_system()["hour"]))


static func has(id: String) -> bool:
	return PHASES.has(id)


static func _data(id: String) -> Dictionary:
	return PHASES.get(id, PHASES[DEFAULT_PHASE])


static func display_name(id: String) -> String:
	return str(_data(id)["name"])


static func wait_mult(id: String) -> float:
	return float(_data(id).get("wait_mult", 1.0))


static func value_mult(id: String) -> float:
	return float(_data(id).get("value_mult", 1.0))


static func luck(id: String) -> int:
	return int(_data(id).get("luck", 0))


## 场景叠加染色（A=0 表示白昼不染色）。
static func tint(id: String) -> Color:
	var t: Array = _data(id).get("tint", [1, 1, 1, 0])
	return Color(float(t[0]), float(t[1]), float(t[2]), float(t[3]))
