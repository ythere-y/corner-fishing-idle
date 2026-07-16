class_name RelationshipData
## 河湾「人情簿」的静态人物真值。事件排程、送礼与委托逻辑后续独立到 relationships.gd。

const FAVOR_LEVELS := ["初识", "点头之交", "熟脸", "熟人", "靠得住", "旧交", "至交"]
const VISIT_KINDS := ["story", "hint", "task", "buff", "finale"]
const BUFF_DURATION := 600.0
const STORY_LEVEL_MAX := 5  # 初识到旧交；至交的第七个里程碑由一次性终章承载。
const LEVEL_EVENTS := {
	"lin_aunt": [
		{"title": "河边第一壶茶", "body": "林阿姨认出你是新搬来的钓鱼人，顺手把一壶热茶搁在岸边。她说河湾不缺鱼，先学会按时回家。"},
		{"title": "留鱼的规矩", "body": "她家饭桌不讲稀奇，只认鲫鱼、鲤鱼这些家常味。送得合适，她会认真记住；送得太贵重，反倒让人不自在。"},
		{"title": "水草边的消息", "body": "林阿姨说清晨水草轻轻晃时，鱼口往往比正午好。邻里间传来的小消息，不必当命令，只当一条可试的线索。"},
		{"title": "空碗不催人", "body": "她从不催你交鱼，只在路过时问一句吃过没有。熟人之间的照应可以慢慢来，不需要把河湾变成待办清单。"},
		{"title": "一双暖手", "body": "天凉时，林阿姨会提前把热茶焐好。你已经是她愿意主动帮一把的人，往后到访时可能带来咬钩提速的照应。"},
		{"title": "家书留了一行", "body": "她在给远方家人的信里留下一行空白，等写进你从外地带回的那道鱼。那会是这段邻里关系的一次正式收束。"},
	],
	"zhou_uncle": [
		{"title": "先看竿梢", "body": "周叔没有问你用了什么装备，只让你看水面和竿梢。他说真正的大鱼上钩前，往往先让四周安静下来。"},
		{"title": "认水比认鱼先", "body": "他提醒你，大鱼并不等于稀有鱼；河湖里接近自身极限体重的个体，才值得认真记上一笔。"},
		{"title": "秤上的旧纪录", "body": "周叔翻出一本受潮的重量簿，里面没有夸张故事，只有地点、天气和一串改了又改的数字。"},
		{"title": "旧船还拴着", "body": "他说冬泊湖深处还有一条旧船，只是多年没人去擦船牌。普通岸钓不受影响，真正的深水记录以后或许用得上它。"},
		{"title": "压住提竿的手", "body": "周叔开始愿意在你身边多站一会儿，提醒你别被第一下拖拽骗走。往后到访时，他可能帮你盯住大体型鱼的窗口。"},
		{"title": "远方旧竿", "body": "他把旧竿擦净，却没有交给你，只约定先带回一条外地的重量纪录。完成后，那块老钓友船牌才真正有了主人。"},
	],
	"tang": [
		{"title": "先看鱼，再谈价", "body": "阿棠接鱼时先看鳞、看鳃、看体型，最后才报价。她不爱听空泛的稀有，只认能说清价值的渔获。"},
		{"title": "账本上的偏好", "body": "她的账本偏爱高价值河鱼和有地方特色的鱼。合口味的礼物是人情，普通委托则只是清楚的买卖。"},
		{"title": "识货的人", "body": "阿棠会把同样的鱼分给不同买家：有人买鲜味，有人买体面，也有人只收没见过的品种。"},
		{"title": "城外来电", "body": "她偶尔收到外地收购人的消息，但从不为了赶单催你换地图。联系人应该组织目标，而不是封住普通钓鱼。"},
		{"title": "熟价", "body": "阿棠开始愿意替你多谈一句价。往后到访时，她可能短暂提高售鱼和人情委托的结算。"},
		{"title": "跨城收购名片", "body": "她把一张尚未署名的收购名片压在账本里，等你用一条真正有分量的外地渔获完成这次终极大单。"},
	],
	"xiaoman": [
		{"title": "从名字开始", "body": "小满先问你认不认识鱼，而不是值多少钱。她说名字、地点和出现时间，都是河流留下的第一层记录。"},
		{"title": "原生的线索", "body": "她更在意原生鱼和保护对象。合适的记录不一定昂贵，但必须能说明这条鱼为什么属于这里。"},
		{"title": "昼夜与冷水", "body": "小满把图鉴摊开，标出夜行、冷水和溪流标签。换时段、换水域，有时比继续堆幸运更有效。"},
		{"title": "看见不等于带走", "body": "她提醒你，保护鱼最重要的是留下可靠记录。以后真正接入放流簿时，登记与带走会是两件不同的事。"},
		{"title": "观察笔记", "body": "小满愿意把新发现的水草和鱼道写给你看。往后到访时，她可能短暂提高未发现鱼与原生鱼的权重。"},
		{"title": "许可上的空格", "body": "高级标记许可只差最后一条冷水记录。她请你从河湾之外带回证据，鱼本身仍由你保留。"},
	],
	"ma": [
		{"title": "从下一站回来", "body": "马会长每次出现都像刚从另一条路回来。他不急着告诉你终点，只问今晚有没有见到和平时不同的鱼。"},
		{"title": "夜里才开的窗口", "body": "他偏爱夜行鱼，也提醒你有些稀罕并不靠品阶，而靠时间、事件和耐心共同碰上。"},
		{"title": "鳞光不只一种", "body": "马会长认得斑斓、鎏金与七彩的差别。他说稀有变体适合留下纪录，不该在玩家没看见时被任务悄悄吞掉。"},
		{"title": "地图不是门槛", "body": "他带回不少外地传闻，但从不拿联系人卡住路线。地图照常解锁，人脉只负责给旅程多一个方向。"},
		{"title": "旅人传闻", "body": "你已是他愿意分享时机的人。往后到访时，他可能短暂提高事件匹配窗口中的稀有权重。"},
		{"title": "名册最后一页", "body": "旅途联系人名册只剩最后一页空着。带回一条外地稀有记录，这条关系线便会留下永久署名。"},
	],
}
const FINALE_REWARDS := {
	"lin_aunt": {
		"id": "family_letter", "name": "家书纪念", "consumes": true,
		"description": "林阿姨把外地家宴写进家书，作为这段邻里关系的永久纪念。",
	},
	"zhou_uncle": {
		"id": "old_boat_pass", "name": "老钓友船牌", "consumes": false,
		"description": "周叔留下旧船通行牌；冬泊湖水文台接入后可用于深水观测。",
	},
	"tang": {
		"id": "trade_contact", "name": "跨城收购名片", "consumes": true,
		"description": "阿棠留下跨城收购联系人的名片，永久记入人情簿。",
	},
	"xiaoman": {
		"id": "marking_permit", "name": "高级标记许可", "consumes": false,
		"description": "小满签发高级标记许可；雪线溪谷放流簿接入后可用于高阶记录。",
	},
	"ma": {
		"id": "travel_contacts", "name": "旅途联系人名册", "consumes": false,
		"description": "马会长交出旅途联系人名册，永久记录后续旅程的人脉线索。",
	},
}
const BUFFS := {
	"lin_aunt": {"name": "热茶暖手", "wait_mult": 0.88, "value_mult": 1.0, "luck": 0, "variant_bias": 0.0,
		"dialogue": ["林阿姨：手冻僵了吧？喝口热茶再钓。", "玩家：这下浮漂看得清多了。"]},
	"zhou_uncle": {"name": "老钓友指点", "wait_mult": 1.0, "value_mult": 1.0, "luck": 2, "variant_bias": 0.0,
		"dialogue": ["周叔：今天别急着提竿，水底有几条压竿的。", "玩家：我盯着竿梢，等它真正沉下去。"]},
	"tang": {"name": "摊主熟价", "wait_mult": 1.0, "value_mult": 1.12, "luck": 0, "variant_bias": 0.0,
		"dialogue": ["阿棠：今天收鱼的人多，我帮你把价钱说高一点。", "玩家：那我挑几条体面的送过去。"]},
	"xiaoman": {"name": "观察笔记", "wait_mult": 1.0, "value_mult": 1.0, "luck": 1, "variant_bias": 0.0,
		"dialogue": ["小满：这几处水草边有新动静，你可以试试看。", "玩家：我换个落点，不惊着它们。"]},
	"ma": {"name": "旅人传闻", "wait_mult": 1.0, "value_mult": 1.0, "luck": 1, "variant_bias": 0.7,
		"dialogue": ["马会长：路上听来的消息，今天水色不太一样。", "玩家：那就多等一会儿，看看有没有稀罕货。"]},
}

