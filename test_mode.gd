class_name TestMode
## 测试模式（开发期工具，纯静态模块）。第一参数 g = 主节点 CornerFishing。
##
## ⚠ g 故意「不带类型标注」：本模块被工具脚本 validate_game.gd 在启动早期（autoload 尚未
##   注册前）静态引用；若 g 标注为 CornerFishing，会把 main.gd 拖进早期编译相，连带触发
##   main.gd / orders.gd 里 `Audio` autoload「Identifier not found」编译坑（见 memory:
##   module-extraction-pattern）。故本模块只在编译期依赖纯数据类（FishData/Weather/SpotData/DT），
##   一切涉及 Audio 链（Orders/SaveSystem）的逻辑都经 g 的薄壳方法在运行期调用。
##
## 设计：「仅本会话生效、不写档」——
##   · 进入时先把正式进度刷盘，再冻结存档(save_enabled=false)，此后改动只在内存；
##   · 退出（切回游玩）时从磁盘重载正式档(g._test_reload_real_save)，丢弃测试改动，恢复写档。
##   → 正式存档永不被测试数据污染；重启天然回到正式档。
##
## 发布前剥离：删本文件 + ui_panels.fill_test_console + main 里 test_* 变量/钩子/两个 _test_* 薄壳。

# 各时段在「连续昼夜调色」里的代表时刻（喂给 painter.debug_tod，使氛围色与强制时段一致）。
const PHASE_TOD := {"dawn": 6.0, "day": 12.0, "dusk": 18.5, "night": 23.0}
const RelationshipDataScript := preload("res://relationship_data.gd")

# 钓鱼提速档位：等待/咬钩时长除以此值（1=正常，最后一档≈即时）。
const SPEED_OPTIONS := [1.0, 3.0, 10.0, 40.0]
const SPEED_LABELS := ["×1", "×3", "×10", "即时"]


# ============================ 模式开关 / 存档隔离 ============================

## 切换游玩/测试模式。进入=冻结写档；退出=重载正式档丢弃测试改动。
static func set_enabled(g, on: bool) -> void:
	if on == g.test_mode:
		return
	if on:
		g._save()                       # 进测试前先把当前正式进度落盘（退出时据此还原）
		g.save_enabled = false          # 冻结磁盘：测试期一切改动只在内存
		g.test_mode = true
		g.test_feature_manual_override = false
		g.test_feature_panel_open = true
		g._toast("已进入测试模式 · 改动不写档", 2.6, DT.GOLD_BRIGHT)
	else:
		g.test_mode = false
		g.test_feature_manual_override = false
		g.test_feature_panel_open = false
		g._forced_phase = ""            # 复位运行态覆盖
		g.test_speed = 1.0
		if g.painter:
			g.painter.debug_tod = -1.0
		g.save_enabled = true
		g._test_reload_real_save()      # 丢弃测试改动，回到正式档（薄壳：用 SaveSystem，运行期安全）
		g._toast("已回到游玩模式 · 正式存档", 2.6, DT.POSITIVE)
	if g.has_method("_rebuild_bottom_nav"):
		g._rebuild_bottom_nav()
	if g.display_mode != "immersive":
		if on and not is_instance_valid(g._dev_tools_bar):
			g._build_dev_tools_bar()
		elif not on:
			if is_instance_valid(g._dev_tools_bar):
				g._dev_tools_bar.queue_free()
			if is_instance_valid(g._dev_attrs_panel):
				g._dev_attrs_panel.queue_free()
			if is_instance_valid(g._feature_mgmt_panel):
				g._feature_mgmt_panel.queue_free()
			if "_relationship_debug_panel" in g and is_instance_valid(g._relationship_debug_panel):
				g._relationship_debug_panel.queue_free()
			if "_relationship_debug_open" in g:
				g._relationship_debug_open = false
	g._update_hud()
	g._refresh_panel()


# ============================ 时间 / 节奏 ============================

## 强制昼夜时段：定 _forced_phase（_tick_phase 不再被真实时钟覆盖），并立即切底图/染色/调色。
static func force_phase(g, phase: String) -> void:
	if not Weather.has(phase):
		return
	g._forced_phase = phase
	paint_phase_now(g, phase, float(PHASE_TOD.get(phase, 12.0)))
	g._update_hud()
	g._refresh_panel()


## 取消强制，回到真实时钟驱动。
static func follow_clock(g) -> void:
	g._forced_phase = ""
	if g.painter:
		g.painter.debug_tod = -1.0
	paint_phase_now(g, Weather.current_phase(), -1.0)
	g._update_hud()
	g._refresh_panel()


