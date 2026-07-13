class_name Events
## 随机事件管理器（从 main.gd 拆出）。EventData 驱动；状态仍在主节点 g 上
## （active_event / _event_buff_t / _event_next_t）。同一时刻最多一个 buff 在场。
## 行为与原 main.gd 内嵌实现完全一致（仅迁移 + g. 前缀）；main 留薄壳 wrapper。


## 当前钓点可触发的事件 id 列表（事件池 ∩ EventData 适配本钓点）。
static func eligible(g: CornerFishing) -> Array:
	var out: Array = []
	for eid in SpotData.event_pool(g.current_spot):
		if EventData.has(str(eid)) and EventData.applies_to(str(eid), g.current_spot):
			out.append(str(eid))
	return out


## 事件主循环：buff 在场则走时长，否则走间隔到点触发。
static func tick(g: CornerFishing, delta: float) -> void:
	if g.active_event != "":
		g._event_buff_t -= delta
		if g._event_buff_t <= 0.0:
			end_buff(g)
		return
	g._event_next_t -= delta
	if g._event_next_t <= 0.0:
		fire(g)


## 触发一次事件：从当前钓点池随机挑选（forced 用于测试指定）。buff 进场 / instant 结算。
static func fire(g: CornerFishing, forced := "") -> void:
	var pool := eligible(g)
	if pool.is_empty():
		g._event_next_t = g.rng.randf_range(g.EVENT_FIRST.x, g.EVENT_FIRST.y)
		return
	var id := forced if (forced != "" and forced in pool) else str(pool[g.rng.randi() % pool.size()])
	if EventData.is_instant(id):
		resolve_instant(g, id)
		schedule_next_after(g, id)
	else:
		activate_buff(g, id)


## buff 事件进场：设时长、提示、可选闪光，并立刻按新节奏重排下一口。
static func activate_buff(g: CornerFishing, id: String) -> void:
	g.active_event = id
	var e: Dictionary = EventData.get_event(id)
	var dur: Array = e.get("dur", [45.0, 70.0])
	g._event_buff_t = g.rng.randf_range(float(dur[0]), float(dur[1]))
	if EventData.wants_flash(id) and not g.focus_mode:
		g._flash()
	Audio.play_sfx("sfx_event_appear")   # buff 类事件进场此前完全无声（7 种里的 6 种）
	var tin := str(e.get("toast_in", ""))
	if tin != "":
		g._toast(tin, 3.5, EventData.color(id))
	# 咬钩中不打断（与 _apply_phase 同约定）：预掷渔获/稀有驻留金环不被事件掐掉，
	# buff 的节奏变化从本竿结算后的下一次 _begin_wait 自然生效。
	if g._state != CornerFishing.ST_BITE:
		g._begin_wait()
	g._update_hud()


## buff 事件退场：清状态、提示、排下一次事件。
static func end_buff(g: CornerFishing) -> void:
	var id := g.active_event
	g.active_event = ""
	var tout := str(EventData.get_event(id).get("toast_out", ""))
	if tout != "":
		g._toast(tout, 2.4, Color(0.62, 0.70, 0.74))
	schedule_next_after(g, id)
	g._update_hud()


## instant 事件结算：发一次性金币奖励（随鱼竿轻微缩放），文案含 +金额。
static func resolve_instant(g: CornerFishing, id: String) -> void:
	var e: Dictionary = EventData.get_event(id)
	var rb: Array = e.get("reward_base", [40, 120])
	var reward := int(round(g.rng.randf_range(float(rb[0]), float(rb[1])) * (1.0 + float(g.rod_level - 1) * 0.35)))
	reward = maxi(1, reward)
	g.coins += reward  # 拾得/保育奖励：进金币但不计入卖鱼终身收入
	# 先响事件进场提示，隔开 0.3s 再落金币——同帧叠两个音会糊，且丢掉"发生了什么→得到什么"的因果。
	Audio.play_sfx("sfx_event_appear")
	g.get_tree().create_timer(0.30).timeout.connect(func() -> void: Audio.play_sfx("coin"))
	var tin := str(e.get("toast_in", ""))
	if tin != "":
		g._toast(tin % reward if "%d" in tin else tin, 3.2, EventData.color(id))
	g._check_achievements()
	g._update_hud()
	g._refresh_panel()


## 按某事件的 gap 排下一次事件出现时间。
static func schedule_next_after(g: CornerFishing, id: String) -> void:
	var gap: Array = EventData.get_event(id).get("gap", [900.0, 1800.0])
	g._event_next_t = g.rng.randf_range(float(gap[0]), float(gap[1]))
