extends SceneTree
## 无头回归测试：鱼数据 / 抽取分布 / 体重价格 / 背包与卖鱼 / 满包暂停 / 存档v2+v1迁移 / 离线产鱼。
## 运行: godot_console --headless -s tools/validate_game.gd

var failures := 0
const AnglerEquipmentScript := preload("res://systems/angler/angler_equipment.gd")


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	print("=== 数据检查 ===")
	_check_data()

	print("=== 钓点 / 事件数据 ===")
	_check_spot_event_data()

	print("=== 抽取分布（rod=1，20000 次）===")
	_check_distribution()

	print("=== 体重→价格 ===")
	_check_weight_value()

	print("=== 端到端：上鱼入包 / 满包暂停 ===")
	await _check_gameplay()

	print("=== 卖鱼 / 扩容 ===")
	await _check_sell_expand()

	print("=== 鱼篓排序 / 筛选 ===")
	await _check_bag_sort()

	print("=== 鱼竿数值 ===")
	_check_rod()

	print("=== 速度装备 / 绕线轮 ===")
	await _check_reel_speed()

	print("=== 角色属性 → 钓鱼属性映射 ===")
	await _check_attribute_mapping()

	print("=== 鱼饵 / 星级品质 ===")
	_check_quality()

	print("=== 鱼钩 / 双钩 ===")
	await _check_hook()

	print("=== 诱饵 / 窝料（变体杠杆）===")
	await _check_lure()

	print("=== 鱼贩合约（自动贩卖）===")
	await _check_autosell()

	print("=== 彩鳞与长线成就（数值 P1）===")
	await _check_p1_scales()

	print("=== 试竿保底（升级体感）===")
	await _check_showcase()

	print("=== 成就系统 ===")
	await _check_achievements_feature()

	print("=== 流动鱼贩 ===")
	await _check_merchant()

	print("=== 随机事件（EventData 驱动）===")
	await _check_fish_run()

	print("=== 周目标 ===")
	await _check_weekly()

	print("=== 今日统计 ===")
	await _check_day_stat()

	print("=== 每日订单 ===")
	await _check_daily_order()

	print("=== 多钓点：切换 / 鱼池 / 解锁 ===")
	await _check_spots()

	print("=== 水族箱/陈列系统 ===")
	await _check_decor()

	print("=== 活水族箱（鱼缸游动）===")
	await _check_aquarium()

	print("=== 稀有变体系统 ===")
	await _check_variants()

	print("=== 昼夜时段系统 ===")
	await _check_weather()

	print("=== 存档 v2 往返 ===")
	await _check_save_v2()

	print("=== 存档 v8 多钓点往返 / 旧档迁移 ===")
	await _check_save_v8()

	print("=== 存档原子写 / 损坏回退 ===")
	await _check_save_robust()

	print("=== v1 老存档迁移 ===")
	await _check_migration_v1()

	print("=== 离线产鱼 ===")
	await _check_offline()

	print("=== 满篓兜底（在线折价兑换）===")
	await _check_overflow()

	print("=== 动态美术层 ===")
	await _check_effects()

	print("=== 专注模式（手动安静）===")
	await _check_focus()

	print("=== 专注奖励（离开有惊喜）===")
	await _check_focus_reward()

	print("=== 桌面宠物（小馋猫）===")
	await _check_pet()

	print("=== 存档 v11/v12 往返 / 旧档迁移 ===")
	await _check_save_v11()

	print("=== 主界面入口收敛（点金币开面板）===")
	await _check_hud_entry()

	print("=== 测试模式（开发工具）===")
	await _check_test_mode()

	print("=== 开启新存档（开发工具）===")
	await _check_new_save()

	print("=== 结果: %d 失败 ===" % failures)
	quit(1 if failures > 0 else 0)


func _check_data() -> void:
	_assert(FishData.TIER_NAMES.size() == 6, "应有 6 档品阶")
	_assert(FishData.TIER_COLORS.size() == 6, "应有 6 个品阶颜色")
	var by_tier := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for id in FishData.FISH:
		var f: Dictionary = FishData.FISH[id]
		for k in ["name", "tier", "wmin", "wmax", "vmin", "vmax", "tags"]:
			_assert(f.has(k), "%s 缺字段 %s" % [id, k])
		_assert(float(f["wmin"]) <= float(f["wmax"]), "%s wmin 应 <= wmax" % id)
		_assert(int(f["vmin"]) <= int(f["vmax"]), "%s vmin 应 <= vmax" % id)
		_assert((f["tags"] as Array).size() > 0, "%s tags 不应为空" % id)
		by_tier[int(f["tier"])] += 1
	for t in by_tier:
		_assert(by_tier[t] > 0, "品阶 %d 至少应有一种鱼" % t)
	# 鱼种规模与旧 id 兼容（旧 28 种必须仍在且带 river 标签 → 新手河湾体验不变）
	_assert(FishData.FISH.size() >= 60, "鱼种应扩到 ≥60，实际 %d" % FishData.FISH.size())
	for old_id in ["whitebait", "crucian", "carp", "mandarin", "snakehead", "koi",
			"sturgeon", "chinese_sturgeon", "kaluga"]:
		_assert(FishData.FISH.has(old_id), "旧鱼 id %s 应保留" % old_id)
		_assert("river" in FishData.tags_of(old_id), "旧鱼 %s 应带 river 标签" % old_id)
	print("  鱼种数 %d，按品阶分布 %s" % [FishData.FISH.size(), str(by_tier)])


func _check_spot_event_data() -> void:
	# —— 钓点 ——
	_assert(SpotData.SPOTS.size() >= 3, "至少 3 个钓点")
	_assert(SpotData.has(SpotData.DEFAULT_SPOT), "默认钓点应存在")
	_assert(SpotData.default_unlocked(SpotData.DEFAULT_SPOT), "默认钓点应默认解锁")
	for sid in SpotData.SPOT_ORDER:
		_assert(SpotData.has(sid), "SPOT_ORDER 引用了不存在的钓点 %s" % sid)
	for sid in SpotData.SPOTS:
		_assert(sid in SpotData.SPOT_ORDER, "钓点 %s 未列入 SPOT_ORDER" % sid)
		var s: Dictionary = SpotData.SPOTS[sid]
		for k in ["name", "desc", "habitat_tags", "event_pool", "bg_key"]:
			_assert(s.has(k), "钓点 %s 缺字段 %s" % [sid, k])
		_assert((s["habitat_tags"] as Array).size() > 0, "钓点 %s habitat_tags 不应为空" % sid)
		# 事件池引用必须有效，且该事件适用于本钓点
		for eid in s["event_pool"]:
			_assert(EventData.has(str(eid)), "钓点 %s 引用了不存在的事件 %s" % [sid, eid])
			_assert(EventData.applies_to(str(eid), sid),
				"钓点 %s 的事件 %s 的 spots 未包含本钓点" % [sid, eid])
		# 每个钓点至少 2 个专属（非全局）事件
		var exclusive := 0
		for eid in s["event_pool"]:
			if not (EventData.get_event(str(eid)).get("spots", []) as Array).is_empty():
				exclusive += 1
		_assert(exclusive >= 2, "钓点 %s 应至少有 2 个专属事件，实际 %d" % [sid, exclusive])
	# river_bend 鱼池非空（扩 tags 前靠无 tags→river 回退也应有鱼）
	_assert(SpotData.pool_for("river_bend").size() > 0, "新手河湾鱼池不应为空")
	# 招牌景观：黎明命中显示「晨雾日出」，其余时段空串
	_assert(SpotData.scenic_name("river_bend", "dawn") == "晨雾日出", "河湾黎明应显示招牌景观「晨雾日出」")
	_assert(SpotData.scenic_name("river_bend", "day") == "", "河湾非黎明时段不应显示招牌景观")
	_assert(SpotData.scenic_name("still_lake", "dawn") == "", "无招牌景观的钓点应返回空串")
	print("  钓点 %d 个：%s" % [SpotData.SPOTS.size(), str(SpotData.SPOT_ORDER)])

	# —— 事件 ——
	_assert(EventData.EVENTS.size() >= 5, "至少 5 个随机事件")
	_assert(EventData.is_buff("fish_run"), "鱼汛应为 buff 型")
	_assert((EventData.get_event("fish_run").get("spots", []) as Array).is_empty(),
		"鱼汛应为全钓点共享")
	for eid in EventData.EVENTS:
		var e: Dictionary = EventData.EVENTS[eid]
		for k in ["name", "kind", "dur", "gap", "first", "spots"]:
			_assert(e.has(k), "事件 %s 缺字段 %s" % [eid, k])
		for tk in ["dur", "gap", "first"]:
			var arr: Array = e[tk]
			_assert(arr.size() == 2 and float(arr[0]) <= float(arr[1]),
				"事件 %s 的 %s 应为 [min<=max]" % [eid, tk])
		_assert(EventData.is_buff(str(eid)) or EventData.is_instant(str(eid)),
			"事件 %s kind 应为 buff/instant" % eid)
		# 事件 spots 引用的钓点必须有效
		for sid in e["spots"]:
			_assert(SpotData.has(str(sid)), "事件 %s 引用了不存在的钓点 %s" % [eid, sid])
		if EventData.is_instant(str(eid)):
			var rb: Array = e.get("reward_base", [0, 0])
			_assert(rb.size() == 2 and int(rb[0]) > 0 and int(rb[0]) <= int(rb[1]),
				"instant 事件 %s 应有合法 reward_base" % eid)
	print("  事件 %d 个，结构/钓点适配 通过" % EventData.EVENTS.size())

	# —— 钓点鱼池隔离：池内抽鱼绝不逸出到别的钓点 ——
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	for sid in SpotData.SPOT_ORDER:
		var pool: Array = SpotData.pool_for(sid)
		_assert(pool.size() >= 6, "钓点 %s 鱼池过小（%d）" % [sid, pool.size()])
		var pool_set := {}
		for fid in pool:
			pool_set[fid] = true
		var escaped := 0
		# 用高 luck 逼出高阶（含池内可能缺的 t5）以验证就近回退不逸出
		for i in 3000:
			var c := FishData.roll_catch(rng, 6, 0, 8, pool)
			if not pool_set.has(str(c["id"])):
				escaped += 1
		_assert(escaped == 0, "钓点 %s 抽鱼逸出鱼池 %d 次" % [sid, escaped])
	# river_bend 仍含全部原始河鱼（向后兼容）且已 v2 扩充（>28）；各钓点池都应足够丰富
	var river_pool := SpotData.pool_for("river_bend")
	for old_id in ["crucian", "carp", "bass", "snakehead", "koi", "kaluga"]:
		_assert(old_id in river_pool, "新手河湾应仍含原始鱼 %s" % old_id)
	_assert(river_pool.size() > 28, "新手河湾应已扩充到 >28，实际 %d" % river_pool.size())
	for sid2 in ["river_bend", "still_lake", "coast_pier"]:
		_assert(SpotData.pool_for(sid2).size() >= 40,
			"钓点 %s 鱼池应 ≥40，实际 %d" % [sid2, SpotData.pool_for(sid2).size()])
	# 海/湖各自的专属海鱼/湖鱼不应出现在对方池里
	_assert(not ("hairtail" in SpotData.pool_for("still_lake")), "带鱼不应在静水湖泊池")
	_assert(not ("largemouth" in SpotData.pool_for("coast_pier")), "大口黑鲈不应在海岸码头池")
	_assert("hairtail" in SpotData.pool_for("coast_pier"), "带鱼应在海岸码头池")
	_assert("largemouth" in SpotData.pool_for("still_lake"), "大口黑鲈应在静水湖泊池")
	print("  钓点鱼池隔离：%s 各池就近回退不逸出 通过" % str(SpotData.SPOT_ORDER))


func _check_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	var weights := FishData.weights_for_rod(1)
	for i in 20000:
		var id := FishData.roll_fish(weights, rng)
		counts[FishData.tier_of(id)] += 1
	print("  分布 %s" % str(counts))
	_assert(counts[0] > counts[1] and counts[1] > counts[2], "低阶应多于高阶")
	_assert(counts[4] > 0, "20000 次内应至少出 1 次传说")
	_assert(counts[5] > 0, "20000 次内应至少出 1 次神话")
	_assert(counts[5] < counts[4], "神话应少于传说")


func _check_weight_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var in_range := true
	var light_sum := 0.0
	var light_n := 0
	var heavy_sum := 0.0
	var heavy_n := 0
	for i in 2000:
		var c := FishData.roll_catch(rng, 1)
		var f: Dictionary = FishData.FISH[c["id"]]
		if c["w"] < float(f["wmin"]) - 0.011 or c["w"] > float(f["wmax"]) + 0.011:
			in_range = false
		_assert(int(c["v"]) >= 1, "鱼价值应 ≥1")
		# 只用鲤鱼对比轻重价差
		if c["id"] == "carp":
			var mid := (float(f["wmin"]) + float(f["wmax"])) * 0.5
			if c["w"] < mid:
				light_sum += c["v"]
				light_n += 1
			else:
				heavy_sum += c["v"]
				heavy_n += 1
	_assert(in_range, "体重应在鱼种区间内")
	if light_n > 10 and heavy_n > 10:
		_assert(heavy_sum / heavy_n > light_sum / light_n, "大鱼应比小鱼值钱")
		print("  鲤鱼均价：轻 %.1f (n=%d) vs 重 %.1f (n=%d)" % [
			light_sum / light_n, light_n, heavy_sum / heavy_n, heavy_n])


