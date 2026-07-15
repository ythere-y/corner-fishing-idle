class_name SaveSystem
## 存档系统（从 main.gd 拆出）：序列化 / 反序列化 / 迁移 / 原子写 / .bak 回退。
## 纯函数，游戏状态在主节点 g 上读写。main 只保留薄壳调用 + 离线结算。
const RelationshipDataScript := preload("res://relationship_data.gd")
## 存档结构升级历史：v1 id列表→图鉴纪录轴；inv 三→四→五元组；dex 2→4元组徽章；
## daily_order 补 kind/tier/minw；新增 hook/weekly/day_stat/best_q/giant/ach/seen_intro/focus/win_pos；
## v8 多钓点：spot(当前钓点)/unlocked(已解锁)/seen(已造访)/event(在场 buff)，旧档默认 river_bend。
## v9 陈列：display(陈列架上的鱼，最多 Decor.NUM_SLOTS)，旧档默认空。
## v10 稀有变体：inv/display 第 6 元 var、dex 第 5 元 vmask、best_var；旧档默认普通(0)。
## v11 陪伴向：dex 第 6 元 fd(首捕日期，水族箱纪录卡用)；专注奖励 focus_min/rt/rd/pend；
##     桌面宠物 pet_steals。旧档默认 fd=""、专注/宠物计数 0（display 复用为水族箱，无损）。
## v12 第四成长线：lure(诱饵/窝料下标，决定稀有变体偏置 vbias)。旧档默认 0=无窝料（与基线一致，无损）。
## 【修改】v13 背包客人设：character(选择的角色 id，"jim"/"ganie")、chosen_character(是否已选过)。
##     旧档默认 chosen_character=true（老玩家不重新弹选人页），character 默认 CharacterData.DEFAULT_CHARACTER，无损迁移。
## v14 鱼贩合约：autosell {b:已买断, on:开关, n/v:累计带走条数与入金}。旧档默认未购买，无损迁移。
## v15 数值 P1：scales(彩鳞——重复变体折算的定向兑换货币)、yest_income(昨日卖鱼收入——周赛/
##     周目标奖励锚)、competition.wins(巨物赛累计夺金，跨周携带)。旧档全部默认 0，无损迁移。
## v16 帧率默认 30→120：≤v15 档的 max_fps=30 视为旧默认、一次性迁到 120（v16 起选 30 被尊重）。
## v17 独立速度装备：reel_level(绕线轮等级，提供 speed 属性并缩短一竿周期)。旧档默认 0，无损迁移。
## v18 属性装备扩展：鱼线/浮漂/探鱼器/钓鱼笔记/钓鱼手套等级。旧档默认 0，无损迁移。
## v19 修 bug：dex 第 7 元 wd(刷新最大体重的日期，鱼种详情卡「破纪录于」用)。此前只存 6 元、
##     wd 每次重启即丢，详情卡必显「—」。旧档默认 wd=""，无损迁移（新旧代码可互读）。
## v20 功能渐进开放：features(底栏系统开放状态)、feature_spend_equipment(装备消费累计)。
## v21 河湾人情簿：relationships（NPC 独立好感、到访队列与排程）。


