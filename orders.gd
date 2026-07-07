class_name Orders
## 每日订单 + 周目标 + 今日统计（从 main.gd 拆出）。纯逻辑，状态在主节点 g 上
## （daily_order / weekly / day_stat）。行为与原 main.gd 内嵌实现完全一致（仅迁移 + g. 前缀）。
## main 留薄壳 wrapper（测试 / ui_panels / 主控均按 g._foo 调用，API 不变）。


# ============================ 今日统计 ============================

static func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## 维护当日起点快照（跨天自动重置）。用于统计页"今日渔获/收入"。
static func ensure_day_stat(g: CornerFishing) -> void:
	var today := today_key()
	if str(g.day_stat.get("date", "")) != today:
		if g.day_stat.has("date"):
			# 跨天：沉淀"昨日"（上个游玩日）卖鱼收入，作周赛/周目标奖励的收入锚（P1）
			g.yest_income = maxi(0, g.lifetime_coins - int(g.day_stat.get("coins", 0)))
		g.day_stat = {"date": today, "catches": g.lifetime_catches, "coins": g.lifetime_coins}


static func today_catches(g: CornerFishing) -> int:
	ensure_day_stat(g)
	return maxi(0, g.lifetime_catches - int(g.day_stat.get("catches", 0)))


static func today_income(g: CornerFishing) -> int:
	ensure_day_stat(g)
	return maxi(0, g.lifetime_coins - int(g.day_stat.get("coins", 0)))


# ============================ 每日订单 ============================

static func ensure_daily_order(g: CornerFishing) -> void:
	var today := today_key()
	if g.daily_order.has("date") and str(g.daily_order.get("date", "")) == today \
			and FishData.FISH.has(str(g.daily_order.get("fish", ""))) \
			and int(g.daily_order.get("need", 0)) > 0:
		return
	g.daily_order = make_daily_order(g, today)


## 生成每日订单。kind ∈ species/tier/weight/perfect（perfect 需鱼饵≥2 才出，避免难以达成）。
## fish 字段恒为一个有效鱼 id（作图标与 species 目标），保证旧存档守卫兼容。
static func make_daily_order(g: CornerFishing, date_key: String) -> Dictionary:
	var local := RandomNumberGenerator.new()
	local.seed = int(abs(("%s:%d" % [date_key, g.rod_level]).hash()))
	var max_tier := clampi(1 + int(float(g.rod_level - 1) / 3.0), 1, 3)
	# 候选鱼 = 所有已解锁钓点鱼池的并集（保证订单可在某已解锁钓点完成；多钓点感知）
	var ids := g._order_pool()
	if ids.is_empty():
		ids = FishData.FISH.keys()
	var candidates: Array = []
	for id in ids:
		if FishData.tier_of(str(id)) <= max_tier:
			candidates.append(str(id))
	if candidates.is_empty():
		candidates = ids
	var fish_id: String = candidates[local.randi() % candidates.size()]
	var kinds := ["species", "species", "species", "tier", "weight"]
	if g.bait_level >= 2:
		kinds.append("perfect")
	var kind: String = kinds[local.randi() % kinds.size()]
	var order := {"date": date_key, "kind": kind, "fish": fish_id, "done": false,
		"need": 1, "tier": 1, "minw": 1.0}
	# P1 吞吐上调（balance_audit §3.1：原 need 1~5 使订单收入占比 <0.5%，噪声级）：
	# 目标 = 订单消化渔获 5~15%、收入占比有存在感；need 恒按鱼篓容量封顶（防物理不可能）。
	match kind:
		"tier":
			var mt := local.randi_range(1, max_tier)
			order["tier"] = mt
			order["need"] = maxi(7 - 2 * mt, 2)   # t1:5 / t2:3 / t3:2
			order["fish"] = rep_fish_of_tier(mt, local, ids)
		"weight":
			order["minw"] = [1.0, 2.0, 3.0][local.randi_range(0, 2)]
			order["need"] = local.randi_range(2, 4)
		"perfect":
			order["need"] = 1
		_:  # species
			match FishData.tier_of(fish_id):
				0: order["need"] = local.randi_range(8, 12)
				1: order["need"] = local.randi_range(5, 8)
				2: order["need"] = local.randi_range(3, 5)
				_: order["need"] = local.randi_range(1, 2)
	order["need"] = mini(int(order["need"]), maxi(1, g._bag_capacity() - 4))
	order["spot"] = g._best_spot_for(str(order["fish"]))  # 建议钓点提示
	return order