func _check_gameplay() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	game.save_enabled = false
	root.add_child(game)
	await process_frame
	_assert(game.coins == 0, "起始金币应为 0")
	_assert(game.inventory.is_empty(), "起始背包应为空")
	_assert(game._bag_capacity() == 20, "初始容量应为 20")

	# 上鱼入包，不产金币（lifetime_coins 只统计卖鱼；成就奖励单独计 coins 不计此）
	for i in 5:
		game._do_catch()
	_assert(game.inventory.size() == 5, "钓 5 条应入包 5 条，实际 %d" % game.inventory.size())
	_assert(game.lifetime_coins == 0, "钓鱼不应产生卖鱼收入")
	_assert(game.lifetime_catches == 5, "终身渔获应为 5")
	_assert(game.dex.size() >= 1, "图鉴应有收录")

	# 钓满
	for i in 25:
		game._do_catch()
	_assert(game.inventory.size() == 20, "背包应止步于容量 20，实际 %d" % game.inventory.size())
	_assert(game._bag_full(), "背包应为满")

	# 满包时等待结束不应进入咬钩
	game._begin_wait()
	game._state_t = 0.0
	game._process(0.016)
	_assert(game._state == game.ST_WAIT, "满包时应暂停（不进入咬钩）")

	# 腾出一格后恢复咬钩
	game._sell_one(0)
	game._state_t = 0.0
	game._process(0.016)
	_assert(game._state == game.ST_BITE, "腾格后应恢复咬钩")
	print("  入包/满包暂停/恢复 通过")

	game.queue_free()
	await process_frame


func _check_sell_expand() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	game.save_enabled = false
	root.add_child(game)
	await process_frame

	for i in 6:
		game._do_catch()
	# 收藏锁：锁两条，全卖应跳过
	game._toggle_lock(0)
	game._toggle_lock(2)
	_assert(bool(game.inventory[0]["lock"]), "上锁应生效")
	var locked_id: String = game.inventory[0]["id"]
	var total := 0
	for c in game.inventory:
		if not bool(c.get("lock", false)):
			total += int(c["v"])
	game._sell_one(0)
	_assert(game.inventory.size() == 6, "锁定的鱼不应被单卖")
	game._sell_all()
	# 用 lifetime_coins 校验卖鱼收入（不含成就奖励），避免被成就金币干扰
	_assert(game.lifetime_coins == total, "全卖应只卖未锁定，卖鱼收入应为 %d，实际 %d" % [total, game.lifetime_coins])
	_assert(game.inventory.size() == 2, "全卖后应留 2 条收藏，实际 %d" % game.inventory.size())
	_assert(str(game.inventory[0]["id"]) == locked_id, "留下的应是锁定那条")
	_assert(game.lifetime_coins == total, "累计卖鱼金额应为 %d" % total)
	game._toggle_lock(0)
	game._toggle_lock(1)
	game._sell_all()
	_assert(game.inventory.is_empty(), "解锁后全卖应清空")
	total = game.coins

	# 扩容
	game.coins = 200
	game._try_expand_bag()
	_assert(game.bag_level == 2, "扩容后 bag_level 应为 2")
	_assert(game._bag_capacity() == 25, "扩容后容量应为 25")
	_assert(game.coins == 200 - 100, "扩容应扣 100 金币，余 %d" % game.coins)
	# 钱不够不能扩
	game.coins = 0
	game._try_expand_bag()
	_assert(game.bag_level == 2, "金币不足不应扩容")
	print("  卖鱼/扩容 通过（容量 20→25，费用 100）")

	game.queue_free()
	await process_frame


func _check_day_stat() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.lifetime_catches = 10
	g.lifetime_coins = 200
	g.day_stat = {"date": g._today_key(), "catches": 10, "coins": 200}
	_assert(g._today_catches() == 0 and g._today_income() == 0, "当日起点应为 0")
	g.lifetime_catches = 35
	g.lifetime_coins = 950
	_assert(g._today_catches() == 25, "今日渔获应为 25，实际 %d" % g._today_catches())
	_assert(g._today_income() == 750, "今日收入应为 750，实际 %d" % g._today_income())
	# 跨天重置：把快照日期改成旧日期，访问应重新以当前为起点
	g.day_stat["date"] = "2000-01-01"
	_assert(g._today_catches() == 0 and g._today_income() == 0, "跨天应重置今日统计为 0")
	_assert(str(g.day_stat["date"]) == g._today_key(), "跨天应刷新快照日期")
	print("  今日统计：增量/跨天重置 通过")
	g.queue_free()
	await process_frame


func _check_weekly() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	# 造一个"卖鱼"类周目标，base 锚定当前
	g.lifetime_coins = 1000
	g.weekly = {"week": g._week_id(), "kind": "coins", "target": 500, "base": 1000, "reward": 7000, "done": false}
	_assert(g._weekly_progress() == 0, "周目标进度起始应为 0")
	g.lifetime_coins = 1400
	g._check_achievements()  # 先消化 coin_1k 等里程碑成就，避免奖励污染领取断言
	_assert(g._weekly_progress() == 400, "卖鱼 +400 应反映为周进度 400")
	var before: int = g.coins
	g._try_claim_weekly()
	_assert(not bool(g.weekly["done"]), "未达标不应可领")
	_assert(g.coins == before, "未达标不发奖")
	g.lifetime_coins = 1600  # 达标(+600 ≥500)
	g._try_claim_weekly()
	_assert(bool(g.weekly["done"]) and g.coins == before + 7000, "达标领取应 +7000，实际 +%d" % (g.coins - before))
	# 跨周刷新
	g.weekly["week"] = g._week_id() - 1
	g._ensure_weekly()
	_assert(int(g.weekly["week"]) == g._week_id() and not bool(g.weekly["done"]), "跨周应重置周目标")
	print("  周目标：进度/领取/跨周刷新 通过")
	g.queue_free()
	await process_frame


func _check_fish_run() -> void:
	# 鱼汛 luck 抬高高阶占比
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var hi_norm := 0
	var hi_run := 0
	for i in 4000:
		if FishData.tier_of(FishData.roll_catch(rng, 1, 0, 0)["id"]) >= 3:
			hi_norm += 1
		if FishData.tier_of(FishData.roll_catch(rng, 1, 0, 7)["id"]) >= 3:
			hi_run += 1
	_assert(hi_run > hi_norm * 1.4, "鱼汛应显著提高高阶鱼占比（普通 %d vs 鱼汛 %d）" % [hi_norm, hi_run])
	# —— 事件管理器（EventData 驱动）——
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.day_phase = "day"  # 钉死白昼，剔除真实时钟带来的昼夜运气/等待修正干扰（同 _check_weather）
	_assert(g.active_event == "", "起始无 buff 事件")
	# 河湾事件池
	var elig: Array = g._eligible_events()
	_assert("fish_run" in elig and "morning_fog" in elig and "drift_crate" in elig,
		"河湾事件池应含鱼汛/晨雾/漂流木箱")
	# 触发鱼汛 buff：进场 + 等待提速 + 运气加成
	g._fire_event("fish_run")
	_assert(g.active_event == "fish_run", "应触发鱼汛 buff")
	g._begin_wait()
	_assert(g._state_t <= 7.0 * EventData.wait_mult("fish_run") * SpotData.wait_mult("river_bend") + 0.01,
		"鱼汛期间等待应提速")
	_assert(g._catch_luck() == EventData.luck("fish_run"), "鱼汛应给品阶运气加成")
	# buff 到时退场并排下一次
	g._event_buff_t = 0.0
	g._tick_events(0.016)
	_assert(g.active_event == "" and g._event_next_t > 0.0, "buff 到时应退场并排下次")
	# instant 事件：发金币、不占 buff 槽
	var coins_before: int = g.coins
	g._fire_event("drift_crate")
	_assert(g.coins > coins_before, "漂流木箱应发金币奖励")
	_assert(g.active_event == "", "instant 事件不应占用 buff 槽")
	# 钓点适配：海岸码头有涨潮、无晨雾
	g.current_spot = "coast_pier"
	var celig: Array = g._eligible_events()
	_assert("tide_in" in celig and not ("morning_fog" in celig),
		"海岸码头应有涨潮、无晨雾")
	# 涨潮 + 海岸常驻系数 → 增值系数 >1
	g._fire_event("tide_in")
	_assert(g._catch_value_mult() > 1.0, "涨潮在海岸应抬高渔获价值")
	print("  随机事件：池/鱼汛buff提速运气/instant金币/钓点适配/增值 通过（普通 %d→运气 %d）" % [hi_norm, hi_run])
	g.queue_free()
	await process_frame


func _check_hook() -> void:
	_assert(FishData.HOOKS.size() == 4, "鱼钩应 4 档")
	_assert(float(FishData.HOOKS[0]["double"]) == 0.0, "基础钩双钩率应为 0")
	_assert(float(FishData.HOOKS[3]["double"]) > float(FishData.HOOKS[1]["double"]), "高级钩双钩率应更高")
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	# 基础钩不双钩
	g.hook_level = 0
	g.inventory = []
	g._do_catch()
	_assert(g.inventory.size() == 1, "基础钩单次只上 1 条")
	# 高级钩统计上应出现双钩
	g.hook_level = 3
	var doubles := 0
	for i in 300:
		g.inventory = []
		g._do_catch()
		if g.inventory.size() == 2:
			doubles += 1
	_assert(doubles > 0, "双叉钩 300 次内应触发双钩，实际 %d" % doubles)
	# 边界：满篓附近双钩不应溢出容量
	g.bag_level = 1  # cap 20
	var cap: int = g._bag_capacity()
	g.inventory = []
	for i in cap - 1:
		g.inventory.append({"id": "carp", "w": 1.0, "v": 10, "q": 0})
	for i in 50:
		g._do_catch()
		_assert(g.inventory.size() <= cap, "双钩不应超出鱼篓容量 %d，实际 %d" % [cap, g.inventory.size()])
	# 成就
	g._check_achievements()
	_assert(g.achievements_done.has("hook_master"), "用上双叉钩应解锁成就")
	print("  鱼钩：双钩触发 %d/300 · 成就 通过" % doubles)
	g.queue_free()
	await process_frame


## 诱饵/窝料（P2 变体杠杆第四成长线）：数据档位 + lure_level→_variant_bias()→_roll_one 端到端接线。
func _check_lure() -> void:
	_assert(FishData.LURES.size() == 4, "诱饵应 4 档")
	_assert(FishData.lure_vbias(0) == 0.0, "无窝料 vbias 应为 0（基线不破）")
	_assert(FishData.lure_vbias(3) > FishData.lure_vbias(1), "高档窝料 vbias 应更高")
	_assert(FishData.lure_vbias(99) == FishData.lure_vbias(3), "越界档位应夹到最高档")
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	# _variant_bias() 累加器：0 级窝料贡献 0，满级 > 0（接到杠杆）
	g.lure_level = 0
	_assert(g._variant_bias() == 0.0, "0 级窝料 _variant_bias() 应为 0")
	g.lure_level = FishData.LURES.size() - 1
	_assert(g._variant_bias() > 0.0, "满级窝料 _variant_bias() 应 > 0")
	# 端到端：满级窝料的 _roll_one 变体率应显著高于无窝料（统计，证明接线生效）
	g.lure_level = 0
	var base_v := 0
	for i in 6000:
		if int(g._roll_one(0).get("var", 0)) >= 1:
			base_v += 1
	g.lure_level = FishData.LURES.size() - 1
	var lured_v := 0
	for i in 6000:
		if int(g._roll_one(0).get("var", 0)) >= 1:
			lured_v += 1
	print("  变体出现率(各 6000)：无窝料=%d / 满级窝料=%d" % [base_v, lured_v])
	_assert(lured_v > base_v, "满级窝料应显著抬高 _roll_one 的变体出现率（杠杆接线生效）")
	# 升级流程 + 成就
	g.coins = 999999
	for i in FishData.LURES.size() - 1:
		g._try_upgrade_lure()
	_assert(g.lure_level == FishData.LURES.size() - 1, "应能逐级升满窝料")
	g._check_achievements()
	_assert(g.achievements_done.has("lure_master"), "用上麝香窝料应解锁成就")
	print("  诱饵：4 档 / 累加器 / _roll_one 接线 / 升级 / 成就 通过")
	g.queue_free()
	await process_frame


func _check_focus() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g._set_focus(true)
	_assert(g.focus_mode and g.painter.quiet, "专注模式应置位并静默场景")
	var before: int = g.ui_root.get_child_count()
	g._popup("x", Vector2.ZERO, Color.WHITE)
	_assert(g.ui_root.get_child_count() == before, "专注模式应抑制飘字")
	g._set_focus(false)
	_assert(not g.painter.quiet, "关闭专注应恢复场景事件")
	print("  专注模式 通过")
	g.queue_free()
	await process_frame


