class_name RelationshipData
## 河湾「人情簿」的静态人物真值。事件排程、送礼与委托逻辑后续独立到 relationships.gd。

const FAVOR_LEVELS := ["初识", "点头之交", "熟脸", "熟人", "靠得住", "旧交", "至交"]
const VISIT_KINDS := ["story", "hint", "task", "buff", "finale"]
const BUFF_DURATION := 600.0
const STORY_LEVEL_MAX := 5  # 初识到旧交；至交的第七个里程碑由一次性终章承载。
const LEVEL_EVENTS := {
	"lin_aunt": [
		{"title": "河边第一壶茶", "body": "新搬来的吧？先喝口热茶。河湾不缺鱼，天晚了记得回家。"},
		{"title": "留鱼的规矩", "body": "我家饭桌不讲稀奇，家常河鱼就很好。太贵重的，我反倒不好收。"},
		{"title": "水草边的消息", "body": "清早水草轻轻晃的时候，鱼口常比正午好。你下次可以试试。"},
		{"title": "空碗不催人", "body": "我不是来催鱼的。就是路过，问问你吃过没有。"},
		{"title": "一双暖手", "body": "天凉了，我给你焐壶茶。往后手冻僵了，就来喊我。"},
		{"title": "家书留了一行", "body": "我在家书里留了一行。哪天你从外地带道好鱼回来，我就写进去。"},
	],
	"zhou_uncle": [
		{"title": "先看竿梢", "body": "别先看装备，看水面和竿梢。真正的大鱼来前，四周会先静下来。"},
		{"title": "认水比认鱼先", "body": "大鱼不等于稀有鱼。快长到自身极限的，才值得认真记一笔。"},
		{"title": "秤上的旧纪录", "body": "这是我的旧重量簿。地点、天气、重量，都比夸张故事靠得住。"},
		{"title": "旧船还拴着", "body": "冬泊湖深处还拴着我的旧船。以后真要做深水记录，也许用得上。"},
		{"title": "压住提竿的手", "body": "第一下拖拽别急着提。我在旁边，帮你盯着大鱼的动静。"},
		{"title": "远方旧竿", "body": "替我带一条外地的重量纪录回来。到那时，这块老船牌就交给你。"},
	],
	"tang": [
		{"title": "先看鱼，再谈价", "body": "我先看鳞、鳃和体型，再谈价。别只说稀有，得说清它值在哪儿。"},
		{"title": "账本上的偏好", "body": "我喜欢有价值、有地方特色的河鱼。礼物是人情，委托是买卖，我分得清。"},
		{"title": "识货的人", "body": "同一条鱼，我会分给不同买家。有人买鲜味，有人只收没见过的。"},
		{"title": "城外来电", "body": "城外偶尔有人找鱼，但你不用为我的单子赶路。照自己的节奏钓。"},
		{"title": "熟价", "body": "以后你来卖鱼，我替你多谈一句价。熟人的账，我不会亏待。"},
		{"title": "跨城收购名片", "body": "这张跨城收购名片还没署名。带条真正有分量的外地鱼回来吧。"},
	],
	"xiaoman": [
		{"title": "从名字开始", "body": "你认识这条鱼吗？名字、地点和时间，都是河流留下的记录。"},
		{"title": "原生的线索", "body": "我更关心原生鱼和保护鱼。记录不必昂贵，但要能说明它为什么属于这里。"},
		{"title": "昼夜与冷水", "body": "看看这些夜行、冷水和溪流标签。换时间、换水域，常比碰运气有效。"},
		{"title": "看见不等于带走", "body": "保护鱼最重要的是留下可靠记录。登记它，不一定要带走它。"},
		{"title": "观察笔记", "body": "我记了几处新鱼道。下次我带笔记来，你可以换个落点试试。"},
		{"title": "许可上的空格", "body": "高级标记许可只差一条冷水记录。带证据回来，鱼仍然由你保留。"},
	],
	"ma": [
		{"title": "从下一站回来", "body": "我刚从下一站回来。今晚，你见过和平时不一样的鱼吗？"},
		{"title": "夜里才开的窗口", "body": "我偏爱夜行鱼。有些稀罕不看品阶，只看时间、事件和耐心。"},
		{"title": "鳞光不只一种", "body": "斑斓、鎏金、七彩，我都认得。稀有变体该先留好记录。"},
		{"title": "地图不是门槛", "body": "我带消息，不替你定路线。地图照常走，人脉只是多指一个方向。"},
		{"title": "旅人传闻", "body": "现在有些消息，我愿意先告诉你。碰上特别的水色，就多等一会儿。"},
		{"title": "名册最后一页", "body": "名册只剩最后一页。带条外地稀有记录回来，我把你的名字写上去。"},
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
		"dialogue": ["手冻僵了吧？喝口热茶，我替你看一会儿鱼情。"]},
	"zhou_uncle": {"name": "老钓友指点", "wait_mult": 1.0, "value_mult": 1.0, "luck": 2, "variant_bias": 0.0,
		"dialogue": ["今天别急着提竿。水底有几条压竿的，我替你盯着。"]},
	"tang": {"name": "摊主熟价", "wait_mult": 1.0, "value_mult": 1.12, "luck": 0, "variant_bias": 0.0,
		"dialogue": ["今天收鱼的人多。我帮你把价钱往上谈一谈。"]},
	"xiaoman": {"name": "观察笔记", "wait_mult": 1.0, "value_mult": 1.0, "luck": 1, "variant_bias": 0.0,
		"dialogue": ["这几处水草边有新动静。我把落点记给你。"]},
	"ma": {"name": "旅人传闻", "wait_mult": 1.0, "value_mult": 1.0, "luck": 1, "variant_bias": 0.7,
		"dialogue": ["路上听来个消息：今天水色不一样。我陪你多等一会儿。"]},
}

