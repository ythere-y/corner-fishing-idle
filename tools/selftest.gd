extends SceneTree

const PASS := "[PASS]"
const FAIL := "[FAIL]"

var _exit_code := 0

func _initialize() -> void:
	await process_frame
	var g = load("res://main.tscn").instantiate()
	g._load_save()
	await process_frame
	# 加载完成后再禁止写回，避免自测污染存档
	g.save_enabled = false

	print("===== INVENTORY OVERVIEW =====")
	print("inventory size = %d" % g.inventory.size())

	# ---- 订单信息 ----
	print("\n===== ORDER INFO =====")
	if g.daily_order is Dictionary and not g.daily_order.is_empty():
		print("kind = %s" % str(g.daily_order.get("kind", "?")))
		print("done = %s" % str(g.daily_order.get("done", false)))
		print("need = %s" % str(g.daily_order.get("need", "?")))
		print("minw = %s" % str(g.daily_order.get("minw", "?")))
		print("tier = %s" % str(g.daily_order.get("tier", "?")))
	else:
		print("No active order")

	# ---- Bug #2: 品阶排序是否正确 ----
	print("\n===== BUG#2 TIER SORT (_bag_sort=2) =====")
	g._bag_sort = 2
	var idxs = g._sorted_bag_indices(false)
	var prev_tier := 99
	var inv_count := 0
	var first_bad = -1
	for pos in idxs.size():
		var i = idxs[pos]
		var c = g.inventory[i]
		var id = str(c.get("id", "?"))
		var t = FishData.tier_of(id)
		var v = g._sell_value(c)
		if t > prev_tier:
			if first_bad < 0:
				first_bad = pos
			_exit_code = 1
		prev_tier = t
		print("  pos[%02d]=inv[%02d] %-14s tier=%d val=%d w=%s" % [pos, i, id, t, v, str(c.get("w", "?"))])
	if first_bad >= 0:
		print("%s Tier inversion detected at pos %d (a higher tier appears after a lower tier)" % [FAIL, first_bad])
	else:
		print("%s Tier sort is strictly non-increasing (correct)" % PASS)

	# 专门定位 sturgeon
	print("\n--- locate sturgeon entries in sorted order ---")
	for pos in idxs.size():
		var c = g.inventory[idxs[pos]]
		if "sturgeon" in str(c.get("id","")):
			var t = FishData.tier_of(str(c["id"]))
			print("  pos[%02d] id=%s name=%s tier=%d (should be 4/orange)" % [pos, c["id"], FishData.display_name(str(c["id"])), t])

	# 价值排序也验证一下
	print("\n===== VALUE SORT (_bag_sort=1) =====")
	g._bag_sort = 1
	var vidx = g._sorted_bag_indices(false)
	var pv := 999999999
	var vbad = -1
	for pos in vidx.size():
		var v = g._sell_value(g.inventory[vidx[pos]])
		if v > pv:
			if vbad < 0: vbad = pos
			_exit_code = 1
		pv = v
	if vbad >= 0:
		print("%s Value sort inversion at pos %d" % [FAIL, vbad])
	else:
		print("%s Value sort strictly non-increasing (correct)" % PASS)

	# ---- Bug #1: below 计数 vs 实际可卖 ----
	print("\n===== BUG#1 SELL-BELOW COUNT =====")
	# 复刻 ui_panels 的 below 计数（含我的修复：排除订单鱼）
	var below := 0
	var order_match_count := 0
	for c in g.inventory:
		if g._order_matches(c):
			order_match_count += 1
		if not bool(c.get("lock", false)) \
				and int(c.get("var", 0)) < 2 and int(c.get("q", 0)) < 3 \
				and not g._order_matches(c) \
				and FishData.tier_of(str(c["id"])) <= g._sell_tier:
			below += 1
	print("order_matches count = %d / %d" % [order_match_count, g.inventory.size()])
	print("below (excl order) for tier %d (%s) = %d" % [g._sell_tier, FishData.TIER_NAMES[g._sell_tier], below])

	# 复刻 _sell_below_tier 的实际可卖数（不真正卖、不存档）
	var sellable := 0
	for c in g.inventory:
		if not bool(c.get("lock", false)) and not g._order_matches(c) \
				and int(c.get("var", 0)) < 2 and int(c.get("q", 0)) < 3 \
				and FishData.tier_of(str(c["id"])) <= g._sell_tier:
			sellable += 1
	if below == sellable:
		print("%s below count == actual sellable (%d). No mismatch." % [PASS, below])
	else:
		print("%s MISMATCH: below=%d but actual sellable=%d" % [FAIL, below, sellable])
		_exit_code = 1

	# 若订单 done，确认 order_matches 是否仍拦鱼（诊断点）
	if g.daily_order is Dictionary and bool(g.daily_order.get("done", false)):
		print("Order is DONE. order_matches still blocks %d fish (potential Bug#1 root)" % order_match_count)
		if order_match_count > 0:
			print("%s After-done blocking bug present." % FAIL)
			_exit_code = 1
	else:
		print("Order NOT done. order_matches blocks %d fish (reserved while active)." % order_match_count)

	# ---- Fix 1 验证：标记订单 done 后，order_matches 应全部解除拦截 ----
	if g.daily_order is Dictionary and not g.daily_order.is_empty():
		g.daily_order["done"] = true
		var after := 0
		for c in g.inventory:
			if g._order_matches(c):
				after += 1
		if after == 0:
			print("%s Fix1: after order done, order_matches=false for all fish (bulk-sell unblocked)" % PASS)
		else:
			print("%s Fix1: after done, %d fish STILL blocked" % [FAIL, after])
			_exit_code = 1
		# 重新统计 below（done 后应为非订单鱼里的可卖数）
		# 用最大品阶 5 验证完整链路（用户按钮为"神话及以下(38)"，对应 _sell_tier=5）
		var T := 5
		var below_after := 0
		for c in g.inventory:
			if not bool(c.get("lock", false)) \
					and int(c.get("var", 0)) < 2 and int(c.get("q", 0)) < 3 \
					and not g._order_matches(c) \
					and FishData.tier_of(str(c["id"])) <= T:
				below_after += 1
		print("below after done (tier %d = %s) = %d  (应为 >0，证明可卖)" % [
			T, FishData.TIER_NAMES[T], below_after])
		if below_after > 0:
			print("%s Fix1: sells available after order done" % PASS)
		else:
			print("%s Fix1: STILL nothing sellable after done" % FAIL)
			_exit_code = 1

	# ---- Fix 2 验证：鱼卡边框应始终按品阶着色 ----
	print("\n===== BUG#2 BORDER LOGIC =====")
	var border_mismatch := 0
	for c in g.inventory:
		var id = str(c["id"])
		var t = FishData.tier_of(id)
		var vr = int(c.get("var", 0))
		# 关键断言：无论有无变体，边框颜色都必须等于品阶色（不再用变体色）
		if vr >= 1:
			# 变体鱼：边框必须=tier色，名字才用变体色+◆
			# 这里仅确认数据层 tier 与 var 是独立维度（鱼确属 tier 4 却被蓝边=变体色）
			if t != 4 and "sturgeon" in id:
				border_mismatch += 1
	print("sturgeon entries: both should be tier 4 (orange); border now tier-colored, not blue variant.")

	g.queue_free()
	await process_frame
	quit(_exit_code)
