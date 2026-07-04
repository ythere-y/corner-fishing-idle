class_name SpotData
## 钓点数据（纯数据）：多钓点生态挂机的可扩展骨架。
## 每个钓点用 habitat_tags 圈定鱼池（与 FishData 每条鱼的 tags 求交集），
## event_pool 决定可触发的随机事件（见 event_data.gd），可选 wait/value/luck 修正整体手感。
## 谱系/选种依据见 docs/spot-research-20260614.md（FishBase 生境 + 中文垂钓习性 + IGFA 目标鱼）。
##
## unlock：{} 表示默认解锁；否则 {"kind": catches/coins/species, "n": 阈值}。
## habitat_tags：river/lake/stream/coast/deep/cold/night/protected（与 FishData tags 对应）。
## order_bias：每日订单优先从本钓点鱼池生成（保证订单可在当前钓点完成）。
## wait_mult/value_mult/luck_bonus：钓点常驻系数（叠加在鱼竿/事件之上），默认中性。

const SPOTS := {
	"river_bend": {
		# 【修改】name/desc 改为"背包客旅程手记"叙事（v2：补上国家标注——中国，出发起点）；unlock/tags/event_pool/数值等原样保留，玩法零改动。
		"name": "第1站 · 中国 · 家门口河湾",
		"desc": "出发头一天就耍赖，没走远——先在家门口这条河边扎营，试试新钓竿手感。白条到国宝鲟都爱来凑热闹，新手全能款，图一个热身。",
		"unlock": {},  # 默认解锁
		"habitat_tags": ["river"],
		"event_pool": ["fish_run", "lucky_current", "morning_fog", "drift_crate"],
		"bg_key": "river_bend",
		"order_bias": "river",
		"wait_mult": 1.0,
		"value_mult": 1.0,
		"luck_bonus": 0,
		# 招牌景观：命中时段时 HUD 显示景观名（asset_phase 对应 spot_<key>_<phase>.png 时段图）
		"best_view": {
			"phase": "dawn",
			"name": "晨雾日出",
			"asset_phase": "dawn",
		},
	},
	"still_lake": {
		# 【修改】name/desc 改写（v2：补上国家标注——中国，国内热身第二站）
		"name": "第2站 · 中国 · 冬泊湖",
		"desc": "沿河一路往上，撞进一片被水草和乱石护着的冷湖。鲈、鳜、黑鱼、狗鱼在这儿称王，偶尔冒出条巨鲟或欧鲶，看得人倒吸一口气。",
		"unlock": {"kind": "catches", "n": 80},
		"habitat_tags": ["lake"],
		"event_pool": ["fish_run", "morning_fog", "cold_front", "lucky_current"],
		"bg_key": "still_lake",
		"order_bias": "lake",
		"wait_mult": 1.08,    # 静水咬钩略慢
		"value_mult": 1.06,   # 但鱼更肥、更值钱
		"luck_bonus": 0,
	},
	"coast_pier": {
		# 【修改】name/desc 改写（v2：定为「国家路线」，本站落地菲律宾）
		"name": "第5站 · 菲律宾 · 出海码头",
		"desc": "第一次出国，落地就直奔渔港——空气里都是咸腥味。海鲈、鲷、带鱼、石斑、马鲛轮番上钩，栈桥灯下听当地船家吹牛说深处藏着金枪与旗鱼——留了个心愿单。",
		"unlock": {"kind": "catches", "n": 300},
		"habitat_tags": ["coast"],
		"event_pool": ["fish_run", "tide_in", "drift_crate", "protected_release"],
		"bg_key": "coast_pier",
		"order_bias": "coast",
		"wait_mult": 0.96,    # 海里鱼多，咬钩略勤
		"value_mult": 1.12,   # 海鱼整体更值钱
		"luck_bonus": 0,
	},
	# —— v3 新增专属钓点（背景图待补：缺图自动回退河湾主图，不崩；见 docs/fish-expansion-plan.md）——
	"mountain_stream": {
		# 【修改】name/desc 改写（v2：补上国家标注——中国，川藏线高原溪谷）
		"name": "第3站 · 中国 · 雪线溪谷",
		"desc": "背包换成登山包，一路爬到雪线以下。溪水凛冷透亮，柳根、白甲挤在浅滩，深潭里藏着茴鱼、石爬鮡，还有极危的川陕哲罗鲑——运气好才见得着。",
		"unlock": {"kind": "catches", "n": 180},
		"habitat_tags": ["stream", "cold"],
		"event_pool": ["fish_run", "cold_front", "lucky_current", "morning_fog"],
		"bg_key": "mountain_stream",
		"order_bias": "stream",
		"wait_mult": 1.1,     # 清冷急流，咬钩略慢
		"value_mult": 1.08,   # 冷水鱼更精贵
		"luck_bonus": 0,
	},
	"deep_sea": {
		# 【修改】name/desc 改写（v2：本站落地新西兰，深海船钓胜地）
		"name": "第7站 · 新西兰 · 租船出深海",
		"desc": "飞到新西兰，把钓竿换成配重更狠的家伙，跟当地船家凑了张船票直奔深蓝。灯火照不到底，鮟鱇提着灯笼路过，更深处是月鱼和大王乌贼的地盘——胆子被撑大了不少。",
		"unlock": {"kind": "catches", "n": 600},
		"habitat_tags": ["deep"],
		"event_pool": ["fish_run", "tide_in", "drift_crate", "protected_release"],
		"bg_key": "deep_sea",
		"order_bias": "deep",
		"wait_mult": 0.95,    # 深海鱼多，咬钩勤
		"value_mult": 1.18,   # 深海鱼最值钱
		"luck_bonus": 1,      # 深渊出大物
	},
	# —— v3 第二波生态钓点（背景图待补：缺图回退河湾主图，不崩；见 docs/fish-expansion-plan.md）——
	"urban_pond": {
		# 【修改】name/desc 改写（v2：补上国家标注——中国，出境前最后补给站）
		"name": "第4站 · 中国 · 下山进城",
		"desc": "翻下雪线，一脚踩回人间烟火——桥洞下、护栏边的一汪绿水，浮着落叶与零碎倒影。食蚊鱼、清道夫、巴西龟，偶尔有人放生的招财，咬钩飞快、个个皮实，歇脚补给刚好，出境前最后补一波给养。",
		"unlock": {"kind": "catches", "n": 250},
		"habitat_tags": ["urban"],
		"event_pool": ["fish_run", "drift_crate", "lucky_current", "protected_release"],
		"bg_key": "urban_pond",
		"order_bias": "urban",
		"wait_mult": 0.92,    # 野塘咬钩飞快
		"value_mult": 0.95,   # 杂鱼不值钱
		"luck_bonus": 0,
	},
	"estuary": {
		# 【修改】name/desc 改写（v2：本站落地马来西亚）
		"name": "第6站 · 马来西亚 · 红树滩",
		"desc": "跨境南下，扎进咸淡水交汇的红树林。弹涂鱼在泥滩上蹦、射水鱼打水花猎虫，深处据说有大海鲢和极危的黄唇鱼——蹲了三天只为看它一眼。",
		"unlock": {"kind": "catches", "n": 450},
		"habitat_tags": ["brackish"],
		"event_pool": ["fish_run", "tide_in", "drift_crate", "protected_release"],
		"bg_key": "estuary",
		"order_bias": "brackish",
		"wait_mult": 1.0,
		"value_mult": 1.1,
		"luck_bonus": 0,
	},
	"coral_reef": {
		# 【修改】name/desc 改写（v2：本站落地澳大利亚大堡礁）
		"name": "第8站 · 澳大利亚 · 潜进珊瑚园",
		"desc": "从深海折返，一路开到大堡礁，扎进暖透的浅海花园。小丑鱼、神仙鱼、鹦哥在珊瑚丛里晃来晃去，礁缘偶尔巡过苏眉和蝠鲼——鱼篓被塞得五颜六色。",
		"unlock": {"kind": "catches", "n": 800},
		"habitat_tags": ["reef"],
		"event_pool": ["fish_run", "tide_in", "drift_crate", "protected_release"],
		"bg_key": "coral_reef",
		"order_bias": "reef",
		"wait_mult": 1.0,
		"value_mult": 1.15,   # 热带鱼缤纷值钱
		"luck_bonus": 0,
	},
	"polar_lake": {
		# 【修改】name/desc 改写（v2：本站落地冰岛）
		"name": "第9站 · 冰岛 · 凿冰入极地",
		"desc": "一路往冷门方向绕到冰岛，冰层下透着幽蓝，凿开一个洞就是入口。北极红点鲑、白鲑挤在冷水里，深处沉着活了几百年的格陵兰睡鲨和巨鳇——手都冻僵了还想多等一条。",
		"unlock": {"kind": "catches", "n": 1200},
		"habitat_tags": ["polar"],
		"event_pool": ["fish_run", "cold_front", "morning_fog"],
		"bg_key": "polar_lake",
		"order_bias": "polar",
		"wait_mult": 1.12,    # 冰下鱼口慢
		"value_mult": 1.16,   # 冷水鱼精贵
		"luck_bonus": 1,      # 但个个是大物
	},
	"cavern_pool": {
		# 【修改】name/desc 改写（v2：本站落地斯洛文尼亚——波斯托伊纳洞穴同款地貌）
		"name": "第10站 · 斯洛文尼亚 · 溶洞尽头",
		"desc": "路线走到最偏的一段，跑去斯洛文尼亚，跟着向导摸进钟乳石垂落的暗河。退色的盲鱼贴着壁游，潭底藏着多鳍鱼、肺鱼这些活化石，据说更深处还有传说中的大鲵——手记先写到这儿，下一段等信号恢复。",
		"unlock": {"kind": "species", "n": 110},
		"habitat_tags": ["cavern"],
		"event_pool": ["fish_run", "morning_fog", "drift_crate"],
		"bg_key": "cavern_pool",
		"order_bias": "cavern",
		"wait_mult": 1.15,    # 暗水鱼少咬钩慢
		"value_mult": 1.2,    # 盲鱼/活化石稀奇值钱
		"luck_bonus": 1,
	},
}

