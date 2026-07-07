class_name FishData
## 鱼种图鉴与抽取配置（纯数据）。
## 谱系依据：中国北方冬季冰钓真实鱼种（黑龙江"三花五罗"名贵层 + 冷水鲑科高端层），
## 品阶概率/价格倍率/体重定价参考 Stardew/Fisch/WEBFISHING/动森 调研（docs/fish-research.md）。
## 6 档品阶（见色识阶：灰绿蓝紫橙红）；卖价与体重线性挂钩，大个体更值钱。

const TIER_NAMES := ["普通", "优良", "稀有", "史诗", "传说", "神话"]
const TIER_COLORS := [
	Color(0.78, 0.78, 0.80),  # 0 普通 灰
	Color(0.35, 0.78, 0.30),  # 1 优良 绿
	Color(0.30, 0.62, 0.95),  # 2 稀有 蓝
	Color(0.72, 0.42, 0.95),  # 3 史诗 紫
	Color(1.00, 0.55, 0.12),  # 4 传说 橙
	Color(1.00, 0.38, 0.32),  # 5 神话 红
]

## wmin/wmax = 体重区间(kg)，vmin/vmax = 对应体重端点的卖价(金币)，按体重线性插值。
## 相邻品阶价值倍率 ≈ ×3.5~4.5（调研结论），全谱跨度 ≈ ×5000。
## tags = 生态标签，决定鱼出现在哪些钓点（SpotData.habitat_tags 与之求交集）：
##   river 河流 / lake 静水湖泊 / stream 山涧溪流 / coast 海岸 / deep 深水 /
##   cold 冷水 / night 夜行 / protected 保护鱼（养殖放流设定）。
## 旧 id 与数值保持不变（旧存档兼容）。
## 219 种鱼（v3 扩充：+山涧溪流/远海深渊各专属，+珊瑚礁/河口红树林/极地冰湖/古潭溶洞/城市野塘 5 生态；
## 谱系与设计见 docs/fish-expansion-plan.md）。各生态用独立 tag（reef/brackish/polar/cavern/urban）保证鱼池互不串。
## 钓点见 spot_data.gd（10 个）；缺图标的新鱼运行时回退品阶通用图标。
const FISH := {
	# —— 0 普通（常见杂鱼，基本盘）——
	"whitebait": {"name": "白条", "tier": 0, "wmin": 0.01, "wmax": 0.02, "vmin": 1, "vmax": 3, "tags": ["river", "lake"]},
	"topmouth": {"name": "麦穗鱼", "tier": 0, "wmin": 0.01, "wmax": 0.03, "vmin": 1, "vmax": 3, "tags": ["river", "lake"]},
	"loach": {"name": "泥鳅", "tier": 0, "wmin": 0.03, "wmax": 0.15, "vmin": 2, "vmax": 5, "tags": ["river", "lake", "night"]},
	"crucian": {"name": "鲫鱼", "tier": 0, "wmin": 0.1, "wmax": 0.6, "vmin": 3, "vmax": 9, "tags": ["river", "lake"]},
	"bighead": {"name": "鲢鳙", "tier": 0, "wmin": 1.5, "wmax": 3.0, "vmin": 6, "vmax": 14, "tags": ["river", "lake"]},
	"yellowhead": {"name": "黄颡鱼", "tier": 0, "wmin": 0.1, "wmax": 0.3, "vmin": 8, "vmax": 18, "tags": ["river", "lake", "night"]},
	# 新增 · 湖
	"bluegill": {"name": "蓝鳃太阳鱼", "tier": 0, "wmin": 0.05, "wmax": 0.4, "vmin": 2, "vmax": 6, "tags": ["lake"]},
	"icefish": {"name": "银鱼", "tier": 0, "wmin": 0.005, "wmax": 0.02, "vmin": 3, "vmax": 8, "tags": ["lake", "cold"]},
	"bitterling": {"name": "鳑鲏", "tier": 0, "wmin": 0.005, "wmax": 0.02, "vmin": 1, "vmax": 3, "tags": ["lake"]},
	# 新增 · 海
	"sardine": {"name": "沙丁鱼", "tier": 0, "wmin": 0.02, "wmax": 0.1, "vmin": 2, "vmax": 5, "tags": ["coast"]},
	"filefish": {"name": "马面鲀", "tier": 0, "wmin": 0.1, "wmax": 0.5, "vmin": 4, "vmax": 10, "tags": ["coast"]},
	"goby": {"name": "虾虎鱼", "tier": 0, "wmin": 0.01, "wmax": 0.08, "vmin": 1, "vmax": 4, "tags": ["coast"]},
	# 扩充 v2 · 溪河/湖/海杂鱼
	"minnow": {"name": "马口鱼", "tier": 0, "wmin": 0.03, "wmax": 0.15, "vmin": 3, "vmax": 8, "tags": ["river", "stream"]},
	"zacco": {"name": "宽鳍鱲", "tier": 0, "wmin": 0.02, "wmax": 0.1, "vmin": 2, "vmax": 6, "tags": ["river", "stream"]},
	"gudgeon": {"name": "棒花鱼", "tier": 0, "wmin": 0.01, "wmax": 0.08, "vmin": 1, "vmax": 4, "tags": ["river", "lake"]},
	"spined_loach": {"name": "中华花鳅", "tier": 0, "wmin": 0.02, "wmax": 0.1, "vmin": 2, "vmax": 5, "tags": ["river", "lake", "night"]},
	"ricefish": {"name": "青鳉", "tier": 0, "wmin": 0.002, "wmax": 0.01, "vmin": 2, "vmax": 6, "tags": ["lake"]},
	"paradisefish": {"name": "斗鱼", "tier": 0, "wmin": 0.01, "wmax": 0.05, "vmin": 3, "vmax": 8, "tags": ["lake"]},
	"anchovy": {"name": "鳀鱼", "tier": 0, "wmin": 0.005, "wmax": 0.02, "vmin": 2, "vmax": 5, "tags": ["coast"]},
	"halfbeak": {"name": "鱵鱼", "tier": 0, "wmin": 0.02, "wmax": 0.12, "vmin": 3, "vmax": 8, "tags": ["coast"]},
	"sandlance": {"name": "玉筋鱼", "tier": 0, "wmin": 0.005, "wmax": 0.03, "vmin": 2, "vmax": 6, "tags": ["coast"]},
	# —— 1 优良（常见经济鱼）——
	"dace": {"name": "雅罗鱼", "tier": 1, "wmin": 0.3, "wmax": 1.0, "vmin": 14, "vmax": 26, "tags": ["river", "cold"]},
	"carp": {"name": "鲤鱼", "tier": 1, "wmin": 1.0, "wmax": 8.0, "vmin": 16, "vmax": 40, "tags": ["river", "lake"]},
	"grass": {"name": "草鱼", "tier": 1, "wmin": 2.0, "wmax": 12.0, "vmin": 16, "vmax": 42, "tags": ["river", "lake"]},
	"bream": {"name": "鳊鱼", "tier": 1, "wmin": 0.5, "wmax": 2.0, "vmin": 18, "vmax": 36, "tags": ["river", "lake"]},
	"blackcarp": {"name": "青鱼", "tier": 1, "wmin": 4.0, "wmax": 15.0, "vmin": 24, "vmax": 55, "tags": ["river", "lake"]},
	# 新增 · 湖
	"perch": {"name": "河鲈", "tier": 1, "wmin": 0.2, "wmax": 1.2, "vmin": 18, "vmax": 38, "tags": ["lake"]},
	"catfish": {"name": "鲇鱼", "tier": 1, "wmin": 0.5, "wmax": 4.0, "vmin": 16, "vmax": 44, "tags": ["lake", "night"]},
	"swampeel": {"name": "黄鳝", "tier": 1, "wmin": 0.1, "wmax": 0.7, "vmin": 20, "vmax": 45, "tags": ["lake", "night"]},
	"tilapia": {"name": "罗非鱼", "tier": 1, "wmin": 0.2, "wmax": 1.5, "vmin": 14, "vmax": 30, "tags": ["lake"]},
	# 新增 · 海
	"mackerel": {"name": "鲐鱼", "tier": 1, "wmin": 0.2, "wmax": 1.0, "vmin": 14, "vmax": 30, "tags": ["coast"]},
	"small_croaker": {"name": "小黄鱼", "tier": 1, "wmin": 0.1, "wmax": 0.4, "vmin": 20, "vmax": 44, "tags": ["coast"]},
	"mullet": {"name": "鲻鱼", "tier": 1, "wmin": 0.3, "wmax": 2.0, "vmin": 16, "vmax": 36, "tags": ["coast"]},
	"rockfish": {"name": "许氏平鲉", "tier": 1, "wmin": 0.2, "wmax": 1.5, "vmin": 22, "vmax": 48, "tags": ["coast"]},
	# 扩充 v2 · 河湖经济鱼 + 海岸食用鱼
	"redeye": {"name": "赤眼鳟", "tier": 1, "wmin": 0.3, "wmax": 2.0, "vmin": 16, "vmax": 36, "tags": ["river", "lake"]},
	"wuchang": {"name": "武昌鱼", "tier": 1, "wmin": 0.5, "wmax": 2.5, "vmin": 18, "vmax": 40, "tags": ["river", "lake"]},
	"spotted_steed": {"name": "唇䱻", "tier": 1, "wmin": 0.3, "wmax": 1.5, "vmin": 18, "vmax": 38, "tags": ["river", "stream"]},
	"bigscale_loach": {"name": "大鳞副泥鳅", "tier": 1, "wmin": 0.05, "wmax": 0.3, "vmin": 16, "vmax": 34, "tags": ["lake", "night"]},
	"yellowtail_fish": {"name": "黄尾鲴", "tier": 1, "wmin": 0.2, "wmax": 1.0, "vmin": 16, "vmax": 32, "tags": ["river", "lake"]},
	"yellow_drum": {"name": "黄姑鱼", "tier": 1, "wmin": 0.3, "wmax": 2.0, "vmin": 20, "vmax": 44, "tags": ["coast"]},
	"greenling": {"name": "六线鱼", "tier": 1, "wmin": 0.2, "wmax": 1.5, "vmin": 22, "vmax": 46, "tags": ["coast"]},
	"haarder": {"name": "梭鱼", "tier": 1, "wmin": 0.3, "wmax": 2.5, "vmin": 18, "vmax": 40, "tags": ["coast"]},
	"flathead_fish": {"name": "鲬", "tier": 1, "wmin": 0.3, "wmax": 1.5, "vmin": 20, "vmax": 42, "tags": ["coast"]},
	# —— 2 稀有（地方名贵，"三花五罗"层 + 湖海中坚）——
	"bass": {"name": "鲈鱼", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 55, "vmax": 120, "tags": ["river", "lake"]},
	"fangbream": {"name": "三角鲂", "tier": 2, "wmin": 0.5, "wmax": 5.0, "vmin": 60, "vmax": 130, "tags": ["river", "lake"]},
	"barbel": {"name": "花䱻", "tier": 2, "wmin": 0.3, "wmax": 1.5, "vmin": 70, "vmax": 140, "tags": ["river", "stream"]},
	"culter": {"name": "翘嘴鲌", "tier": 2, "wmin": 1.0, "wmax": 5.0, "vmin": 80, "vmax": 170, "tags": ["river", "lake"]},
	"mandarin": {"name": "鳜鱼", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 90, "vmax": 190, "tags": ["river", "lake", "night"]},
	# 新增 · 湖
	"largemouth": {"name": "大口黑鲈", "tier": 2, "wmin": 0.5, "wmax": 4.0, "vmin": 70, "vmax": 160, "tags": ["lake"]},
	# 新增 · 海
	"seabass": {"name": "海鲈", "tier": 2, "wmin": 0.5, "wmax": 5.0, "vmin": 70, "vmax": 160, "tags": ["coast"]},
	"blackbream": {"name": "黑鲷", "tier": 2, "wmin": 0.3, "wmax": 2.5, "vmin": 65, "vmax": 150, "tags": ["coast"]},
	"hairtail": {"name": "带鱼", "tier": 2, "wmin": 0.2, "wmax": 1.5, "vmin": 60, "vmax": 140, "tags": ["coast", "deep", "night"]},
	"flounder": {"name": "牙鲆", "tier": 2, "wmin": 0.5, "wmax": 4.0, "vmin": 80, "vmax": 180, "tags": ["coast"]},
	"conger": {"name": "海鳗", "tier": 2, "wmin": 0.5, "wmax": 5.0, "vmin": 60, "vmax": 140, "tags": ["coast", "night"]},
	"pufferfish": {"name": "红鳍东方鲀", "tier": 2, "wmin": 0.3, "wmax": 2.0, "vmin": 90, "vmax": 190, "tags": ["coast"]},
	# 扩充 v2 · 河湖名贵 + 海岸名鱼/头足类
	"spinibarbus": {"name": "光倒刺鲃", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 60, "vmax": 130, "tags": ["river", "stream"]},
	"mongolian_redfin": {"name": "蒙古鲌", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 60, "vmax": 130, "tags": ["river", "lake"]},
	"small_snakehead": {"name": "月鳢", "tier": 2, "wmin": 0.3, "wmax": 1.5, "vmin": 60, "vmax": 130, "tags": ["lake", "night"]},
	"yellowfin_seabream": {"name": "黄鳍鲷", "tier": 2, "wmin": 0.3, "wmax": 2.0, "vmin": 65, "vmax": 150, "tags": ["coast"]},
	"crimson_snapper": {"name": "红笛鲷", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 70, "vmax": 160, "tags": ["coast"]},
	"spotted_scat": {"name": "金钱鱼", "tier": 2, "wmin": 0.2, "wmax": 1.0, "vmin": 60, "vmax": 130, "tags": ["coast"]},
	"octopus": {"name": "章鱼", "tier": 2, "wmin": 0.5, "wmax": 4.0, "vmin": 70, "vmax": 160, "tags": ["coast", "night"]},
	"squid": {"name": "鱿鱼", "tier": 2, "wmin": 0.2, "wmax": 2.0, "vmin": 60, "vmax": 140, "tags": ["coast", "night"]},
	"cuttlefish": {"name": "墨鱼", "tier": 2, "wmin": 0.3, "wmax": 2.5, "vmin": 65, "vmax": 150, "tags": ["coast"]},
	# —— 3 史诗（冷水掠食/高端食用鱼）——
	"snakehead": {"name": "黑鱼", "tier": 3, "wmin": 1.0, "wmax": 6.0, "vmin": 200, "vmax": 420, "tags": ["river", "lake", "night"]},
	"trout": {"name": "虹鳟", "tier": 3, "wmin": 0.8, "wmax": 4.0, "vmin": 210, "vmax": 430, "tags": ["river", "stream", "cold"]},
	"pike": {"name": "白斑狗鱼", "tier": 3, "wmin": 1.0, "wmax": 8.0, "vmin": 220, "vmax": 450, "tags": ["river", "lake", "cold"]},
	"zander": {"name": "梭鲈", "tier": 3, "wmin": 1.0, "wmax": 14.0, "vmin": 240, "vmax": 500, "tags": ["river", "lake"]},
	"longsnout": {"name": "江团", "tier": 3, "wmin": 1.0, "wmax": 5.0, "vmin": 260, "vmax": 520, "tags": ["river", "night"]},
	"lenok": {"name": "细鳞鱼", "tier": 3, "wmin": 0.5, "wmax": 3.0, "vmin": 280, "vmax": 560, "tags": ["river", "stream", "cold"]},
	# 新增 · 湖
	"yellowcheek": {"name": "鳡鱼", "tier": 3, "wmin": 2.0, "wmax": 30.0, "vmin": 240, "vmax": 560, "tags": ["lake"]},
	"eel": {"name": "鳗鲡", "tier": 3, "wmin": 0.3, "wmax": 3.0, "vmin": 220, "vmax": 460, "tags": ["lake", "night"]},
	# 新增 · 海
	"seabream": {"name": "真鲷", "tier": 3, "wmin": 0.5, "wmax": 4.0, "vmin": 240, "vmax": 500, "tags": ["coast"]},
	"spanish_mackerel": {"name": "马鲛鱼", "tier": 3, "wmin": 1.0, "wmax": 8.0, "vmin": 220, "vmax": 470, "tags": ["coast"]},
	"pomfret": {"name": "银鲳", "tier": 3, "wmin": 0.2, "wmax": 1.5, "vmin": 230, "vmax": 480, "tags": ["coast"]},
	"grouper": {"name": "石斑鱼", "tier": 3, "wmin": 0.8, "wmax": 8.0, "vmin": 260, "vmax": 560, "tags": ["coast", "deep"]},
	"yellowcroaker": {"name": "大黄鱼", "tier": 3, "wmin": 0.3, "wmax": 3.0, "vmin": 300, "vmax": 580, "tags": ["coast"]},
	# 扩充 v2 · 冷水高端 + 海岸/深水掠食
	"chinese_sucker": {"name": "胭脂鱼", "tier": 3, "wmin": 1.0, "wmax": 6.0, "vmin": 260, "vmax": 540, "tags": ["river"]},
	"burbot": {"name": "江鳕", "tier": 3, "wmin": 1.0, "wmax": 8.0, "vmin": 240, "vmax": 500, "tags": ["river", "lake", "cold", "night"]},
	"manchurian_trout": {"name": "花羔红点鲑", "tier": 3, "wmin": 0.5, "wmax": 3.0, "vmin": 260, "vmax": 540, "tags": ["river", "stream", "cold"]},
	"amur_catfish": {"name": "怀头鲇", "tier": 3, "wmin": 2.0, "wmax": 20.0, "vmin": 240, "vmax": 520, "tags": ["lake", "deep", "night"]},
	"amberjack": {"name": "高体鰤", "tier": 3, "wmin": 2.0, "wmax": 15.0, "vmin": 260, "vmax": 560, "tags": ["coast", "deep"]},
	"cobia": {"name": "军曹鱼", "tier": 3, "wmin": 3.0, "wmax": 20.0, "vmin": 260, "vmax": 560, "tags": ["coast", "deep"]},
	"barramundi": {"name": "尖吻鲈", "tier": 3, "wmin": 1.0, "wmax": 8.0, "vmin": 240, "vmax": 500, "tags": ["coast"]},
	"miiuy_croaker": {"name": "鮸鱼", "tier": 3, "wmin": 1.0, "wmax": 8.0, "vmin": 240, "vmax": 500, "tags": ["coast"]},
	# —— 4 传说（洄游名贵 / 湖海巨物 / 运动钓目标鱼）——
	"koi": {"name": "锦鲤", "tier": 4, "wmin": 1.0, "wmax": 8.0, "vmin": 750, "vmax": 1600, "tags": ["river", "lake"]},
	"salmon": {"name": "大马哈鱼", "tier": 4, "wmin": 3.0, "wmax": 14.0, "vmin": 800, "vmax": 1700, "tags": ["river", "coast", "cold"]},
	"sturgeon": {"name": "施氏鲟", "tier": 4, "wmin": 5.0, "wmax": 30.0, "vmin": 900, "vmax": 1900, "tags": ["river", "lake", "deep"]},
	"taimen": {"name": "哲罗鲑", "tier": 4, "wmin": 3.0, "wmax": 50.0, "vmin": 1000, "vmax": 2200, "tags": ["river", "stream", "cold"]},
	# 新增 · 湖
	"wels_catfish": {"name": "六须鲇", "tier": 4, "wmin": 5.0, "wmax": 100.0, "vmin": 850, "vmax": 2000, "tags": ["lake", "deep", "night"], "limited": {"phases": ["night"], "label": "夜行·深潭巨鲇", "hint": "入夜后才离开深潭出来觅食"}},
	# 新增 · 海
	"tuna": {"name": "金枪鱼", "tier": 4, "wmin": 5.0, "wmax": 200.0, "vmin": 900, "vmax": 2000, "tags": ["coast", "deep"]},
	"giant_grouper": {"name": "龙趸石斑", "tier": 4, "wmin": 10.0, "wmax": 300.0, "vmin": 1000, "vmax": 2200, "tags": ["coast", "deep"]},
	# 扩充 v2 · 洄游名贵 + 大洋运动钓巨物
	"mahseer": {"name": "结鱼", "tier": 4, "wmin": 3.0, "wmax": 30.0, "vmin": 800, "vmax": 1800, "tags": ["river", "stream", "cold"]},
	"marbled_eel": {"name": "花鳗鲡", "tier": 4, "wmin": 2.0, "wmax": 20.0, "vmin": 800, "vmax": 1800, "tags": ["river", "lake", "night"]},
	"marlin": {"name": "马林鱼", "tier": 4, "wmin": 30.0, "wmax": 300.0, "vmin": 1000, "vmax": 2200, "tags": ["coast", "deep"]},
	"giant_trevally": {"name": "浪人鲹", "tier": 4, "wmin": 5.0, "wmax": 50.0, "vmin": 900, "vmax": 2000, "tags": ["coast", "deep"]},
	"mahimahi": {"name": "鲯鳅", "tier": 4, "wmin": 3.0, "wmax": 30.0, "vmin": 800, "vmax": 1800, "tags": ["coast", "deep"]},
	"swordfish": {"name": "剑鱼", "tier": 4, "wmin": 30.0, "wmax": 200.0, "vmin": 950, "vmax": 2100, "tags": ["coast", "deep"]},
	"wahoo": {"name": "刺鲅", "tier": 4, "wmin": 2.0, "wmax": 40.0, "vmin": 800, "vmax": 1800, "tags": ["coast", "deep"]},
	# —— 5 神话（"活化石"国宝层 + 海洋顶级运动钓；游戏设定为养殖放流/限时个体）——
	"chinese_sturgeon": {"name": "中华鲟", "tier": 5, "wmin": 20.0, "wmax": 300.0, "vmin": 4500, "vmax": 9500, "tags": ["river", "coast", "protected"]},
	"kaluga": {"name": "达氏鳇", "tier": 5, "wmin": 50.0, "wmax": 1000.0, "vmin": 5000, "vmax": 11000, "tags": ["river", "deep", "protected"]},
	# 新增 · 海
	"sailfish": {"name": "旗鱼", "tier": 5, "wmin": 20.0, "wmax": 90.0, "vmin": 5000, "vmax": 10000, "tags": ["coast", "deep"]},
	# 扩充 v2 · 活化石 / 深海传奇
	"paddlefish": {"name": "白鲟", "tier": 5, "wmin": 50.0, "wmax": 300.0, "vmin": 5000, "vmax": 11000, "tags": ["river", "protected"]},
	"coelacanth": {"name": "矛尾鱼", "tier": 5, "wmin": 30.0, "wmax": 90.0, "vmin": 6000, "vmax": 12000, "tags": ["coast", "deep"]},
	"oarfish": {"name": "皇带鱼", "tier": 5, "wmin": 50.0, "wmax": 200.0, "vmin": 5500, "vmax": 11000, "tags": ["coast", "deep", "night"], "limited": {"phases": ["night"], "label": "夜行·深海传说", "hint": "深夜的洋面，才会浮起这条龙宫使者"}},
	"whale_shark": {"name": "鲸鲨", "tier": 5, "wmin": 200.0, "wmax": 1000.0, "vmin": 6000, "vmax": 13000, "tags": ["coast", "deep", "protected"]},
	# —— 扩充 v3 · 山涧溪流专属（stream/cold：冷水清流，小而精，补低阶基本盘 + 国宝压轴）——
	"amur_minnow": {"name": "柳根鱼", "tier": 0, "wmin": 0.02, "wmax": 0.12, "vmin": 2, "vmax": 6, "tags": ["stream", "cold"]},
	"hillstream_loach": {"name": "平鳍鳅", "tier": 0, "wmin": 0.01, "wmax": 0.05, "vmin": 2, "vmax": 6, "tags": ["stream"]},
	"plateau_loach": {"name": "高原鳅", "tier": 0, "wmin": 0.02, "wmax": 0.1, "vmin": 2, "vmax": 7, "tags": ["stream", "cold"]},
	"largescale_shoveljaw": {"name": "多鳞白甲鱼", "tier": 1, "wmin": 0.2, "wmax": 1.2, "vmin": 16, "vmax": 34, "tags": ["stream"]},
	"taiwan_shoveljaw": {"name": "台湾铲颌鱼", "tier": 1, "wmin": 0.2, "wmax": 1.0, "vmin": 18, "vmax": 40, "tags": ["stream"]},
	"rock_carp": {"name": "岩原鲤", "tier": 2, "wmin": 0.5, "wmax": 2.5, "vmin": 65, "vmax": 150, "tags": ["stream", "cold"]},
	"schizothorax": {"name": "裂腹鱼", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 60, "vmax": 140, "tags": ["stream", "cold"]},
	"torrent_catfish": {"name": "石爬鮡", "tier": 3, "wmin": 0.2, "wmax": 1.0, "vmin": 220, "vmax": 460, "tags": ["stream", "cold", "night"]},
	"grayling": {"name": "北极茴鱼", "tier": 3, "wmin": 0.3, "wmax": 1.5, "vmin": 240, "vmax": 500, "tags": ["stream", "cold"]},
	"sichuan_taimen": {"name": "川陕哲罗鲑", "tier": 5, "wmin": 5.0, "wmax": 50.0, "vmin": 4800, "vmax": 10000, "tags": ["stream", "cold", "protected"]},
	# —— 扩充 v3 · 远海深渊专属（deep：补足低阶基本盘 + 发光鱼 + 头足传奇）——
	"lanternfish": {"name": "灯笼鱼", "tier": 0, "wmin": 0.005, "wmax": 0.03, "vmin": 3, "vmax": 9, "tags": ["deep", "night"]},
	"bristlemouth": {"name": "钻光鱼", "tier": 0, "wmin": 0.002, "wmax": 0.01, "vmin": 3, "vmax": 8, "tags": ["deep"]},
	"hatchetfish": {"name": "银斧鱼", "tier": 1, "wmin": 0.01, "wmax": 0.08, "vmin": 16, "vmax": 36, "tags": ["deep"]},
	"rattail": {"name": "鼠尾鳕", "tier": 1, "wmin": 0.3, "wmax": 2.0, "vmin": 18, "vmax": 44, "tags": ["deep"]},
	"dragonfish": {"name": "巨口鱼", "tier": 2, "wmin": 0.05, "wmax": 0.3, "vmin": 60, "vmax": 140, "tags": ["deep", "night"]},
	"lancetfish": {"name": "帆蜥鱼", "tier": 2, "wmin": 1.0, "wmax": 5.0, "vmin": 65, "vmax": 150, "tags": ["deep"]},
	"anglerfish": {"name": "鮟鱇", "tier": 3, "wmin": 0.5, "wmax": 4.0, "vmin": 230, "vmax": 500, "tags": ["deep", "night"]},
	"escolar": {"name": "异鳞蛇鲭", "tier": 3, "wmin": 2.0, "wmax": 15.0, "vmin": 220, "vmax": 470, "tags": ["deep"]},
	"opah": {"name": "月鱼", "tier": 4, "wmin": 10.0, "wmax": 70.0, "vmin": 850, "vmax": 1900, "tags": ["deep"]},
	"giant_squid": {"name": "大王乌贼", "tier": 5, "wmin": 50.0, "wmax": 250.0, "vmin": 5500, "vmax": 11500, "tags": ["deep"]},
	# ============================================================
	# 扩充 v3 第二波（生态批次，目标 ~200+；各生态用独立 tag，鱼池互不串）
	# ============================================================
	# —— 热带珊瑚礁（reef）：高颜值收集天堂，暖水缤纷 ——
	"clownfish": {"name": "小丑鱼", "tier": 0, "wmin": 0.01, "wmax": 0.06, "vmin": 4, "vmax": 12, "tags": ["reef"]},
	"damselfish": {"name": "雀鲷", "tier": 0, "wmin": 0.01, "wmax": 0.05, "vmin": 3, "vmax": 9, "tags": ["reef"]},
	"cardinalfish": {"name": "天竺鲷", "tier": 0, "wmin": 0.01, "wmax": 0.06, "vmin": 3, "vmax": 10, "tags": ["reef"]},
	"chromis": {"name": "蓝绿光鳃鱼", "tier": 0, "wmin": 0.005, "wmax": 0.03, "vmin": 3, "vmax": 9, "tags": ["reef"]},
	"blenny": {"name": "鳚鱼", "tier": 0, "wmin": 0.01, "wmax": 0.05, "vmin": 3, "vmax": 9, "tags": ["reef"]},
	"firefish": {"name": "红火箭", "tier": 0, "wmin": 0.01, "wmax": 0.05, "vmin": 4, "vmax": 11, "tags": ["reef"]},
	"butterflyfish": {"name": "蝴蝶鱼", "tier": 1, "wmin": 0.05, "wmax": 0.3, "vmin": 16, "vmax": 36, "tags": ["reef"]},
	"surgeonfish": {"name": "刺尾鱼", "tier": 1, "wmin": 0.1, "wmax": 0.6, "vmin": 18, "vmax": 42, "tags": ["reef"]},
	"anthias": {"name": "金拟花鮨", "tier": 1, "wmin": 0.02, "wmax": 0.15, "vmin": 16, "vmax": 34, "tags": ["reef"]},
	"wrasse": {"name": "隆头鱼", "tier": 1, "wmin": 0.1, "wmax": 0.8, "vmin": 18, "vmax": 40, "tags": ["reef"]},
	"foxface": {"name": "狐狸鱼", "tier": 1, "wmin": 0.2, "wmax": 1.0, "vmin": 18, "vmax": 40, "tags": ["reef"]},
	"hawkfish": {"name": "鹰斑鲷", "tier": 1, "wmin": 0.05, "wmax": 0.4, "vmin": 16, "vmax": 34, "tags": ["reef"]},
	"angelfish": {"name": "神仙鱼", "tier": 2, "wmin": 0.3, "wmax": 2.0, "vmin": 65, "vmax": 150, "tags": ["reef"]},
	"parrotfish": {"name": "鹦哥鱼", "tier": 2, "wmin": 0.5, "wmax": 4.0, "vmin": 70, "vmax": 160, "tags": ["reef"]},
	"triggerfish": {"name": "鳞鲀", "tier": 2, "wmin": 0.3, "wmax": 2.5, "vmin": 60, "vmax": 140, "tags": ["reef"]},
	"lionfish": {"name": "狮子鱼", "tier": 2, "wmin": 0.2, "wmax": 1.2, "vmin": 70, "vmax": 160, "tags": ["reef"]},
	"moray": {"name": "裸胸鳝", "tier": 2, "wmin": 0.5, "wmax": 4.0, "vmin": 65, "vmax": 150, "tags": ["reef", "night"]},
	"boxfish": {"name": "箱鲀", "tier": 2, "wmin": 0.1, "wmax": 0.8, "vmin": 60, "vmax": 130, "tags": ["reef"]},
	"spotted_puffer": {"name": "斑点叉鼻鲀", "tier": 2, "wmin": 0.3, "wmax": 2.0, "vmin": 60, "vmax": 140, "tags": ["reef"]},
	"coral_grouper": {"name": "东星斑", "tier": 3, "wmin": 0.5, "wmax": 4.0, "vmin": 240, "vmax": 520, "tags": ["reef"]},
	"bohar_snapper": {"name": "千年笛鲷", "tier": 3, "wmin": 0.8, "wmax": 6.0, "vmin": 240, "vmax": 500, "tags": ["reef"]},
	"emperor_fish": {"name": "龙占鱼", "tier": 3, "wmin": 0.5, "wmax": 4.0, "vmin": 220, "vmax": 480, "tags": ["reef"]},
	"unicornfish": {"name": "独角倒吊", "tier": 3, "wmin": 0.5, "wmax": 3.0, "vmin": 220, "vmax": 460, "tags": ["reef"]},
	"bumphead_parrot": {"name": "隆头鹦哥", "tier": 4, "wmin": 5.0, "wmax": 40.0, "vmin": 800, "vmax": 1800, "tags": ["reef"]},
	"dogtooth_tuna": {"name": "狗牙金枪", "tier": 4, "wmin": 3.0, "wmax": 30.0, "vmin": 850, "vmax": 1900, "tags": ["reef", "deep"]},
	"napoleon_wrasse": {"name": "苏眉", "tier": 5, "wmin": 10.0, "wmax": 80.0, "vmin": 5000, "vmax": 11000, "tags": ["reef", "protected"]},
	"manta_ray": {"name": "蝠鲼", "tier": 5, "wmin": 50.0, "wmax": 500.0, "vmin": 5500, "vmax": 12000, "tags": ["reef", "protected"]},
	# —— 河口红树林（brackish）：汽水带，潮汐泥滩 ——
	"mudskipper": {"name": "弹涂鱼", "tier": 0, "wmin": 0.01, "wmax": 0.08, "vmin": 3, "vmax": 10, "tags": ["brackish"]},
	"glassfish": {"name": "玻璃鱼", "tier": 0, "wmin": 0.005, "wmax": 0.03, "vmin": 3, "vmax": 9, "tags": ["brackish"]},
	"silverside": {"name": "银汉鱼", "tier": 0, "wmin": 0.01, "wmax": 0.06, "vmin": 3, "vmax": 9, "tags": ["brackish"]},
	"archerfish": {"name": "射水鱼", "tier": 1, "wmin": 0.1, "wmax": 0.5, "vmin": 16, "vmax": 34, "tags": ["brackish"]},
	"threadfin": {"name": "四指马鲅", "tier": 1, "wmin": 0.3, "wmax": 2.0, "vmin": 18, "vmax": 44, "tags": ["brackish"]},
	"marble_sleeper": {"name": "笋壳鱼", "tier": 1, "wmin": 0.2, "wmax": 1.5, "vmin": 18, "vmax": 42, "tags": ["brackish", "night"]},
	"silverbiddy": {"name": "碟仔鱼", "tier": 1, "wmin": 0.05, "wmax": 0.3, "vmin": 16, "vmax": 32, "tags": ["brackish"]},
	"mangrove_snapper": {"name": "紫红笛鲷", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 60, "vmax": 140, "tags": ["brackish"]},
	"fingermark": {"name": "画眉笛鲷", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 65, "vmax": 150, "tags": ["brackish"]},
	"milkfish": {"name": "虱目鱼", "tier": 2, "wmin": 0.5, "wmax": 4.0, "vmin": 60, "vmax": 130, "tags": ["brackish"]},
	"tigerperch": {"name": "花身鸡鱼", "tier": 2, "wmin": 0.2, "wmax": 1.0, "vmin": 60, "vmax": 130, "tags": ["brackish"]},
	"king_threadfin": {"name": "大午", "tier": 3, "wmin": 2.0, "wmax": 15.0, "vmin": 240, "vmax": 500, "tags": ["brackish"]},
	"tarpon": {"name": "大海鲢", "tier": 3, "wmin": 3.0, "wmax": 25.0, "vmin": 240, "vmax": 520, "tags": ["brackish"]},
	"estuary_stingray": {"name": "赤魟", "tier": 3, "wmin": 2.0, "wmax": 20.0, "vmin": 220, "vmax": 470, "tags": ["brackish", "night"]},
	"bull_shark": {"name": "公牛鲨", "tier": 4, "wmin": 5.0, "wmax": 100.0, "vmin": 850, "vmax": 1900, "tags": ["brackish", "night"]},
	"giant_threadfin": {"name": "巨马鲅", "tier": 4, "wmin": 5.0, "wmax": 40.0, "vmin": 800, "vmax": 1800, "tags": ["brackish"]},
	"bahaba": {"name": "黄唇鱼", "tier": 5, "wmin": 10.0, "wmax": 100.0, "vmin": 5500, "vmax": 11500, "tags": ["brackish", "protected"]},
	"sawfish": {"name": "锯鳐", "tier": 5, "wmin": 20.0, "wmax": 300.0, "vmin": 6000, "vmax": 12000, "tags": ["brackish", "protected", "night"]},
	# —— 极地冰湖（polar）：冰下冷水，鲑鳟白鲑层 ——
	"polar_smelt": {"name": "北极公鱼", "tier": 0, "wmin": 0.01, "wmax": 0.06, "vmin": 3, "vmax": 9, "tags": ["polar"]},
	"ninespine_stickleback": {"name": "九刺鱼", "tier": 0, "wmin": 0.005, "wmax": 0.02, "vmin": 3, "vmax": 8, "tags": ["polar"]},
	"capelin": {"name": "毛鳞鱼", "tier": 0, "wmin": 0.02, "wmax": 0.1, "vmin": 3, "vmax": 10, "tags": ["polar"]},
	"pond_smelt": {"name": "西太公鱼", "tier": 0, "wmin": 0.01, "wmax": 0.05, "vmin": 3, "vmax": 9, "tags": ["polar"]},
	"arctic_cisco": {"name": "北极白鲑", "tier": 1, "wmin": 0.3, "wmax": 2.0, "vmin": 16, "vmax": 40, "tags": ["polar"]},
	"whitefish": {"name": "高白鲑", "tier": 1, "wmin": 0.3, "wmax": 2.5, "vmin": 18, "vmax": 44, "tags": ["polar"]},
	"sculpin": {"name": "杜父鱼", "tier": 1, "wmin": 0.1, "wmax": 0.8, "vmin": 16, "vmax": 34, "tags": ["polar"]},
	"ruffe": {"name": "梅花鲈", "tier": 1, "wmin": 0.05, "wmax": 0.3, "vmin": 16, "vmax": 32, "tags": ["polar"]},
	"arctic_char": {"name": "北极红点鲑", "tier": 2, "wmin": 0.5, "wmax": 4.0, "vmin": 65, "vmax": 160, "tags": ["polar"]},
	"inconnu": {"name": "北鲑", "tier": 2, "wmin": 1.0, "wmax": 8.0, "vmin": 70, "vmax": 160, "tags": ["polar"]},
	"round_whitefish": {"name": "圆白鲑", "tier": 2, "wmin": 0.3, "wmax": 2.0, "vmin": 60, "vmax": 140, "tags": ["polar"]},
	"fourhorn_sculpin": {"name": "四角杜父鱼", "tier": 2, "wmin": 0.1, "wmax": 0.6, "vmin": 60, "vmax": 130, "tags": ["polar"]},
	"lake_trout": {"name": "湖红点鲑", "tier": 3, "wmin": 1.0, "wmax": 15.0, "vmin": 240, "vmax": 520, "tags": ["polar"]},
	"arctic_cod": {"name": "北极鳕", "tier": 3, "wmin": 1.0, "wmax": 8.0, "vmin": 220, "vmax": 460, "tags": ["polar"]},
	"broad_whitefish": {"name": "宽白鲑", "tier": 3, "wmin": 1.0, "wmax": 6.0, "vmin": 220, "vmax": 470, "tags": ["polar"]},
	"greenland_halibut": {"name": "格陵兰庸鲽", "tier": 4, "wmin": 5.0, "wmax": 40.0, "vmin": 800, "vmax": 1800, "tags": ["polar", "deep"]},
	"arctic_skate": {"name": "北极鳐", "tier": 4, "wmin": 5.0, "wmax": 30.0, "vmin": 800, "vmax": 1700, "tags": ["polar"]},
	"greenland_shark": {"name": "格陵兰睡鲨", "tier": 5, "wmin": 50.0, "wmax": 700.0, "vmin": 5500, "vmax": 12000, "tags": ["polar", "deep", "protected", "night"]},
	"beluga_sturgeon": {"name": "欧洲鳇", "tier": 5, "wmin": 50.0, "wmax": 800.0, "vmin": 6000, "vmax": 13000, "tags": ["polar", "protected"]},
	# —— 古潭溶洞（cavern）：暗水盲鱼 + 活化石，多为夜行 ——
	"cave_loach": {"name": "盲鳅", "tier": 0, "wmin": 0.01, "wmax": 0.05, "vmin": 3, "vmax": 10, "tags": ["cavern", "night"]},
	"blind_cavefish": {"name": "盲鱼", "tier": 0, "wmin": 0.01, "wmax": 0.06, "vmin": 4, "vmax": 12, "tags": ["cavern", "night"]},
	"cave_minnow": {"name": "洞穴金线鲃", "tier": 0, "wmin": 0.02, "wmax": 0.1, "vmin": 4, "vmax": 12, "tags": ["cavern", "night"]},
	"cave_catfish": {"name": "盲鲶", "tier": 1, "wmin": 0.05, "wmax": 0.4, "vmin": 16, "vmax": 36, "tags": ["cavern", "night"]},
	"olm": {"name": "洞螈", "tier": 1, "wmin": 0.05, "wmax": 0.3, "vmin": 18, "vmax": 44, "tags": ["cavern", "night"]},
	"cave_eel": {"name": "洞穴合鳃", "tier": 1, "wmin": 0.1, "wmax": 0.7, "vmin": 16, "vmax": 40, "tags": ["cavern", "night"]},
	"golden_barb": {"name": "金线鲃", "tier": 2, "wmin": 0.3, "wmax": 1.5, "vmin": 60, "vmax": 140, "tags": ["cavern", "night"]},
	"blind_eel": {"name": "盲鳗", "tier": 2, "wmin": 0.3, "wmax": 2.0, "vmin": 60, "vmax": 140, "tags": ["cavern", "night"]},
	"cave_sleeper": {"name": "暗塘鳢", "tier": 2, "wmin": 0.2, "wmax": 1.5, "vmin": 65, "vmax": 150, "tags": ["cavern", "night"]},
	"cavern_catfish": {"name": "巨洞鲶", "tier": 3, "wmin": 2.0, "wmax": 15.0, "vmin": 240, "vmax": 500, "tags": ["cavern", "night"]},
	"ancient_loach": {"name": "古鳅", "tier": 3, "wmin": 0.5, "wmax": 3.0, "vmin": 220, "vmax": 470, "tags": ["cavern", "night"]},
	"bichir": {"name": "多鳍鱼", "tier": 4, "wmin": 0.5, "wmax": 4.0, "vmin": 800, "vmax": 1700, "tags": ["cavern", "night"]},
	"lungfish": {"name": "肺鱼", "tier": 4, "wmin": 1.0, "wmax": 8.0, "vmin": 850, "vmax": 1900, "tags": ["cavern", "night"]},
	"giant_salamander": {"name": "大鲵", "tier": 5, "wmin": 5.0, "wmax": 50.0, "vmin": 5000, "vmax": 11000, "tags": ["cavern", "protected", "night"]},
	"alligator_gar": {"name": "鳄雀鳝", "tier": 5, "wmin": 10.0, "wmax": 100.0, "vmin": 5500, "vmax": 11500, "tags": ["cavern", "night"]},
	# —— 城市野塘（urban）：皮实/入侵/趣味，节奏快价低 ——
	"mosquitofish": {"name": "食蚊鱼", "tier": 0, "wmin": 0.002, "wmax": 0.01, "vmin": 1, "vmax": 4, "tags": ["urban"]},
	"feral_goldfish": {"name": "野金鱼", "tier": 0, "wmin": 0.05, "wmax": 0.4, "vmin": 2, "vmax": 8, "tags": ["urban"]},
	"feral_guppy": {"name": "野孔雀鱼", "tier": 0, "wmin": 0.001, "wmax": 0.008, "vmin": 2, "vmax": 6, "tags": ["urban"]},
	"plecostomus": {"name": "清道夫", "tier": 1, "wmin": 0.2, "wmax": 1.5, "vmin": 14, "vmax": 32, "tags": ["urban", "night"]},
	"crayfish": {"name": "小龙虾", "tier": 1, "wmin": 0.05, "wmax": 0.3, "vmin": 16, "vmax": 34, "tags": ["urban", "night"]},
	"bullfrog": {"name": "牛蛙", "tier": 1, "wmin": 0.1, "wmax": 0.6, "vmin": 16, "vmax": 36, "tags": ["urban", "night"]},
	"walking_catfish": {"name": "革胡子鲶", "tier": 1, "wmin": 0.3, "wmax": 2.0, "vmin": 16, "vmax": 40, "tags": ["urban", "night"]},
	"red_eared_slider": {"name": "巴西龟", "tier": 2, "wmin": 0.3, "wmax": 2.0, "vmin": 60, "vmax": 130, "tags": ["urban"]},
	"channel_catfish": {"name": "斑点叉尾鮰", "tier": 2, "wmin": 0.5, "wmax": 4.0, "vmin": 60, "vmax": 140, "tags": ["urban", "night"]},
	"giant_gourami": {"name": "招财鱼", "tier": 2, "wmin": 0.5, "wmax": 3.0, "vmin": 60, "vmax": 140, "tags": ["urban"]},
	"snapping_turtle": {"name": "大鳄龟", "tier": 3, "wmin": 2.0, "wmax": 30.0, "vmin": 240, "vmax": 500, "tags": ["urban", "night"]},
	"flathead_catfish": {"name": "平头鲶", "tier": 3, "wmin": 2.0, "wmax": 20.0, "vmin": 240, "vmax": 500, "tags": ["urban", "night"]},
	"arapaima": {"name": "巨骨舌鱼", "tier": 4, "wmin": 10.0, "wmax": 100.0, "vmin": 850, "vmax": 1900, "tags": ["urban"]},
	"yangtze_softshell": {"name": "斑鳖", "tier": 5, "wmin": 30.0, "wmax": 200.0, "vmin": 6000, "vmax": 12000, "tags": ["urban", "protected", "night"]},
}

