class_name RelationshipData
## 河湾「人情簿」的静态人物真值。事件排程、送礼与委托逻辑后续独立到 relationships.gd。

const FAVOR_LEVELS := ["初识", "点头之交", "熟脸", "熟人", "靠得住", "旧交", "至交"]
const VISIT_KINDS := ["hint", "task", "buff", "finale"]
const BUFF_DURATION := 600.0
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
		npc[str(d["id"])] = {"favor": 0, "finale_done": false}
	return {"npc": npc, "visits": {}, "next_visit_at": 0.0, "visit_seq": 0, "buff": {}}


static func get_npc(id: String) -> Dictionary:
	for d in NPCS:
		if str(d["id"]) == id:
			return d.duplicate(true)
	return {}


static func favor_name(value: int) -> String:
	return str(FAVOR_LEVELS[clampi(value, 0, FAVOR_LEVELS.size() - 1)])


static func make_visit(npc_id: String, kind: String, now: float) -> Dictionary:
	if not kind in VISIT_KINDS:
		kind = "hint"
	return {"npc": npc_id, "kind": kind, "created_at": maxf(0.0, now)}


static func visit_kind_label(kind: String) -> String:
	match kind:
		"task": return "委托"
		"buff": return "帮忙"
		"finale": return "终章"
		_: return "闲谈"


static func visit_title(npc: Dictionary, visit: Dictionary) -> String:
	var name := str(npc.get("name", "熟人"))
	match str(visit.get("kind", "hint")):
		"task": return "%s带来一件委托" % name
		"buff": return "%s愿意帮你一把" % name
		"finale": return "%s带来终章大单" % name
		_: return "%s留了几句话" % name


static func visit_body(npc: Dictionary, visit: Dictionary) -> String:
	match str(visit.get("kind", "hint")):
		"task":
			return "这次委托想收一条合胃口的鱼。完成后会给金币，也会让关系更踏实；好感够高后，终章会指向：%s。" % str(npc.get("finale", ""))
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
	if bool(catch.get("lock", false)) or not is_external_fish(catch):
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
	if bool(catch.get("lock", false)):
		return "这条鱼还锁着，不能交给终章大单。"
	if not is_external_fish(catch):
		return "终章大单需要来自河湾之外的渔获。"
	var npc := get_npc(npc_id)
	return "这条还不符合%s的终章方向：%s" % [str(npc.get("name", "对方")), str(npc.get("finale", ""))]