## 专注奖励：失焦累计达 25/50 分钟 → 下一竿强制升级；切回清零；每日封顶。
func _check_focus_reward() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.focus_mode = true   # 顺便关掉宠物偷鱼，使升级断言确定（与专注奖励逻辑无关）
	g.bag_level = 8
	g.focus_reward_date = g._today_key()
	g.focus_reward_today = 0
	# 失焦 + 静默累计到 25 分钟阈值（喂一个超阈值的 delta）
	g._window_focused = false
	g._tick_focus(g.FOCUS_T1 + 1.0)
	_assert(g.focus_pending >= 1, "失焦满 25 分钟应挂起专注奖励")
	_assert(g.focus_reward_today == 0, "P1 额度按兑现计：发放时不占每日额度")
	_assert(g.focus_minutes_total >= 25.0, "应累计专注分钟，实际 %.1f" % g.focus_minutes_total)
	# 下一竿强制升级（保底极品★★），并清空挂起；此刻才占每日额度
	g.inventory = []
	g._do_catch()
	_assert(g.focus_pending == 0, "上钩后应消费掉专注奖励")
	_assert(g.focus_reward_today == 1, "兑现时才占每日额度（同段 T1+T2 合并算 1 次）")
	_assert(int(g.inventory.back()["q"]) >= 2,
		"专注奖励应保底高星（q>=2），实际 %d" % int(g.inventory.back()["q"]))
	# 切回窗口 → 60s 宽限窗（不清零）；宽限窗外操作 → 折算保留 80%
	g._focus_away_t = 0.0
	g._window_focused = false
	g._tick_focus(60.0)
	_assert(g._focus_away_t > 0.0, "失焦应累计专注段")
	var seg: float = g._focus_away_t
	g._notification(g.NOTIFICATION_APPLICATION_FOCUS_IN)
	_assert(absf(g._focus_away_t - seg) < 0.01, "切回窗口不清零专注段（宽限窗启动）")
	_assert(g._focus_grace_t > 0.0, "回焦应开启宽限窗")
	g._focus_grace_t = 0.0   # 快进：宽限窗过期
	g._fold_focus_streak()   # 宽限窗外点击（_input 路径同函数）
	_assert(absf(g._focus_away_t - seg * 0.8) < 0.01, "宽限窗外操作应折算保留 80%")
	# 50 分钟档：保底鎏金变体（var>=2）
	g._window_focused = false
	g._focus_granted = 1   # 直接验证 50 分钟档
	g._tick_focus(g.FOCUS_T2 + 1.0)
	_assert(g.focus_pending == 2, "失焦满 50 分钟应保底鎏金（pending=2），实际 %d" % g.focus_pending)
	g.inventory = []
	g._do_catch()
	_assert(int(g.inventory.back().get("var", 0)) >= 2, "50 分钟奖励应保底鎏金变体（var>=2）")
	# 每日封顶：达上限后不再发奖励
	g.focus_reward_today = g.FOCUS_REWARD_DAILY_CAP
	g._focus_away_t = 0.0
	g._focus_granted = 0
	g._window_focused = false
	g._tick_focus(g.FOCUS_T1 + 1.0)
	_assert(g.focus_pending == 0, "达每日封顶后不应再发奖励")
	# 成就：累计专注分钟达标
	g.focus_minutes_total = 200.0
	g._check_achievements()
	_assert(g.achievements_done.has("flow_state"), "累计专注 ≥120 分钟应解锁心流时刻")
	print("  专注奖励：25/50 分钟保底升级 / 切回清零 / 每日封顶 / 成就 通过")
	g.queue_free()
	await process_frame


## 主界面入口收敛（沉浸模式 HUD）：金币栏可点、主界面无独立按钮、点金币开关背包页。
## 注：默认已切带框 App 模式，此项专测沉浸模式 HUD，故 _ready 前先置 immersive。
func _check_hud_entry() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	g.display_mode = "immersive"
	root.add_child(g)
	await process_frame
	_assert(g.coins_label.mouse_filter == Control.MOUSE_FILTER_STOP, "金币栏应可点(mouse_filter=STOP)")
	_assert(g._spot_round_btns.is_empty(), "主界面应无独立按钮(已撤鱼篓按钮)，实际 %d" % g._spot_round_btns.size())
	# 点金币 → 开背包页(tab 0)
	g._catch_tab = 0
	g._toggle_panel("catch")
	_assert(g._panel_kind == "catch" and g._catch_tab == 0, "点金币应打开面板背包页")
	# 再点金币 → 关闭(toggle)
	g._toggle_panel("catch")
	_assert(g._panel_kind == "", "再点金币应关闭面板")
	# 钓点签/订单签深链仍在
	_assert(is_instance_valid(g.spot_chip) and is_instance_valid(g.order_chip), "钓点签/订单签应仍存在")
	print("  主界面入口收敛：金币栏可点 / 无独立按钮 / 开关背包页 通过")
	g.queue_free()
	await process_frame


## 桌面宠物：只偷最廉价的可舍弃杂鱼，锁定/订单/贵鱼受保护。
func _check_pet() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	# 谁都匹配不上的订单，排除订单保护干扰本用例
	g.daily_order = {"date": g._today_key(), "kind": "weight", "fish": "carp", "tier": 1, "need": 1, "minw": 9999.0, "done": false}
	g.display = []
	g.pet_steals = 0
	g.inventory = [
		{"id": "koi", "w": 3.0, "v": 300, "q": 0, "lock": false},       # 贵，不偷
		{"id": "crucian", "w": 0.4, "v": 5, "q": 0, "lock": true},      # 锁定，不偷
		{"id": "whitebait", "w": 0.02, "v": 3, "q": 0, "lock": false},  # 最廉价 → 被偷
		{"id": "carp", "w": 1.0, "v": 20, "q": 0, "lock": false},
	]
	var stolen: String = g._pet_steal_cheapest()
	_assert(stolen == "whitebait", "应叼走最廉价的白条，实际 %s" % stolen)
	_assert(g.pet_steals == 1, "偷鱼计数应 +1")
	_assert(g.inventory.size() == 3, "应少一条")
	for c in g.inventory:
		_assert(str(c["id"]) != "whitebait", "白条应已被叼走")
	# 全是贵鱼/锁定/订单 → 绝不偷
	g.daily_order = {"date": g._today_key(), "kind": "species", "fish": "koi", "tier": 1, "need": 1, "minw": 1.0, "done": false}
	g.inventory = [
		{"id": "koi", "w": 3.0, "v": 300, "q": 0, "lock": false},   # 订单目标，保护
		{"id": "kaluga", "w": 80.0, "v": 9000, "q": 0, "lock": true},
	]
	var none: String = g._pet_steal_cheapest()
	_assert(none == "", "无可舍弃廉价鱼时不应偷")
	_assert(g.inventory.size() == 2, "珍藏/订单鱼不应被动")
	# 成就
	g.pet_steals = 1
	g._check_achievements()
	_assert(g.achievements_done.has("cat_tax"), "被偷过应解锁猫税成就")
	print("  桌面宠物：偷最廉价杂鱼 / 保护锁定与订单 / 成就 通过")
	g.queue_free()
	await process_frame


## 存档 v11：dex 首捕日期 + 专注/宠物计数往返；v10→v11 无损迁移。
func _check_save_v11() -> void:
	var path := ProjectSettings.globalize_path(TEST_SAVE)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(path)
	var g1: Node = load("res://main.tscn").instantiate()
	g1.save_enabled = true
	g1.save_path = TEST_SAVE
	root.add_child(g1)
	await process_frame
	g1.dex = {"koi": {"n": 3, "w": 5.0, "big": true, "perf": false, "vmask": (1 << 2), "fd": "2026-06-15"}}
	g1.display = [{"id": "koi", "w": 5.0, "v": 1600, "q": 1, "lock": false, "var": 2}]
	g1.focus_minutes_total = 137.5
	g1.focus_reward_today = 2
	g1.focus_reward_date = g1._today_key()
	g1.focus_pending = 1
	g1.pet_steals = 4
	g1.lure_level = 2   # v12 诱饵/窝料
	g1.max_fps = 90
	g1.ui_scale = 1.25
	g1._save()
	g1.queue_free()
	await process_frame
	var g2: Node = load("res://main.tscn").instantiate()
	g2.save_enabled = true
	g2.save_path = TEST_SAVE
	root.add_child(g2)
	await process_frame
	_assert(str(g2.dex["koi"].get("fd", "")) == "2026-06-15", "v11 应恢复 dex 首捕日期")
	_assert(g2.display.size() == 1 and str(g2.display[0]["id"]) == "koi", "v11 应恢复缸内鱼")
	_assert(absf(g2.focus_minutes_total - 137.5) < 0.01, "v11 应恢复累计专注分钟")
	_assert(g2.focus_reward_today == 2 and g2.focus_pending == 1, "v11 应恢复专注奖励计数/挂起")
	_assert(g2.pet_steals == 4, "v11 应恢复宠物偷鱼计数")
	_assert(g2.lure_level == 2, "v12 应恢复诱饵/窝料等级")
	_assert(g2.max_fps == 90 and Engine.max_fps == 90, "应恢复帧率设置并应用到引擎")
	_assert(is_equal_approx(g2.ui_scale, 1.25), "应恢复界面缩放设置")
	g2._set_ui_scale(9.0)
	_assert(is_equal_approx(g2.ui_scale, g2.UI_SCALE_MAX), "界面缩放超上限应夹到 UI_SCALE_MAX")
	g2._set_ui_scale(0.05)
	_assert(is_equal_approx(g2.ui_scale, g2.UI_SCALE_MIN), "界面缩放低于下限应夹到 UI_SCALE_MIN")
	g2.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	# v10 → v11 迁移：旧档无 fd/专注/宠物 → 默认零、display(缸内鱼) 无损
	var old := {
		"ver": 10, "coins": 10, "rod_level": 1, "bag_level": 1, "bait": 0, "hook": 0,
		"inv": [], "display": [["kaluga", 80.0, 9000, 2, 0, 3]],
		"lt_coins": 0, "lt_catches": 5,
		"dex": {"kaluga": [1, 80.0, 1, 0, (1 << 3)]},   # v10 五元组，无 fd
		"opacity": 1.0, "ts": Time.get_unix_time_from_system() - 5.0,
	}
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f = null
	var g3: Node = load("res://main.tscn").instantiate()
	g3.save_enabled = true
	g3.save_path = TEST_SAVE
	root.add_child(g3)
	await process_frame
	_assert(g3.display.size() == 1 and str(g3.display[0]["id"]) == "kaluga", "v10→v11 应无损保留缸内鱼")
	_assert(str(g3.dex["kaluga"].get("fd", "x")) == "", "v10 dex 无 fd → 迁移默认空")
	_assert(int(g3.dex["kaluga"].get("vmask", 0)) == (1 << 3), "v10→v11 应保留 dex 变体掩码")
	_assert(g3.focus_minutes_total == 0.0 and g3.pet_steals == 0 and g3.focus_pending == 0,
		"v10→v11 专注/宠物计数应默认零")
	_assert(g3.lure_level == 0, "旧档无 lure 字段 → 应默认无窝料(0)")
	_assert(g3.max_fps == 120, "旧档无帧率字段 → 应默认 120（v16 起流畅优先）")
	_assert(is_equal_approx(g3.ui_scale, 1.0), "旧档无界面缩放字段 → 应默认 1.0")
	print("  存档 v11/v12：dex首捕/专注/宠物/诱饵 往返 + 旧档无损迁移 通过")
	g3.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)


func _check_bag_sort() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.inventory = [
		{"id": "crucian", "w": 0.5, "v": 5, "q": 0},
		{"id": "koi", "w": 3.0, "v": 300, "q": 0},
		{"id": "carp", "w": 1.0, "v": 20, "q": 0},
	]
	g._bag_sort = 1
	_assert(g._sorted_bag_indices(false)[0] == 1, "价值排序首位应是 koi")
	g._bag_sort = 3
	_assert(g._sorted_bag_indices(false)[0] == 1, "重量排序首位应是 koi")
	g._bag_sort = 0
	_assert(g._sorted_bag_indices(false)[0] == 2, "最新排序首位应是最后入包")
	# 订单鱼筛选按 _order_matches：species 订单只留该种
	g.daily_order = {"date": g._today_key(), "kind": "species", "fish": "carp", "tier": 1, "need": 1, "minw": 1.0, "done": false}
	var only: Array = g._sorted_bag_indices(true)
	_assert(only.size() == 1 and only[0] == 2, "species 订单筛选应只剩 carp")
	# 品阶订单筛选：留所有 ≥tier3 的鱼（koi 是史诗+，crucian/carp 不是）
	g.daily_order = {"date": g._today_key(), "kind": "tier", "fish": "koi", "tier": 3, "need": 1, "minw": 1.0, "done": false}
	var tonly: Array = g._sorted_bag_indices(true)
	_assert(tonly.size() == 1 and tonly[0] == 1, "tier 订单筛选应按品阶匹配(只剩 koi)，实际 %d" % tonly.size())
	# 卖杂鱼：保留订单目标鱼与锁定
	g.daily_order = {"date": g._today_key(), "kind": "species", "fish": "koi", "tier": 1, "need": 1, "minw": 1.0, "done": false}
	g.inventory = [
		{"id": "koi", "w": 3.0, "v": 300, "q": 0},
		{"id": "crucian", "w": 0.5, "v": 5, "q": 0, "lock": true},
		{"id": "carp", "w": 1.0, "v": 20, "q": 0},
	]
	g.lifetime_coins = 0
	g._sell_junk()
	_assert(g.inventory.size() == 2, "卖杂鱼应只卖非订单非锁定，剩 koi+锁定鲫，实际 %d" % g.inventory.size())
	_assert(g.lifetime_coins == 20, "卖杂鱼收入应为 carp 的 20，实际 %d" % g.lifetime_coins)
	var has_koi := false
	for c in g.inventory:
		if str(c["id"]) == "koi":
			has_koi = true
	_assert(has_koi, "订单目标鱼应保留")
	print("  排序/筛选/卖杂鱼 通过")
	g.queue_free()
	await process_frame


func _check_rod() -> void:
	var w1 := FishData.weights_for_rod(1)
	var w8 := FishData.weights_for_rod(8)
	_assert(w8[4] > w1[4] and w8[5] > w1[5], "鱼竿升级应提高传说/神话权重")
	_assert(w8[0] < w1[0], "鱼竿升级应降低普通权重")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var sum1 := 0
	var sum8 := 0
	for i in 600:
		sum1 += int(FishData.roll_catch(rng, 1)["v"])
		sum8 += int(FishData.roll_catch(rng, 8)["v"])
	_assert(sum8 > sum1, "高级竿整体产出应更高")
	print("  整体均价 rod1=%.1f rod8=%.1f" % [sum1 / 600.0, sum8 / 600.0])