## 立刻把场景切到目标时段（底图 + 染色 + 连续调色），并结束慢 crossfade（不等 90s 淡入）。
## tod<0 表示用真实时钟（不强制 debug_tod）。
static func paint_phase_now(g, phase: String, tod: float) -> void:
	g.day_phase = phase
	var p = g.painter
	if p == null:
		return
	if "_spot_phase" in p:
		p._spot_phase = ""              # 逼迫重解析底图（含分时段手绘图）
	g._apply_phase()                    # set_phase_tint：切时段底图 + 染色 + HUD
	if tod >= 0.0:
		p.debug_tod = tod
	if "_spot_fade" in p:               # 立即结束昼夜底图 crossfade
		p._spot_fade = 1.0
		p._spot_prev = null
		p.queue_redraw()


## 设置钓鱼提速倍率（钳到正数）。
static func set_speed(g, mult: float) -> void:
	g.test_speed = maxf(1.0, mult)
	g._update_hud()
	g._refresh_panel()


# ============================ 经济 ============================

static func add_coins(g, amount: int) -> void:
	if g.has_method("_add_coins_safe"):
		g._add_coins_safe(amount)
	else:
		g.coins = maxi(0, g.coins + amount)
	# Audio 是 autoload：本模块被工具早期引用时直接写 Audio 会触发未注册编译坑，故经场景树惰性取用。
	var a = g.get_node_or_null("/root/Audio")
	if a:
		a.play_sfx("coin")
	g._update_hud()
	g._refresh_panel()


static func zero_coins(g) -> void:
	g.coins = 0
	g._update_hud()
	g._refresh_panel()


## 调整装备/背包等级。to_max=true 拉满，否则 +1 档。kind ∈ rod/bait/hook/bag。
static func bump_gear(g, kind: String, to_max: bool) -> void:
	match kind:
		"rod":
			g.rod_level = 10 if to_max else g.rod_level + 1   # 鱼竿无硬上限，拉满取实用高值
		"bait":
			var bmax := FishData.BAITS.size() - 1
			g.bait_level = bmax if to_max else mini(g.bait_level + 1, bmax)
		"hook":
			var hmax := FishData.HOOKS.size() - 1
			g.hook_level = hmax if to_max else mini(g.hook_level + 1, hmax)
		"bag":
			g.bag_level = g.BAG_CAPS.size() if to_max else mini(g.bag_level + 1, g.BAG_CAPS.size())
	g._check_achievements()
	g._update_hud()
	g._refresh_panel()


static func bump_reel(g, delta: int) -> void:
	g.reel_level = maxi(0, int(g.reel_level) + delta)
	g._begin_wait()
	g._update_hud()
	g._refresh_panel()


static func set_reel(g, level: int) -> void:
	g.reel_level = maxi(0, level)
	g._begin_wait()
	g._update_hud()
	g._refresh_panel()


# ============================ 鱼 / 收集 ============================

## 按鱼种 + 星级 + 变体造一条鱼（体重取偏大个体，便于看体型标；价值按现有公式算）。
static func make_fish(g, id: String, q: int, vr: int) -> Dictionary:
	var f: Dictionary = FishData.FISH[id]
	var w: float = snappedf(lerpf(float(f["wmin"]), float(f["wmax"]), 0.6), 0.01)
	var size_ratio := 0.0
	if float(f["wmax"]) > float(f["wmin"]):
		size_ratio = (w - float(f["wmin"])) / (float(f["wmax"]) - float(f["wmin"]))
	var base: float = lerpf(float(f["vmin"]), float(f["vmax"]), size_ratio)
	var rod_mult := 1.0 + float(g.rod_level - 1) * 0.08
	var v := maxi(1, int(round(base * rod_mult * FishData.QUALITY_MULTS[q] * FishData.VARIANT_MULTS[vr])))
	return {"id": id, "w": w, "v": v, "q": q, "var": vr}


## 内部：造鱼入篓 + 登记图鉴/统计（不刷新 UI）。满篓返回 false。
static func _append_fish(g, id: String, q: int, vr: int) -> bool:
	if not FishData.FISH.has(id) or g._bag_full():
		return false
	var c := make_fish(g, id, q, vr)
	g.inventory.append(c)
	g.lifetime_catches += 1
	g.best_quality = maxi(g.best_quality, q)
	g.best_variant = maxi(g.best_variant, vr)
	var ib: bool = FishData.size_tag(id, float(c["w"])) == "巨物·"
	if ib:
		g.caught_giant = true
	g._dex_record(id, float(c["w"]), ib, q >= 3, vr)
	return true


## 给指定鱼入篓。
static func give_fish(g, id: String, q: int, vr: int) -> void:
	if g._bag_full():
		g._toast("鱼篓满了，先清空或扩容", 2.0, DT.BAG_FULL)
		return
	if _append_fish(g, id, q, vr):
		g._check_achievements()
		g._update_hud()
		g._refresh_panel()