# 基础品阶权重（rod Lv.1）：58/25/11/4.5/1.3/0.2（%）
const BASE_WEIGHTS := {0: 58.0, 1: 25.0, 2: 11.0, 3: 4.5, 4: 1.3, 5: 0.2}

# —— 星级品质（WEBFISHING 模板：逐级 roll，鱼饵决定每级通过率）——
const QUALITY_NAMES := ["", "上品", "极品", "完美"]
const QUALITY_MULTS := [1.0, 1.8, 4.0, 8.0]

# —— 稀有变体（Chillquarium 式收集深度护城河）：与星级正交，独立 roll，决定外观色 + 价值倍率。
# 概率与品阶/星级无关；普通占绝大多数，越华丽越稀有。收集轴：每种鱼 ×4 变体（106×3 稀有 = 318 收集格）。
const VARIANT_NAMES := ["", "斑斓", "鎏金", "七彩"]
const VARIANT_MULTS := [1.0, 2.0, 5.0, 12.0]
const VARIANT_COLORS := [
	Color(1, 1, 1),             # 0 普通（不染色）
	Color(0.55, 0.85, 0.95),   # 1 斑斓 青蓝
	Color(1.0, 0.84, 0.35),    # 2 鎏金 金
	Color(0.95, 0.55, 0.95),   # 3 七彩 虹紫
]
# 各稀有变体出现概率（独立判定）：斑斓 2.5% / 鎏金 0.4% / 七彩 0.08%，其余普通。
# 2026-07-07 数值 P1 收敛（原 6%/1.2%/0.2% 使"稀有"沦为背景噪音）：对齐三层惊喜节拍
# 斑斓≈1/40 竿、鎏金≈1/250、七彩≈1/1250（balance_audit §3.4 / 标准 S8）。
const VARIANT_PROBS := [0.0, 0.025, 0.004, 0.0008]
## 鱼饵：金币永久升级（线性进阶，参考 Melvor 自动化的游戏币门控）。
## probs[i] = 从 i-1 星升到 i 星的通过率；P(★)=p1，P(★★)=p1·p2，P(★★★)=p1·p2·p3。
const BAITS := [
	{"name": "蚯蚓", "cost": 0, "probs": [1.0, 0.08, 0.05, 0.02], "desc": "河边随手挖的"},
	{"name": "红虫", "cost": 800, "probs": [1.0, 0.22, 0.10, 0.08], "desc": "冬钓利器，上品率明显提升"},
	{"name": "活虾", "cost": 5000, "probs": [1.0, 0.45, 0.18, 0.12], "desc": "大鱼爱追活食"},
	{"name": "秘制饵", "cost": 60000, "probs": [1.0, 0.70, 0.35, 0.18], "desc": "老钓翁的祖传配方"},
]

