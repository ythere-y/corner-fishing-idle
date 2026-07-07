class_name AchievementData
## 成就配置（纯数据）。kind 决定达成判定，n 为阈值，reward 为达成奖励金币（0 = 纯称号）。
## 判定逻辑在 main.gd::_ach_done()。数量见 LIST（勿在注释写死），覆盖渔获/财富/收集/品阶/
## 品相/装备/陈列/变体/陪伴/周赛多条线；P1 起含 20h→100h 长线断点阶梯。

const LIST := [
	{"id": "first_cast", "name": "初次垂钓", "desc": "钓到第一条鱼", "kind": "catches", "n": 1, "reward": 0},
	{"id": "catch_50", "name": "小有渔获", "desc": "累计钓到 50 条鱼", "kind": "catches", "n": 50, "reward": 200},
	{"id": "catch_300", "name": "老钓客", "desc": "累计钓到 300 条鱼", "kind": "catches", "n": 300, "reward": 800},
	{"id": "catch_1000", "name": "钓鱼大师", "desc": "累计钓到 1000 条鱼", "kind": "catches", "n": 1000, "reward": 3000},
	{"id": "coin_1k", "name": "第一桶金", "desc": "累计卖鱼赚 1,000 金币", "kind": "coins", "n": 1000, "reward": 100},
	{"id": "coin_50k", "name": "富甲一方", "desc": "累计卖鱼赚 50,000 金币", "kind": "coins", "n": 50000, "reward": 2000},
	{"id": "species_10", "name": "鱼类学徒", "desc": "图鉴收集 10 种鱼", "kind": "species", "n": 10, "reward": 500},
	{"id": "species_all", "name": "图鉴大全", "desc": "集齐所有鱼种", "kind": "species_all", "n": 0, "reward": 5000},
	{"id": "tier_rare", "name": "名贵之鱼", "desc": "钓到稀有及以上品阶", "kind": "tier", "n": 2, "reward": 150},
	{"id": "tier_legend", "name": "传说降临", "desc": "钓到传说及以上品阶", "kind": "tier", "n": 4, "reward": 1000},
	{"id": "tier_myth", "name": "国宝入篓", "desc": "钓到神话品阶", "kind": "tier", "n": 5, "reward": 5000},
	{"id": "giant", "name": "巨物猎手", "desc": "钓到一条「巨物」", "kind": "giant", "n": 0, "reward": 600},
	{"id": "perfect", "name": "完美品相", "desc": "钓到完美★★★渔获", "kind": "quality", "n": 3, "reward": 800},
	{"id": "bag_40", "name": "大鱼篓", "desc": "鱼篓扩到 40 格", "kind": "bag", "n": 5, "reward": 0},
	{"id": "rod_5", "name": "精良渔具", "desc": "鱼竿升到 Lv.5", "kind": "rod", "n": 5, "reward": 0},
	{"id": "bait_master", "name": "秘饵传人", "desc": "用上秘制饵", "kind": "bait", "n": 3, "reward": 0},
	{"id": "hook_master", "name": "一线双钩", "desc": "用上双叉钩", "kind": "hook", "n": 3, "reward": 0},
	{"id": "lure_master", "name": "窝料宗师", "desc": "用上麝香窝料", "kind": "lure", "n": 3, "reward": 0},
	# —— 长期里程碑（围绕深度进程）——
	{"id": "catch_5000", "name": "钓鱼宗师", "desc": "累计钓到 5,000 条鱼", "kind": "catches", "n": 5000, "reward": 10000},
	{"id": "coin_500k", "name": "腰缠万贯", "desc": "累计卖鱼赚 500,000 金币", "kind": "coins", "n": 500000, "reward": 20000},
	{"id": "rod_10", "name": "如臂使指", "desc": "鱼竿升到 Lv.10", "kind": "rod", "n": 10, "reward": 0},
	{"id": "bag_max", "name": "巨型鱼篓", "desc": "鱼篓扩到 55 格", "kind": "bag", "n": 8, "reward": 0},
	{"id": "bag_100", "name": "百格渔仓", "desc": "鱼篓扩到 100 格（毕业期工程）", "kind": "bag", "n": 14, "reward": 0},
	{"id": "whopper", "name": "大鱼出水", "desc": "钓到一条 ≥10kg 的鱼", "kind": "maxweight", "n": 10, "reward": 2000},
	{"id": "leviathan", "name": "深渊巨怪", "desc": "钓到一条 ≥100kg 的鱼", "kind": "maxweight", "n": 100, "reward": 8000},
	# —— 水族箱/陈列（健康非数值长线）——
	{"id": "first_display", "name": "初入鱼缸", "desc": "把一条鱼放进水族箱", "kind": "display", "n": 1, "reward": 200},
	{"id": "display_full", "name": "满缸珍藏", "desc": "水族箱养满 8 条", "kind": "display", "n": 8, "reward": 1500},
	# —— 稀有变体（Chillquarium 式收集深度）——
	{"id": "first_variant", "name": "斑斓初见", "desc": "钓到一条稀有变体（斑斓及以上）", "kind": "variant", "n": 1, "reward": 500},
	{"id": "rainbow", "name": "七彩之鳞", "desc": "钓到一条七彩变体", "kind": "variant", "n": 3, "reward": 5000},
	# —— 陪伴向（专注奖励 / 桌面宠物）——
	{"id": "flow_state", "name": "心流时刻", "desc": "累计专注满 120 分钟（开着它去忙别的）", "kind": "focus_minutes", "n": 120, "reward": 1500},
	{"id": "cat_tax", "name": "猫税", "desc": "被小馋猫叼走过一条鱼", "kind": "pet_steals", "n": 1, "reward": 100},
	# —— P1 长线成就（填平 20h→100h 成就真空，balance_audit §3.6）：图鉴断点阶梯 + 变体格 + 周赛沉淀 ——
	{"id": "species_55", "name": "启程的手记", "desc": "图鉴收集 55 种鱼", "kind": "species", "n": 55, "reward": 1000},
	{"id": "species_120", "name": "半本图鉴", "desc": "图鉴收集 120 种鱼", "kind": "species", "n": 120, "reward": 3000},
	{"id": "species_165", "name": "行家眼力", "desc": "图鉴收集 165 种鱼", "kind": "species", "n": 165, "reward": 6000},
	{"id": "species_197", "name": "最后一页之前", "desc": "图鉴收集 197 种鱼", "kind": "species", "n": 197, "reward": 10000},
	{"id": "catch_20k", "name": "千帆过尽", "desc": "累计钓到 20,000 条鱼", "kind": "catches", "n": 20000, "reward": 0},
	{"id": "catch_50k", "name": "与水共生", "desc": "累计钓到 50,000 条鱼", "kind": "catches", "n": 50000, "reward": 0},
	{"id": "vgrid_100", "name": "斑斓集邮册", "desc": "点亮 100 格变体收集", "kind": "vgrid", "n": 100, "reward": 3000},
	{"id": "vgrid_300", "name": "鳞光宝库", "desc": "点亮 300 格变体收集", "kind": "vgrid", "n": 300, "reward": 10000},
	{"id": "vgrid_all", "name": "657 之约", "desc": "点亮全部 657 格变体收集", "kind": "vgrid", "n": 657, "reward": 30000},
	{"id": "comp_wins_5", "name": "赛场常客", "desc": "巨物赛累计夺金 5 次", "kind": "comp_wins", "n": 5, "reward": 2000},
	{"id": "comp_wins_25", "name": "巨物赛传奇", "desc": "巨物赛累计夺金 25 次", "kind": "comp_wins", "n": 25, "reward": 10000},
]
