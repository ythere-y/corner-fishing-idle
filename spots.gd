class_name Spots
## 钓点控制（从 main.gd 拆出）：当前钓点鱼池、运气/增值系数、解锁、切换、订单候选池。
## 状态仍在主节点 g 上（current_spot / unlocked_spots / seen_spots）；main 留薄壳 wrapper。
## 行为与原 main.gd 内嵌实现完全一致（仅迁移 + g. 前缀）。


## 当前钓点鱼池（多钓点）：_do_catch / 离线按此池出鱼。
## 限定鱼（FishData.limited）仅在其时段出现，其余时段从出鱼池剔除（不影响订单候选 order_pool）。
static func pool(g: CornerFishing) -> Array:
	return SpotData.pool_for(g.current_spot).filter(
		func(id): return FishData.is_available(str(id), g.day_phase))


## 钓点常驻 + 昼夜时段 + 当前事件 叠加的品阶运气。
static func catch_luck(g: CornerFishing) -> int:
	var l := SpotData.luck_bonus(g.current_spot)
	l += Weather.luck(g.day_phase)
	if g.active_event != "":
		l += EventData.luck(g.active_event)
	return l


## 钓点常驻 × 昼夜时段 × 当前事件 叠加的渔获增值系数。
static func catch_value_mult(g: CornerFishing) -> float:
	var m := SpotData.value_mult(g.current_spot)
	m *= Weather.value_mult(g.day_phase)
	if g.active_event != "":
		m *= EventData.value_mult(g.active_event)
	return m


## 补登已满足解锁条件的钓点；运行期（_unlocks_inited 后）新解锁会弹提示。
static func refresh_unlocks(g: CornerFishing) -> void:
	var species := g.dex.size()
	for sid in SpotData.SPOT_ORDER:
		if sid in g.unlocked_spots:
			continue
		if SpotData.unlock_met(sid, g.lifetime_catches, g.lifetime_coins, species):
			g.unlocked_spots.append(sid)
			if g._unlocks_inited:
				# 解锁一整个新钓点，此前和买一级鱼竿共用同一个 upgrade 音
				Audio.play_sfx("sfx_spot_unlock")
				g._toast("新钓点解锁：%s！（鱼篓→钓点 切换过去）" % SpotData.display_name(sid),
					4.0, Color(0.6, 0.85, 0.55))


## 切换到某钓点：换鱼池 / 事件 / 背景 / 订单建议。锁定钓点拒绝。
static func switch_to(g: CornerFishing, id: String) -> void:
	if not SpotData.has(id) or not (id in g.unlocked_spots):
		Audio.play_ui("ui_error")
		g._toast("这个钓点还没解锁", 1.6, Color(1.0, 0.5, 0.4))
		return
	if id == g.current_spot:
		return
	g.current_spot = id
	if not (id in g.seen_spots):
		g.seen_spots.append(id)
	# 换钓点 → 在场事件清空，按新钓点重排下一次事件
	if g.active_event != "":
		g.active_event = ""
		g._event_buff_t = 0.0
	g._event_next_t = g.rng.randf_range(g.EVENT_FIRST.x, g.EVENT_FIRST.y)
	apply_visuals(g)
	g._ensure_daily_order()
	Audio.play_sfx("upgrade")
	g._toast("已来到 %s" % SpotData.display_name(id), 2.2, Color(0.6, 0.82, 0.95))
	g._begin_wait()
	g._update_hud()
	g._refresh_panel()
	g._save()


## 把当前钓点的背景切给 ScenePainter（缺图自动回退现有主图，不崩）。
static func apply_visuals(g: CornerFishing) -> void:
	if g.painter.has_method("set_spot"):
		g.painter.set_spot(str(SpotData.get_spot(g.current_spot).get("bg_key", "")))
	# 干净 spot 显示图标按钮、river 隐藏。这里是切钓点的唯一入口（switch_to 直接调本函数），
	# 之前只放在 main._apply_spot_visuals 包装里，switch_to 绕过它 → 按钮一直没显示。
	g._update_spot_buttons()


## 订单候选鱼池：所有已解锁钓点鱼池的并集（保证订单总能在某个已解锁钓点完成）。
static func order_pool(g: CornerFishing) -> Array:
	var seen := {}
	var out: Array = []
	for sid in g.unlocked_spots:
		for fid in SpotData.pool_for(sid):
			if not seen.has(fid):
				seen[fid] = true
				out.append(fid)
	out.sort_custom(func(a, b):
		var ta := FishData.tier_of(str(a))
		var tb := FishData.tier_of(str(b))
		if ta != tb:
			return ta < tb
		return str(a) < str(b))
	return out


## 某鱼最适合在哪个已解锁钓点钓（订单 UI 的"建议钓点"提示）。
static func best_spot_for(g: CornerFishing, fish_id: String) -> String:
	for sid in SpotData.SPOT_ORDER:
		if sid in g.unlocked_spots and fish_id in SpotData.pool_for(sid):
			return sid
	return g.current_spot