# —— 鱼钩：第三条成长线，决定「双钩」几率（一次钓上两条）。鱼竿管稀有度、鱼饵管星级、鱼钩管产量。——
const HOOKS := [
	{"name": "基础鱼钩", "cost": 0, "double": 0.0, "desc": "普普通通的单钩"},
	{"name": "宽门钩", "cost": 6000, "double": 0.10, "desc": "钩门更宽，偶尔双钩"},
	{"name": "倒刺钩", "cost": 12000, "double": 0.20, "desc": "倒刺挂得牢，双钩更常见"},
	{"name": "双叉钩", "cost": 180000, "double": 0.32, "desc": "一线两钩，常常成对上鱼"},
]

# —— 诱饵/窝料：第四条成长线，决定「稀有变体」偏置（vbias）。鱼竿管稀有度、鱼饵管星级、
# 鱼钩管产量、诱饵管变体——补齐四轴对称。vbias 喂给 roll_variant 经 variant_scale 分档抬高变体率；
# 0 级（无窝料）vbias=0，与基线逐位一致（不破回归）。作为变体墙收集轴的专属长线 coin sink。
# ⚠ 本线按「收集杠杆」定价（麝香：七彩 ×4、彩鳞产出 ×~3），P1 变体收敛后金币口径回本 ≈50h
# 系有意取舍——勿按 S2 回本带宽把它当定价事故来"修"（决策见 BACKLOG 2026-07-07）。——
const LURES := [
	{"name": "无窝料", "cost": 0, "vbias": 0.0, "desc": "空钩直钓，花色全凭运气"},
	{"name": "碎米窝", "cost": 30000, "vbias": 0.6, "desc": "撒把碎米打窝，斑斓鱼更常照面"},
	{"name": "酒米窝", "cost": 45000, "vbias": 1.5, "desc": "发酵酒米，鎏金鱼明显变勤"},
	{"name": "麝香窝料", "cost": 400000, "vbias": 3.0, "desc": "老饵师麝香配方，七彩亦偶现身"},
]


