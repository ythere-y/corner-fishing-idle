class_name Competition
## 每周巨物赛（与 Orders.weekly 同构）：每周自动选一目标鱼，玩家在本周内"现钓"该鱼，
## 把本周最佳体重冲过影子线即夺金。状态在主节点 g.competition 上，存档软兼容（旧档现生成）。
## 低干扰：钓到达标个体当场自动发奖 + 高光，不催不打断（契合"安静桌面陪伴"）。

const SHADOW_RATIO := 0.55   # 影子线 = 目标鱼 wmax × 此系数（要现钓到大个体才达标）


static func week_id() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0 / 7.0)


## 确保 g.competition 是当前周的（跨周自动重选目标鱼、清零本周最佳）。
static func ensure(g: CornerFishing) -> void:
	Orders.ensure_day_stat(g)   # 重建赛事前先沉淀"昨日收入"锚（与 Orders.ensure_weekly 同理）
	var wk := week_id()
	if g.competition.has("week") and int(g.competition.get("week", -1)) == wk \
			and FishData.FISH.has(str(g.competition.get("fish", ""))):
		return
	g.competition = make(g, wk)


## 生成本周巨物赛：hash(周号) 确定性从已解锁池里挑一条 t2–t4 的鱼（够稀有有挑战，又非神话遥不可及）。
static func make(g: CornerFishing, wk: int) -> Dictionary:
	var local := RandomNumberGenerator.new()
	local.seed = int(abs(("comp:%d" % wk).hash()))
	var ids := g._order_pool()
	if ids.is_empty():
		ids = FishData.FISH.keys()
	var cands: Array = []
	for id in ids:
		var t := FishData.tier_of(str(id))
		if t >= 2 and t <= 4:
			cands.append(str(id))
	if cands.is_empty():
		cands = ids
	var fish_id: String = str(cands[local.randi() % cands.size()])
	# 奖励锚定昨日收入 8%（P1）：产出随竿级指数、奖励原是线性，毕业期塌缩成 1 分钟收入；
	# wins 跨周携带（累计夺金——comp_wins 成就 + 第二收集线的沉淀）。
	return {"week": wk, "fish": fish_id, "best": 0.0, "claimed": false,
		"reward": maxi(2500 + g.rod_level * 1200, int(float(g.yest_income) * 0.08)),
		"wins": int(g.competition.get("wins", 0))}


## 本周影子线（达标门槛体重）。
static func shadow_weight(g: CornerFishing) -> float:
	var fid := str(g.competition.get("fish", ""))
	if not FishData.FISH.has(fid):
		return 0.0
	return float(FishData.FISH[fid]["wmax"]) * SHADOW_RATIO


static func is_target(g: CornerFishing, id: String) -> bool:
	ensure(g)
	return str(g.competition.get("fish", "")) == id


## 钓到一条鱼时调用：若为本周目标鱼则刷新本周最佳。返回本次夺金奖励（0 = 未夺金）。
## 副作用（音效/toast/flash）交由调用方 main 处理——本模块不直接引用 Audio autoload（早解析坑）。
static func on_catch(g: CornerFishing, c: Dictionary) -> int:
	ensure(g)
	if str(c.get("id", "")) != str(g.competition.get("fish", "")):
		return 0
	var w := float(c.get("w", 0.0))
	if w <= float(g.competition.get("best", 0.0)):
		return 0
	g.competition["best"] = w
	if bool(g.competition.get("claimed", false)) or w < shadow_weight(g):
		return 0
	g.competition["claimed"] = true
	g.competition["wins"] = int(g.competition.get("wins", 0)) + 1   # 累计夺金沉淀（跨周携带）
	var reward := int(g.competition.get("reward", 0))
	if g.has_method("_add_coins_safe"):
		g._add_coins_safe(reward)   # 与 weekly 一致：赛事奖励不计入 lifetime_coins（卖鱼终身收入语义）
	else:
		g.coins += reward
	return reward


## 详情卡/任务页用的一句话状态（调用前需已 ensure）。
static func status_line(g: CornerFishing) -> String:
	var best := float(g.competition.get("best", 0.0))
	if bool(g.competition.get("claimed", false)):
		return "✓ 本周已夺金（最佳 %.2f kg）" % best
	return "目标 ≥%.2f kg　·　本周最佳 %.2f kg" % [shadow_weight(g), best]