const NPCS := [
	{
		"id": "lin_aunt", "name": "林阿姨", "role": "隔壁邻居", "color": Color("C98472"),
		"likes": "家常河鱼：鲫鱼、鲤鱼", "hint": "她总记得河湾哪一段水草边最有鱼口。",
		"buff": "河湾咬钩速度提升", "finale": "外地家宴：指定优质食用鱼的大单",
	},
	{
		"id": "zhou_uncle", "name": "周叔", "role": "老钓友", "color": Color("6F8EA3"),
		"likes": "大体型河鱼、重量纪录鱼", "hint": "他只对压得住竿梢的大家伙多看两眼。",
		"buff": "大体型尾部概率提升", "finale": "远方旧竿：跨图重量纪录委托",
	},
	{
		"id": "tang", "name": "阿棠", "role": "河边摊主", "color": Color("C49A50"),
		"likes": "高价值河鱼、特色鱼", "hint": "她能一眼看出哪条鱼值得留给识货的人。",
		"buff": "河湾售鱼／人情委托结算提升", "finale": "跨城收购：外地高价值鱼终极大单",
	},
	{
		"id": "xiaoman", "name": "小满", "role": "自然观察员", "color": Color("76A68A"),
		"likes": "原生鱼、保护鱼", "hint": "她把每一种鱼都当成河流留下的线索。",
		"buff": "未发现鱼与原生鱼权重提升", "finale": "冷水报告：溪谷标记放流／回捕记录",
	},
	{
		"id": "ma", "name": "马会长", "role": "旅行钓友", "color": Color("9075A6"),
		"likes": "夜行鱼、稀有变体鱼", "hint": "他总能从旅人的口中带回下一站的消息。",
		"buff": "事件匹配时的稀有权重小幅提升", "finale": "旅程联络：外地稀有渔获清单",
	},
]