## 诱饵/窝料等级 -> 变体偏置 vbias（喂给 roll_variant）。越界自动夹取。
static func lure_vbias(lure_idx: int) -> float:
	return float(LURES[clampi(lure_idx, 0, LURES.size() - 1)]["vbias"])


# —— 彩鳞（P1 变体兑换货币，balance_audit §3.4）：重复变体折「同档鳞」、定向点亮 657 格缺格，
# 把收集轴尾部的纯赌命（T5×七彩单格期望 ~90h）压回可规划区间（目标 1~3h/格）。
# ⚠ 分三种币、同档兑同档（S8「重复稀有 3~5 换 1 定向」的严格口径）：对抗审查证明单一货币会让
# 高频的斑斓/鎏金重复金流直接供给最稀缺的七彩格，T5 格塌缩到分钟级——七彩格只认重复七彩。——
const SCALE_NAMES := ["斑斓鳞", "鎏金鳞", "七彩鳞"]   # 下标 = 变体档 − 1


## 定向点亮一格 vi 档变体所需的「同档鳞」枚数：按鱼品阶分层（t0~2=3 / t3~4=4 / t5=5）。
static func scale_cost(tier: int) -> int:
	if tier >= 5:
		return 5
	if tier >= 3:
		return 4
	return 3


## 星级抽取：逐级 roll，失败即停。
static func roll_quality(bait_idx: int, rng: RandomNumberGenerator) -> int:
	var probs: Array = BAITS[clampi(bait_idx, 0, BAITS.size() - 1)]["probs"]
	var q := 0
	for lvl in range(1, probs.size()):
		if rng.randf() < float(probs[lvl]):
			q = lvl
		else:
			break
	return q