func _check_reel_speed() -> void:
	_assert(AnglerEquipmentScript.reel_next_cost(10) > AnglerEquipmentScript.reel_next_cost(1),
		"绕线轮单级成本应随等级递增")
	_assert(AnglerEquipmentScript.reel_upgrade_cost(0, 10) > AnglerEquipmentScript.reel_upgrade_cost(0, 1),
		"绕线轮 +10 成本应包含 10 个逐级成本")
	_assert(AnglerEquipmentScript.equipment_next_cost("reel", 10000) > 0,
		"高等级装备单级成本不应溢出为负数")
	_assert(AnglerEquipmentScript.equipment_upgrade_cost("reel", 10000, 100) == AnglerEquipmentScript.MAX_ECON_VALUE,
		"极高等级装备批量成本应钳制到经济上限")
	_assert(AnglerEquipmentScript.reel_wait_mult(100) < AnglerEquipmentScript.reel_wait_mult(0),
		"绕线轮等级应降低速度等待倍率")
	_assert(AnglerEquipmentScript.reel_wait_mult(300) < AnglerEquipmentScript.reel_wait_mult(100),
		"绕线轮曲线应平滑渐近，不能在中高等级硬撞地板")
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	var t0: float = g._avg_wait_for_reel(0)
	var t50: float = g._avg_wait_for_reel(50)
	var t100: float = g._avg_wait_for_reel(100)
	_assert(t50 < t0 and t100 < t50, "绕线轮等级应逐步缩短一竿周期 %.2f/%.2f/%.2f" % [t0, t50, t100])
	g.coins = 0
	g._try_upgrade_reel(10)
	_assert(g.reel_level == 0 and g.coins == 0, "绕线轮正式升级应检查金币，不足时不升级")
	g.rod_level = 1000
	_assert(g._rod_cost() > 1.0e200 and g._rod_cost() < g.MAX_ECON_VALUE,
		"高等级鱼竿成本应使用浮点大数而非 64 位钳制，实际 %s" % g._coin_str(g._rod_cost()))
	g.rod_level = 2000
	_assert(g._rod_cost() == g.MAX_ECON_VALUE, "极端等级鱼竿成本应钳制到 double 经济上限")
	_assert(g._coin_str(12345) == "12.3K" and g._coin_str(1234567) == "1.23M"
			and g._coin_str(1234567890123456) == "1.23Qa" and g._coin_str(1.23e24) == "1.23Sp",
		"金币显示应使用 K/M/B/T/Qa... 短单位，实际 %s / %s / %s / %s" % [
			g._coin_str(12345), g._coin_str(1234567), g._coin_str(1234567890123456), g._coin_str(1.23e24)])
	g.rod_level = 1
	var chain: Array = g._equipment_chain()
	_assert(chain == ["fish_line", "reel", "bobber", "sonar", "notebook", "gloves"],
		"属性装备解锁顺序应由独立顺序表控制")
	var unlock_reel_cost: int = g._equipment_unlock_cost("reel")
	var raw_reel_anchor: int = AnglerEquipmentScript.equipment_next_cost(
		"fish_line", AnglerEquipmentScript.equipment_unlock_target("reel") - 1)
	_assert(unlock_reel_cost == 2500 and unlock_reel_cost == AnglerEquipmentScript.equipment_next_cost("reel", 0)
			and AnglerEquipmentScript.equipment_next_cost("reel", 1) > unlock_reel_cost,
		"绕线轮解锁应购买 Lv.1，价格由鱼线锚点单次价规整得到，raw=%d rounded=%d" % [raw_reel_anchor, unlock_reel_cost])
	var unlock_bobber_cost: int = g._equipment_unlock_cost("bobber")
	var raw_bobber_anchor: int = AnglerEquipmentScript.equipment_next_cost(
		"reel", AnglerEquipmentScript.equipment_unlock_target("bobber") - 1)
	_assert(unlock_bobber_cost == 30000 and unlock_bobber_cost == AnglerEquipmentScript.equipment_next_cost("bobber", 0)
			and unlock_bobber_cost > unlock_reel_cost,
		"浮漂解锁应购买 Lv.1，价格由绕线轮锚点单次价规整得到，raw=%d rounded=%d" % [raw_bobber_anchor, unlock_bobber_cost])
	_assert(g._visible_equipment_chain() == ["fish_line", "reel"],
		"属性装备应逐步显露：初始只显示鱼线与绕线轮解锁")
	g.coins = unlock_reel_cost
	g._try_unlock_equipment("reel")
	_assert(g.reel_level == 1 and g.coins == 0, "绕线轮应通过链式解锁进入 Lv.1")
	_assert(g._visible_equipment_chain() == ["fish_line", "reel", "bobber"],
		"绕线轮解锁后应显示浮漂解锁，但不能提前显示探鱼器")
	var cost9: int = g._reel_upgrade_cost(9)
	g.coins = cost9
	g._try_upgrade_reel(9)
	_assert(g.reel_level == 10 and g.coins == 0, "绕线轮正式升级应真实扣除金币")
	var line_cost10: int = g._gear_upgrade_cost("fish_line", 10)
	g.coins = line_cost10
	g._try_upgrade_attr_gear("fish_line", 10)
	var stats = g._angler_stats()
	_assert(g.fish_line_level == 10 and g.coins == 0 and stats.technique > 0.0 and stats.stability > 0.0,
		"鱼线应可正式扣费升级，并同时提供技巧/稳定属性")
	var line700 = AnglerEquipmentScript.attr_equipment_stats("fish_line", 700)
	var line710 = AnglerEquipmentScript.attr_equipment_stats("fish_line", 710)
	_assert(absf(float(line710.technique) - float(line700.technique) - 5.5) < 0.001
			and absf(float(line710.stability) - float(line700.stability) - 4.5) < 0.001,
		"装备等级→角色属性应持续线性增长，鱼线 700→710 仍应增加技巧 5.5 / 稳定 4.5")
	TestMode.bump_reel(g, -3)
	_assert(g.reel_level == 7, "测试台应支持绕线轮降级")
	TestMode.set_reel(g, 100)
	_assert(g.reel_level == 100 and g._avg_wait_for_reel(100) < t0, "测试台应支持设定绕线轮等级")
	g.bobber_level = 2
	g.sonar_level = 3
	g.notebook_level = 4
	g.gloves_level = 5
	var d: Dictionary = SaveSystem.collect(g)
	_assert(int(d["ver"]) == 18 and int(d["reel_level"]) == 100 and int(d["gloves_level"]) == 5,
		"v18 应保存 reel_level 与五件属性装备等级")
	g.reel_level = 0
	g.fish_line_level = 0
	g.bobber_level = 0
	g.sonar_level = 0
	g.notebook_level = 0
	g.gloves_level = 0
	SaveSystem.apply(g, d)
	_assert(g.reel_level == 100 and g.fish_line_level == 10 and g.bobber_level == 2
			and g.sonar_level == 3 and g.notebook_level == 4 and g.gloves_level == 5,
		"v18 应恢复 reel_level 与五件属性装备等级")
	var od := d.duplicate()
	od.erase("reel_level")
	od.erase("fish_line_level")
	od.erase("bobber_level")
	od.erase("sonar_level")
	od.erase("notebook_level")
	od.erase("gloves_level")
	SaveSystem.apply(g, od)
	_assert(g.reel_level == 0 and g.fish_line_level == 0 and g.gloves_level == 0,
		"旧档无属性装备等级应默认 0")
	print("  属性装备：链式解锁/平滑倍率/扣费升级/测试升降/存档往返 通过")
	g.queue_free()
	await process_frame


func _check_attribute_mapping() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.rod_level = 1
	g.bait_level = 0
	g.hook_level = 0
	g.lure_level = 0
	g.reel_level = 0
	var base_wait: float = g._avg_wait_for_reel(0)
	var base_weights: Dictionary = g._effective_tier_weights(0)
	var base_q: Array = FishData.quality_probs(g.bait_level, g._quality_attr_bonus())
	var base_vbias: float = g._variant_bias()
	var base_double: float = g._double_chance()
	var base_power: float = g._weight_power()
	g.fish_line_level = 120
	g.bobber_level = 120
	g.sonar_level = 120
	g.notebook_level = 120
	g.gloves_level = 120
	var high_wait: float = g._avg_wait_for_reel(0)
	var high_weights: Dictionary = g._effective_tier_weights(0)
	var high_q: Array = FishData.quality_probs(g.bait_level, g._quality_attr_bonus())
	var high_vbias: float = g._variant_bias()
	var high_double: float = g._double_chance()
	var high_power: float = g._weight_power()
	_assert(high_wait < base_wait, "反应属性应缩短一竿周期 %.2f -> %.2f" % [base_wait, high_wait])
	_assert(float(high_weights[4]) > float(base_weights[4]) and float(high_weights[5]) > float(base_weights[5]),
		"生态/感知应提高传说/神话品阶权重")
	_assert(float(high_q[1]) > float(base_q[1]) and float(high_q[2]) > float(base_q[2]),
		"技巧/稳定应提高星级逐级通过率")
	_assert(high_vbias > base_vbias, "感知/生态应提高变体 vbias")
	_assert(high_double > base_double, "反应/技巧应提高双钩率")
	_assert(high_power < base_power, "力量/稳定应降低体重指数，让大鱼尾部更常见")
	print("  属性映射：节奏/品阶/星级/变体/双钩/体型 通过")
	g.queue_free()
	await process_frame


const TEST_SAVE := "user://test_save.json"


func _check_quality() -> void:
	_assert(FishData.QUALITY_NAMES.size() == 4 and FishData.QUALITY_MULTS.size() == 4,
		"星级应为 4 档")
	_assert(FishData.BAITS.size() == 4, "鱼饵应为 4 档")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var q0 := {0: 0, 1: 0, 2: 0, 3: 0}
	var q3 := {0: 0, 1: 0, 2: 0, 3: 0}
	for i in 8000:
		q0[FishData.roll_quality(0, rng)] += 1
		q3[FishData.roll_quality(3, rng)] += 1
	print("  星级分布(8000)：蚯蚓 %s ｜ 秘制饵 %s" % [str(q0), str(q3)])
	_assert(q0[0] > q3[0], "高级饵应减少无星渔获")
	_assert(q3[1] + q3[2] + q3[3] > q0[1] + q0[2] + q0[3], "高级饵应提高星级率")
	_assert(q3[3] > 0, "秘制饵 8000 次内应出完美★★★")
	_assert(q0[1] > q0[2] and q3[1] > q3[3], "星级越高越稀有")
	var v0 := 0
	var v3 := 0
	for i in 1500:
		v0 += int(FishData.roll_catch(rng, 1, 0)["v"])
		v3 += int(FishData.roll_catch(rng, 1, 3)["v"])
	_assert(v3 > v0, "高级饵整体产出应更高")
	print("  均价：蚯蚓 %.1f → 秘制饵 %.1f" % [v0 / 1500.0, v3 / 1500.0])


func _check_merchant() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	game.save_enabled = false
	root.add_child(game)
	await process_frame
	_assert(not game._merchant_active, "起始鱼贩不在场")
	# 放一条已知价值的鱼，平时按原价卖
	game.inventory = [{"id": "carp", "w": 2.0, "v": 100, "q": 0}]
	game._merchant_active = false
	_assert(game._sell_value(game.inventory[0]) == 100, "平时卖价应为原价")
	# 鱼贩在场 → ×1.5
	game._merchant_active = true
	_assert(game._sell_value(game.inventory[0]) == 150, "鱼贩在场卖价应 ×1.5")
	game._sell_one(0)
	_assert(game.lifetime_coins == 150, "鱼贩在场单卖应得 150，实际 %d" % game.lifetime_coins)
	# 计时切换：在场倒计时归零应离场并排下次
	game._merchant_active = true
	game._merchant_t = 0.0
	game._tick_merchant(0.1)
	_assert(not game._merchant_active, "在场结束应离场")
	_assert(game._merchant_t >= game.MERCHANT_GAP.x, "离场后应排下次出现")
	# 不在场倒计时归零应到场
	game._merchant_t = 0.0
	game._tick_merchant(0.1)
	_assert(game._merchant_active, "间隔结束应到场")
	_assert(game._merchant_t >= game.MERCHANT_DUR.x, "到场后应设停留时长")
	print("  鱼贩：×1.5 卖价 / 到场离场计时切换 通过")
	game.queue_free()
	await process_frame


func _check_daily_order() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	game.save_enabled = false
	root.add_child(game)
	await process_frame
	game.daily_order = {"date": game._today_key(), "fish": "carp", "need": 2, "done": false}
	game.inventory = [
		{"id": "carp", "w": 2.0, "v": 10, "q": 0},
		{"id": "carp", "w": 3.0, "v": 100, "q": 0, "lock": true},
		{"id": "bream", "w": 1.0, "v": 40, "q": 0},
		{"id": "carp", "w": 4.0, "v": 30, "q": 0},
		{"id": "carp", "w": 5.0, "v": 20, "q": 0},
	]
	var idx: Array = game._daily_order_indices()
	_assert(idx.size() == 3, "每日订单应只统计未上锁目标鱼，实际 %d" % idx.size())
	_assert(game._daily_order_reward(idx) == 125, "订单应按最高价值 2 条 ×2.5 结算为 125")
	game._merchant_active = true
	_assert(game._daily_order_reward(idx) == 188, "收鱼郎在场订单应再 ×1.5 = 188，实际 %d" % game._daily_order_reward(idx))
	game._merchant_active = false
	game._try_complete_daily_order()
	_assert(bool(game.daily_order["done"]), "交付后今日订单应标记完成")
	_assert(game.coins == 125 and game.lifetime_coins == 125, "订单收益应进金币和累计卖鱼收入")
	_assert(game.inventory.size() == 3, "订单应消耗 2 条目标鱼，实际剩余 %d" % game.inventory.size())
	_assert(bool(game.inventory[1].get("lock", false)), "锁定目标鱼不应被订单消耗")
	_assert(str(game.inventory[0]["id"]) == "carp" and int(game.inventory[0]["v"]) == 10,
		"订单应优先交付高价值目标鱼，低价值未锁定目标鱼应留下")
	var before: int = game.coins
	game._try_complete_daily_order()
	_assert(game.coins == before, "完成后的订单不应重复领奖")
	game.daily_order = {"date": "2000-01-01", "fish": "carp", "need": 2, "done": true}
	game._ensure_daily_order()
	_assert(str(game.daily_order["date"]) == game._today_key(), "跨日应刷新为今日订单")
	_assert(not bool(game.daily_order["done"]), "新日期订单应未完成")
	_assert(FishData.FISH.has(str(game.daily_order["fish"])), "新订单目标鱼应有效")
	game._catch_tab = 2
	game._open_panel("catch")
	_assert(is_instance_valid(game._panel), "订单页签应能正常打开")
	# 多类型订单匹配
	game.inventory = [
		{"id": "koi", "w": 4.0, "v": 300, "q": 0},
		{"id": "crucian", "w": 0.4, "v": 5, "q": 0},
		{"id": "carp", "w": 2.5, "v": 30, "q": 1},
	]
	game.daily_order = {"date": game._today_key(), "kind": "tier", "fish": "koi", "tier": 3, "need": 1, "minw": 1.0, "done": false}
	var ti: Array = game._daily_order_indices()
	_assert(ti.size() == 1 and ti[0] == 0, "品阶订单应只匹配 ≥tier3 的 koi")
	game.daily_order = {"date": game._today_key(), "kind": "weight", "fish": "carp", "tier": 1, "need": 1, "minw": 2.0, "done": false}
	var wi: Array = game._daily_order_indices()
	_assert(wi.size() == 2, "重量订单应匹配 ≥2.0kg 的 koi+carp，实际 %d" % wi.size())
	# 完美订单只匹配 q3（perfect 单豁免珍稀排除）
	game.inventory.append({"id": "koi", "w": 4.0, "v": 900, "q": 3})
	game.daily_order = {"date": game._today_key(), "kind": "perfect", "fish": "koi", "tier": 1, "need": 1, "minw": 1.0, "done": false}
	var pi: Array = game._daily_order_indices()
	_assert(pi.size() == 1 and int(game.inventory[pi[0]]["q"]) == 3, "完美订单应只匹配 q3")
	_assert(game._order_short() == "完美★" and game._order_title().begins_with("收"), "订单标题/短标签应可生成")
	# 珍稀排除（P1）：非 perfect 单不自动交付 q3/鎏金+七彩变体
	game.daily_order = {"date": game._today_key(), "kind": "species", "fish": "koi", "tier": 1, "need": 1, "minw": 1.0, "done": false}
	var si: Array = game._daily_order_indices()
	_assert(si.size() == 1 and int(game.inventory[si[0]].get("q", 0)) == 0,
		"species 单应排除珍稀（★★★ 不自动交付），只留普通 koi")
	game.inventory.append({"id": "koi", "w": 4.0, "v": 600, "q": 0, "var": 3})
	_assert(game._daily_order_indices().size() == 1, "七彩变体不应进自动交单池")
	print("  每日订单：生成 / 锁定跳过 / 交付 ×2.5 / 跨日刷新 / 多类型匹配 / 珍稀排除 通过")
	game.queue_free()
	await process_frame