static func default_state() -> Dictionary:
	var npc := {}
	for d in NPCS:
		npc[str(d["id"])] = {
			"favor": 0,
			"finale_done": false,
			"story_seen": -1,
			"next_visit_at": 0.0,
			"visit_seq": 0,
		}
	return {"npc": npc, "visits": {}, "buff": {}, "unlocks": {}}


static func get_npc(id: String) -> Dictionary:
	for d in NPCS:
		if str(d["id"]) == id:
			return d.duplicate(true)
	return {}


static func favor_name(value: int) -> String:
	return str(FAVOR_LEVELS[clampi(value, 0, FAVOR_LEVELS.size() - 1)])


static func make_visit(npc_id: String, kind: String, now: float, story_level := -1) -> Dictionary:
	if not kind in VISIT_KINDS:
		kind = "hint"
	var visit := {"npc": npc_id, "kind": kind, "created_at": maxf(0.0, now)}
	if kind == "story":
		visit["story_level"] = clampi(int(story_level), 0, STORY_LEVEL_MAX)
	return visit


static func visit_kind_label(kind: String) -> String:
	match kind:
		"story": return "近况"
		"task": return "委托"
		"buff": return "帮忙"
		"finale": return "终章"
		_: return "闲谈"


static func visit_title(npc: Dictionary, visit: Dictionary) -> String:
	var name := str(npc.get("name", "熟人"))
	match str(visit.get("kind", "hint")):
		"story": return str(level_event_for(str(npc.get("id", "")), int(visit.get("story_level", 0))).get("title", "%s来聊近况" % name))
		"task": return "%s带来一件委托" % name
		"buff": return "%s愿意帮你一把" % name
		"finale": return "%s带来终章大单" % name
		_: return "%s留了几句话" % name