static func quality_label(q: int) -> String:
	if q <= 0:
		return ""
	return QUALITY_NAMES[clampi(q, 0, 3)] + "★".repeat(q) + "·"


## 变体杠杆的分档倍率：越稀有的档吃到的偏置越足——顶级窝料的边际卖点是「七彩更常见」
## 而不是「斑斓刷屏」（P1 差异化：斑斓 ×(1+0.25b) / 鎏金 ×(1+0.5b) / 七彩 ×(1+b)）。
## vbias=0 时各档均为 ×1，与基线逐位一致。
static func variant_scale(vi: int, vbias: float) -> float:
	var b := clampf(vbias, 0.0, 10.0)
	match vi:
		3: return 1.0 + b
		2: return 1.0 + 0.5 * b
		1: return 1.0 + 0.25 * b
	return 1.0


## 稀有变体抽取：从最稀有向常见累加判定，落空则普通。
## vbias≥0：收集杠杆（诱饵/悬赏/钓点亲和给的偏置），经 variant_scale 分档抬高变体概率；
## vbias=0 时与原分布逐位一致（保证基线回归不破）。
static func roll_variant(rng: RandomNumberGenerator, vbias := 0.0) -> int:
	var r := rng.randf()
	var acc := 0.0
	for vi in range(VARIANT_PROBS.size() - 1, 0, -1):
		acc += float(VARIANT_PROBS[vi]) * variant_scale(vi, vbias)
		if r < acc:
			return vi
	return 0


