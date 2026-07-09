class_name AnglerEquipment
extends RefCounted
## 人物属性装备公式。装备等级持续线性提供角色属性；钓鱼结果层再做软上限。

const AnglerStatsScript := preload("res://systems/angler/angler_stats.gd")

const REEL_NAME := "绕线轮"
const REEL_COST_BASE := 250.0
const REEL_COST_GROWTH := 1.12
const SPEED_EFFECT_SOFTNESS := 80.0
const SPEED_WAIT_MULT_FLOOR := 0.42
const ATTR_COST_BASE := 250.0
const ATTR_COST_GROWTH := 1.12

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


static func reel_next_cost(level: int) -> int:
	return int(round(REEL_COST_BASE * pow(REEL_COST_GROWTH, maxi(0, level))))


static func reel_upgrade_cost(level: int, count: int) -> int:
	var total := 0
	for i in maxi(0, count):
		total += reel_next_cost(level + i)
	return total


static func reel_stats(level: int):
	var stats = AnglerStatsScript.new()
	stats.speed = float(maxi(0, level))
	return stats


static func speed_wait_mult(speed: float) -> float:
	var progress := 1.0 - exp(-maxf(0.0, speed) / SPEED_EFFECT_SOFTNESS)
	return lerpf(1.0, SPEED_WAIT_MULT_FLOOR, progress)


static func reel_wait_mult(level: int) -> float:
	return speed_wait_mult(reel_stats(level).speed)


static func attr_equipment_next_cost(level: int) -> int:
	return int(round(ATTR_COST_BASE * pow(ATTR_COST_GROWTH, maxi(0, level))))


static func attr_equipment_upgrade_cost(level: int, count: int) -> int:
	var total := 0
	for i in maxi(0, count):
		total += attr_equipment_next_cost(level + i)
	return total


static func attr_equipment_stats(id: String, level: int):
	var stats = AnglerStatsScript.new()
	if not ATTR_EQUIPMENT.has(id):
		return stats
	var lv := float(maxi(0, level))
	var attrs: Dictionary = ATTR_EQUIPMENT[id]["attrs"]
	for key in attrs:
		stats.set(str(key), lv * float(attrs[key]))
	return stats