## 鱼贩合约（自动贩卖）：签约扣款 / 只卖最便宜杂鱼 / 珍品·收藏·订单全保护 / 开关 / 存档往返。
func _check_autosell() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.daily_order = {}  # 解耦 _ready 按真实日期种子生成的订单（tier/weight 单会保护全部 carp → 假失败）；订单保护下面单测
	var junk := func(v: int) -> Dictionary:
		return {"id": "carp", "w": 1.0, "v": v, "q": 0, "lock": false, "var": 0}
	# 未签约：满篓也不动（老玩家行为不变）
	g.inventory = []
	for i in g._bag_capacity():
		g.inventory.append(junk.call(10))
	_assert(not g._try_auto_sell(), "未签约不应自动卖")
	# 签约：扣款 + 默认开启
	var cost: int = g.AUTO_SELL_COST
	g.coins = cost + 10000
	g._try_buy_autosell()
	_assert(g.auto_sell_bought and g.auto_sell_on, "签约后应买断并默认开启")
	_assert(g.coins == 10000, "签约应扣 %d 金币，余 %d" % [cost, g.coins])
	# 满篓：按市价带走「最便宜」那条杂鱼
	g.inventory[3] = junk.call(5)
	var before: int = g.coins
	_assert(g._try_auto_sell(), "签约后满篓应自动带走一条")
	_assert(g.inventory.size() == g._bag_capacity() - 1, "带走后应腾出 1 格")
	_assert(g.coins == before + 5 and g.auto_sold_n == 1 and g.auto_sold_v == 5,
		"应按市价卖出最便宜那条(5)并计数")
	# 五道内在护栏（无订单干扰）：变体/高星/高品阶/巨物/收藏锁——每条恰好只踩一道，独立可验
	g.inventory = [
		{"id": "carp", "w": 1.0, "v": 10, "q": 0, "lock": false, "var": 1},   # 斑斓变体
		{"id": "carp", "w": 1.0, "v": 10, "q": 2, "lock": false, "var": 0},   # ★★ 高星
		{"id": "kaluga", "w": 80.0, "v": 9000, "q": 0, "lock": false, "var": 0},  # 高品阶
		{"id": "carp", "w": 7.9, "v": 38, "q": 0, "lock": false, "var": 0},   # 巨物体型（≥wmin+0.95×跨度）
		{"id": "carp", "w": 1.0, "v": 10, "q": 0, "lock": true, "var": 0},    # 收藏锁
	]
	var protected_n: int = g.inventory.size()
	_assert(not g._try_auto_sell(), "篓里全是珍品/受保护鱼时不应卖出任何一条")
	_assert(g.inventory.size() == protected_n, "受保护鱼一条不能少")
	# 第六道：订单保护看 done——未交付的目标鱼不碰，交付后解除（防 tier/weight 单冻住合约一整天）
	g.daily_order = {"date": "x", "kind": "species", "fish": "carp", "need": 99,
		"tier": 1, "minw": 1.0, "spot": g.current_spot, "done": false}
	g.inventory = [junk.call(10)]
	_assert(not g._try_auto_sell(), "未交付订单的目标鱼不应被自动卖")
	g.daily_order["done"] = true
	_assert(g._try_auto_sell(), "订单交付后应解除保护、恢复可卖")
	g.daily_order = {}
	# 开关：暂停后即使有杂鱼也不动
	g.inventory = [junk.call(10)]
	g._toggle_autosell()
	_assert(not g.auto_sell_on and not g._try_auto_sell(), "暂停后不应自动卖")
	g._toggle_autosell()
	_assert(g.auto_sell_on and g._try_auto_sell(), "重新开启后应恢复自动卖")
	# 存档往返：v14 四字段全覆盖（n=3 次卖出：5+10+10 → v=25）
	var d: Dictionary = SaveSystem.collect(g)
	_assert(int(d["ver"]) == 18, "存档版本应为 v18")
	g.auto_sell_bought = false
	g.auto_sell_on = false
	g.auto_sold_n = 0
	g.auto_sold_v = 0
	SaveSystem.apply(g, d)
	_assert(g.auto_sell_bought and g.auto_sell_on and g.auto_sold_n == 3 and g.auto_sold_v == 25,
		"合约字段应随档往返（含 n/v 累计），实得 n=%d v=%d" % [g.auto_sold_n, g.auto_sold_v])
	# 旧档（无 autosell 字段）→ 默认未购买、计数归零
	var old_d: Dictionary = d.duplicate()
	old_d.erase("autosell")
	SaveSystem.apply(g, old_d)
	_assert(not g.auto_sell_bought and not g.auto_sell_on and g.auto_sold_n == 0 and g.auto_sold_v == 0,
		"旧档迁移应默认未签约、计数归零")
	print("  鱼贩合约：签约/最便宜杂鱼/六道护栏独立命中/订单done解除/开关/往返+旧档迁移 通过")
	g.queue_free()
	await process_frame


## 数值 P1：重复变体折彩鳞 / 定向兑换（点亮 vmask、扣鳞、边界）/ vgrid·comp_wins 成就 / v15 往返。
func _check_p1_scales() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	# 首见变体不折鳞；重复折 1 枚「同档鳞」（三币种：防低档金流刷穿七彩格）
	g.dex.clear()
	g.scales = [0, 0, 0]
	g._dex_record("carp", 1.0, false, false, 1)
	_assert(int(g.scales[0]) == 0, "首见变体不应折鳞")
	g._dex_record("carp", 1.0, false, false, 1)
	_assert(int(g.scales[0]) == 1 and int(g.scales[2]) == 0, "重复斑斓应折 1 枚斑斓鳞")
	g._dex_record("carp", 1.0, false, false, 3)
	g._dex_record("carp", 1.0, false, false, 3)
	_assert(int(g.scales[2]) == 1 and int(g.scales[0]) == 1, "重复七彩应折 1 枚七彩鳞（不混档）")
	# 定向兑换：扣同档鳞 + 点亮；余额不足/异档鳞再多也不动/已点亮不扣
	g.scales = [99, 2, 0]
	g._redeem_variant("carp", 2)   # carp tier1 → 需 3 枚鎏金鳞，只有 2
	_assert((int(g.dex["carp"]["vmask"]) & (1 << 2)) == 0 and int(g.scales[1]) == 2,
		"同档鳞不足不应兑换（异档鳞不可代用）")
	g.scales = [0, 3, 0]
	g._redeem_variant("carp", 2)
	_assert((int(g.dex["carp"]["vmask"]) & (1 << 2)) != 0, "兑换应点亮鎏金位")
	_assert(int(g.scales[1]) == 0, "兑换应扣 3 枚鎏金鳞，余 %d" % int(g.scales[1]))
	g.scales = [0, 0, 9]
	g._redeem_variant("carp", 3)   # 首见七彩时已点亮 → 不扣
	_assert(int(g.scales[2]) == 9, "已点亮格不应重复扣鳞")
	_assert(FishData.scale_cost(1) == 3 and FishData.scale_cost(4) == 4 and FishData.scale_cost(5) == 5,
		"分层定价应为 3/4/5 枚同档鳞")
	# vgrid 成就：34 种 ×3 位 = 102 格
	g.dex.clear()
	for id in FishData.FISH.keys().slice(0, 34):
		g.dex[str(id)] = {"n": 1, "w": 1.0, "big": false, "perf": false, "vmask": 0b1110, "fd": ""}
	_assert(g._vgrid_count() == 102, "vgrid 计数应 102，实际 %d" % g._vgrid_count())
	g._check_achievements()
	_assert(g.achievements_done.has("vgrid_100"), "点亮 ≥100 格应解锁 vgrid_100")
	# comp_wins：夺金累计跨周携带 + 成就（经 main 薄壳调用，避免编译期把 main.gd 拖进 -s 时序竞争）
	g.competition = {"week": -99, "fish": "carp", "best": 0.0, "claimed": false, "reward": 100, "wins": 4}
	g._ensure_competition()
	_assert(int(g.competition.get("wins", 0)) == 4, "跨周重建应携带累计夺金")
	g.competition["wins"] = 5
	g._check_achievements()
	_assert(g.achievements_done.has("comp_wins_5"), "累计夺金 5 次应解锁 comp_wins_5")
	# v15 往返：scales 三元数组 / yest_income / competition.wins
	g.scales = [7, 2, 1]
	g.yest_income = 12345
	var d: Dictionary = SaveSystem.collect(g)
	g.scales = [0, 0, 0]
	g.yest_income = 0
	g.competition = {}
	SaveSystem.apply(g, d)
	_assert(int(g.scales[0]) == 7 and int(g.scales[1]) == 2 and int(g.scales[2]) == 1 \
		and g.yest_income == 12345 and int(g.competition.get("wins", 0)) == 5,
		"v15 字段应随档往返（scales[]/yest_income/wins）")
	# 过渡档兼容：scales 为旧 int 形态 → 归零不崩
	var od2: Dictionary = d.duplicate()
	od2["scales"] = 41
	SaveSystem.apply(g, od2)
	_assert(g.scales == [0, 0, 0], "int 形态的过渡 scales 应安全归零")
	print("  彩鳞折算 / 定向兑换与边界 / 分层价 / vgrid·comp_wins 成就 / v15 往返 通过")
	g.queue_free()
	await process_frame


## 试竿保底：四条升级线购买后下一竿的保底展示（挂起/消费/效果/存档往返）。
func _check_showcase() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.daily_order = {}
	g.focus_mode = true   # 关宠物偷鱼，保证条数断言确定
	g.coins = 99999999
	g.bag_level = 8
	# 鱼饵：升到红虫 → 下一竿保底 ★
	g.bait_level = 0
	g._try_upgrade_bait()
	_assert(g.showcase_pending == "bait", "升级鱼饵应挂起试竿")
	g.inventory = []
	g._do_catch()
	_assert(g.showcase_pending == "", "试竿应被消费（一次性）")
	_assert(int(g.inventory[0].get("q", 0)) >= 1, "鱼饵试竿应保底 ★，实际 q=%d" % int(g.inventory[0].get("q", 0)))
	# 窝料：保底斑斓
	g._try_upgrade_lure()
	_assert(g.showcase_pending == "lure", "升级窝料应挂起试竿")
	g.inventory = []
	g._do_catch()
	_assert(int(g.inventory[0].get("var", 0)) >= 1, "窝料试竿应保底斑斓变体")
	# 鱼钩：必双钩
	g.hook_level = 0
	g._try_upgrade_hook()
	_assert(g.showcase_pending == "hook", "升级鱼钩应挂起试竿")
	g.inventory = []
	g._do_catch()
	_assert(g.inventory.size() == 2, "鱼钩试竿应必出双钩，实际 %d 条" % g.inventory.size())
	# 鱼竿：高运气一竿（概率性，不断言品阶，只验挂起与消费）
	g._try_upgrade_rod()
	_assert(g.showcase_pending == "rod", "升级鱼竿应挂起试竿")
	g.inventory = []
	g._do_catch()
	_assert(g.showcase_pending == "", "鱼竿试竿应被消费")
	# 存档往返：升级后未钓即退出也不丢
	g.showcase_pending = "hook"
	var d: Dictionary = SaveSystem.collect(g)
	g.showcase_pending = ""
	SaveSystem.apply(g, d)
	_assert(g.showcase_pending == "hook", "试竿挂起应随档往返")
	print("  试竿保底：四线挂起/消费/保底效果/往返 通过")
	g.queue_free()
	await process_frame