static func variant_label(v: int) -> String:
	if v <= 0:
		return ""
	return VARIANT_NAMES[clampi(v, 0, VARIANT_NAMES.size() - 1)] + "·"


static func variant_color(v: int) -> Color:
	return VARIANT_COLORS[clampi(v, 0, VARIANT_COLORS.size() - 1)]


## 按权重抽品阶，再在该品阶内随机选种，返回鱼 id。
## pool 非空时只在该钓点鱼池内抽（多钓点生态）：抽到的品阶在池内无鱼时，
## 就近降阶/升阶到池内最近有鱼的品阶，绝不逸出到全鱼池（保证钓点隔离）。
static func roll_fish(weights: Dictionary, rng: RandomNumberGenerator, pool: Array = []) -> String:
	var total := 0.0
	for r in weights:
		total += weights[r]
	var pick := rng.randf() * total
	var tier := 0
	for r in weights:
		pick -= weights[r]
		if pick <= 0.0:
			tier = r
			break
	var ids: Array = pool if not pool.is_empty() else FISH.keys()
	var candidates := _ids_of_tier(ids, tier)
	if candidates.is_empty():
		# 就近品阶回退（先降后升），始终留在同一鱼池内
		for d in range(1, 6):
			candidates = _ids_of_tier(ids, tier - d)
			if candidates.is_empty():
				candidates = _ids_of_tier(ids, tier + d)
			if not candidates.is_empty():
				break
	if candidates.is_empty():
		candidates = ids
	return candidates[rng.randi() % candidates.size()]