## 样本包：每品阶各给一条（取该品阶第一个鱼种）。
static func sample_pack(g) -> void:
	var picked := {}
	for id in FishData.FISH:
		var t := FishData.tier_of(str(id))
		if not picked.has(t):
			picked[t] = str(id)
	var n := 0
	for t in range(FishData.TIER_NAMES.size()):
		if picked.has(t) and _append_fish(g, str(picked[t]), 0, 0):
			n += 1
	g._check_achievements()
	g._update_hud()
	g._refresh_panel()
	g._toast("样本包：每品阶 +1 条（共 %d）" % n, 2.2, DT.GOLD)


static func clear_bag(g) -> void:
	g.inventory.clear()
	g._update_hud()
	g._refresh_panel()
	g._toast("已清空鱼篓", 1.8, DT.TEXT_MUTED_GLASS)


## 解锁全部钓点（含已造访标记）。
static func unlock_all_spots(g) -> void:
	g.unlocked_spots = SpotData.SPOT_ORDER.duplicate()
	g.seen_spots = SpotData.SPOT_ORDER.duplicate()
	g._update_hud()
	g._refresh_panel()
	g._toast("已解锁全部钓点", 2.0, DT.POSITIVE)


## 手动控制功能开放（测试模式本会话生效）。
static func set_feature_unlock(g, id: String, on: bool) -> void:
	if id == "settings":
		on = true
	g.test_feature_manual_override = true
	g._normalize_feature_unlocks()
	g.feature_unlocks[id] = on
	if not g._tab_unlocked(g._catch_tab):
		g._catch_tab = g._fallback_feature_tab()
	g._rebuild_bottom_nav()
	g._update_hud()
	g._refresh_panel()
	if g.has_method("_refresh_feature_mgmt_panel"):
		g._refresh_feature_mgmt_panel()
	if g.has_method("_layout_widget"):
		g._layout_widget()
	g._toast("%s：%s" % [id, "开放" if on else "关闭"], 1.6, DT.GOLD)


# ============================ 人情模块 ============================

static func set_relationships_unlocked(g, on := true) -> void:
	set_feature_unlock(g, "relations", on)
	if on:
		g.relationship_state = RelationshipDataScript.default_state() if g.relationship_state.is_empty() else g.relationship_state
		g._ensure_relationship_state()
		g._update_relationship_visit_bar()
		if g.has_method("_refresh_relationship_debug_panel"):
			g._refresh_relationship_debug_panel()


static func summon_relationship_visit(g, npc_id: String, kind: String) -> void:
	g._ensure_relationship_state()
	g.feature_unlocks["relations"] = true
	var visits: Dictionary = g.relationship_state.get("visits", {})
	visits[npc_id] = RelationshipDataScript.make_visit(npc_id, kind, Time.get_unix_time_from_system())
	g.relationship_state["visits"] = visits
	g.selected_relationship_visit_id = npc_id
	g._update_relationship_visit_bar()
	g._open_panel("relationship_visit")
	if g.has_method("_refresh_relationship_debug_panel"):
		g._refresh_relationship_debug_panel()


static func open_relationship_book(g) -> void:
	g.feature_unlocks["relations"] = true
	g._catch_tab = 9
	g._open_panel("catch")
	g._update_relationship_visit_bar()


static func open_relationship_visit(g, npc_id: String) -> void:
	g._ensure_relationship_state()
	var visits: Dictionary = g.relationship_state.get("visits", {})
	if not visits.has(npc_id):
		visits[npc_id] = RelationshipDataScript.make_visit(npc_id, "hint", Time.get_unix_time_from_system())
		g.relationship_state["visits"] = visits
	g.selected_relationship_visit_id = npc_id
	g._open_panel("relationship_visit")
	g._update_relationship_visit_bar()


static func adjust_relationship_favor(g, npc_id: String, delta: int) -> void:
	g._ensure_relationship_state()
	var npc_state: Dictionary = g.relationship_state.get("npc", {})
	var state: Dictionary = npc_state.get(npc_id, {"favor": 0, "finale_done": false})
	state["favor"] = clampi(int(state.get("favor", 0)) + delta, 0, RelationshipDataScript.FAVOR_LEVELS.size() - 1)
	npc_state[npc_id] = state
	g.relationship_state["npc"] = npc_state
	g._refresh_panel()
	if g.has_method("_refresh_relationship_debug_panel"):
		g._refresh_relationship_debug_panel()


