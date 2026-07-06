extends SceneTree
## 数值平衡探针（只读分析，不改存档）：打印各鱼竿/鱼饵/鱼钩/诱饵下的产出曲线与升级回本时间。
## 回本口径统一为「边际」：升级花费 ÷ (下一档收益 − 当前档收益)——强制逐档购买下这是唯一正确口径
## （旧版 成本÷该档总收入 / 对 0 档差分 会把回本虚低 1.5~4.5 倍，见 docs/balance_audit_2026-07-06.md）。
## ⚠ 本文件含真值公式的手工副本，主代码改动后必须同步，否则探针静默漂移：
##   main.gd —— 间隔基数 5.25 与等待折扣 0.04（_begin_wait/_offline_catch）、竿价 400×1.7^n（_rod_cost）、
##              离线 8h 上限与 0.5 效率（OFFLINE_CAP/OFFLINE_EFFICIENCY）、背包扩容价目文本；
##   fish_data.gd —— 价值 +8%/级（roll_catch 的 rod_mult）；品质/变体倍率已改为直读常量，不会漂。
## 运行: godot_console --headless -s tools/balance_probe.gd

func _init() -> void:
	_run()


func _avg_interval(rod: int) -> float:
	return 5.25 * maxf(0.4, 1.0 - float(rod - 1) * 0.04) + 0.9   # 同 main._begin_wait/_offline_catch


func _quality_mult(bait: int) -> float:
	var p: Array = FishData.BAITS[bait]["probs"]
	var p1 := float(p[1])
	var p2 := float(p[2])
	var p3 := float(p[3])
	var probs := [1.0 - p1, p1 - p1 * p2, p1 * p2 - p1 * p2 * p3, p1 * p2 * p3]
	var ev := 0.0
	for q in 4:
		ev += float(probs[q]) * float(FishData.QUALITY_MULTS[q])
	return ev


func _variant_mult(lure: int) -> float:
	# 变体期望倍率：E = 1 + Σ P(vi)·(1+vbias)·(mult(vi)−1)，同 FishData.roll_variant 的 scale 语义。
	var s := 1.0 + clampf(FishData.lure_vbias(lure), 0.0, 10.0)
	var ev := 1.0
	for vi in range(1, FishData.VARIANT_PROBS.size()):
		ev += float(FishData.VARIANT_PROBS[vi]) * s * (float(FishData.VARIANT_MULTS[vi]) - 1.0)
	return ev


func _base_ev(rod: int) -> float:
	var w := FishData.weights_for_rod(rod)
	var total := 0.0
	for r in w:
		total += w[r]
	var count := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for id in FishData.FISH:
		count[FishData.tier_of(str(id))] += 1
	var ev := 0.0
	for id in FishData.FISH:
		var f: Dictionary = FishData.FISH[id]
		var r := int(f["tier"])
		var pr: float = (float(w[r]) / total) / float(count[r])
		ev += pr * (float(f["vmin"]) + float(f["vmax"])) * 0.5
	return ev * (1.0 + float(rod - 1) * 0.08)


func _rod_cost(level: int) -> int:
	return int(round(400.0 * pow(1.7, level - 1)))   # 同 main._rod_cost


## 金币/分钟（含品质期望；钩/变体维度由各段落按需另乘）。
func _income(rod: int, bait: int) -> float:
	return _base_ev(rod) * _quality_mult(bait) * 60.0 / _avg_interval(rod)


func _run() -> void:
	await process_frame
	print("=== 产出曲线（金币/分钟，含品质期望）===")
	print("rod | bait蚯蚓 | bait秘制 | 间隔s")
	for rod in [1, 3, 5, 8]:
		print("  %d | %6.1f | %6.1f | %.2f" % [rod, _income(rod, 0), _income(rod, 3), _avg_interval(rod)])

	print("=== 鱼竿升级回本（蚯蚓，纯主动，边际口径）===")
	var cum := 0
	for lv in range(1, 17):
		var cost := _rod_cost(lv)
		cum += cost
		var cur := _income(lv, 0)
		var delta := _income(lv + 1, 0) - cur
		print("  Lv%d→%d 花费 %d（累计 %d）｜该级 %.1f 金/分（升级 +%.1f）｜边际回本 %.1f 分" % [
			lv, lv + 1, cost, cum, cur, delta, float(cost) / maxf(delta, 0.01)])

	print("=== 鱼饵回本（rod=3 基准，相邻档边际）===")
	for bait in range(FishData.BAITS.size()):
		var b: Dictionary = FishData.BAITS[bait]
		var gain := _income(3, bait)
		var delta := 0.0
		if bait > 0:
			delta = gain - _income(3, bait - 1)
		var payback := float(int(b["cost"])) / maxf(delta, 0.01) if bait > 0 else 0.0
		print("  %s 花费 %d ｜ %.1f 金/分（比上一档 +%.1f）｜边际回本 %.1f 分" % [
			str(b["name"]), int(b["cost"]), gain, delta, payback])

	print("=== 鱼钩回本（rod=5 秘制饵基准，相邻档边际）===")
	var hbase := _income(5, 3)
	for hk in range(FishData.HOOKS.size()):
		var h: Dictionary = FishData.HOOKS[hk]
		var gain := hbase * (1.0 + float(h["double"]))
		var delta := 0.0
		if hk > 0:
			delta = hbase * (float(h["double"]) - float(FishData.HOOKS[hk - 1]["double"]))
		var payback := float(int(h["cost"])) / maxf(delta, 0.01) if hk > 0 else 0.0
		print("  %s 花费 %d ｜双钩 %d%% ｜ %.0f 金/分（比上一档 +%.0f）｜边际回本 %.1f 分" % [
			str(h["name"]), int(h["cost"]), int(float(h["double"]) * 100.0), gain, delta, payback])

	print("=== 诱饵/窝料回本（rod=5 秘制饵基准，变体期望，相邻档边际）===")
	for li in range(FishData.LURES.size()):
		var l: Dictionary = FishData.LURES[li]
		var gain := hbase * _variant_mult(li)
		var delta := 0.0
		if li > 0:
			delta = hbase * (_variant_mult(li) - _variant_mult(li - 1))
		var payback := float(int(l["cost"])) / maxf(delta, 0.01) if li > 0 else 0.0
		print("  %s 花费 %d ｜vbias %.1f ｜变体期望 ×%.3f ｜ %.0f 金/分（比上一档 +%.0f）｜边际回本 %.1f 分" % [
			str(l["name"]), int(l["cost"]), FishData.lure_vbias(li), _variant_mult(li), gain, delta, payback])

	print("=== 背包扩容 vs 离线 8h 产出（rod=3 蚯蚓）===")
	var off8 := _income(3, 0) * 8.0 * 60.0 * 0.5
	print("  离线 8h 估值上限 ≈ %d 金币（实际受背包格数截断）" % int(off8))
	print("  背包容量/扩容费：20→25(100) 25→30(250) ... 50→55(25000)")

	print("=== 全装满 vs 全裸 产出对比（含钩/变体维度）===")
	var bare := _income(1, 0) * (1.0 + float(FishData.HOOKS[0]["double"])) * _variant_mult(0)
	var maxed := _income(10, 3) * (1.0 + float(FishData.HOOKS[FishData.HOOKS.size() - 1]["double"])) \
		* _variant_mult(FishData.LURES.size() - 1)
	print("  全裸(rod1/蚯蚓/基础钩/无窝料) %.0f 金/分 → 全满(rod10/秘制/双叉/麝香) %.0f 金/分（×%.1f）" % [
		bare, maxed, maxed / bare])
	quit()