static func _ids_of_tier(ids: Array, tier: int) -> Array:
	var out: Array = []
	if tier < 0 or tier > 5:
		return out
	for id in ids:
		if int(FISH[id]["tier"]) == tier:
			out.append(id)
	return out


static func tags_of(id: String) -> Array:
	return FISH[id].get("tags", ["river"]) if FISH.has(id) else []


## 限定鱼配置（{} = 非限定，全时段可遇）。schema: {"phases":[...], "label":..., "hint":...}
static func limited_of(id: String) -> Dictionary:
	return FISH[id].get("limited", {}) if FISH.has(id) else {}


## 当前时段能否遇到该鱼：限定鱼仅在其 phases 列出的时段出现；非限定鱼总可遇。
static func is_available(id: String, phase: String) -> bool:
	var lim: Dictionary = limited_of(id)
	if lim.is_empty():
		return true
	var phases: Array = lim.get("phases", [])
	return phases.is_empty() or phase in phases


## 限定标签（图鉴徽章/说明用），非限定返回 ""。
static func limited_label(id: String) -> String:
	var lim: Dictionary = limited_of(id)
	return str(lim.get("label", "限定")) if not lim.is_empty() else ""


## 鱼竿等级 -> 品阶权重（等级越高，高阶占比越大）。
static func weights_for_rod(rod_level: int) -> Dictionary:
	var lv := float(rod_level - 1)
	return {
		0: maxf(16.0, BASE_WEIGHTS[0] - lv * 2.4),
		1: BASE_WEIGHTS[1] + lv * 0.7,
		2: BASE_WEIGHTS[2] + lv * 0.85,
		3: BASE_WEIGHTS[3] + lv * 0.50,
		4: BASE_WEIGHTS[4] + lv * 0.22,
		5: BASE_WEIGHTS[5] + lv * 0.05,
	}