static func set_relationship_favor(g, npc_id: String, value: int) -> void:
	g._ensure_relationship_state()
	var npc_state: Dictionary = g.relationship_state.get("npc", {})
	var state: Dictionary = npc_state.get(npc_id, {"favor": 0, "finale_done": false})
	state["favor"] = clampi(value, 0, RelationshipDataScript.FAVOR_LEVELS.size() - 1)
	npc_state[npc_id] = state
	g.relationship_state["npc"] = npc_state
	g._refresh_panel()
	if g.has_method("_refresh_relationship_debug_panel"):
		g._refresh_relationship_debug_panel()


static func set_relationship_finale_done(g, npc_id: String, done: bool) -> void:
	g._ensure_relationship_state()
	var npc_state: Dictionary = g.relationship_state.get("npc", {})
	var state: Dictionary = npc_state.get(npc_id, {"favor": 0, "finale_done": false})
	state["finale_done"] = done
	npc_state[npc_id] = state
	g.relationship_state["npc"] = npc_state
	var unlocks: Dictionary = g.relationship_state.get("unlocks", {})
	var reward_id := RelationshipDataScript.finale_reward_id(npc_id)
	if done and reward_id != "":
		unlocks[reward_id] = true
	elif reward_id != "":
		unlocks.erase(reward_id)
	g.relationship_state["unlocks"] = unlocks
	if g.has_method("_refresh_relationship_debug_panel"):
		g._refresh_relationship_debug_panel()


static func give_relationship_gift_fish(g, npc_id: String) -> void:
	var id := "crucian"
	match npc_id:
		"lin_aunt": id = "crucian"
		"zhou_uncle": id = "carp"
		"tang": id = "bass"
		"xiaoman": id = "minnow"
		"ma": id = "loach"
	give_fish(g, id, 1, 0)


static func give_relationship_finale_fish(g, npc_id: String) -> void:
	var id := "mackerel"
	match npc_id:
		"lin_aunt": id = "mackerel"
		"zhou_uncle": id = "oarfish" if FishData.FISH.has("oarfish") else "mackerel"
		"tang": id = "oarfish" if FishData.FISH.has("oarfish") else "koi"
		"xiaoman": id = "icefish"
		"ma": id = "catfish"
	if not FishData.FISH.has(id):
		id = "mackerel"
	give_fish(g, id, 2, 1)


static func clear_relationship_visits(g) -> void:
	g._ensure_relationship_state()
	g.relationship_state["visits"] = {}
	g.selected_relationship_visit_id = ""
	g._update_relationship_visit_bar()
	g._refresh_panel()
	if g.has_method("_refresh_relationship_debug_panel"):
		g._refresh_relationship_debug_panel()


static func clear_relationship_buff(g) -> void:
	g._ensure_relationship_state()
	g.relationship_state["buff"] = {}
	g._update_hud()
	if g.has_method("_refresh_relationship_debug_panel"):
		g._refresh_relationship_debug_panel()


## 点亮全图鉴：每种鱼登记一条满纪录（最大体重 + 巨物/完美 + 三种稀有变体已见）。
static func fill_dex(g) -> void:
	var today: String = g._today_key()
	for id in FishData.FISH:
		var f: Dictionary = FishData.FISH[id]
		var prev_n := 0
		if g.dex.has(id):
			prev_n = int((g.dex[id] as Dictionary).get("n", 0))
		g.dex[str(id)] = {
			"n": maxi(1, prev_n), "w": float(f["wmax"]),
			"big": true, "perf": true,
			"vmask": (1 << 1) | (1 << 2) | (1 << 3),   # 斑斓/鎏金/七彩 全已见
			"fd": today, "wd": today,
		}
	g._check_achievements()
	g._update_hud()
	g._refresh_panel()
	g._toast("已点亮全部图鉴", 2.2, DT.GOLD)


# ============================ 系统触发 ============================

static func summon_merchant(g) -> void:
	g._merchant_active = true
	g._merchant_t = g.rng.randf_range(g.MERCHANT_DUR.x, g.MERCHANT_DUR.y)
	g._toast("收鱼郎来了！限时收购 ×1.5", 2.6, DT.MERCHANT)
	g._update_hud()
	g._refresh_panel()


## 重置今日订单（薄壳委托 main：用 Orders 重 roll，运行期编译安全）。
static func reroll_order(g) -> void:
	g._test_reroll_order()
	g._update_hud()
	g._refresh_panel()
	g._toast("已重置今日订单", 2.0, DT.GOLD)


## 充能专注奖励（下一竿强制升级出货）。level 1=保底高星 / 2=再保底鎏金。
static func charge_focus(g, level: int) -> void:
	g.focus_pending = clampi(level, 1, 2)
	g._toast("已充能专注奖励，下一竿出惊喜 ✨", 2.2, Color(0.74, 0.86, 0.98))


## 立即触发一次随机事件（forced：指定事件 id；空＝当前钓点池随机）。
static func fire_event(g, forced := "") -> void:
	g._fire_event(forced)