const NPCS := [
	{
		"id": "lin_aunt", "name": "林阿姨", "role": "隔壁邻居", "color": Color("C98472"),
		"portrait": "res://assets/art/character/npc/lin_aunt.png",
		"head_crop": Rect2(310, 190, 520, 520),
		"likes": "家常河鱼：鲫鱼、鲤鱼", "likes_hint": "似乎偏爱能端上家常饭桌的河鱼",
		"hint": "我记得河湾哪一段水草边最有鱼口。",
		"buff": "河湾咬钩速度提升", "finale": "外地家宴：指定优质食用鱼的大单",
	},
	{
		"id": "zhou_uncle", "name": "周叔", "role": "老钓友", "color": Color("6F8EA3"),
		"portrait": "res://assets/art/character/npc/zhou_uncle.png",
		"head_crop": Rect2(700, 20, 400, 400),
		"likes": "大体型河鱼、重量纪录鱼", "likes_hint": "谈到压得住竿梢的大家伙时格外来劲",
		"hint": "我只对压得住竿梢的大家伙多看两眼。",
		"buff": "大体型尾部概率提升", "finale": "远方旧竿：跨图重量纪录委托",
	},
	{
		"id": "tang", "name": "阿棠", "role": "河边摊主", "color": Color("C49A50"),
		"portrait": "res://assets/art/character/npc/tang.png",
		"head_crop": Rect2(390, 120, 430, 430),
		"likes": "高价值河鱼、特色鱼", "likes_hint": "眼光总落在值钱或少见的河鱼上",
		"hint": "我一眼就能看出，哪条鱼该留给识货的人。",
		"buff": "河湾售鱼／人情委托结算提升", "finale": "跨城收购：外地高价值鱼终极大单",
	},
	{
		"id": "xiaoman", "name": "小满", "role": "自然观察员", "color": Color("76A68A"),
		"portrait": "res://assets/art/character/npc/xiaoman.png",
		"head_crop": Rect2(150, 450, 480, 480),
		"likes": "原生鱼、保护鱼", "likes_hint": "更关心能说明河流生态状况的鱼",
		"hint": "我把每一种鱼，都当成河流留下的线索。",
		"buff": "未发现鱼与原生鱼权重提升", "finale": "冷水报告：溪谷标记放流／回捕记录",
	},
	{
		"id": "ma", "name": "马会长", "role": "旅行钓友", "color": Color("9075A6"),
		"portrait": "res://assets/art/character/npc/ma.png",
		"head_crop": Rect2(690, 10, 420, 420),
		"likes": "夜行鱼、稀有变体鱼", "likes_hint": "喜欢带着夜色或旅途奇闻的渔获",
		"hint": "我刚从旅人口中听到下一站的消息。",
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


static func preference_stage(favor: int) -> int:
	if favor < 2:
		return 0
	return 1 if favor < 4 else 2


static func preference_text(npc: Dictionary, favor: int) -> String:
	match preference_stage(favor):
		0: return "???"
		1: return str(npc.get("likes_hint", "似乎有自己的偏好"))
		_: return str(npc.get("likes", "尚未摸清"))


static func gift_feedback(npc_id: String, catch: Dictionary, accepted: bool) -> String:
	var npc := get_npc(npc_id)
	var fish_name := FishData.display_name(str(catch.get("id", "")))
	if accepted:
		return "这条%s我很喜欢，谢谢你。" % fish_name
	if bool(catch.get("lock", false)):
		return "这条鱼还被你仔细留着，先别拿来送人。"
	return "这条还是留给更合适的人吧。"


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
			return "我正缺一条合适的鱼。你要是愿意帮忙，就从鱼篓里挑一条让我看看。"
		"buff":
			return "今天我正好有空，可以替你照看一阵鱼情。"
		"finale":
			return "有件要紧事，我想当面托付给你。你带回来的渔获，能让我看看吗？"
		_:
			return str(npc.get("hint", "河边风大，先坐下来聊几句吧。"))


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
