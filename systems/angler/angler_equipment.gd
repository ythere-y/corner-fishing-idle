class_name AnglerEquipment
extends RefCounted
## 人物属性装备公式。装备等级持续线性提供角色属性；钓鱼结果层再做软上限。

const AnglerStatsScript := preload("res://systems/angler/angler_stats.gd")

const REEL_NAME := "绕线轮"
const SPEED_EFFECT_SOFTNESS := 80.0
const SPEED_WAIT_MULT_FLOOR := 0.42

const EQUIPMENT_UNLOCK_ORDER := ["fish_line", "reel", "bobber", "sonar", "notebook", "gloves"]
const FIRST_EQUIPMENT_BASE_COST := 250.0
const EQUIPMENT_UNLOCK_ANCHOR_LEVEL := 22
const EQUIPMENT_COST_GROWTH_BASE := 1.12
const EQUIPMENT_COST_GROWTH_STEP := 0.005
const MAX_ECON_VALUE := 1.0e300

const ATTR_EQUIPMENT := {
	"fish_line": {
		"name": "鱼线",
		"icon": "res://assets/art/equipment/fish_line.png",
		"attrs": {"technique": 0.55, "stability": 0.45},
		"desc": "提升技巧与巨物稳定性",
	},
	"bobber": {
		"name": "浮漂",
		"icon": "res://assets/art/equipment/bobber.png",
		"attrs": {"reaction": 0.60, "perception": 0.40},
		"desc": "提升反应与事件感知",
	},
	"sonar": {
		"name": "探鱼器",
		"icon": "res://assets/art/equipment/fish_finder.png",
		"attrs": {"ecology": 0.55, "perception": 0.45},
		"desc": "提升生态知识与稀有感知",
	},
	"notebook": {
		"name": "钓鱼笔记",
		"icon": "res://assets/art/equipment/fishing_notebook.png",
		"attrs": {"ecology": 0.50, "tracking": 0.50},
		"desc": "提升生态知识与图鉴追踪",
	},
	"gloves": {
		"name": "钓鱼手套",
		"icon": "res://assets/art/equipment/fishing_gloves.png",
		"attrs": {"strength": 0.55, "technique": 0.45},
		"desc": "提升力量与技巧",
	},
}

const ATTR_EQUIPMENT_ORDER := ["fish_line", "bobber", "sonar", "notebook", "gloves"]


static func equipment_order() -> Array:
	return EQUIPMENT_UNLOCK_ORDER.duplicate()


static func equipment_index(id: String) -> int:
	return EQUIPMENT_UNLOCK_ORDER.find(id)


static func equipment_name(id: String) -> String:
	if id == "reel":
		return REEL_NAME
	if ATTR_EQUIPMENT.has(id):
		return str(ATTR_EQUIPMENT[id]["name"])
	return id


static func equipment_prev_id(id: String) -> String:
	var idx := equipment_index(id)
	if idx <= 0:
		return ""
	return str(EQUIPMENT_UNLOCK_ORDER[idx - 1])


static func equipment_cost_growth(id: String) -> float:
	var idx := equipment_index(id)
	if idx < 0:
		idx = 0
	return EQUIPMENT_COST_GROWTH_BASE + EQUIPMENT_COST_GROWTH_STEP * float(idx)


static func equipment_base_cost(id: String) -> float:
	var idx := equipment_index(id)
	if idx <= 0:
		return round(FIRST_EQUIPMENT_BASE_COST)
	var prev := equipment_prev_id(id)
	return _round_unlock_cost(equipment_next_cost(prev, EQUIPMENT_UNLOCK_ANCHOR_LEVEL - 1))


static func equipment_next_cost(id: String, level: int) -> float:
	var raw := float(equipment_base_cost(id)) * pow(equipment_cost_growth(id), maxi(0, level))
	return _safe_econ_number(raw)


static func equipment_upgrade_cost(id: String, level: int, count: int) -> float:
	var total := 0.0
	for i in maxi(0, count):
		total += equipment_next_cost(id, level + i)
		if total >= MAX_ECON_VALUE:
			return MAX_ECON_VALUE
	return _safe_econ_number(total)


static func equipment_unlock_target(id: String) -> int:
	var prev := equipment_prev_id(id)
	if prev == "":
		return 0
	return EQUIPMENT_UNLOCK_ANCHOR_LEVEL


static func equipment_unlock_cost(id: String) -> float:
	var prev := equipment_prev_id(id)
	if prev == "":
		return 0.0
	return equipment_next_cost(id, 0)


static func equipment_unlock_note(id: String) -> String:
	var prev := equipment_prev_id(id)
	if prev == "":
		return ""
	return "约等于%s Lv.%d 单次价" % [equipment_name(prev), equipment_unlock_target(id)]


static func _round_unlock_cost(raw: float) -> float:
	if raw < 1000:
		return round(raw / 10.0) * 10.0
	if raw < 10000:
		return round(raw / 500.0) * 500.0
	if raw < 100000:
		return round(raw / 5000.0) * 5000.0
	if raw < 1000000:
		return round(raw / 50000.0) * 50000.0
	return round(raw / 100000.0) * 100000.0


static func _safe_econ_number(raw: float) -> float:
	if is_nan(raw) or is_inf(raw) or raw <= 0.0:
		return 0.0 if not is_inf(raw) else MAX_ECON_VALUE
	if raw >= MAX_ECON_VALUE:
		return MAX_ECON_VALUE
	return round(raw)


static func reel_next_cost(level: int) -> float:
	return equipment_next_cost("reel", level)


static func reel_upgrade_cost(level: int, count: int) -> float:
	return equipment_upgrade_cost("reel", level, count)


static func reel_stats(level: int):
	var stats = AnglerStatsScript.new()
	stats.speed = float(maxi(0, level))
	return stats


static func speed_wait_mult(speed: float) -> float:
	var progress := 1.0 - exp(-maxf(0.0, speed) / SPEED_EFFECT_SOFTNESS)
	return lerpf(1.0, SPEED_WAIT_MULT_FLOOR, progress)


static func reel_wait_mult(level: int) -> float:
	return speed_wait_mult(reel_stats(level).speed)


static func attr_equipment_next_cost(level: int) -> float:
	return equipment_next_cost("fish_line", level)


static func attr_equipment_upgrade_cost(level: int, count: int) -> float:
	return equipment_upgrade_cost("fish_line", level, count)


static func attr_equipment_stats(id: String, level: int):
	var stats = AnglerStatsScript.new()
	if not ATTR_EQUIPMENT.has(id):
		return stats
	var lv := float(maxi(0, level))
	var attrs: Dictionary = ATTR_EQUIPMENT[id]["attrs"]
	for key in attrs:
		stats.set(str(key), lv * float(attrs[key]))
	return stats