func _check_achievements_feature() -> void:
	_assert(AchievementData.LIST.size() >= 12, "成就至少 12 项")
	var ids := {}
	for a in AchievementData.LIST:
		_assert(not ids.has(a["id"]), "成就 id 不应重复：%s" % a["id"])
		ids[a["id"]] = true
		for k in ["name", "desc", "kind", "n"]:
			_assert(a.has(k), "成就 %s 缺字段 %s" % [a["id"], k])
	var game: Node = load("res://main.tscn").instantiate()
	game.save_enabled = false
	root.add_child(game)
	await process_frame
	_assert(game.achievements_done.is_empty(), "起始无成就")
	# 钓一条 → first_cast 达成
	game._do_catch()
	_assert(game.achievements_done.has("first_cast"), "钓第一条应解锁初次垂钓")
	# 累计渔获里程碑（直接设计数，避开背包上限）
	game.lifetime_catches = 60
	game._check_achievements()
	_assert(game.achievements_done.has("catch_50"), "渔获 50+ 应解锁")
	# 鱼竿/鱼饵里程碑
	game.coins = 999999
	game.rod_level = 4
	game._try_upgrade_rod()  # → 5
	_assert(game.achievements_done.has("rod_5"), "鱼竿 Lv.5 应解锁")
	game.bait_level = 2
	game._try_upgrade_bait()  # → 3 秘制饵
	_assert(game.achievements_done.has("bait_master"), "秘制饵应解锁")
	# 奖励发放：清掉 species_10 已达成态，凑满 10 种再校验恰好 +500
	game.achievements_done.erase("species_10")
	game.dex.clear()
	for id in FishData.FISH.keys().slice(0, 10):
		game.dex[id] = {"n": 1, "w": 1.0}
	var before: int = game.coins
	game._check_achievements()
	_assert(game.achievements_done.has("species_10"), "图鉴 10 种应解锁")
	_assert(game.coins == before + 500, "species_10 应发 500 奖励，实得 %d" % (game.coins - before))
	# 重量里程碑成就（maxweight 扫图鉴最大体重）
	# 先清掉可能被前面随机 _do_catch 撞上巨物而提前解锁的重量成就，保证判定确定性
	game.achievements_done.erase("whopper")
	game.achievements_done.erase("leviathan")
	game.dex["koi"] = {"n": 1, "w": 12.0, "big": true, "perf": false}
	game._check_achievements()
	_assert(game.achievements_done.has("whopper"), "≥10kg 应解锁大鱼出水")
	_assert(not game.achievements_done.has("leviathan"), "12kg 不应解锁深渊巨怪(需100kg)")
	game.dex["koi"]["w"] = 150.0
	game._check_achievements()
	_assert(game.achievements_done.has("leviathan"), "≥100kg 应解锁深渊巨怪")
	game.queue_free()
	await process_frame
	# 静默补登：老存档（无 ach 字段）回屏不应触发成就 toast，但应标记已达成
	var path := ProjectSettings.globalize_path(TEST_SAVE)
	var old := {
		"ver": 4, "coins": 0, "rod_level": 6, "bag_level": 5, "bait": 0, "inv": [],
		"lt_coins": 0, "lt_catches": 400, "dex": {}, "opacity": 1.0,
		"ts": Time.get_unix_time_from_system() - 5.0,
	}
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f = null
	var g2: Node = load("res://main.tscn").instantiate()
	g2.save_enabled = true
	g2.save_path = TEST_SAVE
	root.add_child(g2)
	await process_frame
	_assert(g2.achievements_done.has("catch_300") and g2.achievements_done.has("rod_5"),
		"老存档回屏应静默补登已满足成就")
	_assert(g2.coins == 0, "静默补登不应补发奖励（金币应仍为 0）")
	print("  成就：解锁/奖励/老存档静默补登 通过（共 %d 项）" % AchievementData.LIST.size())
	g2.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)


func _check_spots() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	_assert(g.current_spot == "river_bend", "起始应在新手河湾")
	_assert(g.unlocked_spots.size() == 1 and "river_bend" in g.unlocked_spots, "起始仅河湾解锁")
	# 未解锁钓点不可切
	g._switch_spot("still_lake")
	_assert(g.current_spot == "river_bend", "未解锁钓点不应切过去")
	# 达成解锁条件 → 解锁
	g.lifetime_catches = 80
	g._refresh_unlocks()
	_assert("still_lake" in g.unlocked_spots, "达成 80 渔获应解锁静水湖泊")
	# 切到已解锁：换鱼池 + 清在场事件 + 重排
	g.active_event = "fish_run"
	g._event_buff_t = 50.0
	g._switch_spot("still_lake")
	_assert(g.current_spot == "still_lake", "应切到静水湖泊")
	_assert(g.active_event == "", "切钓点应清空在场事件")
	_assert("still_lake" in g.seen_spots, "切过去应记入已造访")
	# 鱼池随之变化：钓上的鱼都应属于湖泊池
	var lset := {}
	for fid in SpotData.pool_for("still_lake"):
		lset[fid] = true
	g.inventory = []
	g.bag_level = 8  # 放大容量便于多钓几条
	for i in 40:
		g._do_catch()
	var off_pool := 0
	for c in g.inventory:
		if not lset.has(str(c["id"])):
			off_pool += 1
	_assert(off_pool == 0, "切到湖泊后只应钓到湖鱼，越界 %d 条" % off_pool)
	# 事件适配随钓点改变
	_assert("cold_front" in g._eligible_events(), "湖泊应可触发寒潮")
	_assert(not ("tide_in" in g._eligible_events()), "湖泊不应触发涨潮")
	# 鱼图标回退：新鱼缺专属图应回退到品阶通用图标（非空、不崩）
	var ic_new: TextureRect = g._fish_icon("hairtail", 40)
	_assert(ic_new.texture != null, "新鱼缺专属图应回退品阶通用图标（非空）")
	var ic_old: TextureRect = g._fish_icon("carp", 40)
	_assert(ic_old.texture != null, "已有专属图的鱼应正常显示图标")
	ic_new.queue_free()
	ic_old.queue_free()
	print("  钓点：解锁/拒切未解锁/切换换池清事件/事件适配/图标回退 通过")
	g.queue_free()
	await process_frame


func _check_save_v8() -> void:
	var path := ProjectSettings.globalize_path(TEST_SAVE)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(path)
	# 往返：解锁全部 + 切到海岸 + 在场涨潮事件
	var g1: Node = load("res://main.tscn").instantiate()
	g1.save_enabled = true
	g1.save_path = TEST_SAVE
	root.add_child(g1)
	await process_frame
	g1.lifetime_catches = 400  # 满足 still_lake(80) + coast_pier(300)
	g1._refresh_unlocks()
	g1._switch_spot("coast_pier")
	g1.active_event = "tide_in"
	g1._event_buff_t = 3600.0  # 载档会按真实离开时长衰减 buff——给足余量，避免慢机器上被衰减清零
	g1._save()
	g1.queue_free()
	await process_frame
	var g2: Node = load("res://main.tscn").instantiate()
	g2.save_enabled = true
	g2.save_path = TEST_SAVE
	root.add_child(g2)
	await process_frame
	_assert(g2.current_spot == "coast_pier", "v8 应恢复当前钓点海岸码头")
	_assert("still_lake" in g2.unlocked_spots and "coast_pier" in g2.unlocked_spots,
		"v8 应恢复已解锁钓点")
	_assert("coast_pier" in g2.seen_spots, "v8 应恢复已造访钓点")
	_assert(g2.active_event == "tide_in" and g2._event_buff_t > 3000.0,
		"v8 应恢复在场 buff 事件（仍适用当前钓点，且未被离线衰减误清）")
	g2.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	# 旧档（v7 无 spot 字段）迁移 → 默认 river_bend，仅默认钓点解锁
	var old := {
		"ver": 7, "coins": 50, "rod_level": 2, "bag_level": 2, "bait": 0, "hook": 0,
		"inv": [], "lt_coins": 0, "lt_catches": 10, "dex": {}, "opacity": 1.0,
		"ts": Time.get_unix_time_from_system() - 5.0,
	}
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f = null
	var g3: Node = load("res://main.tscn").instantiate()
	g3.save_enabled = true
	g3.save_path = TEST_SAVE
	root.add_child(g3)
	await process_frame
	_assert(g3.current_spot == "river_bend", "旧档应默认落点河湾")
	_assert(g3.unlocked_spots.size() == 1 and "river_bend" in g3.unlocked_spots,
		"旧档(低渔获)应仅解锁河湾，实际 %s" % str(g3.unlocked_spots))
	_assert(g3.active_event == "", "旧档无在场事件")
	print("  存档 v8：多钓点往返 / 旧档迁移默认河湾 通过")
	g3.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)


func _check_decor() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.inventory = [
		{"id": "koi", "w": 3.0, "v": 300, "q": 0},
		{"id": "carp", "w": 1.0, "v": 20, "q": 0},
	]
	g.display = []
	_assert(g._sell_value(g.inventory[0]) == 300, "无陈列时卖价应无加成")
	Decor.add_from_inventory(g, 0)
	_assert(g.display.size() == 1 and g.inventory.size() == 1, "上架应从鱼篓移入陈列")
	_assert(str(g.display[0]["id"]) == "koi", "陈列的应是 koi")
	_assert(g.achievements_done.has("first_display"), "首次陈列应解锁成就")
	_assert(absf(Decor.value_bonus(g) - 0.01) < 0.0001, "1 件陈列应 +1%%")
	_assert(g._sell_value({"id": "carp", "w": 1.0, "v": 100, "q": 0}) == int(ceil(100 * 1.01)),
		"陈列加成应计入卖价")
	Decor.remove_to_inventory(g, 0)
	_assert(g.display.is_empty() and g.inventory.size() == 2, "取下应放回鱼篓")
	# 满架 + 封顶 + 成就 + 拒绝超额
	g.inventory = []
	for i in 8:
		g.inventory.append({"id": "crucian", "w": 0.4, "v": 5, "q": 0})
	for i in Decor.NUM_SLOTS:
		Decor.add_from_inventory(g, 0)
	_assert(g.display.size() == Decor.NUM_SLOTS, "应养满 %d 条" % Decor.NUM_SLOTS)
	_assert(g.achievements_done.has("display_full"), "满缸应解锁成就")
	var before: int = g.inventory.size()
	Decor.add_from_inventory(g, 0)
	_assert(g.display.size() == Decor.NUM_SLOTS and g.inventory.size() == before, "满缸不应再放入")
	_assert(absf(Decor.value_bonus(g) - 0.05) < 0.0001, "满缸应封顶 +5%%（观赏加成）")
	g.queue_free()
	await process_frame
	# 存档 v9 往返：display 应完整恢复
	var path := ProjectSettings.globalize_path(TEST_SAVE)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(path)
	var g1: Node = load("res://main.tscn").instantiate()
	g1.save_enabled = true
	g1.save_path = TEST_SAVE
	root.add_child(g1)
	await process_frame
	g1.display = [{"id": "kaluga", "w": 80.0, "v": 9000, "q": 2, "lock": false}]
	g1._save()
	g1.queue_free()
	await process_frame
	var g2: Node = load("res://main.tscn").instantiate()
	g2.save_enabled = true
	g2.save_path = TEST_SAVE
	root.add_child(g2)
	await process_frame
	_assert(g2.display.size() == 1 and str(g2.display[0]["id"]) == "kaluga",
		"v9 应恢复陈列架内容")
	g2.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	print("  水族箱：放入/捞回/加成封顶/成就/存档 v9 往返 通过")


## 活水族箱：开缸视图、游鱼数量、后台上鱼不重建、捞回鱼篓。
func _check_aquarium() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.display = [
		{"id": "koi", "w": 3.0, "v": 900, "q": 1, "lock": false, "var": 3},
		{"id": "carp", "w": 1.0, "v": 20, "q": 0, "lock": false, "var": 0},
	]
	g._catch_tab = g.TANK_TAB
	g._open_panel("catch")
	_assert(is_instance_valid(g._panel), "鱼缸页签应能打开")
	var aq: Node = g._panel.find_child("Aquarium", true, false)
	_assert(aq != null, "鱼缸页应含 Aquarium 视图")
	_assert(aq != null and aq.swimmers.size() == 2,
		"缸内应有 2 条游鱼，实际 %d" % (aq.swimmers.size() if aq != null else -1))
	# 后台上鱼（_refresh_panel）不应重建鱼缸，否则游动会被打断
	var same: Variant = g._panel
	g._refresh_panel()
	_assert(g._panel == same, "鱼缸页签时后台刷新不应重建面板")
	if aq != null:
		aq._process(0.2)  # 推进动画不应崩
	# 捞回鱼篓：display 减少且会强制重建
	Decor.remove_to_inventory(g, 0)
	_assert(g.display.size() == 1, "捞回一条后缸内应剩 1，实际 %d" % g.display.size())
	print("  活水族箱：开缸/游鱼数/后台不重建/捞回 通过")
	g.queue_free()
	await process_frame