## 取某品阶的代表鱼 id（仅用于订单图标/建议）。pool 限定候选鱼范围。
static func rep_fish_of_tier(t: int, local: RandomNumberGenerator, pool: Array = []) -> String:
	var src: Array = pool if not pool.is_empty() else FishData.FISH.keys()
	var bucket: Array = []
	for id in src:
		if FishData.tier_of(str(id)) == t:
			bucket.append(str(id))
	if bucket.is_empty():
		return str(src[0]) if not src.is_empty() else str(FishData.FISH.keys()[0])
	bucket.sort()
	return str(bucket[local.randi() % bucket.size()])


## 一条渔获是否满足当前订单（不含上锁判定）。
static func order_matches(g: CornerFishing, c: Dictionary) -> bool:
	match str(g.daily_order.get("kind", "species")):
		"tier":
			return FishData.tier_of(str(c.get("id", ""))) >= int(g.daily_order.get("tier", 1))
		"weight":
			return float(c.get("w", 0.0)) >= float(g.daily_order.get("minw", 1.0))
		"perfect":
			return int(c.get("q", 0)) >= 3
		_:
			return str(c.get("id", "")) == str(g.daily_order.get("fish", ""))


## 订单一句话标题。
static func order_title(g: CornerFishing) -> String:
	var need := int(g.daily_order.get("need", 1))
	match str(g.daily_order.get("kind", "species")):
		"tier":
			return "收 %d 条 %s及以上" % [need, FishData.TIER_NAMES[int(g.daily_order.get("tier", 1))]]
		"weight":
			return "收 %d 条 ≥%.1fkg 的鱼" % [need, float(g.daily_order.get("minw", 1.0))]
		"perfect":
			return "收 %d 条 完美★★★渔获" % need
		_:
			return "收 %d 条 %s" % [need, FishData.display_name(str(g.daily_order.get("fish", "")))]


## HUD 用的订单短标签。
static func order_short(g: CornerFishing) -> String:
	match str(g.daily_order.get("kind", "species")):
		"tier":
			return "%s+" % FishData.TIER_NAMES[int(g.daily_order.get("tier", 1))]
		"weight":
			return "≥%.1fkg" % float(g.daily_order.get("minw", 1.0))
		"perfect":
			return "完美★"
		_:
			return FishData.display_name(str(g.daily_order.get("fish", "")))


static func is_daily_order_target(g: CornerFishing, id: String) -> bool:
	ensure_daily_order(g)
	return not bool(g.daily_order.get("done", false)) and id == str(g.daily_order.get("fish", ""))


static func daily_order_indices(g: CornerFishing) -> Array:
	ensure_daily_order(g)
	var perfect_kind := str(g.daily_order.get("kind", "species")) == "perfect"
	var out: Array = []
	for i in g.inventory.size():
		var c: Dictionary = g.inventory[i]
		if not order_matches(g, c) or bool(c.get("lock", false)):
			continue
		# 珍品不自动交单（P1）：鎏金/七彩变体、完美★★★（perfect 单本身豁免）——
		# 失焦挂机钓到的七彩不该被一次点击永久交掉（balance_audit §3.7）
		if int(c.get("var", 0)) >= 2:
			continue
		if not perfect_kind and int(c.get("q", 0)) >= 3:
			continue
		out.append(i)
	out.sort_custom(func(a, b):
		return int(g.inventory[int(a)]["v"]) > int(g.inventory[int(b)]["v"]))
	return out


static func daily_order_reward(g: CornerFishing, indices: Array) -> int:
	var need := int(g.daily_order.get("need", 0))
	var total := 0
	for i in mini(need, indices.size()):
		total += int(g.inventory[int(indices[i])]["v"])
	var mult := g.DAILY_ORDER_MULT
	if g._merchant_active:
		mult *= g.MERCHANT_MULT  # 收鱼郎在场：订单结算再 ×1.5（黄金时刻）
	return int(ceil(float(total) * mult))