## 显示与解锁推荐顺序（UI 列表、解锁提示用）。大致按解锁阈值递增排（古潭按图鉴种数解锁，排末位）。
const SPOT_ORDER := ["river_bend", "still_lake", "mountain_stream", "urban_pond", "coast_pier",
	"estuary", "deep_sea", "coral_reef", "polar_lake", "cavern_pool"]

## 默认钓点（旧存档迁移落点）。
const DEFAULT_SPOT := "river_bend"


static func has(id: String) -> bool:
	return SPOTS.has(id)


static func get_spot(id: String) -> Dictionary:
	return SPOTS.get(id, SPOTS[DEFAULT_SPOT])


static func display_name(id: String) -> String:
	return str(get_spot(id)["name"])


## 钓点鱼池：FishData 中 tags 与本钓点 habitat_tags 有交集的鱼 id（按品阶、id 稳定排序）。
## 没有 tags 的鱼默认视为 river（保证扩 tags 之前 river_bend 仍是全鱼池，旧体验不变）。
static func pool_for(id: String) -> Array:
	var spot := get_spot(id)
	var want: Array = spot.get("habitat_tags", ["river"])
	var out: Array = []
	for fid in FishData.FISH:
		var tags: Array = FishData.FISH[fid].get("tags", ["river"])
		for t in want:
			if t in tags:
				out.append(fid)
				break
	out.sort_custom(func(a, b):
		var ta := FishData.tier_of(str(a))
		var tb := FishData.tier_of(str(b))
		if ta != tb:
			return ta < tb
		return str(a) < str(b))
	return out


