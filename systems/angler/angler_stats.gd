class_name AnglerStats
extends RefCounted
## 主角属性层。装备先汇总到这里，再间接影响钓鱼结果与开发面板指标。

var speed := 0.0
var technique := 0.0
var stability := 0.0
var reaction := 0.0
var perception := 0.0
var ecology := 0.0
var tracking := 0.0
var strength := 0.0


func add(other: AnglerStats) -> void:
	speed += other.speed
	technique += other.technique
	stability += other.stability
	reaction += other.reaction
	perception += other.perception
	ecology += other.ecology
	tracking += other.tracking
	strength += other.strength


func copy() -> AnglerStats:
	var out := AnglerStats.new()
	out.speed = speed
	out.technique = technique
	out.stability = stability
	out.reaction = reaction
	out.perception = perception
	out.ecology = ecology
	out.tracking = tracking
	out.strength = strength
	return out