## 把主节点状态收集成可序列化字典。
static func collect(g) -> Dictionary:
	var inv: Array = []
	for c in g.inventory:
		inv.append([c["id"], c["w"], c["v"], int(c.get("q", 0)),
			1 if bool(c.get("lock", false)) else 0, int(c.get("var", 0))])
	var disp: Array = []
	for c in g.display:
		disp.append([c["id"], c["w"], c["v"], int(c.get("q", 0)),
			1 if bool(c.get("lock", false)) else 0, int(c.get("var", 0))])
	var data := {
		"ver": 21,   # 20→21：新增河湾人情簿状态
		"coins": g.coins,
		"rod_level": g.rod_level,
		"reel_level": g.reel_level,
		"fish_line_level": g.fish_line_level,
		"bobber_level": g.bobber_level,
		"sonar_level": g.sonar_level,
		"notebook_level": g.notebook_level,
		"gloves_level": g.gloves_level,
		"bag_level": g.bag_level,
		"bait": g.bait_level,
		"hook": g.hook_level,
		"lure": g.lure_level,   # v12 第四成长线：诱饵/窝料（决定稀有变体偏置 vbias）
		"inv": inv,
		"display": disp,
		"lt_coins": g.lifetime_coins,
		"lt_catches": g.lifetime_catches,
		"dex": dex_to_save(g),
		"daily_order": g.daily_order,
		"weekly": g.weekly,
		"competition": g.competition,
		"day_stat": g.day_stat,
		"best_q": g.best_quality,
		"best_var": g.best_variant,
		"giant": g.caught_giant,
		"ach": g.achievements_done.keys(),
		"features": g.feature_unlocks,
		"feature_spend_equipment": g.feature_spend_equipment,
		"relationships": g.relationship_state,
		"opacity": g._opacity,
		"max_fps": g.max_fps,           # 帧率上限设置（旧档无 → 载入默认 120）
		"ui_scale": g.ui_scale,         # 界面缩放设置（旧档无 → 载入默认 1.0）
		"paper_grain": g.paper_grain,   # 水彩纸纹偏好（旧档无 → 载入默认开）
		"focus": g.focus_mode,
		"seen_intro": g.seen_intro,
		# —— 【新增】v13 背包客人设 ——
		"character": g.player_character,
		"chosen_character": g.chosen_character,
		# —— v8 多钓点 ——
		"spot": g.current_spot,
		"unlocked": g.unlocked_spots,
		"seen": g.seen_spots,
		"event": {"id": g.active_event, "t": g._event_buff_t} if g.active_event != "" else {},
		# —— v11 陪伴向 ——
		"focus_min": g.focus_minutes_total,   # 累计专注分钟
		"focus_rt": g.focus_reward_today,      # 今日已发专注奖励次数（封顶）
		"focus_rd": g.focus_reward_date,       # 封顶计数对应日期
		"focus_pend": g.focus_pending,         # 待兑专注奖励等级
		"pet_steals": g.pet_steals,            # 桌面宠物叼走鱼计数
		"hand_n": g.hand_catches,              # 亲手起钩累计（P0 好玩补丁；旧档无 → 载入默认 0）
		# —— v14 鱼贩合约（自动贩卖）——
		"autosell": {"b": g.auto_sell_bought, "on": g.auto_sell_on,
			"n": g.auto_sold_n, "v": g.auto_sold_v},
		# —— v15 数值 P1 ——
		"scales": g.scales,            # 彩鳞三元数组 [斑斓,鎏金,七彩]（competition.wins 随 competition 整字典走）
		"yest_income": g.yest_income,  # 昨日卖鱼收入（周赛/周目标奖励锚）
		"showcase": g.showcase_pending,  # 试竿保底挂起（升级后未钓即退出也不丢）
		"ts": Time.get_unix_time_from_system(),
	}
	if DisplayServer.get_name() != "headless":
		var wp := DisplayServer.window_get_position()
		data["win_pos"] = [wp.x, wp.y]
		if g._widget_pos != null:
			var gp: Vector2 = g._widget_pos
			data["widget_pos"] = [gp.x, gp.y]
	return data


static func dex_to_save(g) -> Dictionary:
	var out := {}
	for id in g.dex:
		var r: Dictionary = g.dex[id]
		out[id] = [int(r["n"]), float(r["w"]),
			1 if bool(r.get("big", false)) else 0,
			1 if bool(r.get("perf", false)) else 0,
			int(r.get("vmask", 0)),       # v10：见过的稀有变体位掩码
			str(r.get("fd", "")),          # v11：首次捕获日期（水族箱纪录卡）
			str(r.get("wd", ""))]          # v19：刷新最大体重的日期（鱼种详情卡「破纪录于」）
	return out


## 原子写：临时文件 → 旧档移 .bak → 改名顶替。防进程被杀时截断主档。
static func write_atomic(path: String, data: Dictionary) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	DirAccess.rename_absolute(tmp, path)


## 读一个存档文件，解析失败返回 null。
static func read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else null