func _check_variants() -> void:
	_assert(FishData.VARIANT_NAMES.size() == 4 and FishData.VARIANT_MULTS.size() == 4, "变体应 4 档")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var vc := {0: 0, 1: 0, 2: 0, 3: 0}
	for i in 50000:
		vc[FishData.roll_variant(rng)] += 1
	print("  变体分布(5万)：%s" % str(vc))
	_assert(vc[0] > vc[1] and vc[1] > vc[2] and vc[2] > vc[3], "变体越华丽越稀有")
	_assert(vc[3] > 0, "5 万次内应出七彩")
	_assert(FishData.VARIANT_MULTS[3] > FishData.VARIANT_MULTS[1], "高变体价值倍率更高")
	# 收集杠杆（P2 地基）：vbias>0 应整体抬高变体出现率；vbias=0 与基线逐位一致（同种子同流）
	var rb := RandomNumberGenerator.new()
	rb.seed = 11
	var base_v := 0
	for i in 50000:
		if FishData.roll_variant(rb) >= 1:
			base_v += 1
	rb.seed = 11
	var biased_v := 0
	for i in 50000:
		if FishData.roll_variant(rb, 2.0) >= 1:
			biased_v += 1
	print("  变体出现率 bias0=%d / bias2=%d（/5万）" % [base_v, biased_v])
	# P1 分档杠杆后 vbias=2 的总出现率 ≈×1.6（斑斓只吃 1/4 偏置；顶档才吃满，杠杆重心移向稀有档）
	_assert(biased_v > int(float(base_v) * 1.4), "vbias=2 应显著抬高变体出现率（杠杆生效）")
	# 分档差异化：偏置对七彩的抬升倍数应高于斑斓（顶级窝料的卖点是稀有档）
	rb.seed = 11
	var hi_base := 0
	for i in 50000:
		if FishData.roll_variant(rb) == 3:
			hi_base += 1
	rb.seed = 11
	var hi_biased := 0
	for i in 50000:
		if FishData.roll_variant(rb, 2.0) == 3:
			hi_biased += 1
	_assert(hi_biased >= hi_base * 2, "vbias=2 对七彩档应有 ≥2 倍抬升（分档杠杆重心正确）")
	# roll_catch 带 var 字段，且会出现变体
	var seen := false
	for i in 20000:
		var c := FishData.roll_catch(rng, 1)
		_assert(c.has("var"), "roll_catch 应含 var")
		if int(c["var"]) >= 1:
			seen = true
	_assert(seen, "2 万次 roll_catch 应出现稀有变体")
	# dex vmask 记录 + 成就
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.dex.clear()
	g._dex_record("carp", 1.0, false, false, 2)
	_assert(int(g.dex["carp"]["vmask"]) == (1 << 2), "应记录鎏金变体位")
	g._dex_record("carp", 1.0, false, false, 1)
	_assert(int(g.dex["carp"]["vmask"]) == ((1 << 2) | (1 << 1)), "应累积变体位（不覆盖）")
	g.best_variant = 3
	g._check_achievements()
	_assert(g.achievements_done.has("first_variant") and g.achievements_done.has("rainbow"),
		"变体成就应解锁")
	g.queue_free()
	await process_frame
	# 存档 v10 往返：渔获 var / dex vmask / best_variant
	var path := ProjectSettings.globalize_path(TEST_SAVE)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(path)
	var g1: Node = load("res://main.tscn").instantiate()
	g1.save_enabled = true
	g1.save_path = TEST_SAVE
	root.add_child(g1)
	await process_frame
	g1.inventory = [{"id": "koi", "w": 3.0, "v": 900, "q": 1, "lock": false, "var": 3}]
	g1.dex = {"koi": {"n": 2, "w": 3.0, "big": false, "perf": false, "vmask": (1 << 3)}}
	g1.best_variant = 3
	g1._save()
	g1.queue_free()
	await process_frame
	var g2: Node = load("res://main.tscn").instantiate()
	g2.save_enabled = true
	g2.save_path = TEST_SAVE
	root.add_child(g2)
	await process_frame
	_assert(int(g2.inventory[0].get("var", 0)) == 3, "v10 应恢复渔获变体")
	_assert(int(g2.dex["koi"].get("vmask", 0)) == (1 << 3), "v10 应恢复 dex 变体掩码")
	_assert(g2.best_variant == 3, "v10 应恢复 best_variant")
	g2.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	print("  稀有变体：分布/抬价/dex掩码累积/成就/存档 v10 往返 通过")


func _check_weather() -> void:
	# 时段划分
	_assert(Weather.phase_for_hour(6) == "dawn" and Weather.phase_for_hour(12) == "day"
		and Weather.phase_for_hour(18) == "dusk" and Weather.phase_for_hour(23) == "night"
		and Weather.phase_for_hour(3) == "night", "时段应按小时正确划分")
	_assert(Weather.value_mult("dusk") > 1.0 and Weather.luck("night") >= 1
		and Weather.value_mult("day") == 1.0 and Weather.luck("day") == 0,
		"金色时段应加成、白昼应中性")
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	g.current_spot = "river_bend"
	g.active_event = ""
	g.day_phase = "day"
	var base_v: float = g._catch_value_mult()
	var base_l: int = g._catch_luck()
	g.day_phase = "dusk"
	_assert(g._catch_value_mult() > base_v, "黄昏应抬高渔获增值系数")
	g.day_phase = "night"
	_assert(g._catch_luck() > base_l, "夜晚应抬高品阶运气")
	# 场景染色接入：夜晚有染色、白昼无
	g._apply_phase()
	_assert(g.painter.phase_tint.a > 0.0, "夜晚应有场景染色")
	g.day_phase = "day"
	g._apply_phase()
	_assert(g.painter.phase_tint.a == 0.0, "白昼不应染色")
	print("  昼夜时段：划分/金色时段加成/夜晚运气/染色接入 通过")
	g.queue_free()
	await process_frame


func _check_save_robust() -> void:
	for p in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = true
	g.save_path = TEST_SAVE
	root.add_child(g)
	await process_frame
	g.coins = 555
	g._save()
	g.coins = 777
	g._save()
	_assert(FileAccess.file_exists(TEST_SAVE), "保存应生成主存档")
	_assert(FileAccess.file_exists(TEST_SAVE + ".bak"), "二次保存应生成 .bak")
	_assert(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "原子写后不应残留 .tmp")
	g.queue_free()
	await process_frame
	# 损坏主档（模拟写到一半被杀），应从 .bak 恢复
	var bad := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	bad.store_string("{\"coins\": 77")  # 截断的 JSON
	bad.close()
	var g2: Node = load("res://main.tscn").instantiate()
	g2.save_enabled = true
	g2.save_path = TEST_SAVE
	root.add_child(g2)
	await process_frame
	_assert(g2.coins == 555, "主档损坏应从 .bak 恢复 555，实际 %d" % g2.coins)
	print("  存档原子写/损坏回退 通过（恢复金币 %d）" % g2.coins)
	g2.queue_free()
	await process_frame
	for p in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _check_save_v2() -> void:
	var path := ProjectSettings.globalize_path(TEST_SAVE)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(path)
	var g1: Node = load("res://main.tscn").instantiate()
	g1.save_enabled = true
	g1.save_path = TEST_SAVE
	root.add_child(g1)
	await process_frame
	g1.coins = 777
	g1.rod_level = 4
	g1.bag_level = 3
	g1.bait_level = 2
	g1.hook_level = 2
	g1.inventory = [
		{"id": "koi", "w": 3.5, "v": 880, "q": 3, "lock": true},
		{"id": "crucian", "w": 0.4, "v": 5, "q": 0},
	]
	g1.dex = {"koi": {"n": 3, "w": 5.5, "big": true, "perf": true}, "crucian": {"n": 12, "w": 0.58}}
	g1.daily_order = {"date": g1._today_key(), "fish": "carp", "need": 2, "done": true}
	g1._save()
	g1.queue_free()
	await process_frame

	var g2: Node = load("res://main.tscn").instantiate()
	g2.save_enabled = true
	g2.save_path = TEST_SAVE
	root.add_child(g2)
	await process_frame
	_assert(g2.coins == 777, "v2 应恢复金币 777，实际 %d" % g2.coins)
	_assert(g2.bag_level == 3, "v2 应恢复 bag_level 3")
	_assert(g2.inventory.size() == 2, "v2 应恢复背包 2 条鱼，实际 %d" % g2.inventory.size())
	_assert(str(g2.inventory[0]["id"]) == "koi" and int(g2.inventory[0]["v"]) == 880,
		"背包条目应完整恢复")
	_assert(int(g2.inventory[0]["q"]) == 3, "星级应随存档恢复")
	_assert(bool(g2.inventory[0]["lock"]) and not bool(g2.inventory[1].get("lock", false)),
		"收藏锁应随存档恢复")
	_assert(g2.bait_level == 2, "鱼饵等级应随存档恢复")
	_assert(g2.hook_level == 2, "鱼钩等级应随存档恢复")
	_assert(bool(g2.dex["koi"].get("big", false)) and bool(g2.dex["koi"].get("perf", false)),
		"图鉴 巨物/完美 徽章应随存档恢复")
	_assert(not bool(g2.dex["crucian"].get("big", false)), "未达成的徽章不应误置")
	_assert(int(g2.dex["crucian"]["n"]) == 12 and absf(float(g2.dex["koi"]["w"]) - 5.5) < 0.01,
		"图鉴纪录（捕获数/最大体重）应随存档恢复")
	_assert(str(g2.daily_order["fish"]) == "carp" and int(g2.daily_order["need"]) == 2
		and bool(g2.daily_order["done"]), "每日订单应随存档恢复")
	print("  v2 往返：金币 %d 背包 %d 条 容量 %d" % [g2.coins, g2.inventory.size(), g2._bag_capacity()])
	g2.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _check_migration_v1() -> void:
	# 构造一份 v1 老存档（无 ver/inv/bag_level，dex 含已移除鱼种 arowana），ts=刚刚 → 不触发离线
	var v1 := {
		"coins": 321, "rod_level": 2, "lt_coins": 500, "lt_catches": 60,
		"dex": ["crucian", "carp", "arowana"], "opacity": 0.9,
		"ts": Time.get_unix_time_from_system() - 5.0,
	}
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f = null

	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = true
	g.save_path = TEST_SAVE
	root.add_child(g)
	await process_frame
	_assert(g.coins == 321, "v1 迁移应保留金币 321，实际 %d" % g.coins)
	_assert(g.rod_level == 2, "v1 迁移应保留鱼竿 Lv.2")
	_assert(g.bag_level == 1, "v1 迁移 bag_level 应默认 1")
	_assert(g.inventory.is_empty(), "v1 迁移背包应为空")
	_assert(g.dex.has("crucian") and g.dex.has("carp"), "v1 迁移应保留有效图鉴")
	_assert(not g.dex.has("arowana"), "v1 迁移应丢弃已移除鱼种")
	_assert(int(g.dex["crucian"]["n"]) == 1 and float(g.dex["crucian"]["w"]) == 0.0,
		"旧版 id 列表应迁移为纪录结构（n=1, w=0）")
	# 纪录逻辑：前 5 条不播报，第 6 条更重才算破纪录
	g.dex["carp"] = {"n": 5, "w": 3.0}
	_assert(not g._dex_record("carp", 2.0), "未超纪录不应播报")
	_assert(g._dex_record("carp", 4.2), "超纪录且 n≥5 应播报")
	_assert(absf(float(g.dex["carp"]["w"]) - 4.2) < 0.01 and int(g.dex["carp"]["n"]) == 7,
		"纪录应更新（w=4.2, n=7）")
	g.dex["bass"] = {"n": 1, "w": 1.0}
	_assert(not g._dex_record("bass", 2.0), "n<5 即使超纪录也不播报")
	_assert(g.lifetime_coins == 500 and g.lifetime_catches == 60, "v1 迁移应保留终身统计")
	print("  v1→v2 迁移通过（金币/鱼竿/图鉴保留，背包默认空）")
	g.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _check_offline() -> void:
	# 钉死时段：离线结算的 day_phase 在 _ready 内部取真实时钟（测试插手不到），
	# 不钉死则出鱼池/价值系数随开发机时间漂移——本函数所有断言必须保持相位无关或钉死后再加。
	Weather.force_phase = "day"
	# 预置全部成就为已达成：离线结算后会补 _check_achievements()（P1），随机钓到稀有时
	# 成就发金币会污染"coins 只来自兜底折价"的断言（且随机 → flaky）
	var all_ach: Array = []
	for a in AchievementData.LIST:
		all_ach.append(str(a["id"]))
	# —— 子用例 1：离线时长不足以装满 → 全部入篓，不触发折价、不直接产金币 ——
	var short_save := {
		"ver": 2, "coins": 0, "rod_level": 1, "bag_level": 1,
		"inv": [["ghostfish", 1.0, 10], ["carp", 2.0, 30]],  # 未知鱼种过滤；v2 三元组 → q=0
		"lt_coins": 0, "lt_catches": 0, "dex": [], "opacity": 1.0, "ach": all_ach,
		"ts": Time.get_unix_time_from_system() - 60.0,  # 仅 1 分钟 → est 远小于空格
	}
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(short_save))
	f = null
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = true
	g.save_path = TEST_SAVE
	root.add_child(g)
	await process_frame
	_assert(g.inventory.size() > 1, "短离线应有渔获入篓（起始已有 1 条 carp）")
	_assert(g.inventory.size() <= g._bag_capacity(), "短离线渔获不应超过容量")
	_assert(int(g._offline_report.get("overflow_n", 0)) == 0, "未满篓不应触发折价兜底")
	_assert(g.coins == 0, "未满篓离线不应直接产金币（鱼都进了篓）")
	for c in g.inventory:
		_assert(str(c["id"]) != "ghostfish", "未知鱼种应在载入时被过滤")
	_assert(int(g.inventory[0].get("q", -1)) == 0, "v2 三元组迁移后 q 应为 0")
	print("  短离线 1min：入篓 %d 条（容量 %d），无折价兜底" % [g.inventory.size(), g._bag_capacity()])
	g.queue_free()
	await process_frame

	# —— 子用例 2：离线远超容量 → 鱼篓填满 + 多出折价兜底产金币（调研 3.2，不再硬截断）——
	var long_save := {
		"ver": 2, "coins": 0, "rod_level": 1, "bag_level": 1,
		"inv": [["carp", 2.0, 30]],
		"lt_coins": 0, "lt_catches": 0, "dex": [], "opacity": 1.0, "ach": all_ach,
		"ts": Time.get_unix_time_from_system() - 3600.0,  # 1 小时 → est 远超 20 格
	}
	f = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(long_save))
	f = null
	var g2: Node = load("res://main.tscn").instantiate()
	g2.save_enabled = true
	g2.save_path = TEST_SAVE
	root.add_child(g2)
	await process_frame
	_assert(g2.inventory.size() == g2._bag_capacity(), "长离线应把鱼篓填满")
	_assert(int(g2._offline_report.get("overflow_n", 0)) > 0, "超容量部分应触发折价兜底")
	_assert(g2.coins > 0, "满篓离线应折价产金币（不再硬截断惩罚挂机）")
	_assert(g2.coins == int(g2._offline_report.get("overflow_v", -1)), "兜底金币应与小结一致")
	print("  长离线 1h：填满 %d 格 + 折价兑 %d 条 = +%d 金币" % [
		g2.inventory.size(), int(g2._offline_report.get("overflow_n", 0)), g2.coins])
	# —— 切片函数不变量（force_phase 复位后直调，覆盖小时回推循环——钉死时段的用例跑不到它）——
	Weather.force_phase = ""
	for hrs in [0.5, 3.0, 12.0, 24.0]:
		var sl: Array = g2._offline_phase_slices(hrs * 3600.0)
		var sum_sec := 0.0
		var prev_ph := ""
		for seg in sl:
			var ph := str(seg["phase"])
			_assert(Weather.has(ph), "切片时段应合法：%s" % ph)
			_assert(ph != prev_ph, "相邻切片时段不应相同（应已合并）")
			_assert(float(seg["sec"]) > 0.0, "切片秒数应为正")
			sum_sec += float(seg["sec"])
			prev_ph = ph
		_assert(absf(sum_sec - hrs * 3600.0) < 0.01, "切片总秒数应等于离线时长（%.1fh）" % hrs)
		_assert(sl.size() <= int(hrs) + 2, "切片段数应有限（%.1fh → %d 段）" % [hrs, sl.size()])
	g2.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