static func try_complete_daily_order(g: CornerFishing) -> void:
	ensure_daily_order(g)
	if bool(g.daily_order.get("done", false)):
		g._toast("今日订单已经完成", 1.6, Color(0.76, 0.72, 0.64))
		return
	var need := int(g.daily_order.get("need", 0))
	var indices := daily_order_indices(g)
	if indices.size() < need:
		# 区分"真不够"与"够但含珍稀"（珍稀被排除在自动交单池外）
		var all_n := 0
		for c in g.inventory:
			if order_matches(g, c) and not bool(c.get("lock", false)):
				all_n += 1
		if all_n >= need:
			g._toast("目标鱼够数，但珍稀（鎏金/七彩/★★★）不自动交单——再钓 %d 条普通品相的就行" % (need - indices.size()),
				3.0, Color(0.95, 0.78, 0.42))
		else:
			g._toast("目标鱼还不够", 1.6, Color(1.0, 0.5, 0.4))
		return
	var reward := daily_order_reward(g, indices)
	var chosen := indices.slice(0, need)
	chosen.sort_custom(func(a, b): return int(a) > int(b))
	for idx in chosen:
		g.inventory.remove_at(int(idx))
	g.coins += reward
	g.lifetime_coins += reward
	g.daily_order["done"] = true
	Audio.play_sfx("coin")
	g._toast("每日订单完成：+%d 金币%s" % [reward, "（收鱼郎×1.5）" if g._merchant_active else ""],
		2.6, Color(0.98, 0.82, 0.40))
	g._check_achievements()
	g._update_hud()
	g._refresh_panel()
	g._save()


# ============================ 周目标 ============================

static func week_id() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0 / 7.0)


static func ensure_weekly(g: CornerFishing) -> void:
	ensure_day_stat(g)   # 重建周字典前先沉淀"昨日收入"锚（防任何调用路径读到过期锚）
	var wk := week_id()
	if g.weekly.has("week") and int(g.weekly.get("week", -1)) == wk \
			and g.weekly.has("kind") and int(g.weekly.get("target", 0)) > 0:
		return
	g.weekly = make_weekly(g, wk)


static func make_weekly(g: CornerFishing, wk: int) -> Dictionary:
	var local := RandomNumberGenerator.new()
	local.seed = int(abs(("week:%d" % wk).hash()))
	var kind: String = "catches" if local.randi() % 2 == 0 else "coins"
	var target := 0
	var base := 0
	if kind == "catches":
		target = 120 + g.rod_level * 40
		base = g.lifetime_catches
	else:
		target = 4000 + g.rod_level * 2500
		base = g.lifetime_coins
	return {"week": wk, "kind": kind, "target": target, "base": base,
		"reward": maxi(3000 + g.rod_level * 1500, int(float(g.yest_income) * 0.10)), "done": false}


static func weekly_progress(g: CornerFishing) -> int:
	var cur := g.lifetime_catches if str(g.weekly.get("kind", "catches")) == "catches" else g.lifetime_coins
	return maxi(0, cur - int(g.weekly.get("base", 0)))


static func weekly_desc(g: CornerFishing) -> String:
	if str(g.weekly.get("kind", "catches")) == "catches":
		return "本周累计钓到 %d 条鱼" % int(g.weekly.get("target", 0))
	return "本周累计卖鱼赚 %d 金币" % int(g.weekly.get("target", 0))


static func try_claim_weekly(g: CornerFishing) -> void:
	ensure_weekly(g)
	if bool(g.weekly.get("done", false)):
		return
	if weekly_progress(g) < int(g.weekly.get("target", 0)):
		Audio.play_ui("ui_error")
		g._toast("周目标还没达成", 1.6, Color(1.0, 0.5, 0.4))
		return
	var reward := int(g.weekly.get("reward", 0))
	g.coins += reward
	g.weekly["done"] = true
	Audio.play_sfx("coin")
	g._toast("周目标达成：+%d 金币！" % reward, 3.0, Color(0.98, 0.82, 0.40))
	g._check_achievements()
	g._update_hud()
	g._refresh_panel()
	g._save()