## 把存档字典恢复到主节点（含各版本迁移）。不含离线结算与成就补登（留在 main）。
static func apply(g, data: Dictionary) -> void:
	g.coins = float(data.get("coins", 0.0))
	g.rod_level = max(1, int(data.get("rod_level", 1)))
	g.reel_level = maxi(0, int(data.get("reel_level", 0)))
	g.fish_line_level = maxi(0, int(data.get("fish_line_level", 0)))
	g.bobber_level = maxi(0, int(data.get("bobber_level", 0)))
	g.sonar_level = maxi(0, int(data.get("sonar_level", 0)))
	g.notebook_level = maxi(0, int(data.get("notebook_level", 0)))
	g.gloves_level = maxi(0, int(data.get("gloves_level", 0)))
	g.bag_level = max(1, int(data.get("bag_level", 1)))  # v1 无此字段 → 1
	g.bait_level = clampi(int(data.get("bait", 0)), 0, FishData.BAITS.size() - 1)  # v2 及更早 → 蚯蚓
	g.hook_level = clampi(int(data.get("hook", 0)), 0, FishData.HOOKS.size() - 1)  # 旧档 → 基础钩
	g.lure_level = clampi(int(data.get("lure", 0)), 0, FishData.LURES.size() - 1)  # v11 及更早 → 无窝料
	g.inventory = []
	for e in data.get("inv", []):           # v1 无此字段 → 空背包
		if e is Array and e.size() >= 3 and FishData.FISH.has(str(e[0])):
			g.inventory.append({"id": str(e[0]), "w": float(e[1]), "v": int(e[2]),
				"q": int(e[3]) if e.size() >= 4 else 0,    # v2 三元组 → 无星级
				"lock": e.size() >= 5 and int(e[4]) == 1,  # v3 及更早 → 未锁定
				"var": int(e[5]) if e.size() >= 6 else 0}) # v9 及更早 → 普通变体
	g.display = []                            # v9 陈列架；v8 及更早无 → 空
	# 防御性上限 8（玩法层实际封顶 Decor.NUM_SLOTS=5；此处避免引入 SaveSystem→Decor 依赖环）
	for e in data.get("display", []):
		if e is Array and e.size() >= 3 and FishData.FISH.has(str(e[0])) and g.display.size() < 8:
			g.display.append({"id": str(e[0]), "w": float(e[1]), "v": int(e[2]),
				"q": int(e[3]) if e.size() >= 4 else 0,
				"lock": e.size() >= 5 and int(e[4]) == 1,
				"var": int(e[5]) if e.size() >= 6 else 0})
	g.lifetime_coins = float(data.get("lt_coins", 0.0))
	g.lifetime_catches = int(data.get("lt_catches", 0))
	g.best_quality = int(data.get("best_q", 0))
	g.best_variant = int(data.get("best_var", 0))
	g.caught_giant = bool(data.get("giant", false))
	g.achievements_done = {}
	for id in data.get("ach", []):
		g.achievements_done[str(id)] = true
	g.feature_unlocks = {"settings": true}
	var features_raw: Variant = data.get("features", {})
	if features_raw is Dictionary:
		for fid in features_raw:
			g.feature_unlocks[str(fid)] = bool(features_raw[fid])
	g.feature_unlocks["settings"] = true
	g.feature_spend_equipment = maxf(0.0, float(data.get("feature_spend_equipment", 0.0)))
	g.relationship_state = _relationships_from_save(data.get("relationships", {}))
	g.dex = {}
	var dex_raw: Variant = data.get("dex", [])
	if dex_raw is Dictionary:                # v4+：{id: [n, w_max, big?, perf?]}
		for id in dex_raw:
			if FishData.FISH.has(str(id)) and dex_raw[id] is Array and (dex_raw[id] as Array).size() >= 2:
				var e: Array = dex_raw[id]
				g.dex[str(id)] = {"n": int(e[0]), "w": float(e[1]),
					"big": e.size() >= 3 and int(e[2]) == 1,
					"perf": e.size() >= 4 and int(e[3]) == 1,
					"vmask": int(e[4]) if e.size() >= 5 else 0,   # v10 变体掩码
					"fd": str(e[5]) if e.size() >= 6 else "",      # v11 首捕日期
					"wd": str(e[6]) if e.size() >= 7 else ""}      # v19 破纪录日期
	elif dex_raw is Array:                   # v1~v3：仅 id 列表 → 纪录从头积累
		for id in dex_raw:
			if FishData.FISH.has(str(id)):
				g.dex[str(id)] = {"n": 1, "w": 0.0, "big": false, "perf": false, "vmask": 0}
	g.daily_order = {}
	var order_raw: Variant = data.get("daily_order", {})
	if order_raw is Dictionary:
		var od: Dictionary = order_raw
		var fish_id := str(od.get("fish", ""))
		if FishData.FISH.has(fish_id):
			g.daily_order = {
				"date": str(od.get("date", "")),
				"kind": str(od.get("kind", "species")),  # 旧档无 kind → 指定鱼种
				"fish": fish_id,
				"need": max(1, int(od.get("need", 1))),
				"tier": clampi(int(od.get("tier", 1)), 1, 5),
				"minw": float(od.get("minw", 1.0)),
				"spot": str(od.get("spot", "")),         # v7 及更早无 → 留空，运行时再补
				"done": bool(od.get("done", false)),
			}
	var wk_raw: Variant = data.get("weekly", {})  # 旧档无 → main._ensure_weekly 现生成
	if wk_raw is Dictionary and wk_raw.has("week") and wk_raw.has("kind"):
		g.weekly = {
			"week": int(wk_raw.get("week", -1)),
			"kind": str(wk_raw.get("kind", "catches")),
			"target": max(1, int(wk_raw.get("target", 1))),
			"base": float(wk_raw.get("base", 0.0)),
			"reward": int(wk_raw.get("reward", 0)),
			"done": bool(wk_raw.get("done", false)),
		}
	var comp_raw: Variant = data.get("competition", {})  # 旧档无 → main._ensure_competition 现生成
	if comp_raw is Dictionary and comp_raw.has("week") and comp_raw.has("fish"):
		g.competition = {
			"week": int(comp_raw.get("week", -1)),
			"fish": str(comp_raw.get("fish", "")),
			"best": float(comp_raw.get("best", 0.0)),
			"claimed": bool(comp_raw.get("claimed", false)),
			"reward": int(comp_raw.get("reward", 0)),
			"wins": maxi(0, int(comp_raw.get("wins", 0))),   # v15 累计夺金（旧档 0）
		}
	var ds_raw: Variant = data.get("day_stat", {})  # 旧档无 → main._ensure_day_stat 现生成
	if ds_raw is Dictionary and ds_raw.has("date"):
		g.day_stat = {
			"date": str(ds_raw.get("date", "")),
			"catches": int(ds_raw.get("catches", 0)),
			"coins": float(ds_raw.get("coins", 0.0)),
		}
	g._opacity = float(data.get("opacity", 1.0))
	g._set_opacity(g._opacity)
	# 帧率：默认 120（用户拍板"默认最高"）。≤v15 档里的 30 是旧默认落盘的 → 一次性迁到 120；
	# v16 起玩家主动选的 30 正常尊重（新档写 ver=16，不会再被迁移）。
	var fps_saved := int(data.get("max_fps", 120))
	if int(data.get("ver", 0)) <= 15 and fps_saved == 30:
		fps_saved = 120
	g._set_max_fps(fps_saved)
	g._set_ui_scale(float(data.get("ui_scale", 1.0)))   # 校验 + 应用窗口缩放，旧档默认 1.0
	g._set_paper_grain(bool(data.get("paper_grain", true)))   # 水彩纸纹偏好，旧档默认开
	g.seen_intro = bool(data.get("seen_intro", true))  # 有存档=老玩家，默认已看过引导
	# 【新增】v13 背包客人设迁移：旧档无该字段 → 视为"老玩家早就出发了"，不重新弹选人页；
	# character 缺省落到 CharacterData.DEFAULT_CHARACTER（仅影响文案称呼，不影响数值）。
	g.chosen_character = bool(data.get("chosen_character", true))
	g.player_character = str(data.get("character", CharacterData.DEFAULT_CHARACTER))
	if not CharacterData.has(g.player_character):
		g.player_character = CharacterData.DEFAULT_CHARACTER
	if bool(data.get("focus", false)):
		g._set_focus(true)
	# —— v11 陪伴向（旧档无 → 全部归零，无损迁移）——
	g.focus_minutes_total = float(data.get("focus_min", 0.0))
	g.focus_reward_today = int(data.get("focus_rt", 0))
	g.focus_reward_date = str(data.get("focus_rd", ""))
	g.focus_pending = clampi(int(data.get("focus_pend", 0)), 0, 2)
	g.pet_steals = int(data.get("pet_steals", 0))
	g.hand_catches = int(data.get("hand_n", 0))   # 亲手起钩累计（旧档无 → 0，无损迁移）
	# —— v15 数值 P1（旧档无 → 0，无损迁移；scales 为三元数组，非数组的过渡值直接归零）——
	g.scales = [0, 0, 0]
	var sc_raw: Variant = data.get("scales", [])
	if sc_raw is Array:
		for i in mini(3, (sc_raw as Array).size()):
			g.scales[i] = maxi(0, int(sc_raw[i]))
	g.yest_income = maxf(0.0, float(data.get("yest_income", 0.0)))
	g.showcase_pending = str(data.get("showcase", ""))
	if not (g.showcase_pending in ["rod", "bait", "hook", "lure"]):
		g.showcase_pending = ""
	# —— v14 鱼贩合约（旧档无/字段损坏 → 未购买；先复位再覆盖，保证 apply 完全决定状态）——
	g.auto_sell_bought = false
	g.auto_sell_on = false
	g.auto_sold_n = 0
	g.auto_sold_v = 0.0
	var asr: Variant = data.get("autosell", {})
	if asr is Dictionary:
		g.auto_sell_bought = bool(asr.get("b", false))
		g.auto_sell_on = bool(asr.get("on", false)) and g.auto_sell_bought
		g.auto_sold_n = maxi(0, int(asr.get("n", 0)))
		g.auto_sold_v = maxf(0.0, float(asr.get("v", 0.0)))
	var wp: Variant = data.get("win_pos", null)
	if wp is Array and wp.size() >= 2:
		g._saved_win_pos = Vector2i(int(wp[0]), int(wp[1]))
	var widget_pos: Variant = data.get("widget_pos", null)
	if widget_pos is Array and widget_pos.size() >= 2:
		g._widget_pos = Vector2(float(widget_pos[0]), float(widget_pos[1]))
	apply_spots(g, data)