## 满篓兜底核心 _absorb_overflow：留贵兑贱、上锁/订单鱼绝不被兑、折价正确。
func _check_overflow() -> void:
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = false
	root.add_child(g)
	await process_frame
	# 用一个谁都匹配不上的订单，排除每日订单对“可兑换鱼”的保护干扰
	g.daily_order = {"kind": "weight", "minw": 9999.0, "need": 1, "done": false}
	g.display = []  # 无陈列加成，卖价 = 原价，便于精确断言
	# 造满篓：1 条上锁高价鱼 + 余下廉价鱼（v=5）填满
	g.inventory = []
	var locked := {"id": "carp", "w": 50.0, "v": 9999, "q": 3, "lock": true}
	g.inventory.append(locked)
	while g.inventory.size() < g._bag_capacity():
		g.inventory.append({"id": "carp", "w": 1.0, "v": 5, "q": 0})
	var cap: int = g._bag_capacity()
	# 钓到中等价鱼 → 应替换最廉价那条（v=5），上锁鱼绝不动
	var mid := {"id": "carp", "w": 10.0, "v": 100, "q": 0}
	var gain: int = g._absorb_overflow(mid)
	_assert(g.inventory.size() == cap, "兜底后鱼篓格数不变")
	_assert(g.inventory.has(locked), "上锁收藏鱼绝不被兑掉")
	_assert(g.inventory.has(mid), "更值钱的新鱼应被收进篓")
	_assert(gain == int(ceil(5 * g.OVERFLOW_SELL_RATE)), "兑掉最廉价那条、按折价计（应=%d）" % int(ceil(5 * g.OVERFLOW_SELL_RATE)))
	# 钓到比篓里所有可兑换鱼更便宜的鱼 → 直接兑掉新鱼，篓不变
	var cheap := {"id": "carp", "w": 0.5, "v": 1, "q": 0}
	var gain2: int = g._absorb_overflow(cheap)
	_assert(not g.inventory.has(cheap), "更便宜的新鱼应被直接兑掉、不进篓")
	_assert(g.inventory.size() == cap, "兜底后鱼篓格数始终不变")
	_assert(gain2 >= 1, "兜底金币至少 1")
	# 极端：全篓上锁（无可兑换）→ 仍只兑掉新鱼、绝不动收藏
	for c in g.inventory:
		c["lock"] = true
	var snapshot: int = g.inventory.size()
	var g3: int = g._absorb_overflow({"id": "carp", "w": 2.0, "v": 80, "q": 0})
	_assert(g.inventory.size() == snapshot, "全篓上锁时不应动任何收藏鱼")
	_assert(g3 >= 1, "全篓上锁仍折价兑掉新鱼")
	print("  满篓兜底：留贵兑贱 / 上锁与订单鱼受保护 / 折价正确（gain=%d）" % gain)
	g.queue_free()
	await process_frame


func _check_effects() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	game.save_enabled = false
	root.add_child(game)
	await process_frame
	var p: Node2D = game.painter
	_assert(p.use_composite, "应处于合成主图模式")
	_assert(p._shimmer_tex.size() == 6, "水流高光应 6 帧，实际 %d" % p._shimmer_tex.size())
	_assert(p._mist_tex.size() == 3, "雾气应 3 层，实际 %d" % p._mist_tex.size())
	_assert(p._snow_tex.size() == 3, "雪粒应 3 层，实际 %d" % p._snow_tex.size())
	_assert(p._ripple_tex.size() == 4, "浮漂涟漪应 4 帧，实际 %d" % p._ripple_tex.size())
	_assert(p._glow_tex.size() == 4, "灯光呼吸应 4 帧，实际 %d" % p._glow_tex.size())
	_assert(p._wild_tex.size() == 4, "小动物应 4 种，实际 %d" % p._wild_tex.size())
	# 统一叠加层：渔夫/灯笼为独立精灵，灯笼光晕锚点跟随固定灯笼锚点（不再从底图扫描）
	_assert(p._fisher != null, "渔夫精灵应加载")
	_assert(p._fisher_pull.size() == 2, "渔夫收竿帧应 2 帧，实际 %d" % p._fisher_pull.size())
	_assert(p._lantern_tex != null, "灯笼精灵应加载")
	# 渔夫情绪 / 桌面宠物 API（Task 4）
	p.fisher_cheer()
	_assert(p.fisher_mood == "cheer", "高星上鱼应触发欢呼情绪")
	p.set_fisher_context(true, true)
	_assert(p.ctx_night and p.ctx_idle, "应接收昼夜/久坐上下文")
	p.pet_react("paw")
	_assert(p.pet_action == "paw", "上鱼应触发宠物扒拉动作")
	p._tick_pet(2.0)
	_assert(p.pet_action == "", "宠物动作应在时长结束后清除")
	_assert(p._lantern == p.lantern_anchor + Vector2(0, -16),
		"灯笼光晕锚点应跟随固定灯笼锚点，实际 %s" % str(p._lantern))
	# 所有钓场底图都应为干净底图（渔夫/灯笼/钓线/按钮全代码叠加，无烤死特例）
	for bg in ["river_bend", "still_lake", "coast_pier"]:
		p.set_spot(bg)
		_assert(p.uses_clean_bg(), "钓场底图 spot_%s.png 应存在且为干净底图" % bg)
	# 昼夜底图：river_bend 四时段应各加载对应时段图（运行时四张图齐全）
	p.set_spot("river_bend")
	for ph in ["dawn", "day", "dusk", "night"]:
		p.set_phase_tint(Weather.tint(ph), ph)   # 第二参传时段，触发底图慢淡入
		_assert(p._spot_base != null
			and p._spot_base.resource_path.ends_with("spot_river_bend_%s.png" % ph),
			"river_bend %s 应加载时段底图，实际 %s" % [ph, str(p._spot_base)])
	# 时段图缺失时回退 spot_<key>.png（still_lake 无时段图），不崩不黑屏
	p.set_spot("still_lake")
	p.set_phase_tint(Weather.tint("dawn"), "dawn")
	_assert(p._spot_base != null and p._spot_base.resource_path.ends_with("spot_still_lake.png"),
		"无时段图的钓点应回退 spot_<key>.png，实际 %s" % str(p._spot_base))
	# 未知时段同样回退现有底图（set_phase_tint 旧/新签名都不应报错）
	p.set_spot("river_bend")
	p.set_phase_tint(Weather.tint("day"))             # 旧签名（无 phase）：只改染色
	p.set_phase_tint(Weather.tint("day"), "nope")     # 未知时段：回退 spot_river_bend.png
	_assert(p.uses_clean_bg(), "未知时段应回退现有底图、不黑屏")
	print("  昼夜底图：四时段切图 + 缺图/未知时段回退 通过")
	# 小动物事件生命周期：fish 时长 0.7~1.1s，推进 2s 应结束并重排下次计时
	p._start_wild("fish")
	_assert(p._wild_kind == "fish", "应启动 fish 事件")
	_assert(not p._ripples.is_empty(), "鱼跃应触发涟漪")
	p._process(2.0)
	_assert(p._wild_kind == "", "事件应在时长结束后清除")
	_assert(p._wild_timer >= 45.0 and p._wild_timer <= 120.0, "下次事件应排在 45~120s 后")
	print("  动态层资源齐全（水光6/雾3/雪3/涟漪4/灯光4/动物4），事件生命周期通过")
	game.queue_free()
	await process_frame


## 测试模式（开发工具）：写档冻结隔离 + 改钱/给鱼即时生效 + 强制时段不被时钟覆盖 + 退出还原正式档。
func _check_test_mode() -> void:
	for p in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = true
	g.save_path = TEST_SAVE
	root.add_child(g)
	await process_frame
	# 正式档基线：coins=4321、空篓，落盘
	g.coins = 4321
	g.inventory.clear()
	g._save()
	# 进入测试模式：冻结写档
	TestMode.set_enabled(g, true)
	_assert(g.test_mode and not g.save_enabled, "进入测试模式应冻结写档")
	# 设置页（含测试台）应能正常构建（覆盖 fill_test_console：鱼种下拉/分段按钮/事件按钮）
	g._open_panel("set")
	await process_frame
	_assert(is_instance_valid(g._panel), "测试模式下设置页（测试台）应正常构建")
	g._set_dev_attrs_open(true)
	await process_frame
	_assert(is_instance_valid(g._dev_attrs_panel) and g._dev_attrs_panel.visible, "测试模式下属性面板应独立构建并显示")
	g._open_panel("catch")
	await process_frame
	_assert(is_instance_valid(g._panel) and is_instance_valid(g._dev_attrs_panel) and g._dev_attrs_panel.visible,
		"打开鱼篓等玩家面板不应关闭开发属性面板")
	g._open_panel("set")
	await process_frame
	# 改钱 / 给鱼即时生效（仅内存）
	TestMode.add_coins(g, 1000)
	_assert(g.coins == 5321, "测试加币应即时生效")
	var before: int = g.inventory.size()
	var sample_id := str(FishData.FISH.keys()[0])
	TestMode.give_fish(g, sample_id, 2, 1)
	_assert(g.inventory.size() == before + 1, "测试给鱼应入篓一条")
	_assert(g.dex.has(sample_id), "测试给鱼应登记图鉴")
	# 提速生效
	TestMode.set_speed(g, 10.0)
	_assert(is_equal_approx(g.test_speed, 10.0), "测试提速应改 test_speed")
	# 强制时段：_tick_phase 不被真实时钟覆盖（选一个与当前真实时段不同的强制值）
	var other := "day" if Weather.current_phase() != "day" else "night"
	g._forced_phase = other
	g.day_phase = other
	g._tick_phase()
	_assert(g.day_phase == other, "测试强制时段不应被真实时钟覆盖")
	# 退出测试模式：丢弃测试改动、还原正式档、恢复写档与默认运行态
	TestMode.set_enabled(g, false)
	_assert(not g.test_mode and g.save_enabled, "退出测试模式应恢复写档")
	_assert(g.coins == 4321, "退出测试模式应还原正式档金币（丢弃测试改动）")
	_assert(g.inventory.is_empty(), "退出测试模式应还原正式档鱼篓（测试给的鱼被丢弃）")
	_assert(g._forced_phase == "" and is_equal_approx(g.test_speed, 1.0),
		"退出测试模式应复位强制时段/提速")
	print("  测试模式：写档冻结/独立属性页/改钱给鱼/强制时段/退出还原正式档 通过")
	g.queue_free()
	await process_frame
	for p in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## 开启新存档（开发工具）：清空磁盘存档 + 全状态复位默认 + 落盘全新档 + 重看引导标记。
func _check_new_save() -> void:
	for p in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var g: Node = load("res://main.tscn").instantiate()
	g.save_enabled = true
	g.save_path = TEST_SAVE
	root.add_child(g)
	await process_frame
	# 造一份有进度的存档
	g.coins = 9999
	g.rod_level = 5
	g.bag_level = 3
	g.lifetime_catches = 120
	g.lifetime_coins = 30000
	g.inventory = [{"id": str(FishData.FISH.keys()[0]), "w": 0.02, "v": 3, "q": 0, "lock": false, "var": 0}]
	g.dex = {str(FishData.FISH.keys()[0]): {"n": 5, "w": 0.02, "big": false, "perf": false, "vmask": 0, "fd": "2026-06-01"}}
	g.seen_intro = true
	g.auto_sell_bought = true   # v14 合约：验证新档路径能完整复位
	g.auto_sell_on = true
	g._save()
	_assert(FileAccess.file_exists(TEST_SAVE), "前置：应已落盘有进度的存档")
	# 开启新存档
	g._new_save()
	_assert(g.coins == 0 and g.lifetime_catches == 0 and g.lifetime_coins == 0, "新存档应清零金币/累计")
	_assert(g.rod_level == 1 and g.bag_level == 1 and g.bait_level == 0 and g.hook_level == 0, "新存档应复位装备")
	_assert(not g.auto_sell_bought and not g.auto_sell_on, "新存档应复位鱼贩合约")
	_assert(g.inventory.is_empty() and g.dex.is_empty(), "新存档应清空鱼篓与图鉴")
	_assert(not g.seen_intro, "新存档应重置引导标记（重看引导）")
	_assert(g.current_spot == SpotData.DEFAULT_SPOT and g.unlocked_spots.size() == 1, "新存档应回默认钓点")
	# 落盘的新档读回应也是干净的
	var disk: Variant = SaveSystem.read_file(TEST_SAVE)
	_assert(disk is Dictionary and int((disk as Dictionary).get("coins", -1)) == 0, "新存档应已落盘为干净档")
	print("  开启新存档：清空进度/复位默认/落盘干净档/重看引导 通过")
	g.queue_free()
	await process_frame
	for p in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("失败: " + msg)