## 钓一条鱼：抽种 + 抽体重 + 抽星级 + 算价值。返回 {"id", "w"(kg), "v"(金币), "q"(星级)}。
## 体重 roll 偏向小个体（k²），卖价与体重线性挂钩（Fisch 模型）再乘星级倍率。
## luck：额外品阶运气（如鱼汛事件 +N），仅抬高高阶权重，不影响鱼价基准。
## pool 非空时只在该钓点鱼池内出鱼（多钓点）；为空保持旧行为（全鱼池）。
static func roll_catch(rng: RandomNumberGenerator, rod_level: int, bait_idx := 0, luck := 0, pool: Array = [], vbias := 0.0) -> Dictionary:
	var id := roll_fish(weights_for_rod(rod_level + luck), rng, pool)
	var f: Dictionary = FISH[id]
	var k := rng.randf()
	k = k * k  # 偏向小体型，大鱼稀罕
	var w: float = lerpf(float(f["wmin"]), float(f["wmax"]), k)
	var size_ratio: float = 0.0
	if float(f["wmax"]) > float(f["wmin"]):
		size_ratio = (w - float(f["wmin"])) / (float(f["wmax"]) - float(f["wmin"]))
	var base: float = lerpf(float(f["vmin"]), float(f["vmax"]), size_ratio)
	var rod_mult := 1.0 + float(rod_level - 1) * 0.08
	var jitter := rng.randf_range(0.92, 1.08)
	var q := roll_quality(bait_idx, rng)
	var vr := roll_variant(rng, vbias)
	return {
		"id": id,
		"w": snappedf(w, 0.01),
		"v": max(1, int(round(base * rod_mult * jitter * QUALITY_MULTS[q] * VARIANT_MULTS[vr]))),
		"q": q,
		"var": vr,
	}


## 体型前缀：同种鱼里的大个体（约 13%）标「大·」，顶级个体（约 2.5%）标「巨物·」。
static func size_tag(id: String, w: float) -> String:
	var f: Dictionary = FISH[id]
	if float(f["wmax"]) <= float(f["wmin"]):
		return ""
	var r := (w - float(f["wmin"])) / (float(f["wmax"]) - float(f["wmin"]))
	if r >= 0.95:
		return "巨物·"
	if r >= 0.75:
		return "大·"
	return ""


static func tier_of(id: String) -> int:
	return int(FISH[id]["tier"])


static func display_name(id: String) -> String:
	return str(FISH[id]["name"])