## v8 多钓点迁移：当前钓点 / 已解锁 / 已见 / 在场事件。
## 旧档（无 spot 字段）默认落点 river_bend，仅解锁默认钓点。
static func apply_spots(g, data: Dictionary) -> void:
	g.current_spot = str(data.get("spot", SpotData.DEFAULT_SPOT))
	if not SpotData.has(g.current_spot):
		g.current_spot = SpotData.DEFAULT_SPOT
	g.unlocked_spots = []
	for s in data.get("unlocked", [SpotData.DEFAULT_SPOT]):
		if SpotData.has(str(s)) and not (str(s) in g.unlocked_spots):
			g.unlocked_spots.append(str(s))
	if not (SpotData.DEFAULT_SPOT in g.unlocked_spots):
		g.unlocked_spots.append(SpotData.DEFAULT_SPOT)  # 默认钓点必在
	if not (g.current_spot in g.unlocked_spots):
		g.current_spot = SpotData.DEFAULT_SPOT          # 当前钓点必须已解锁
	g.seen_spots = []
	for s in data.get("seen", [g.current_spot]):
		if SpotData.has(str(s)) and not (str(s) in g.seen_spots):
			g.seen_spots.append(str(s))
	if not (g.current_spot in g.seen_spots):
		g.seen_spots.append(g.current_spot)
	# 在场 buff 事件：仅当事件仍适用于当前钓点时恢复，否则丢弃
	g.active_event = ""
	g._event_buff_t = 0.0
	var ev: Variant = data.get("event", {})
	if ev is Dictionary:
		var eid := str(ev.get("id", ""))
		if EventData.has(eid) and EventData.is_buff(eid) and EventData.applies_to(eid, g.current_spot):
			g.active_event = eid
			g._event_buff_t = maxf(0.0, float(ev.get("t", 0.0)))
	# 旧档订单缺 spot → 归到当前钓点
	if g.daily_order is Dictionary and str(g.daily_order.get("spot", "")) == "":
		g.daily_order["spot"] = g.current_spot