static func visit_body(npc: Dictionary, visit: Dictionary) -> String:
	match str(visit.get("kind", "hint")):
		"story":
			return str(level_event_for(str(npc.get("id", "")), int(visit.get("story_level", 0))).get("body", str(npc.get("hint", ""))))
		"task":
			return "这次委托想收一条合胃口的鱼。完成后只结算金币；好感仍需在闲谈到访时送出合适的鱼来推进。终章方向：%s。" % str(npc.get("finale", ""))
		"buff":
			return "这次到访会提供限时增益方向：%s。" % str(npc.get("buff", ""))
		"finale":
			return "这是一件来自其他地点的终章大单。完成后会留下长期关系记录，并获得一笔高额结算：%s。" % str(npc.get("finale", ""))
		_:
			return "%s\n\n偏好线索：%s" % [str(npc.get("hint", "")), str(npc.get("likes", ""))]


static func buff_for(npc_id: String) -> Dictionary:
	return BUFFS.get(npc_id, {}).duplicate(true)


static func buff_name(npc_id: String) -> String:
	return str(buff_for(npc_id).get("name", "人情帮忙"))


static func buff_dialogue(npc_id: String) -> Array:
	return buff_for(npc_id).get("dialogue", [])


static func buff_wait_mult(npc_id: String) -> float:
	return float(buff_for(npc_id).get("wait_mult", 1.0))


static func buff_value_mult(npc_id: String) -> float:
	return float(buff_for(npc_id).get("value_mult", 1.0))


static func buff_luck(npc_id: String) -> int:
	return int(buff_for(npc_id).get("luck", 0))


static func buff_variant_bias(npc_id: String) -> float:
	return float(buff_for(npc_id).get("variant_bias", 0.0))


static func gift_match(npc_id: String, catch: Dictionary) -> bool:
	if bool(catch.get("lock", false)):
		return false
	var fish_id := str(catch.get("id", ""))
	if not FishData.FISH.has(fish_id):
		return false
	var data: Dictionary = FishData.FISH[fish_id]
	var tags: Array = data.get("tags", [])
	var tier := FishData.tier_of(fish_id)
	var w := float(catch.get("w", 0.0))
	var wmax := maxf(0.01, float(data.get("wmax", 0.01)))
	match npc_id:
		"lin_aunt":
			return fish_id in ["crucian", "carp", "grass", "bream", "bighead", "wuchang"]
		"zhou_uncle":
			return ("river" in tags or "lake" in tags) and w >= wmax * 0.62
		"tang":
			return ("river" in tags or "lake" in tags) and (tier >= 2 or int(catch.get("v", 0)) >= 80)
		"xiaoman":
			return "protected" in tags or ("stream" in tags and tier <= 3)
		"ma":
			return "night" in tags or int(catch.get("var", 0)) > 0
		_:
			return false


static func gift_reject_reason(npc_id: String, catch: Dictionary) -> String:
	if bool(catch.get("lock", false)):
		return "这条鱼被你锁着，暂时不适合作为礼物。"
	var npc := get_npc(npc_id)
	if npc.is_empty():
		return "这份礼物没有送出去。"
	return "不是%s偏好的鱼。偏好：%s" % [str(npc.get("name", "对方")), str(npc.get("likes", ""))]


static func task_title(npc_id: String) -> String:
	var npc := get_npc(npc_id)
	if npc.is_empty():
		return "人情委托"
	return "%s的委托：交一条合胃口的鱼" % str(npc.get("name", "熟人"))