## 该钓点是否默认解锁（无 unlock 条件）。
static func default_unlocked(id: String) -> bool:
	return (get_spot(id).get("unlock", {}) as Dictionary).is_empty()


## 解锁条件一句话（UI 显示）。已解锁/默认解锁返回空串。
static func unlock_text(id: String) -> String:
	var u: Dictionary = get_spot(id).get("unlock", {})
	if u.is_empty():
		return ""
	match str(u.get("kind", "")):
		"catches": return "累计钓到 %d 条鱼解锁" % int(u.get("n", 0))
		"coins": return "累计卖鱼赚 %d 金币解锁" % int(u.get("n", 0))
		"species": return "图鉴收集 %d 种鱼解锁" % int(u.get("n", 0))
	return ""


## 判定某钓点是否满足解锁条件。catches/coins 用终身累计，species 用图鉴种数。
static func unlock_met(id: String, lifetime_catches: int, lifetime_coins: int, species: int) -> bool:
	var u: Dictionary = get_spot(id).get("unlock", {})
	if u.is_empty():
		return true
	var n := int(u.get("n", 0))
	match str(u.get("kind", "")):
		"catches": return lifetime_catches >= n
		"coins": return lifetime_coins >= n
		"species": return species >= n
	return true


## 钓点常驻系数访问器（带默认值，便于 main 安全读取）。
static func wait_mult(id: String) -> float:
	return float(get_spot(id).get("wait_mult", 1.0))


static func value_mult(id: String) -> float:
	return float(get_spot(id).get("value_mult", 1.0))


static func luck_bonus(id: String) -> int:
	return int(get_spot(id).get("luck_bonus", 0))


static func event_pool(id: String) -> Array:
	return get_spot(id).get("event_pool", [])


## 钓点招牌景观（无则空字典）。
static func best_view(id: String) -> Dictionary:
	return get_spot(id).get("best_view", {})


## 当前时段命中钓点招牌景观时返回景观名，否则空串（HUD 用）。
static func scenic_name(id: String, phase: String) -> String:
	var bv := best_view(id)
	if not bv.is_empty() and str(bv.get("phase", "")) == phase:
		return str(bv.get("name", ""))
	return ""