static func _relationships_from_save(raw: Variant) -> Dictionary:
	var out: Dictionary = RelationshipDataScript.default_state()
	if not (raw is Dictionary):
		return out
	var saved_npc: Variant = raw.get("npc", {})
	if saved_npc is Dictionary:
		for d in RelationshipDataScript.NPCS:
			var id := str(d["id"])
			var saved: Variant = saved_npc.get(id, {})
			if saved is Dictionary:
				out["npc"][id] = {
					"favor": clampi(int(saved.get("favor", 0)), 0, RelationshipDataScript.FAVOR_LEVELS.size() - 1),
					"finale_done": bool(saved.get("finale_done", false)),
				}
	var saved_visits: Variant = raw.get("visits", {})
	if saved_visits is Dictionary:
		for key in saved_visits:
			if (out["visits"] as Dictionary).size() >= 5:
				break
			var saved_visit: Variant = saved_visits[key]
			if not (saved_visit is Dictionary):
				continue
			var npc_id := str(saved_visit.get("npc", key))
			if RelationshipDataScript.get_npc(npc_id).is_empty():
				continue
			if (out["visits"] as Dictionary).has(npc_id):
				continue
			var kind := str(saved_visit.get("kind", "hint"))
			var created_at := maxf(0.0, float(saved_visit.get("created_at", 0.0)))
			(out["visits"] as Dictionary)[npc_id] = RelationshipDataScript.make_visit(npc_id, kind, created_at)
	out["next_visit_at"] = maxf(0.0, float(raw.get("next_visit_at", 0.0)))
	out["visit_seq"] = max(0, int(raw.get("visit_seq", 0)))
	var saved_buff: Variant = raw.get("buff", {})
	if saved_buff is Dictionary:
		var npc_id := str(saved_buff.get("npc", ""))
		var t := maxf(0.0, float(saved_buff.get("t", 0.0)))
		if t > 0.0 and not RelationshipDataScript.buff_for(npc_id).is_empty():
			out["buff"] = {"npc": npc_id, "t": t}
	return out