static func task_match(npc_id: String, catch: Dictionary) -> bool:
	return gift_match(npc_id, catch)


static func task_reject_reason(npc_id: String, catch: Dictionary) -> String:
	if bool(catch.get("lock", false)):
		return "这条鱼还锁着，不能交给委托。"
	var npc := get_npc(npc_id)
	return "这条不符合委托口味。需要：%s" % str(npc.get("likes", "对方偏好的鱼"))


static func is_external_fish(catch: Dictionary) -> bool:
	var fish_id := str(catch.get("id", ""))
	if not FishData.FISH.has(fish_id):
		return false
	var tags: Array = FishData.FISH[fish_id].get("tags", [])
	return not ("river" in tags)


static func finale_match(npc_id: String, catch: Dictionary) -> bool:
	if (bool(catch.get("lock", false)) and finale_consumes_catch(npc_id)) or not is_external_fish(catch):
		return false
	var fish_id := str(catch.get("id", ""))
	if not FishData.FISH.has(fish_id):
		return false
	var data: Dictionary = FishData.FISH[fish_id]
	var tags: Array = data.get("tags", [])
	var tier := FishData.tier_of(fish_id)
	var w := float(catch.get("w", 0.0))
	var wmax := maxf(0.01, float(data.get("wmax", 0.01)))
	match npc_id:
		"lin_aunt":
			return "coast" in tags or "lake" in tags
		"zhou_uncle":
			return w >= wmax * 0.58
		"tang":
			return tier >= 3 or int(catch.get("v", 0)) >= 160
		"xiaoman":
			return "stream" in tags or "cold" in tags or "protected" in tags
		"ma":
			return "night" in tags or int(catch.get("var", 0)) > 0 or tier >= 2
		_:
			return false


static func finale_reject_reason(npc_id: String, catch: Dictionary) -> String:
	if bool(catch.get("lock", false)) and finale_consumes_catch(npc_id):
		return "这条鱼还锁着，不能交给终章大单。"
	if not is_external_fish(catch):
		return "终章大单需要来自河湾之外的渔获。"
	var npc := get_npc(npc_id)
	return "这条还不符合%s的终章方向：%s" % [str(npc.get("name", "对方")), str(npc.get("finale", ""))]


static func finale_reward_for(npc_id: String) -> Dictionary:
	return FINALE_REWARDS.get(npc_id, {}).duplicate(true)


static func finale_reward_id(npc_id: String) -> String:
	return str(finale_reward_for(npc_id).get("id", ""))


static func finale_reward_name(npc_id: String) -> String:
	return str(finale_reward_for(npc_id).get("name", "终章纪念"))


static func finale_reward_description(npc_id: String) -> String:
	return str(finale_reward_for(npc_id).get("description", ""))


static func finale_consumes_catch(npc_id: String) -> bool:
	return bool(finale_reward_for(npc_id).get("consumes", true))


static func finale_unlock_ids() -> Array:
	var out: Array = []
	for npc in NPCS:
		var reward_id := finale_reward_id(str(npc["id"]))
		if reward_id != "":
			out.append(reward_id)
	return out


static func level_event_for(npc_id: String, level: int) -> Dictionary:
	var events: Array = LEVEL_EVENTS.get(npc_id, [])
	if level < 0 or level >= events.size():
		return {}
	return (events[level] as Dictionary).duplicate(true)


static func next_story_level(state: Dictionary) -> int:
	var favor := clampi(int(state.get("favor", 0)), 0, STORY_LEVEL_MAX)
	var seen := clampi(int(state.get("story_seen", -1)), -1, STORY_LEVEL_MAX)
	return seen + 1 if seen < favor else -1


static func repeat_visit_kinds(favor: int) -> Array:
	if favor <= 0:
		return ["hint"]
	if favor < 4:
		return ["hint", "task"]
	return ["hint", "task", "buff"]
