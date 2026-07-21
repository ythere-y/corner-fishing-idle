extends Node2D
class_name CornerFishing
## 角落垂钓 · 主控
## 职责：透明角落窗形态 + 挂机钓鱼状态机 + 经济 + 即时反馈（后续接存档/离线/面板）。

@onready var painter: Node2D = $ScenePainter
@onready var ui_root: Control = $HUD/Root
@onready var coins_label: Label = $HUD/Root/Coins
@onready var toast_label: Label = $HUD/Root/Toast

# 主窗口保持大画布；挂机画面固定在右下角，复杂面板在主窗口中央弹出。
const WIN := Vector2i(1040, 720)
const ART := Vector2(520, 400)
const SCENE_OFF := Vector2(520, 320)  # = WIN - ART，场景绘制/按钮/落水点统一加此偏移

# 可交互区（美术画布坐标，绘制时加 SCENE_OFF）：右下角可见场景 + 按钮；其余透明区穿透。
const INTERACT_RECT := Rect2(160, 148, 360, 252)

# 羽化遮罩参数（art 空间中心 + 屏幕像素半径/core），shader 与鼠标穿透多边形共用。
# 注意：Windows 的 window_set_mouse_passthrough 用 SetWindowRgn 会把窗口裁到该多边形，
# 所以空闲时的穿透区必须贴合羽化椭圆边界（alpha≈0 处），否则会把场景裁成硬矩形。
const FEATHER_CENTER := Vector2(478, 388)   # art 空间，绘制时 + SCENE_OFF
const FEATHER_RADII := Vector2(560, 460)
const FEATHER_CORE := 0.20

# —— 显示模式 ——
# framed = 带框普通窗口（默认，CD playable 式：场景填窗 + 底部导航 + 胶囊HUD）。
# immersive = 透明羽化角落挂件（原版，降级为后续完善的「沉浸模式」，代码 gate 保留不删）。
var display_mode := "framed"
const FRAMED_SCENE_SCALE := 2.0                 # 带框模式：场景放大填满窗口宽（参考值；实际 scale 见 _apply_display_mode 含 overscan）
const FRAMED_OVERSCAN := 4.0                    # 带框场景向四周溢出像素：消除分数 DPI 下窗口边缘的浅"描边"接缝
const FRAMED_CONSOLE_H := 80.0                  # 底部导航 console 高（完整容纳 44px 图标 + 文字，不被窗口底切）
const FRAMED_BG := Color(0.105, 0.115, 0.105)   # 带框窗口实底背景（场景外的边）

# —— UI 布局契约 ——
# 主图烤入按钮/落水点的坐标随 Codex 美术版本漂移。优先从 ui_layout.json 读取
# （Codex 更新美术时同步改 json 即可，不用动代码）；无 json 时用下面实测的回退值。
# json 格式：{"buttons": {"catch": [x,y]}, "bite_point": [x,y]}
# 升级（鱼竿/鱼饵/鱼钩）与设置都已并入鱼篓面板页签，主界面只留一个「鱼篓」按钮。
const AnglerEquipmentScript := preload("res://systems/angler/angler_equipment.gd")
const RelationshipDataScript := preload("res://relationship_data.gd")
const RelationshipPortraitScript := preload("res://relationship_portrait.gd")
const UI_LAYOUT_PATHS := ["res://ui_layout.json", "res://assets/art/ui/ui_layout.json"]
var btn_centers := {
	"catch": Vector2(452, 371),
}

# —— 钓鱼状态机 ——
enum {ST_WAIT, ST_BITE}
var _state := ST_WAIT
var _state_t := 0.0
var _started := false

# —— 亲手起钩（P0 好玩补丁）：渔获在咬钩瞬间预掷，咬钩窗口内点「起钩！」= 亲手钓获加成。
# 设计宪法：手动只可能加成、绝不惩罚——不点照常自动上鱼，挂机永远是 100% 基线。
var _pending_catch := {}          # 咬钩时预掷的渔获（空 = 无预掷 → _do_catch 现场掷，兼容测试直调）
var _bite_special := false        # 本次咬钩是否稀有驻留（鎏金/七彩/神话：多挣扎几秒等你伸手）
var hand_catches := 0             # 亲手起钩累计（存档 hand_n，旧档默认 0）
var _capture_card_data := {}      # 稀有捕获卡当前展示的渔获（面板 kind="capture"）
const HAND_HOOK_MULT := 1.1       # 亲手起钩：体重/卖价 ×1.1
const SPECIAL_BITE_HOLD := 4.5    # 稀有咬钩驻留秒数（≈0.5% 竿次，平均节奏影响可忽略）

# —— 存档数据 ——
var coins := 0.0
var rod_level := 1
var reel_level := 0  # 独立速度装备：绕线轮等级，提供 speed 属性并缩短一竿周期
var fish_line_level := 0
var bobber_level := 0
var sonar_level := 0
var notebook_level := 0
var gloves_level := 0
var bag_level := 1
var bait_level := 0  # FishData.BAITS 下标，金币永久升级
var hook_level := 0  # FishData.HOOKS 下标，决定双钩几率
var lure_level := 0  # FishData.LURES 下标，决定稀有变体偏置（vbias），金币永久升级
# —— 鱼贩合约（自动贩卖，VISION 决策 2026-07-07）：满篓只自动带走杂鱼，珍品永远留给手动 ——
var auto_sell_bought := false   # 一次性买断（AUTO_SELL_COST）
var auto_sell_on := false       # 合约开关：买断后默认开，可随时暂停
var auto_sold_n := 0            # 合约累计带走条数（统计页）
var auto_sold_v := 0.0          # 合约累计入金（统计页）
var scales: Array = [0, 0, 0]   # 彩鳞（v15）：斑斓鳞/鎏金鳞/七彩鳞——重复变体折同档鳞（FishData.SCALE_NAMES）
var showcase_pending := ""      # 试竿保底（v15）：购买升级后的下一竿保底展示新效果（"rod"/"bait"/"hook"/"lure"）
var yest_income := 0            # 昨日（上个游玩日）卖鱼收入（v15）：周赛/周目标奖励的收入锚
var inventory: Array = []  # 每条 {"id", "w", "v", "q"(星级)}，一条鱼占一格
var display: Array = []     # 陈列架上的鱼（离开鱼篓、永久展示），最多 Decor.NUM_SLOTS 件
var lifetime_coins := 0.0  # 累计卖鱼所得
var lifetime_catches := 0
var dex := {}  # id -> {"n": 累计捕获数, "w": 最大体重纪录}（图鉴纪录轴）
var best_quality := 0      # 历史最高星级（成就用）
var best_variant := 0      # 历史最高稀有变体（成就用：斑斓/鎏金/七彩）
var caught_giant := false  # 是否钓到过「巨物」（成就用）
var achievements_done := {}  # id -> true，已达成的成就（toast 只触发一次）
var feature_unlocks := {"settings": true}  # 渐进开放的系统入口；开局只显示设置
var feature_spend_equipment := 0.0          # 装备消费累计，达到 10K 后开放任务
var relationship_state := {}                 # v24 河湾人情簿：逐级事件、独立排程、Buff 与终章解锁

# 背包容量与扩容费用（bag_level 1 起步；费用 = 升到下一级）。
# 调研定标：起始 20 格（Melvor 同款），整档 +5 格，费用走 1-2-5 阶梯（首扩几分钟产出可买）。
# 鱼篓阶梯：55 格后的 6 档（60~100）是毕业期大额金币去向（balance_audit §3.3 S11 的荣誉/工程型 sink，
# 25 万→950 万,守住 UI 7 位数预算）；有鱼贩合约后大鱼篓=更大的珍品缓冲区，离线溢出折价更少。
const BAG_CAPS := [20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 80, 90, 100]
const BAG_COSTS := [100, 250, 600, 1500, 8000, 30000, 90000,
	250000, 600000, 1400000, 3000000, 6000000, 9500000]

var save_enabled := true
var _initial_load_complete := false   # async 窗口初始化期间禁止保存默认值覆盖真实存档
var rng := RandomNumberGenerator.new()
var _font: SystemFont
var _serif: Font               # Noto Serif SC —— 标题/钓点名/英雄数字的衬线展示声音
var _serif_num: FontVariation  # 同字体 + 等宽数字
var _font_bold: FontVariation  # 系统字体假粗体（embolden）：HUD 胶囊/导航等 weight 600 处用
var _msg_id := 0
var _panel: Control = null
var _panel_kind := ""
var _panel_view_sig := ""    # 当前面板「视图签名」（kind+页签+详情鱼…）；同签名重建时保留滚动位置，避免挂机上鱼把长列表弹回顶部
var _detail_fish := ""       # 当前「鱼种详情卡」显示的鱼 id
var _story_step := 0         # 【新增】开场故事动画当前播放到第几页（story 面板用）
var _opacity := 1.0
var paper_grain := true          # 水彩纸纹层开关（视觉偏好；真值在 main，经 _set_paper_grain 应用到 painter）
const FPS_OPTIONS := [30, 60, 90, 120]   # 设置里可选的帧率上限
var max_fps := 120               # 帧率上限：默认 120 流畅优先（用户拍板），可在设置降到 30/60 省电
const UI_SCALE_OPTIONS := [1.0, 1.25, 1.5]   # 设置里「快捷跳档」按钮（自由拖拽不受这三个值限制）
const UI_SCALE_MIN := 0.5                    # 自由缩放下限：0.5=520×360，桌面角落挂件可缩到很小；再小手柄/字就难用
const UI_SCALE_MAX := 2.5                    # 自由缩放绝对上限（实际还会再夹到屏幕可用区）
var ui_scale := 1.0              # 当前界面缩放倍率（连续值）；带框模式整窗等比缩放
var _win_resize_guard := false   # 程序内主动改窗口尺寸时置位（仅 _set_ui_scale 用，保留以防误触发监听）
var _widget_pos = null           # Variant：Vector2 或 null；透明覆盖窗内挂机组件左上角
# —— 自绘缩放手柄（无边框窗口没有系统边框，照「自绘移动」的思路补一套缩放）——
var _rz_active := false           # 是否正在拖拽缩放
var _rz_anchor := Vector2.ZERO    # 锚点归一化坐标（拖动时该点在屏幕上不动）∈ {0, .5, 1}²
var _rz_dir := Vector2.ZERO       # 该手柄驱动的轴向（x/y ∈ {-1, 0, 1}）
var _rz_start_mouse := Vector2i.ZERO  # 起拖时全局鼠标
var _rz_start_pos := Vector2i.ZERO    # 起拖时窗口位置
var _rz_start_size := Vector2i.ZERO   # 起拖时窗口尺寸
var focus_mode := false          # 专注/安静模式：停小动物事件 + 抑制飘字 + 轻微变暗
var seen_intro := false          # 是否看过首次引导
# 【新增】背包客人设：先看开场故事动画，再选角色（Jim/Ganie），选完才进入 intro 引导。
var chosen_character := false    # 是否已选过角色（老档默认 true，不重新弹）
var player_character := CharacterData.DEFAULT_CHARACTER  # 当前选择的角色 id
var order_chip: Button = null   # HUD 上的每日订单进度小字（可点开订单页）
var spot_chip: Button = null    # HUD 上的当前钓点·事件小字（可点开钓点页）

# 存档路径用变量：测试可改用独立文件，避免覆盖真实存档。
var save_path := "user://corner_fishing_save.json"
const OFFLINE_CAP_BASE := 12.0 * 3600.0   # 离线结算基础上限 12h（覆盖 21:00→次日 9:00 的典型过夜）
const OFFLINE_CAP_EXT := 24.0 * 3600.0    # 图鉴 ≥145 种（溶洞站同款里程碑）扩到 24h：旅程后期特权
const OFFLINE_EFFICIENCY := 0.5           # 离线效率 50%
const OVERFLOW_SELL_RATE := 0.5       # 满篓兜底：自动折价兑换比例（调研 3.2，避免满篓硬截断惩罚挂机）
const AUTO_SELL_COST := 60000         # 鱼贩合约（自动贩卖）一次性买断价：中期 coin sink（rod5 无窝料口径约 16~33 分钟收入，视鱼饵档；探针 2026-07-07，变体收敛后各档收入 −7%~−26% 注意标尺漂移）
const MAX_ECON_VALUE := 1.0e300
const SHORT_NUMBER_UNITS := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg", "Novg"]
var _save_t := 10.0
var _pending_offline := ""               # 仅"满篓没钓到"等无渔获情况用 toast
var _offline_report := {}                # 离线小结：{dur,count,full,value,top,notable[]}

const RELATION_VISIT_INTERVAL := 3.0 * 60.0 * 60.0
var selected_relationship_visit_id := ""
var relationship_visit_session: Dictionary = {}
var relationship_visit_feedback: Dictionary:
	get:
		return relationship_visit_session.get("feedback", {}) as Dictionary
	set(value):
		relationship_visit_session["feedback"] = value
var relationship_visit_notice: String:
	get:
		return str(relationship_visit_session.get("notice", ""))
	set(value):
		relationship_visit_session["notice"] = value
var relationship_picker_open: bool:
	get:
		return str(relationship_visit_session.get("phase", "")) == "picker"
	set(value):
		if value:
			relationship_visit_session["phase"] = "picker"
		elif str(relationship_visit_session.get("phase", "")) == "picker":
			relationship_visit_session["phase"] = "decision"
var _relationship_tick_t := 0.0

# —— 窗口拖动（默认右下角，可拖到任意位置）——
var _dragging := false
var _drag_pending := false
var _drag_grab := Vector2i.ZERO
var _drag_press_screen := Vector2i.ZERO
const DRAG_START_DISTANCE_PX := 6.0
## Godot 的 canvas final_transform 在窗口恢复后可能跨帧波动约 1-4 个物理像素。
## Region 位于透明羽化边缘，向外留这层原生像素余量可避免稳定前短暂裁掉可见边缘。
const WINDOW_REGION_PADDING_PX := 4.0
var _saved_win_pos = null   # Variant：Vector2i 或 null（无存档位置则用右下角默认）
var _panel_dragging := false
var _panel_drag_offset := Vector2.ZERO
var _panel_saved_pos = null  # Variant：Vector2 或 null，记住弹出面板被拖到的位置
var _hud_chips_box: HBoxContainer = null
var _resize_grips: Array = []

# —— Windows 透明覆盖窗的交互/裁剪区状态 ——
# window_set_mouse_passthrough 在 Windows 上由 SetWindowRgn 实现：它既决定命中，也会裁掉绘制。
# 所有写 Region 的路径必须汇入 _apply_window_region，且把 canvas 逻辑坐标转换为窗口物理像素。
var _window_interactive_full := false
var _window_setup_complete := false
var _window_region_sync_queued := false
var _window_region_retry_count := 0

# —— 流动鱼贩（动森 CJ 模式）：随机出现的限时收购，卖价 ×1.5 ——
const MERCHANT_MULT := 1.5
const MERCHANT_DUR := Vector2(60.0, 90.0)        # 停留时长区间(秒)
const MERCHANT_GAP := Vector2(1200.0, 2400.0)    # 两次出现间隔(秒)
const MERCHANT_FIRST := Vector2(180.0, 360.0)    # 首次出现(秒)，让玩家较快见到一次
var _merchant_active := false
var _merchant_t := 0.0                            # 当前阶段剩余秒数

# —— 随机事件（EventData 驱动）：同一时刻最多一个 buff 在场，instant 一次结算。低干扰。——
# 钓点决定可触发的事件池（SpotData.event_pool）；事件效果叠加 wait/value/luck 到结算。
const EVENT_FIRST := Vector2(180.0, 420.0)         # 首个事件出现窗口（让玩家较快见到一次）
var current_spot := SpotData.DEFAULT_SPOT          # 当前钓点
var unlocked_spots: Array = [SpotData.DEFAULT_SPOT]  # 已解锁钓点 id
var seen_spots: Array = [SpotData.DEFAULT_SPOT]      # 已造访过的钓点 id（首访提示用）
var _unlocks_inited := false                       # 载入期静默解锁，运行期才弹解锁提示
var active_event := ""                             # 当前在场的 buff 事件 id（"" = 无）
var _event_buff_t := 0.0                           # 当前 buff 剩余时长
var _event_next_t := 0.0                           # 距下一次事件的倒计时
var day_phase := Weather.DEFAULT_PHASE             # 昼夜时段（由真实时钟派生，零存档）

# —— 测试模式（开发期工具，逻辑见 test_mode.gd）：仅本会话生效、不写档；切回游玩即还原正式档 ——
@export var test_mode := false   # 可在 Main 节点 Inspector 勾选；启动后读档并冻结写档
var _forced_phase := ""          # 非空＝测试强制时段，_tick_phase 不再被真实时钟覆盖
var test_speed := 1.0            # 测试提速：钓鱼等待/咬钩时长除以此值（1=正常）
var _test_order_nonce := 0       # 测试重置订单的扰动子（绕开当日确定性种子）
var _test_pick_fish := ""        # 测试台「给鱼」记住的鱼种/星级/变体（重建面板不丢选择）
var _test_pick_q := 0
var _test_pick_var := 0
var test_feature_panel_open := false
var test_feature_manual_override := false

# —— 每日订单：每天 1 单，交付指定鱼种，按原价 ×2.5 结算 ——
const DAILY_ORDER_MULT := 2.5
var daily_order := {}  # {"date": yyyy-mm-dd, "fish": id, "need": int, "done": bool}

# —— 周目标：滚动 7 天大挑战（累计渔获或卖鱼达标领大奖），日常之上的长期层 ——
var weekly := {}  # {week:int, kind:"catches"/"coins", target, base, reward, done}
var competition := {}  # {week, fish, best:本周现钓最佳, claimed, reward}（每周巨物赛）
var day_stat := {}  # {date, catches, coins} 当日起点快照，用于"今日渔获/收入"

# —— 专注奖励（Task 5）：窗口失焦 + 无操作 = 你在别处忙，累计连续专注时长；
# 达 25/50 分钟阈值 → 下一竿强制升级（保底高星 / 保底鎏金变体），给"一直开着"一个正向理由。
# 与手动「专注/安静模式」(focus_mode) 是两回事：那是少打扰开关，这是离开时的惊喜渔获。
const FOCUS_T1 := 25.0 * 60.0          # 25 分钟 → 保底极品★★
const FOCUS_T2 := 50.0 * 60.0          # 50 分钟 → 再保底鎏金变体
const FOCUS_REWARD_DAILY_CAP := 4      # 每日封顶，防刷
var _window_focused := true            # 窗口是否聚焦（FOCUS_IN/OUT 通知维护）
var _focus_away_t := 0.0               # 当前连续失焦累计秒（宽限窗外操作折算保留 80%）
var _focus_grace_t := 0.0              # 回焦宽限窗剩余秒：窗内点击不折算专注（容纳快速卖鱼一趟）
var _focus_granted := 0                # 本段已「实际发放」的最高档（0=无 1=25min 2=50min）——
									   # 记事实而非从时长反推：封顶期间越阈未发的档不能被误标已发
var focus_pending := 0                 # 待兑奖励等级（0 无 / 1 高星 / 2 鎏金），下一竿消费
var focus_minutes_total := 0.0         # 累计专注分钟（成就/统计）
var focus_reward_today := 0            # 今日已发奖励次数（封顶）
var focus_reward_date := ""            # 今日封顶计数对应日期
var _idle_t := 0.0                     # 距上次操作的秒数（渔夫打盹 / 专注无操作判定）

# —— 桌面宠物（Task 4）：渔夫旁的小馋猫，上鱼时偶尔扒拉，小概率叼走最廉价的一条当趣味事件 ——
const PET_STEAL_CHANCE := 0.02         # 每次上鱼的偷鱼概率
const PET_STEAL_MAX_VALUE := 30        # 只偷便宜杂鱼（卖价 ≤ 此值），珍藏绝不动
var pet_steals := 0                    # 被叼走的鱼计数（成就/趣味）

const TANK_TAB := 6                    # 鱼篓面板「鱼缸」页签下标（names 第 7 项）
const FEATURE_NAV := [
	{"id": "bag", "label": "鱼篓", "tab": 0, "icon": "res://assets/art/ui/nav_basket.png"},
	{"id": "gear", "label": "装备", "tab": 7, "icon": "res://assets/art/ui/nav_equip.png"},
	{"id": "dex", "label": "图鉴", "tab": 1, "icon": "res://assets/art/ui/nav_dex.png"},
	{"id": "tasks", "label": "任务", "tab": 2, "icon": "res://assets/art/ui/nav_orders.png"},
	{"id": "spots", "label": "钓点", "tab": 5, "icon": "res://assets/art/ui/nav_spots.png"},
	{"id": "tank", "label": "鱼缸", "tab": 6, "icon": "res://assets/art/ui/nav_fishtank.png"},
	{"id": "relations", "label": "人情", "tab": 9, "icon": ""},
	{"id": "settings", "label": "设置", "tab": 8, "icon": "res://assets/art/ui/nav_settings.png"},
]
const FEATURE_TOASTS := {
	"bag": "鱼篓开放：钓到的鱼可以集中查看了，攒够后去贩卖。",
	"gear": "装备开放：卖鱼收入达到 300，可以升级钓具了。",
	"tasks": "任务开放：装备投入达到 10K，每日目标开始出现。",
	"dex": "图鉴开放：第一个钓点已记录一半鱼种。",
	"spots": "钓点开放：新的地图条件已满足，可以换地方钓鱼了。",
	"tank": "鱼缸开放：钓到极品鱼，可以挑珍品展示了。",
	"relations": "人情簿开放：河湾的熟人开始留话给你了。",
}


func _feature_unlocked(id: String) -> bool:
	if id == "settings":
		return true
	return bool(feature_unlocks.get(id, false))


func _tab_unlocked(tab: int) -> bool:
	for n in FEATURE_NAV:
		if int(n["tab"]) == tab:
			return _feature_unlocked(str(n["id"]))
	return tab in [3, 4]  # 成就 / 统计仍是内部页，不放进底栏渐进开放


func _feature_nav_defs() -> Array:
	var out: Array = []
	for n in FEATURE_NAV:
		if _feature_unlocked(str(n["id"])):
			out.append(n)
	return out


func _fallback_feature_tab() -> int:
	for n in _feature_nav_defs():
		return int(n["tab"])
	return 8


func _normalize_feature_unlocks() -> void:
	if not (feature_unlocks is Dictionary):
		feature_unlocks = {}
	feature_unlocks["settings"] = true
	for n in FEATURE_NAV:
		var id := str(n["id"])
		if not feature_unlocks.has(id):
			feature_unlocks[id] = id == "settings"


func _unlock_feature(id: String, silent := false) -> bool:
	_normalize_feature_unlocks()
	if _feature_unlocked(id):
		return false
	feature_unlocks[id] = true
	if not silent:
		_toast(str(FEATURE_TOASTS.get(id, "%s 已开放" % id)), 3.0, Color(0.86, 0.76, 0.45))
	if display_mode == "framed":
		_rebuild_bottom_nav()
	return true


func _has_quality_fish(min_q: int) -> bool:
	if best_quality >= min_q:
		return true
	for c in inventory:
		if int((c as Dictionary).get("q", 0)) >= min_q:
			return true
	for c in display:
		if int((c as Dictionary).get("q", 0)) >= min_q:
			return true
	return false


func _first_spot_dex_half_done() -> bool:
	var pool := SpotData.pool_for(SpotData.DEFAULT_SPOT)
	if pool.is_empty():
		return false
	var have := 0
	for id in pool:
		if dex.has(str(id)):
			have += 1
	var need := int(ceil(float(pool.size()) * 0.5))
	return have >= need


func _second_spot_unlock_met() -> bool:
	if SpotData.SPOT_ORDER.size() < 2:
		return false
	var sid := str(SpotData.SPOT_ORDER[1])
	return sid in unlocked_spots or SpotData.unlock_met(sid, lifetime_catches, lifetime_coins, dex.size())


func _ensure_feature_unlocks(silent := false) -> void:
	_normalize_feature_unlocks()
	if test_feature_manual_override:
		return
	if lifetime_catches >= 3:
		_unlock_feature("bag", silent)
	if lifetime_coins >= 300.0:
		_unlock_feature("gear", silent)
	if feature_spend_equipment >= 10000.0:
		_unlock_feature("tasks", silent)
	if _first_spot_dex_half_done():
		_unlock_feature("dex", silent)
	if _second_spot_unlock_met():
		_unlock_feature("spots", silent)
	if _has_quality_fish(2):
		_unlock_feature("tank", silent)
	if lifetime_catches >= 3:
		_unlock_feature("relations", silent)


func _ensure_relationship_state() -> void:
	if not (relationship_state is Dictionary) or relationship_state.is_empty():
		relationship_state = RelationshipDataScript.default_state()
	if not (relationship_state.get("visits", {}) is Dictionary):
		relationship_state["visits"] = {}
	var legacy_next := maxf(0.0, float(relationship_state.get("next_visit_at", 0.0)))
	var legacy_seq := maxi(0, int(relationship_state.get("visit_seq", 0)))
	var npc_state: Dictionary = relationship_state.get("npc", {})
	for i in range(RelationshipDataScript.NPCS.size()):
		var id := str(RelationshipDataScript.NPCS[i]["id"])
		var state: Dictionary = npc_state.get(id, {})
		state["favor"] = clampi(int(state.get("favor", 0)), 0, RelationshipDataScript.FAVOR_LEVELS.size() - 1)
		state["finale_done"] = bool(state.get("finale_done", false))
		state["story_seen"] = clampi(int(state.get("story_seen", -1)), -1, RelationshipDataScript.STORY_LEVEL_MAX)
		state["next_visit_at"] = maxf(0.0, float(state.get("next_visit_at", legacy_next)))
		state["visit_seq"] = maxi(0, int(state.get("visit_seq", legacy_seq + i)))
		npc_state[id] = state
	relationship_state["npc"] = npc_state
	relationship_state.erase("next_visit_at")
	relationship_state.erase("visit_seq")
	var unlocks: Dictionary = relationship_state.get("unlocks", {})
	for npc in RelationshipDataScript.NPCS:
		var id := str(npc["id"])
		var reward_id := RelationshipDataScript.finale_reward_id(id)
		if reward_id != "" and bool((npc_state.get(id, {}) as Dictionary).get("finale_done", false)):
			unlocks[reward_id] = true
	relationship_state["unlocks"] = unlocks
	if not (relationship_state.get("buff", {}) is Dictionary):
		relationship_state["buff"] = {}


func _relationship_buff_npc() -> String:
	_ensure_relationship_state()
	var buff: Dictionary = relationship_state.get("buff", {})
	if float(buff.get("t", 0.0)) <= 0.0:
		return ""
	var npc_id := str(buff.get("npc", ""))
	return npc_id if not RelationshipDataScript.buff_for(npc_id).is_empty() else ""


func _relationship_buff_wait_mult() -> float:
	var npc_id := _relationship_buff_npc()
	return RelationshipDataScript.buff_wait_mult(npc_id) if npc_id != "" else 1.0


func _relationship_buff_value_mult() -> float:
	var npc_id := _relationship_buff_npc()
	return RelationshipDataScript.buff_value_mult(npc_id) if npc_id != "" else 1.0


func _relationship_buff_luck() -> int:
	var npc_id := _relationship_buff_npc()
	return RelationshipDataScript.buff_luck(npc_id) if npc_id != "" else 0


func _relationship_buff_variant_bias() -> float:
	var npc_id := _relationship_buff_npc()
	return RelationshipDataScript.buff_variant_bias(npc_id) if npc_id != "" else 0.0


func _relationship_buff_label() -> String:
	var npc_id := _relationship_buff_npc()
	return RelationshipDataScript.buff_name(npc_id) if npc_id != "" else ""


func _tick_relationship_buff(delta: float) -> void:
	_ensure_relationship_state()
	var buff: Dictionary = relationship_state.get("buff", {})
	if buff.is_empty():
		return
	var t := float(buff.get("t", 0.0)) - delta
	if t <= 0.0:
		relationship_state["buff"] = {}
		_toast("人情帮忙结束了", 2.0, Color(0.62, 0.70, 0.74))
		_update_hud()
		return
	buff["t"] = t
	relationship_state["buff"] = buff


func _accept_relationship_buff() -> void:
	if not (relationship_visit_session.get("feedback", {}) as Dictionary).is_empty():
		return
	_ensure_relationship_state()
	var npc_id := selected_relationship_visit_id
	var visits: Dictionary = relationship_state.get("visits", {})
	var visit: Dictionary = visits.get(npc_id, {})
	if not _relationship_visit_session_matches(npc_id, visit):
		return
	if visit.is_empty() or str(visit.get("kind", "")) != "buff":
		_toast("这次到访没有可领取的帮忙", 2.0, Color(0.95, 0.55, 0.45))
		return
	visits.erase(npc_id)
	relationship_state["visits"] = visits
	relationship_state["buff"] = {"npc": npc_id, "t": RelationshipDataScript.BUFF_DURATION}
	Audio.play_sfx("upgrade")
	_begin_wait()
	_save()
	_show_relationship_feedback("好，这阵子我替你盯着。\n获得「%s」。" %
		RelationshipDataScript.buff_name(npc_id), "good")


func _decline_relationship_buff() -> void:
	if not (relationship_visit_session.get("feedback", {}) as Dictionary).is_empty():
		return
	_ensure_relationship_state()
	var npc_id := selected_relationship_visit_id
	var visits: Dictionary = relationship_state.get("visits", {})
	var visit: Dictionary = visits.get(npc_id, {})
	if not _relationship_visit_session_matches(npc_id, visit):
		return
	if visit.is_empty() or str(visit.get("kind", "")) != "buff":
		return
	visits.erase(npc_id)
	relationship_state["visits"] = visits
	_save()
	_show_relationship_feedback("没事，需要时再喊我。", "neutral")


func _relationship_now() -> float:
	return Time.get_unix_time_from_system()


func _relationship_visit_for(npc_id: String, seq: int, created_at: float) -> Dictionary:
	var npc_state: Dictionary = relationship_state.get("npc", {})
	var state: Dictionary = npc_state.get(npc_id, {})
	var favor := int(state.get("favor", 0))
	if favor >= RelationshipDataScript.FAVOR_LEVELS.size() - 1 \
			and not bool(state.get("finale_done", false)):
		return RelationshipDataScript.make_visit(npc_id, "finale", created_at)
	var story_level := RelationshipDataScript.next_story_level(state)
	if story_level >= 0:
		return RelationshipDataScript.make_visit(npc_id, "story", created_at, story_level)
	var kinds := RelationshipDataScript.repeat_visit_kinds(favor)
	return RelationshipDataScript.make_visit(npc_id, str(kinds[seq % kinds.size()]), created_at)


func _sync_relationship_visits(show_toast := true) -> bool:
	_ensure_relationship_state()
	if not _feature_unlocked("relations"):
		return false
	var visits: Dictionary = relationship_state.get("visits", {})
	var npc_state: Dictionary = relationship_state.get("npc", {})
	var now := _relationship_now()
	var schedule_initialized := false
	for npc in RelationshipDataScript.NPCS:
		if float((npc_state.get(str(npc["id"]), {}) as Dictionary).get("next_visit_at", 0.0)) > 0.0:
			schedule_initialized = true
			break
	if not schedule_initialized:
		for i in range(RelationshipDataScript.NPCS.size()):
			var id := str(RelationshipDataScript.NPCS[i]["id"])
			var state: Dictionary = npc_state[id]
			state["next_visit_at"] = now if i == 0 else now + RELATION_VISIT_INTERVAL
			npc_state[id] = state
	var changed := false
	for npc in RelationshipDataScript.NPCS:
		var npc_id := str(npc["id"])
		var state: Dictionary = npc_state[npc_id]
		var next_at := float(state.get("next_visit_at", 0.0))
		if next_at <= 0.0 or now < next_at:
			continue
		var elapsed_cycles := maxi(1, int(floor((now - next_at) / RELATION_VISIT_INTERVAL)) + 1)
		var seq := maxi(0, int(state.get("visit_seq", 0)))
		var latest_seq := seq + elapsed_cycles - 1
		var created_at := next_at + float(elapsed_cycles - 1) * RELATION_VISIT_INTERVAL
		visits[npc_id] = _relationship_visit_for(npc_id, latest_seq, created_at)
		state["visit_seq"] = seq + elapsed_cycles
		state["next_visit_at"] = next_at + float(elapsed_cycles) * RELATION_VISIT_INTERVAL
		npc_state[npc_id] = state
		changed = true
	relationship_state["visits"] = visits
	relationship_state["npc"] = npc_state
	if changed and show_toast:
		_toast("有人到访：人情簿里多了新消息", 2.6, Color(0.86, 0.76, 0.45))
	return changed


func _tick_relationship_visits(delta: float) -> void:
	if not _feature_unlocked("relations"):
		return
	_relationship_tick_t -= delta
	if _relationship_tick_t > 0.0:
		return
	_relationship_tick_t = 1.0
	if _sync_relationship_visits():
		_update_relationship_visit_bar()


func _record_equipment_spend(cost) -> void:
	feature_spend_equipment = _econ_sum(feature_spend_equipment, cost)
	_ensure_feature_unlocks()


func _ready() -> void:
	rng.randomize()
	Engine.max_fps = max_fps  # 默认 120 流畅优先；存档载入后按玩家设置覆盖
	get_tree().set_auto_accept_quit(false)  # 退出前存档
	_setup_theme()
	_apply_display_mode()   # 按 framed / immersive 布置场景 + 羽化
	toast_label.size = Vector2(440, 28)
	if display_mode == "immersive":
		_setup_immersive_hud()
	else:
		_build_framed_chrome()
		_build_resize_grips()   # 无边框窗口的自绘缩放手柄（边/角拖拽 → 等比改尺寸）
	_apply_hud_legibility()
	await _setup_window()
	_load_ui_layout()
	# 载档前先定昼夜时段：作为离线分段结算（_offline_phase_slices）后 day_phase 的恢复基准，
	# 也保证结算前 Spots/Weather 读到真实时段而非默认白昼。
	day_phase = Weather.current_phase()
	_load_save()
	_ensure_relationship_state()
	_initial_load_complete = true
	# immersive 的系统窗口位置来自存档；窗口初始化先于载档以消除启动竞态，载入后补一次定位。
	if DisplayServer.get_name() != "headless" and display_mode == "immersive" \
			and _saved_win_pos != null and _pos_on_screen(_saved_win_pos):
		DisplayServer.window_set_position(_clamp_win_to_screen(_saved_win_pos))
	if test_mode:
		if DisplayServer.get_name() == "headless":
			test_mode = false
		else:
			save_enabled = false
	_layout_widget()
	_refresh_unlocks()  # 载入期静默补登已满足解锁的钓点
	_ensure_feature_unlocks(true)
	_sync_relationship_visits(false)
	_update_relationship_visit_bar()
	# 底栏在载档前已创建；老档中的既有解锁不会再次触发 _unlock_feature，需按载入真值重建一次。
	if display_mode == "framed":
		_rebuild_bottom_nav()
	_ensure_day_stat()  # 先沉淀"昨日收入"锚再重建周字典——跨周首启是周奖励重建的主路径，
						# 顺序反了会把锚读成"上上个游玩日"（对抗审查 should-fix）
	_ensure_daily_order()
	_ensure_weekly()
	_ensure_competition()
	_build_buttons()
	# 时段已在载档前确定，此处喂给 painter（决定时段底图），再切钓点底图，避免开局触发 90s 慢淡入
	if painter.has_method("set_phase_tint"):
		painter.set_phase_tint(Weather.tint(day_phase), day_phase)
	_apply_spot_visuals()
	_merchant_t = rng.randf_range(MERCHANT_FIRST.x, MERCHANT_FIRST.y)
	if active_event == "":  # 存档可能恢复了在场事件，则不重排首个事件
		_event_next_t = rng.randf_range(EVENT_FIRST.x, EVENT_FIRST.y)
	_update_hud()
	_begin_wait()
	_unlocks_inited = true
	_started = true
	Audio.set_ambience_scene(current_spot, day_phase)
	# 【修改】首启顺序：先讲背包客的故事(story) → 选角色(character) → 再进原有 tips 引导(intro)。
	# 老档 chosen_character 默认 true（迁移兜底），不会被拉回选人页；只有全新档会走这条新链路。
	if not chosen_character and lifetime_catches == 0 and DisplayServer.get_name() != "headless":
		_open_panel("story")  # 【新增】全新玩家：先看开场世界观动画
	elif not seen_intro and lifetime_catches == 0 and DisplayServer.get_name() != "headless":
		_open_panel("intro")  # 全新玩家首启引导（无头测试不弹）
	elif not _offline_report.is_empty():
		_open_panel("offline")
	elif _pending_offline != "":
		_toast(_pending_offline, 4.5, Color(0.55, 0.85, 0.55))
		_pending_offline = ""
	if display_mode != "immersive" and test_mode:
		_set_dev_attrs_open(true)


# ============================ 窗体形态 ============================

func _setup_window() -> void:
	if DisplayServer.get_name() == "headless":
		_window_setup_complete = true
		return
	var w := get_window()
	if display_mode == "immersive":
		RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
		w.transparent_bg = true
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
		w.borderless = true
		w.always_on_top = true
		await get_tree().process_frame
		if _saved_win_pos != null and _pos_on_screen(_saved_win_pos):
			DisplayServer.window_set_position(_clamp_win_to_screen(_saved_win_pos))
		else:
			_place_corner()  # 无存档位置 / 离屏 → 回右下角
	else:
		# 透明覆盖窗：普通无边框窗口铺满当前屏幕可用区，不触发 macOS 系统全屏 Space。
		RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
		w.transparent_bg = true
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
		w.borderless = true
		w.always_on_top = true
		await get_tree().process_frame
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(usable.position)
		DisplayServer.window_set_size(usable.size)
		await get_tree().process_frame
		_widget_pos = null
		_layout_widget()
	_window_setup_complete = true
	_apply_window_region()


# —— 显示模式布置 ——
var auto_cast := true            # 自动垂钓开关（默认开=原自动行为；关=手动起竿/起钩）
var _action_btn: Button = null   # 带框模式底部「起竿/起钩」按钮
# 带框 HUD 引用（胶囊 + 状态标签）
var _chip_coin: Label = null
var _chip_bag: Label = null
var _chip_dex: Label = null
var _flag_box: VBoxContainer = null
var _relationship_visit_bar: VBoxContainer = null
var _nav_badges := {}   # 导航徽章 {tab: PanelContainer}（鱼篓满/任务可交付）
var _nav_bar: PanelContainer = null   # 底栏容器（背景随面板开关切透明/暗，避免与 sheet 断裂）
var _dev_tools_bar: PanelContainer = null
var _dev_attrs_panel: PanelContainer = null
var _dev_attrs_open := true
var _feature_mgmt_panel: PanelContainer = null
var _feature_mgmt_open := false
var _relationship_debug_panel: PanelContainer = null
var _relationship_debug_open := false
var _dev_pet_state := "无"

func _apply_display_mode() -> void:
	if display_mode == "immersive":
		painter.scale = Vector2.ONE
		painter.position = SCENE_OFF
		if painter.material is ShaderMaterial:
			var fmat := painter.material as ShaderMaterial
			fmat.set_shader_parameter("center", FEATHER_CENTER + SCENE_OFF)
			fmat.set_shader_parameter("radii", FEATHER_RADII)
			fmat.set_shader_parameter("core", FEATHER_CORE)
	else:
		painter.material = null   # 关羽化，场景实心填窗
		_layout_widget()


func _stage_size() -> Vector2:
	return get_viewport_rect().size

func _widget_size() -> Vector2:
	return ART * ui_scale


func _default_widget_pos() -> Vector2:
	var margin := Vector2(24, 24)
	return _stage_size() - _widget_size() - margin


func _clamp_widget_pos(pos: Vector2) -> Vector2:
	var max_pos := _stage_size() - _widget_size()
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, max_pos.x)),
		clampf(pos.y, 0.0, maxf(0.0, max_pos.y)))


func _ensure_widget_pos() -> void:
	if _widget_pos == null:
		_widget_pos = _default_widget_pos()
	_widget_pos = _clamp_widget_pos(_widget_pos)


func _widget_point(p: Vector2) -> Vector2:
	_ensure_widget_pos()
	return (_widget_pos as Vector2) + p * ui_scale


func _layout_widget() -> void:
	if display_mode == "immersive":
		return
	_ensure_widget_pos()
	var s := Vector2(ui_scale, ui_scale)
	painter.scale = s
	painter.position = _widget_pos as Vector2
	toast_label.position = _widget_point(Vector2((ART.x - 440.0) * 0.5, ART.y - FRAMED_CONSOLE_H - 120.0))
	toast_label.scale = s
	if is_instance_valid(_hud_chips_box):
		_hud_chips_box.position = _widget_point(Vector2(16, 12))
		_hud_chips_box.scale = s
	if is_instance_valid(_flag_box):
		_flag_box.position = _widget_point(Vector2(0, 12))
		_flag_box.size = Vector2(ART.x - 16.0, 0)
		_flag_box.scale = s
	if is_instance_valid(_relationship_visit_bar):
		_relationship_visit_bar.position = _widget_point(Vector2(ART.x - 48.0, 132.0))
		_relationship_visit_bar.scale = s
	if is_instance_valid(_nav_bar):
		_nav_bar.position = _widget_point(Vector2(0, ART.y - FRAMED_CONSOLE_H))
		_nav_bar.size = Vector2(ART.x, FRAMED_CONSOLE_H)
		_nav_bar.scale = s
	if is_instance_valid(_dev_tools_bar):
		_dev_tools_bar.position = Vector2.ZERO
		_dev_tools_bar.size = Vector2(96, 114)
		_dev_tools_bar.scale = Vector2.ONE
	if is_instance_valid(_dev_attrs_panel):
		var attrs_pos := Vector2(104, 0)
		var attrs_bottom := _stage_size().y
		_dev_attrs_panel.position = attrs_pos
		_dev_attrs_panel.size = Vector2(360, maxf(240.0, attrs_bottom - attrs_pos.y))
	if is_instance_valid(_feature_mgmt_panel):
		var feature_pos := Vector2(104, 0)
		_feature_mgmt_panel.position = feature_pos
		_feature_mgmt_panel.size = Vector2(360, maxf(240.0, _stage_size().y - feature_pos.y))
	if is_instance_valid(_relationship_debug_panel):
		var rel_pos := Vector2(104, 0)
		_relationship_debug_panel.position = rel_pos
		_relationship_debug_panel.size = Vector2(380, maxf(240.0, _stage_size().y - rel_pos.y))
	_update_action_button()
	_layout_resize_grips()
	if _panel_kind == "":
		_set_window_interaction(false)


## 场景内 art 坐标 → 屏幕坐标（含带框缩放/偏移），飘字/落水定位用。
func _scene_pt(art: Vector2) -> Vector2:
	return painter.position + art * painter.scale


func _setup_immersive_hud() -> void:
	coins_label.position = SCENE_OFF + Vector2(196, 150)
	coins_label.mouse_filter = Control.MOUSE_FILTER_STOP
	coins_label.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_catch_tab = 0 if _tab_unlocked(0) else _fallback_feature_tab()
			_toggle_panel("catch"))
	toast_label.position = SCENE_OFF + Vector2(198, 204)
	_build_spot_chip()
	_build_order_chip()


# —— 带框 App 外壳：底部导航 console + 起竿按钮 + 顶部 HUD ——
func _build_framed_chrome() -> void:
	coins_label.visible = false   # 带框用图标胶囊替代纯文字 HUD
	_build_hud_chips()
	_build_status_flags()
	_build_relationship_visit_bar()
	_build_bottom_nav()
	if test_mode:
		_build_dev_tools_bar()
	_build_action_button()
	_layout_widget()


func _build_dev_tools_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "DevToolsBar"
	bar.z_index = 40
	bar.custom_minimum_size = Vector2(96, 114)
	bar.size = Vector2(96, 114)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.10, 0.72)
	sb.corner_radius_bottom_right = 10
	sb.set_border_width_all(1)
	sb.border_color = DT.GLASS_ROW_BORDER
	bar.add_theme_stylebox_override("panel", sb)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 6)
	mg.add_theme_constant_override("margin_right", 6)
	mg.add_theme_constant_override("margin_top", 6)
	mg.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(mg)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	mg.add_child(stack)
	var attrs := Button.new()
	attrs.text = "属性管理"
	attrs.focus_mode = Control.FOCUS_NONE
	attrs.custom_minimum_size = Vector2(84, 30)
	UIPanels.apply_button_skin(attrs, false)
	attrs.pressed.connect(func() -> void: _set_dev_attrs_open(not _dev_attrs_open))
	stack.add_child(attrs)
	var features := Button.new()
	features.text = "功能管理"
	features.focus_mode = Control.FOCUS_NONE
	features.custom_minimum_size = Vector2(84, 30)
	UIPanels.apply_button_skin(features, false)
	features.pressed.connect(func() -> void: _set_feature_mgmt_open(not _feature_mgmt_open))
	stack.add_child(features)
	var relations := Button.new()
	relations.text = "人情模块"
	relations.focus_mode = Control.FOCUS_NONE
	relations.custom_minimum_size = Vector2(84, 30)
	UIPanels.apply_button_skin(relations, false)
	relations.pressed.connect(func() -> void: _set_relationship_debug_open(not _relationship_debug_open))
	stack.add_child(relations)
	ui_root.add_child(bar)
	_dev_tools_bar = bar
	_build_dev_attrs_panel()
	_build_feature_mgmt_panel()
	_build_relationship_debug_panel()


func _build_dev_attrs_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "DevAttrsPanel"
	panel.z_index = 41
	panel.custom_minimum_size = Vector2(360, 240)
	panel.size = Vector2(360, 720)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.08, 0.84)
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.set_border_width_all(1)
	sb.border_color = DT.GLASS_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", sb)
	ui_root.add_child(panel)
	_dev_attrs_panel = panel
	_refresh_dev_attrs_panel()
	panel.visible = _dev_attrs_open


func _set_dev_attrs_open(open: bool) -> void:
	_dev_attrs_open = open
	if display_mode == "immersive":
		return
	if open:
		_set_feature_mgmt_open(false)
		_set_relationship_debug_open(false)
	if not is_instance_valid(_dev_attrs_panel):
		_build_dev_attrs_panel()
		return
	_dev_attrs_panel.visible = open
	if open:
		_refresh_dev_attrs_panel()
	_layout_widget()


func _build_feature_mgmt_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "FeatureManagementPanel"
	panel.z_index = 41
	panel.custom_minimum_size = Vector2(360, 240)
	panel.size = Vector2(360, 520)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.08, 0.84)
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.set_border_width_all(1)
	sb.border_color = DT.GLASS_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", sb)
	ui_root.add_child(panel)
	_feature_mgmt_panel = panel
	_refresh_feature_mgmt_panel()
	panel.visible = _feature_mgmt_open


func _set_feature_mgmt_open(open: bool) -> void:
	_feature_mgmt_open = open
	test_feature_panel_open = open
	if display_mode == "immersive":
		return
	if open:
		_set_dev_attrs_open(false)
		_set_relationship_debug_open(false)
	if not is_instance_valid(_feature_mgmt_panel):
		_build_feature_mgmt_panel()
		return
	_feature_mgmt_panel.visible = open
	if open:
		_refresh_feature_mgmt_panel()
	_layout_widget()


func _refresh_feature_mgmt_panel() -> void:
	if not is_instance_valid(_feature_mgmt_panel):
		return
	for c in _feature_mgmt_panel.get_children():
		c.free()
	var mg := MarginContainer.new()
	mg.set_anchors_preset(Control.PRESET_FULL_RECT)
	mg.add_theme_constant_override("margin_left", 8)
	mg.add_theme_constant_override("margin_right", 8)
	mg.add_theme_constant_override("margin_top", 8)
	mg.add_theme_constant_override("margin_bottom", 8)
	_feature_mgmt_panel.add_child(mg)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mg.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	var title := Label.new()
	title.text = "功能管理"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", DT.GOLD_BRIGHT)
	v.add_child(title)
	var note := Label.new()
	note.text = "测试模式本会话生效；设置固定开放，其它系统可直接开关。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(note)
	for n in FEATURE_NAV:
		var fid := str(n["id"])
		if fid == "settings":
			continue
		_add_feature_mgmt_row(v, fid, str(n["label"]))


func _add_feature_mgmt_row(v: VBoxContainer, fid: String, label: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 32)
	v.add_child(row)
	var name := Label.new()
	name.text = label
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	row.add_child(name)
	var sw := CheckButton.new()
	sw.text = "开"
	sw.button_pressed = _feature_unlocked(fid)
	sw.focus_mode = Control.FOCUS_NONE
	sw.custom_minimum_size = Vector2(74, 28)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.add_theme_font_size_override("font_size", 12)
	sw.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	sw.add_theme_color_override("font_pressed_color", DT.GOLD_BRIGHT)
	sw.toggled.connect(func(on: bool) -> void: TestMode.set_feature_unlock(self, fid, on))
	row.add_child(sw)


func _build_relationship_debug_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "RelationshipDebugPanel"
	panel.z_index = 41
	panel.custom_minimum_size = Vector2(380, 240)
	panel.size = Vector2(380, 640)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.08, 0.84)
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.set_border_width_all(1)
	sb.border_color = DT.GLASS_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", sb)
	ui_root.add_child(panel)
	_relationship_debug_panel = panel
	_refresh_relationship_debug_panel()
	panel.visible = _relationship_debug_open


func _set_relationship_debug_open(open: bool) -> void:
	_relationship_debug_open = open
	if display_mode == "immersive":
		return
	if open:
		_set_dev_attrs_open(false)
		_set_feature_mgmt_open(false)
	if not is_instance_valid(_relationship_debug_panel):
		_build_relationship_debug_panel()
		return
	_relationship_debug_panel.visible = open
	if open:
		_refresh_relationship_debug_panel()
	_layout_widget()


func _refresh_relationship_debug_panel() -> void:
	if not is_instance_valid(_relationship_debug_panel):
		return
	for c in _relationship_debug_panel.get_children():
		c.free()
	var mg := MarginContainer.new()
	mg.set_anchors_preset(Control.PRESET_FULL_RECT)
	mg.add_theme_constant_override("margin_left", 8)
	mg.add_theme_constant_override("margin_right", 8)
	mg.add_theme_constant_override("margin_top", 8)
	mg.add_theme_constant_override("margin_bottom", 8)
	_relationship_debug_panel.add_child(mg)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mg.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	UIPanels.fill_relationship_debug_panel(self, v)


func _refresh_dev_attrs_panel() -> void:
	if not is_instance_valid(_dev_attrs_panel):
		return
	for c in _dev_attrs_panel.get_children():
		c.free()
	var mg := MarginContainer.new()
	mg.set_anchors_preset(Control.PRESET_FULL_RECT)
	mg.add_theme_constant_override("margin_left", 6)
	mg.add_theme_constant_override("margin_right", 6)
	mg.add_theme_constant_override("margin_top", 6)
	mg.add_theme_constant_override("margin_bottom", 6)
	_dev_attrs_panel.add_child(mg)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mg.add_child(sc)
	var v := VBoxContainer.new()
	v.name = "V"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 5)
	sc.add_child(v)
	UIPanels.fill_debug_attributes(self, v)


## 图标胶囊：[圆角底 + 图标 + 数值]，返回 [PanelContainer, 数值Label]
func _make_hud_chip(icon_path: String) -> Array:
	# 照抄 CD .chip：height 30 / padding 0 11 / bg rgba(20,22,20,.7) / border glass-row-border
	#   / font 13 weight600 / img 17 / shadow 0 2px 8px / color text-on-glass
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0784, 0.0863, 0.0784, 0.70)   # rgba(20,22,20,.7)
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.set_border_width_all(1)
	sb.border_color = DT.GLASS_ROW_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	pc.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)     # CD gap 6
	pc.add_child(hb)
	if ResourceLoader.exists(icon_path):
		var ic := TextureRect.new()
		ic.texture = load(icon_path)
		ic.custom_minimum_size = Vector2(17, 17)         # CD img 17
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ic)
	var lbl := Label.new()
	lbl.add_theme_font_override("font", _font_bold)       # weight 600 → embolden（落地变通）
	lbl.add_theme_font_size_override("font_size", 13)     # CD 13
	lbl.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)  # #ECE8E0
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lbl)
	return [pc, lbl]


func _build_hud_chips() -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	ui_root.add_child(box)
	_hud_chips_box = box
	var coin := _make_hud_chip("res://assets/art/ui/icon_coin.png")
	box.add_child(coin[0])
	_chip_coin = coin[1]
	_chip_coin.add_theme_color_override("font_color", Color(0.941, 0.788, 0.471))  # gold-bright
	var bag := _make_hud_chip("res://assets/art/equipment/fish_basket.png")
	box.add_child(bag[0])
	_chip_bag = bag[1]
	var dexc := _make_hud_chip("res://assets/art/ui/icon_dex.png")
	box.add_child(dexc[0])
	_chip_dex = dexc[1]


## 金币短格式：低位保逗号；高位用 idle 游戏常见 K/M/B/T/Qa/Qi...，超表后降级科学计数。
func _coin_str(n) -> String:
	var value := float(n)
	var abs_n := absf(value)
	if abs_n >= 10000:
		return _short_number_str(value, 3)
	return _commas(int(round(value)))


func _short_number_str(value: float, sig_digits := 3) -> String:
	if is_nan(value):
		return "0"
	if value == 0.0:
		return "0"
	var abs_v := absf(value)
	var tier := int(floor(log(abs_v) / log(1000.0)))
	if tier <= 0:
		return _commas(int(round(_safe_econ_number(value))))
	if tier >= SHORT_NUMBER_UNITS.size():
		return _sci_str(value, sig_digits)
	var scaled := value / pow(1000.0, tier)
	var abs_scaled := absf(scaled)
	if abs_scaled >= 100.0:
		return "%d%s" % [int(round(scaled)), SHORT_NUMBER_UNITS[tier]]
	if abs_scaled >= 10.0:
		return "%.1f%s" % [snappedf(scaled, 0.1), SHORT_NUMBER_UNITS[tier]]
	return "%.2f%s" % [snappedf(scaled, 0.01), SHORT_NUMBER_UNITS[tier]]


func _sci_str(value: float, sig_digits := 3) -> String:
	if is_nan(value):
		return "0"
	if value == 0.0:
		return "0"
	var sign := "-" if value < 0.0 else ""
	var abs_v := absf(value)
	var exp10 := int(floor(log(abs_v) / log(10.0)))
	var mant := abs_v / pow(10.0, exp10)
	var decimals := maxi(0, sig_digits - 1)
	var rounded := snappedf(mant, pow(10.0, -decimals))
	if rounded >= 10.0:
		rounded /= 10.0
		exp10 += 1
	var text := ("%.*f" % [decimals, rounded]).rstrip("0").rstrip(".")
	return "%s%se%d" % [sign, text, exp10]


## 千分位逗号（复刻 JS toLocaleString 的 en-US 行为）
func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out


func _safe_econ_number(raw: float) -> float:
	if is_nan(raw) or raw <= 0.0:
		return 0.0
	if is_inf(raw) or raw >= MAX_ECON_VALUE:
		return MAX_ECON_VALUE
	return round(raw)


func _safe_econ_int(raw: float) -> float:
	return _safe_econ_number(raw)


func _econ_sum(a, b) -> float:
	return _safe_econ_number(float(a) + maxf(0.0, float(b)))


func _add_coins_safe(amount) -> void:
	coins = _econ_sum(coins, amount)


func _add_lifetime_coins_safe(amount) -> void:
	lifetime_coins = _econ_sum(lifetime_coins, amount)


func _add_auto_sold_value_safe(amount) -> void:
	auto_sold_v = _econ_sum(auto_sold_v, amount)


## 右上状态标签胶囊（钓点/时段/事件/鱼贩）；纯展示、不挡点击。
func _make_flag_pill(text: String, bg: Color, fg: Color, fs := 12, hpad := 11) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_SHRINK_END
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(999)
	sb.content_margin_left = hpad
	sb.content_margin_right = hpad
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font_bold)        # CD 这些都是 weight 600
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", fg)
	# 时段无底色时叠场景上需描边
	if bg.a < 0.05:
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.04, 0.85))
		l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	return pc


func _build_status_flags() -> void:
	var box := VBoxContainer.new()
	box.name = "FlagBox"
	box.add_theme_constant_override("separation", 5)
	box.custom_minimum_size = Vector2(ART.x - 16.0, 0)
	box.size = Vector2(ART.x - 16.0, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(box)
	_flag_box = box
	_update_status_flags()


func _update_status_flags() -> void:
	if not is_instance_valid(_flag_box):
		return
	for c in _flag_box.get_children():
		c.free()
	# 钓点名：.spot-name font13 weight600 text-title bg rgba(20,22,20,.6) padding 5/12
	_flag_box.add_child(_make_flag_pill(SpotData.display_name(current_spot),
		Color(0.0784, 0.0863, 0.0784, 0.6), DT.TEXT_TITLE, 13, 12))
	# 时段：.phase font11 muted 无底
	_flag_box.add_child(_make_flag_pill(Weather.display_name(day_phase),
		Color(0, 0, 0, 0), DT.TEXT_MUTED_GLASS, 11, 4))
	# 事件：.flag.event font11.5 weight600 bg variant-1 color #0e1822 padding 4/9
	if active_event != "" and EventData.hud_text(active_event) != "":
		_flag_box.add_child(_make_flag_pill(EventData.display_name(active_event),
			DT.VARIANT[1], Color(0.055, 0.094, 0.133), 12, 9))
	var rel_buff := _relationship_buff_label()
	if rel_buff != "":
		_flag_box.add_child(_make_flag_pill(rel_buff,
			Color(0.56, 0.44, 0.26), DT.INK_ON_GOLD, 12, 9))
	# 鱼贩：.flag.merchant bg merchant color ink-on-gold
	if _merchant_active:
		_flag_box.add_child(_make_flag_pill("🐟 鱼贩 ×1.5",
			DT.MERCHANT, DT.INK_ON_GOLD, 12, 9))
	# 下一目标（near-miss 常驻可见）：永远只显示一个最近目标，极安静的小字——
	# 挂机的每一分钟都在逼近某个具体的东西，玩家离开时脑子里带着"快到了"。
	var goal := _next_goal_text()
	if goal != "":
		_flag_box.add_child(_make_flag_pill("🎯 " + goal,
			Color(0, 0, 0, 0), Color(0.90, 0.80, 0.55, 0.92), 11, 4))


## 自动选取"最近的下一个目标"文案：顺序上第一个未解锁钓点的进度；全解锁后看本水域图鉴缺口。
func _next_goal_text() -> String:
	for sid in SpotData.SPOT_ORDER:
		if sid in unlocked_spots:
			continue
		var up := SpotData.unlock_progress_pair(sid, lifetime_catches, lifetime_coins, dex.size())
		if up.size() == 2 and int(up[1]) > 0:
			var gap := maxi(0, int(up[1]) - int(up[0]))
			var unit := "条"
			match str((SpotData.get_spot(sid).get("unlock", {}) as Dictionary).get("kind", "")):
				"coins": unit = "金币"
				"species": unit = "种"
			return "下一站 %s · 还差 %d %s" % [SpotData.display_name(sid), gap, unit]
		break   # 最近一个锁定钓点无进度可显示（无条件），不再往后看
	var sp: Array = UIPanels.spot_species_progress(self, current_spot)
	if int(sp[1]) > 0 and int(sp[0]) < int(sp[1]):
		return "集齐本水域 · 还差 %d 种" % (int(sp[1]) - int(sp[0]))
	return ""


func _visit_circle_style(color: Color, alpha := 0.92) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, alpha)
	sb.set_corner_radius_all(999)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.96, 0.91, 0.78, 0.70)
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	return sb


func _build_relationship_visit_bar() -> void:
	var bar := VBoxContainer.new()
	bar.name = "RelationshipVisits"
	bar.z_index = 42
	bar.add_theme_constant_override("separation", 7)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bar)
	_relationship_visit_bar = bar
	_update_relationship_visit_bar()


func _update_relationship_visit_bar() -> void:
	if not is_instance_valid(_relationship_visit_bar):
		return
	for c in _relationship_visit_bar.get_children():
		c.free()
	if not _feature_unlocked("relations"):
		_relationship_visit_bar.visible = false
		return
	_ensure_relationship_state()
	var visits: Dictionary = relationship_state.get("visits", {})
	_relationship_visit_bar.visible = not visits.is_empty()
	for npc in RelationshipDataScript.NPCS:
		var id := str(npc["id"])
		if not visits.has(id):
			continue
		var visit: Dictionary = visits[id]
		var b := Button.new()
		b.text = ""
		b.custom_minimum_size = Vector2(42, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "%s · %s" % [str(npc["name"]), RelationshipDataScript.visit_kind_label(str(visit.get("kind", "hint")))]
		b.add_theme_stylebox_override("normal", _visit_circle_style(npc["color"], 0.88))
		b.add_theme_stylebox_override("hover", _visit_circle_style(npc["color"], 1.0))
		b.add_theme_stylebox_override("pressed", _visit_circle_style(npc["color"], 0.78))
		var portrait := RelationshipPortraitScript.make(npc, "circle")
		portrait.name = "RelationshipPortraitCircle"
		portrait.position = Vector2(1, 1)
		b.add_child(portrait)
		var captured_id := id
		b.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Audio.play_ui("ui_click")
				_open_relationship_visit(captured_id))
		_relationship_visit_bar.add_child(b)


func _relationship_visit_key(npc_id: String, visit: Dictionary) -> String:
	return "%s|%s|%.3f|%d" % [
		npc_id,
		str(visit.get("kind", "hint")),
		float(visit.get("created_at", 0.0)),
		int(visit.get("story_level", -1)),
	]


func _relationship_visit_session_matches(npc_id: String, visit: Dictionary) -> bool:
	return not relationship_visit_session.is_empty() \
		and str(relationship_visit_session.get("npc_id", "")) == npc_id \
		and str(relationship_visit_session.get("visit_key", "")) == _relationship_visit_key(npc_id, visit)


func _begin_relationship_visit_session(npc_id: String) -> void:
	_ensure_relationship_state()
	var visits: Dictionary = relationship_state.get("visits", {})
	var visit: Dictionary = visits.get(npc_id, {})
	if not _relationship_visit_session_matches(npc_id, visit):
		relationship_visit_session = {
			"npc_id": npc_id,
			"visit_key": _relationship_visit_key(npc_id, visit),
			"visit_snapshot": visit.duplicate(true),
			"phase": "decision",
			"player_reply": "",
			"notice": "",
			"feedback": {},
		}
	selected_relationship_visit_id = npc_id


func _end_relationship_visit_session() -> void:
	relationship_visit_session = {}
	selected_relationship_visit_id = ""


func _set_relationship_visit_reply(text: String, phase: String) -> void:
	relationship_visit_session["player_reply"] = text
	relationship_visit_session["phase"] = phase
	relationship_visit_session["notice"] = ""


func _open_relationship_visit(npc_id: String) -> void:
	_begin_relationship_visit_session(npc_id)
	_open_panel("relationship_visit")


func _show_relationship_feedback(text: String, tone := "neutral") -> void:
	if not (relationship_visit_session.get("feedback", {}) as Dictionary).is_empty():
		return
	relationship_visit_session["feedback"] = {"text": text, "tone": tone}
	relationship_visit_session["phase"] = "feedback"
	relationship_visit_session["notice"] = ""
	_update_relationship_visit_bar()
	_update_hud()
	_open_panel("relationship_visit")


func _finish_relationship_visit_feedback() -> void:
	_end_relationship_visit_session()
	_close_panel()


func _complete_relationship_story() -> void:
	if not (relationship_visit_session.get("feedback", {}) as Dictionary).is_empty():
		return
	_ensure_relationship_state()
	var npc_id := selected_relationship_visit_id
	var visits: Dictionary = relationship_state.get("visits", {})
	var visit: Dictionary = visits.get(npc_id, {})
	if not _relationship_visit_session_matches(npc_id, visit):
		return
	if visit.is_empty() or str(visit.get("kind", "")) != "story":
		_toast("这次到访没有未读近况", 2.0, Color(0.95, 0.55, 0.45))
		return
	var npc_state: Dictionary = relationship_state.get("npc", {})
	var state: Dictionary = npc_state.get(npc_id, {})
	var story_level := clampi(int(visit.get("story_level", 0)), 0, RelationshipDataScript.STORY_LEVEL_MAX)
	if story_level != RelationshipDataScript.next_story_level(state):
		visits.erase(npc_id)
		relationship_state["visits"] = visits
		selected_relationship_visit_id = ""
		_toast("这段近况已经读过或尚未解锁", 2.2, Color(0.86, 0.76, 0.45))
		_update_relationship_visit_bar()
		_close_panel()
		_save()
		return
	state["story_seen"] = maxi(int(state.get("story_seen", -1)), story_level)
	npc_state[npc_id] = state
	relationship_state["npc"] = npc_state
	visits.erase(npc_id)
	relationship_state["visits"] = visits
	var event := RelationshipDataScript.level_event_for(npc_id, story_level)
	Audio.play_ui("ui_click")
	_save()
	_show_relationship_feedback("好，那我就放心了。\n已记录：%s" %
		str(event.get("title", "河湾近况")), "good")


func _relationship_gift(idx: int) -> void:
	if not (relationship_visit_session.get("feedback", {}) as Dictionary).is_empty():
		return
	_ensure_relationship_state()
	var npc_id := selected_relationship_visit_id
	var visits: Dictionary = relationship_state.get("visits", {})
	var visit: Dictionary = visits.get(npc_id, {})
	if not _relationship_visit_session_matches(npc_id, visit):
		return
	if not visits.has(npc_id):
		_toast("这次到访已经结束了", 1.8, Color(0.86, 0.76, 0.45))
		_close_panel()
		return
	if idx < 0 or idx >= inventory.size():
		relationship_visit_session["notice"] = "这条鱼已经不在鱼篓里了。"
		_open_panel("relationship_visit")
		return
	relationship_visit_session["notice"] = ""
	var c: Dictionary = inventory[idx]
	var npc := RelationshipDataScript.get_npc(npc_id)
	var accepted := RelationshipDataScript.gift_match(npc_id, c)
	visits.erase(npc_id)
	relationship_state["visits"] = visits
	if accepted:
		inventory.remove_at(idx)
		var npc_state: Dictionary = relationship_state.get("npc", {})
		var state: Dictionary = npc_state.get(npc_id, {"favor": 0, "finale_done": false})
		var old_favor := int(state.get("favor", 0))
		state["favor"] = clampi(old_favor + 1, 0, RelationshipDataScript.FAVOR_LEVELS.size() - 1)
		npc_state[npc_id] = state
		relationship_state["npc"] = npc_state
		Audio.play_sfx("coin")
	else:
		Audio.play_ui("ui_click")
	_save()
	_show_relationship_feedback(RelationshipDataScript.gift_feedback(npc_id, c, accepted),
		"good" if accepted else "reject")


func _relationship_task_reward(c: Dictionary) -> int:
	var base := maxi(1, int(c.get("v", 1)))
	return int(ceil(float(base) * 2.2 * _relationship_buff_value_mult()))


func _complete_relationship_task(idx: int) -> void:
	if not (relationship_visit_session.get("feedback", {}) as Dictionary).is_empty():
		return
	_ensure_relationship_state()
	var npc_id := selected_relationship_visit_id
	var visits: Dictionary = relationship_state.get("visits", {})
	var visit: Dictionary = visits.get(npc_id, {})
	if not _relationship_visit_session_matches(npc_id, visit):
		return
	if visit.is_empty() or str(visit.get("kind", "")) != "task":
		_toast("这次到访没有可交付的委托", 2.0, Color(0.95, 0.55, 0.45))
		return
	if idx < 0 or idx >= inventory.size():
		relationship_visit_session["notice"] = "这条鱼已经不在鱼篓里了。"
		_open_panel("relationship_visit")
		return
	relationship_visit_session["notice"] = ""
	var c: Dictionary = inventory[idx]
	if not RelationshipDataScript.task_match(npc_id, c):
		Audio.play_ui("ui_click")
		relationship_visit_session["notice"] = RelationshipDataScript.task_reject_reason(npc_id, c)
		_open_panel("relationship_visit")
		return
	var reward := _relationship_task_reward(c)
	inventory.remove_at(idx)
	_add_coins_safe(reward)
	_add_lifetime_coins_safe(reward)
	visits.erase(npc_id)
	relationship_state["visits"] = visits
	Audio.play_sfx("coin")
	_check_achievements()
	_save()
	_show_relationship_feedback("正是我要的，多谢。\n委托完成：+%s 金币" % _coin_str(reward), "good")


func _relationship_finale_reward(c: Dictionary) -> int:
	return int(ceil(float(maxi(1, int(c.get("v", 1)))) * 8.0 * _relationship_buff_value_mult()))


func _complete_relationship_finale(idx: int) -> void:
	if not (relationship_visit_session.get("feedback", {}) as Dictionary).is_empty():
		return
	_ensure_relationship_state()
	var npc_id := selected_relationship_visit_id
	var visits: Dictionary = relationship_state.get("visits", {})
	var visit: Dictionary = visits.get(npc_id, {})
	if not _relationship_visit_session_matches(npc_id, visit):
		return
	if visit.is_empty() or str(visit.get("kind", "")) != "finale":
		_toast("这次到访没有可交付的终章大单", 2.0, Color(0.95, 0.55, 0.45))
		return
	var npc_state: Dictionary = relationship_state.get("npc", {})
	var state: Dictionary = npc_state.get(npc_id, {
		"favor": RelationshipDataScript.FAVOR_LEVELS.size() - 1, "finale_done": false})
	if bool(state.get("finale_done", false)):
		visits.erase(npc_id)
		relationship_state["visits"] = visits
		selected_relationship_visit_id = ""
		_toast("这段终章已经完成，永久奖励不会重复领取", 2.4, Color(0.86, 0.76, 0.45))
		_update_relationship_visit_bar()
		_close_panel()
		_save()
		return
	if idx < 0 or idx >= inventory.size():
		relationship_visit_session["notice"] = "这条鱼已经不在鱼篓里了。"
		_open_panel("relationship_visit")
		return
	relationship_visit_session["notice"] = ""
	var c: Dictionary = inventory[idx]
	if not RelationshipDataScript.finale_match(npc_id, c):
		Audio.play_ui("ui_click")
		relationship_visit_session["notice"] = RelationshipDataScript.finale_reject_reason(npc_id, c)
		_open_panel("relationship_visit")
		return
	var reward := _relationship_finale_reward(c)
	if RelationshipDataScript.finale_consumes_catch(npc_id):
		inventory.remove_at(idx)
	_add_coins_safe(reward)
	_add_lifetime_coins_safe(reward)
	visits.erase(npc_id)
	relationship_state["visits"] = visits
	state["favor"] = RelationshipDataScript.FAVOR_LEVELS.size() - 1
	state["finale_done"] = true
	npc_state[npc_id] = state
	relationship_state["npc"] = npc_state
	var unlocks: Dictionary = relationship_state.get("unlocks", {})
	var reward_id := RelationshipDataScript.finale_reward_id(npc_id)
	if reward_id != "":
		unlocks[reward_id] = true
	relationship_state["unlocks"] = unlocks
	Audio.play_sfx("coin")
	_check_achievements()
	_save()
	_show_relationship_feedback("就是这份记录，多谢你带回来。\n终章完成：%s · +%s 金币" % [
		RelationshipDataScript.finale_reward_name(npc_id), _coin_str(reward)], "good")


func _update_framed_hud() -> void:
	if is_instance_valid(_chip_coin):
		_chip_coin.text = _coin_str(coins)
	if is_instance_valid(_chip_bag):
		_chip_bag.text = "%d/%d" % [inventory.size(), _bag_capacity()]
		_chip_bag.add_theme_color_override("font_color",
			Color(1.0, 0.780, 0.451) if _bag_alert() else Color(0.925, 0.910, 0.878))
	if is_instance_valid(_chip_dex):
		_chip_dex.text = "%d/%d" % [dex.size(), FishData.FISH.size()]
	# 导航徽章：鱼篓满「满」 / 任务可交付「!」
	if _nav_badges.has(0) and is_instance_valid(_nav_badges[0]):
		var b0: PanelContainer = _nav_badges[0]
		b0.visible = _bag_alert()
		b0.get_node("L").text = "满"
	if _nav_badges.has(2) and is_instance_valid(_nav_badges[2]):
		var b2: PanelContainer = _nav_badges[2]
		var need := int(daily_order.get("need", 1))
		b2.visible = not bool(daily_order.get("done", false)) and _daily_order_indices().size() >= need
		b2.get_node("L").text = "!"
	_update_status_flags()
	_update_relationship_visit_bar()
	_update_action_button()


func _build_bottom_nav() -> void:
	var bar := PanelContainer.new()
	bar.name = "BottomNav"
	bar.custom_minimum_size = Vector2(ART.x, FRAMED_CONSOLE_H)
	bar.size = Vector2(ART.x, FRAMED_CONSOLE_H)
	bar.add_theme_stylebox_override("panel", _nav_idle_sb())  # 闲置半透明暗底，图标不再糊进浅色场景
	ui_root.add_child(bar)
	_nav_bar = bar
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 14)
	mg.add_theme_constant_override("margin_right", 14)
	mg.add_theme_constant_override("margin_top", 6)
	mg.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(mg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	mg.add_child(row)
	# 图标在上、文字在下（CD 布局）；功能未开放前不占底栏。
	var navs := _feature_nav_defs()
	for n in navs:
		var tab: int = int(n["tab"])
		var item := VBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.alignment = BoxContainer.ALIGNMENT_CENTER
		item.add_theme_constant_override("separation", 2)
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		item.tooltip_text = str(n["label"])
		# 图标：用 CenterContainer 保证水平居中；TextureRect 固定尺寸 + 等比不变形（不再用绝对定位）
		var icon_box := CenterContainer.new()
		icon_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(str(n["icon"])):
			var ic := TextureRect.new()
			ic.texture = load(str(n["icon"]))
			ic.custom_minimum_size = Vector2(44, 44)   # 容器据此给尺寸，等比居中绘制（任务栏空间足，放大更醒目）
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_box.add_child(ic)
			if tab == 0 or tab == 2:   # 鱼篓满 / 任务可交付 → 红角标，叠图标右上
				var badge := _make_nav_badge()
				badge.position = Vector2(35, -3)
				ic.add_child(badge)
				_nav_badges[tab] = badge
		else:
			var placeholder := Label.new()
			placeholder.name = "NavIconPlaceholder_%s" % str(n["id"])
			placeholder.text = str(n["label"]).substr(0, 1)
			placeholder.custom_minimum_size = Vector2(44, 44)
			placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			placeholder.add_theme_font_size_override("font_size", 25)
			placeholder.add_theme_color_override("font_color", Color(0.94, 0.84, 0.62, 0.96))
			placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_box.add_child(placeholder)
		item.add_child(icon_box)
		item.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Audio.play_ui("ui_click")
				if _panel_kind == "catch" and _catch_tab == tab:
					_close_panel()
				else:
					_catch_tab = tab if _tab_unlocked(tab) else _fallback_feature_tab()
					_open_panel("catch"))
		# 功能解锁会 queue_free 整条旧导航；不要用捕获 item 的 lambda，避免卖鱼跨 300 金币时
		# mouse_exited 在节点释放后访问悬空 capture。
		item.mouse_entered.connect(_set_nav_item_hover.bind(item, true))
		item.mouse_exited.connect(_set_nav_item_hover.bind(item, false))
		row.add_child(item)
	# 「自动垂钓」开关已移入设置页（见 ui_panels.fill_settings），底栏只留导航图标。


func _rebuild_bottom_nav() -> void:
	if display_mode != "framed":
		return
	if not _tab_unlocked(_catch_tab):
		_catch_tab = _fallback_feature_tab()
	if is_instance_valid(_nav_bar):
		_nav_bar.queue_free()
	_nav_badges.clear()
	_build_bottom_nav()
	_layout_widget()
	_set_nav_solid(_panel_kind != "")
	_update_framed_hud()


func _set_nav_item_hover(item: Control, hovered: bool) -> void:
	if is_instance_valid(item):
		item.modulate = Color(1.18, 1.18, 1.18) if hovered else Color.WHITE


## 底栏背景上下文切换：开面板=暗(与 sheet 连成一片,无断裂)；关=透明(浮场景)。
func _set_nav_solid(solid: bool) -> void:
	if not is_instance_valid(_nav_bar):
		return
	if solid:
		var sb := StyleBoxFlat.new()
		sb.bg_color = DT.GLASS                 # 与 sheet 同色，连续
		sb.border_width_top = 1
		sb.border_color = DT.GLASS_ROW_BORDER  # CD .console border-top
		_nav_bar.add_theme_stylebox_override("panel", sb)
	else:
		_nav_bar.add_theme_stylebox_override("panel", _nav_idle_sb())


## 闲置态底栏背景：半透明暗底 + 顶部细线，让图标在浅色水彩场景上有对比、不发灰。
func _nav_idle_sb() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.10, 0.60)
	sb.border_width_top = 1
	sb.border_color = DT.GLASS_ROW_BORDER
	return sb


func _make_nav_badge() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = DT.RUST
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.name = "L"
	l.add_theme_font_override("font", _font_bold)
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	return pc


func _build_action_button() -> void:
	var b := Button.new()
	b.name = "ActionBtn"
	b.custom_minimum_size = Vector2(220, 48)
	b.size = Vector2(220, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font_bold)       # weight 700 → embolden（落地变通）
	b.add_theme_font_size_override("font_size", 15)     # CD .action 15
	b.pressed.connect(_on_action_pressed)
	ui_root.add_child(b)
	_action_btn = b
	_update_action_button()


func _action_style(bg: Color, quiet := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	if quiet:
		# 安静态（自动垂钓中）：状态提示而非按钮——薄胶囊、无阴影，不抢注意力
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
	else:
		sb.content_margin_top = 11
		sb.content_margin_bottom = 11
		sb.shadow_color = Color(0, 0, 0, 0.38)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
	return sb


func _on_action_pressed() -> void:
	# 满篓警示优先于起钩：此态按钮文案是「鱼篓满了 · 去兑换」，点击必须开面板（文案与行为同源）；
	# 满篓时亲手起钩也无收益（预掷会被 _overflow_catch 丢弃），让给开面板零损失。
	if _state == ST_BITE and not _bag_alert():
		_manual_hook()   # 亲手起钩：任何咬钩瞬间都可点（自动模式同样生效），只加成不惩罚
		return
	if _bag_full():
		_catch_tab = 0
		_open_panel("catch")   # 满篓 → 直接开鱼篓去兑换
		return


func _update_action_button() -> void:
	if not is_instance_valid(_action_btn):
		return
	# 照抄 CD .action 各态：normal=bronze / full=bag-full / bite=rust / wait(自动)=灰
	_action_btn.visible = true
	var txt := "起竿"
	var bg := DT.BRONZE
	var fg := DT.INK_ON_GOLD
	var quiet := false
	if _bag_alert():
		txt = "鱼篓满了 · 去兑换"
		bg = DT.BAG_FULL
	elif _state == ST_BITE and _bite_special:
		# 稀有驻留：这一刻值得打扰——完整红按钮 + 驻留窗口 4.5s，亲手拉上来的是鎏金/七彩
		txt = "起钩！"
		bg = DT.RUST
		fg = Color(1.0, 0.969, 0.937)            # #fff7ef
	elif auto_cast:
		# 安静态：挂机常态下它只是状态角标（用户反馈按钮形态存在感太强）。
		# 普通咬钩不变形不变大（0.9s 一闪即过，膨胀成大红按钮会每竿骚扰一次），
		# 只换文案与微微泛锈——看着它的人知道此刻可点（亲手起钩），没看的人毫无打扰。
		if _state == ST_BITE:
			txt = "· 咬钩了！·"
			bg = Color(0.42, 0.27, 0.18, 0.42)
			fg = Color(0.96, 0.84, 0.72)
		else:
			txt = "· 自动垂钓 ·"
			bg = Color(0.235, 0.251, 0.220, 0.30)
			fg = DT.TEXT_FAINT_GLASS
		quiet = true
	elif _state == ST_BITE:
		txt = "起钩！"
		bg = DT.RUST
		fg = Color(1.0, 0.969, 0.937)            # #fff7ef
	else:
		txt = "起竿"
		bg = DT.BRONZE
	# 几何随状态收放：安静态缩成薄小胶囊并重新居中；行动态（起钩/满篓/起竿）恢复完整按钮
	var bw := 132.0 if quiet else 220.0
	var bh := 26.0 if quiet else 48.0
	_action_btn.custom_minimum_size = Vector2(bw, bh)
	_action_btn.size = Vector2(bw, bh)
	_action_btn.position = _widget_point(Vector2((ART.x - bw) * 0.5,
		ART.y - FRAMED_CONSOLE_H - 66.0 + (11.0 if quiet else 0.0)))
	_action_btn.scale = Vector2(ui_scale, ui_scale)
	_action_btn.add_theme_font_size_override("font_size", 12 if quiet else 15)
	_action_btn.text = txt
	_action_btn.add_theme_color_override("font_color", fg)
	_action_btn.add_theme_stylebox_override("normal", _action_style(bg, quiet))
	# 安静态 hover/pressed 平时不提亮（挂机常态点它无操作）；咬钩瞬间例外——此刻可亲手起钩
	var lift := (not quiet) or _state == ST_BITE
	_action_btn.add_theme_stylebox_override("hover", _action_style(bg.lightened(0.10) if lift else bg, quiet))
	_action_btn.add_theme_stylebox_override("pressed", _action_style(bg.darkened(0.10) if lift else bg, quiet))


# 探针取可见场景内一点（窗口右下角附近），判断挂件是否落在某块屏幕可见区内。
func _pos_on_screen(pos: Vector2i) -> bool:
	var ws := DisplayServer.window_get_size()
	var probe := pos + Vector2i(int(ws.x) - 40, int(ws.y) - 40)
	for i in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(i).has_point(probe):
			return true
	return false


# 把窗口位置钳到所在屏可见区：透明左/上边可溢出，但保证右下角可见场景不被切到屏外。
func _clamp_win_to_screen(pos: Vector2i) -> Vector2i:
	var ws := DisplayServer.window_get_size()
	var probe := pos + Vector2i(int(ws.x) - 40, int(ws.y) - 40)
	for i in DisplayServer.get_screen_count():
		var r := DisplayServer.screen_get_usable_rect(i)
		if r.has_point(probe):
			return Vector2i(
				clampi(pos.x, r.position.x - int(SCENE_OFF.x), r.position.x + r.size.x - ws.x),
				clampi(pos.y, r.position.y - int(SCENE_OFF.y), r.position.y + r.size.y - ws.y))
	return pos


func _place_corner() -> void:
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	var ws := DisplayServer.window_get_size()
	DisplayServer.window_set_position(Vector2i(
		usable.position.x + usable.size.x - ws.x,
		usable.position.y + usable.size.y - ws.y))
	_saved_win_pos = null


## 把 canvas_items 的逻辑多边形转换成原生窗口客户区像素。
## Windows 的 window_set_mouse_passthrough 直接把这些点交给 SetWindowRgn；区域外不仅穿透，
## 也不会绘制。按多边形中心向外取整并留 4px 余量，避免 DPI/恢复抖动裁掉边缘。
static func _region_points_to_window(points: PackedVector2Array, canvas_transform: Transform2D,
		window_size: Vector2i) -> PackedVector2Array:
	if points.size() < 3 or window_size.x <= 0 or window_size.y <= 0:
		return PackedVector2Array()
	var transformed := PackedVector2Array()
	var center := Vector2.ZERO
	for point in points:
		var mapped := canvas_transform * point
		transformed.append(mapped)
		center += mapped
	center /= float(transformed.size())
	var result := PackedVector2Array()
	for mapped in transformed:
		var padded := mapped
		if mapped.x < center.x:
			padded.x -= WINDOW_REGION_PADDING_PX
		elif mapped.x > center.x:
			padded.x += WINDOW_REGION_PADDING_PX
		if mapped.y < center.y:
			padded.y -= WINDOW_REGION_PADDING_PX
		elif mapped.y > center.y:
			padded.y += WINDOW_REGION_PADDING_PX
		var x := floorf(padded.x) if padded.x < center.x else ceilf(padded.x)
		var y := floorf(padded.y) if padded.y < center.y else ceilf(padded.y)
		result.append(Vector2(
			clampf(x, 0.0, float(window_size.x)),
			clampf(y, 0.0, float(window_size.y))))
	return result


static func _region_transform_is_usable(canvas_transform: Transform2D, window_size: Vector2i) -> bool:
	var determinant := canvas_transform.determinant()
	return window_size.x > 0 and window_size.y > 0 \
		and is_finite(determinant) and absf(determinant) > 0.000001


static func _region_polygon_has_extent(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	var min_point := points[0]
	var max_point := points[0]
	for point in points:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
	var extent := max_point - min_point
	return extent.x >= 1.0 and extent.y >= 1.0


static func _drag_threshold_reached(start: Vector2i, current: Vector2i) -> bool:
	return Vector2(current - start).length_squared() >= DRAG_START_DISTANCE_PX * DRAG_START_DISTANCE_PX


func _set_canvas_window_region(points: PackedVector2Array) -> void:
	var window_size := DisplayServer.window_get_size()
	var canvas_transform := get_viewport().get_final_transform()
	if not _region_transform_is_usable(canvas_transform, window_size):
		_request_window_region_retry()
		return
	var native_points := _region_points_to_window(
		points, canvas_transform, window_size)
	if not _region_polygon_has_extent(native_points):
		# 绝不把退化多边形交给 Windows：空/零面积 HRGN 会把整个游戏裁没。
		_request_window_region_retry()
		return
	DisplayServer.window_set_mouse_passthrough(native_points)
	_window_region_retry_count = 0


## 唯一的窗口 Region 写入口。full=true 清除自定义 Region（整窗接收输入/完整绘制）；
## 空闲态则按当前显示形态恢复经过坐标转换的 widget/羽化区域。
func _set_window_interaction(full: bool) -> void:
	_window_interactive_full = full
	_apply_window_region()


func _apply_window_region() -> void:
	if DisplayServer.get_name() == "headless" or not _window_setup_complete:
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	if _window_interactive_full:
		# Godot 约定：空多边形禁用 mouse passthrough，恢复默认的整窗命中；Windows 同时清除 HRGN。
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		_window_region_retry_count = 0
	elif display_mode == "immersive":
		_update_passthrough()
	else:
		_update_widget_passthrough()


## 最小化恢复、DPI / 任务栏 / 分辨率变化时，最终变换会跨帧稳定；合并事件后延迟两帧重算。
func _queue_window_region_sync(reset_retry_count := true) -> void:
	if reset_retry_count:
		_window_region_retry_count = 0
	if DisplayServer.get_name() == "headless" or _window_region_sync_queued:
		return
	_window_region_sync_queued = true
	_sync_window_region_deferred()


func _request_window_region_retry() -> void:
	if _window_region_retry_count >= 3:
		return
	_window_region_retry_count += 1
	_queue_window_region_sync(false)


func _sync_window_region_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		_window_region_sync_queued = false
		return
	# framed 是当前屏幕可用区上的透明覆盖窗；系统几何改变后把覆盖层重新贴合当前屏。
	if display_mode != "immersive":
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		if DisplayServer.window_get_position() != usable.position:
			DisplayServer.window_set_position(usable.position)
		if DisplayServer.window_get_size() != usable.size:
			DisplayServer.window_set_size(usable.size)
			await get_tree().process_frame
			await get_tree().process_frame
		_widget_pos = _clamp_widget_pos(_widget_pos as Vector2) if _widget_pos != null else null
		_layout_widget()
		if is_instance_valid(_panel):
			_panel.position = UIPanels.clamp_panel_position(self, _panel.position, _panel.size)
	_window_region_sync_queued = false
	_apply_window_region()


func _update_passthrough() -> void:
	# 穿透区贴合羽化椭圆（略大于 alpha=0 边界），裁剪发生在场景已透明处 → 不再硬切；
	# 椭圆外（左上透明区）照常穿透到桌面。点超出窗口时钳到窗口边（右下角=屏幕角，实心收边）。
	var c := FEATHER_CENTER + SCENE_OFF
	var radii := FEATHER_RADII * 1.04
	var pts := PackedVector2Array()
	var n := 48
	for i in n:
		var a := TAU * float(i) / float(n)
		var p := c + Vector2(cos(a), sin(a)) * radii
		pts.append(Vector2(clampf(p.x, 0.0, float(WIN.x)), clampf(p.y, 0.0, float(WIN.y))))
	_set_canvas_window_region(pts)


func _update_widget_passthrough() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_widget_pos()
	var p := _widget_pos as Vector2
	var s := _widget_size()
	if is_instance_valid(_dev_tools_bar):
		var left := 0.0
		var top := 0.0
		var stage := _stage_size()
		var dev_right := _dev_tools_bar.position.x + _dev_tools_bar.size.x
		var dev_bottom := _dev_tools_bar.position.y + _dev_tools_bar.size.y
		if _dev_attrs_open and is_instance_valid(_dev_attrs_panel):
			dev_right = _dev_attrs_panel.position.x + _dev_attrs_panel.size.x
			dev_bottom = _dev_attrs_panel.position.y + _dev_attrs_panel.size.y
		var right := minf(stage.x, maxf(p.x + s.x, dev_right))
		var bottom := minf(stage.y, maxf(p.y + s.y, dev_bottom))
		_set_canvas_window_region(PackedVector2Array([
			Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)]))
		return
	_set_canvas_window_region(PackedVector2Array([
		p, p + Vector2(s.x, 0), p + s, p + Vector2(0, s.y)]))


# 任意操作刷新"无操作"计时；宽限窗外的点击/按键把当前专注段折算保留 80%（你回来动手了，
# 但一趟快速卖鱼不该没收全部进度——回焦 60s 宽限窗见 _notification 的 FOCUS_IN 分支）。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey:
		if event.is_pressed():
			_idle_t = 0.0
			if _focus_grace_t <= 0.0:
				_fold_focus_streak()
	elif event is InputEventMouseMotion:
		_idle_t = 0.0
	# 缩放拖拽进行中：在 _input 全局处理移动/松手（鼠标可能已离开手柄热区）
	if _rz_active:
		if event is InputEventMouseMotion:
			_apply_grip_resize(DisplayServer.mouse_get_position())
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_rz_active = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			_save()
			if _panel_kind != "":
				_refresh_panel()   # 刷新设置页「当前 XX%」与档位高亮
			get_viewport().set_input_as_handled()


# 拖动挂机组件：在场景空白处按住左键并超过 6 个物理像素才起拖。
# 普通点击/手抖不改布局；面板打开时不允许拖动被遮住的底层 widget。
func _unhandled_input(event: InputEvent) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _panel_kind != "":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_drag_pending = false
			_dragging = false
		return
	if display_mode == "immersive":
		# 沉浸模式仍保留旧的整窗拖动。
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_pending = true
				_dragging = false
				_drag_press_screen = DisplayServer.mouse_get_position()
				_drag_grab = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
			else:
				var did_drag := _dragging
				_drag_pending = false
				_dragging = false
				if did_drag:
					_save()
		elif event is InputEventMouseMotion and _drag_pending:
			var mouse_screen := DisplayServer.mouse_get_position()
			if not _dragging and _drag_threshold_reached(_drag_press_screen, mouse_screen):
				_dragging = true
			if _dragging:
				DisplayServer.window_set_position(mouse_screen - _drag_grab)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mp := get_viewport().get_mouse_position()
			if Rect2(_widget_pos as Vector2, _widget_size()).has_point(mp):
				_drag_pending = true
				_dragging = false
				_drag_press_screen = DisplayServer.mouse_get_position()
				_drag_grab = Vector2i(mp - (_widget_pos as Vector2))
		else:
			var did_drag := _dragging
			_drag_pending = false
			_dragging = false
			if did_drag:
				_save()
	elif event is InputEventMouseMotion and _drag_pending:
		if not _dragging and _drag_threshold_reached(_drag_press_screen, DisplayServer.mouse_get_position()):
			_dragging = true
		if _dragging:
			_widget_pos = _clamp_widget_pos(get_viewport().get_mouse_position() - Vector2(_drag_grab))
			_layout_widget()


# ============================ 钓鱼循环 ============================

func _process(delta: float) -> void:
	if not _started:
		return
	if save_enabled:
		_save_t -= delta
		if _save_t <= 0.0:
			_save_t = 10.0
			_save()
	_tick_merchant(delta)
	_tick_events(delta)
	_tick_relationship_visits(delta)
	_tick_relationship_buff(delta)
	_tick_phase()
	_tick_focus(delta)
	_flash_cd = maxf(0.0, _flash_cd - delta)
	_state_t -= delta
	match _state:
		ST_WAIT:
			painter.dip = lerpf(painter.dip, 0.0, delta * 6.0)
			if _state_t <= 0.0:
				if _bag_full():
					_try_auto_sell()   # 鱼贩合约：满篓先带走一条杂鱼腾格，挂机不因满篓停产
				if not _bag_full() or _auto_sell_active():
					_begin_bite()      # 合约在手：篓全珍品也照常咬钩，_do_catch 走满篓折价兜底
		ST_BITE:
			painter.dip = lerpf(painter.dip, 1.0, delta * 10.0)
			if _state_t <= 0.0:
				_do_catch()


func _begin_wait() -> void:
	_state = ST_WAIT
	_pending_catch = {}     # 预掷渔获绝不跨周期存活（满篓兜底等提前返回的路径在此兜底清空）
	_bite_special = false
	if painter.has_method("bite_glow_off"):
		painter.bite_glow_off()
	var w := rng.randf_range(3.5, 7.0) * maxf(0.4, 1.0 - float(rod_level - 1) * 0.04) \
		* _speed_wait_mult() * _reaction_wait_mult()
	w *= SpotData.wait_mult(current_spot)          # 钓点常驻系数（阶段④起生效）
	w *= Weather.wait_mult(day_phase)              # 昼夜时段（金色时段咬钩更勤）
	if active_event != "":
		w *= EventData.wait_mult(active_event)      # 事件期间咬钩节奏变化
	w *= _relationship_buff_wait_mult()
	_state_t = maxf(0.05, w / test_speed)           # 测试提速：test_speed=1 时不变
	Audio.play_sfx("cast")
	get_tree().create_timer(0.45).timeout.connect(func() -> void: Audio.play_sfx("bobber_splash"))
	_update_action_button()


## 昼夜时段：每帧轻量比对真实时钟，跨段才刷新（一天仅 4 次，开销可忽略）。
func _tick_phase() -> void:
	if test_mode and _forced_phase != "":
		return  # 测试模式强制时段：不被真实时钟覆盖
	var p := Weather.current_phase()
	if p != day_phase:
		day_phase = p
		_apply_phase()


## 应用当前时段：场景染色 + HUD + 按新节奏重排（不打断已在咬钩）。
func _apply_phase() -> void:
	if painter.has_method("set_phase_tint"):
		painter.set_phase_tint(Weather.tint(day_phase), day_phase)
	Audio.set_ambience_scene(current_spot, day_phase)   # 时段切换 → 环境床随昼夜重铺
	_update_hud()


func _begin_bite() -> void:
	_state = ST_BITE
	# 渔获在咬钩瞬间预掷：稀有（鎏金/七彩/神话）驻留更久 + 浮漂金环，恰好在场的玩家来得及亲手起钩；
	# 没人看时驻留结束照常自动上鱼，零损失。
	_pending_catch = _roll_pending()
	# 满篓（合约在手、篓全珍品）时预掷会被 _overflow_catch 折价兜底丢弃——金环不做空头承诺
	_bite_special = _is_special_catch(_pending_catch) and not _bag_full()
	# 普通咬钩继承装备的速度/反应修正；稀有咬钩固定驻留，保证玩家有时间亲手起钩。
	var bite_hold := SPECIAL_BITE_HOLD if _bite_special else 0.9 * _speed_wait_mult() * _reaction_wait_mult()
	_state_t = maxf(0.12, bite_hold / test_speed)
	painter.add_ripple(painter.bobber_pos(), 44.0 if _bite_special else 22.0)
	if _bite_special and painter.has_method("bite_glow"):
		var vr := int(_pending_catch.get("var", 0))
		painter.bite_glow(_state_t, FishData.variant_color(vr) if vr >= 2 else Color(1.0, 0.86, 0.45))
	Audio.play_sfx("bite")
	# 张力循环填满咬钩→上鱼这 0.9 秒（此前是一片死寂）。音高固定：鱼要到 _do_catch
	# 才 _roll_one，提前摇会改动 rng 序列、打破 validate 的确定性基线。体型的听觉表达
	# 交给上鱼那一刻的 sfx_fish_struggle。
	Audio.start_tension(1)
	_update_action_button()


## 预掷这一竿的渔获（含试竿保底消费）。_do_catch 优先消费预掷；
## 无预掷（测试直调）则现场掷同一套逻辑，RNG 消费顺序与旧版逐位一致。
func _roll_pending() -> Dictionary:
	var luck := _catch_luck()
	# 试竿保底（升级体感）：购买升级后的下一竿保底展示新效果——把"花钱→变强"的回路当场闭合。
	# 只送一竿，经济影响 ≈0；概率型升级没有保底展示就永远"感觉不出来"（S12 感知阈值）。
	# 这里只窥视不消费：保底在真实入篓时才兑现（_do_catch 清），满篓兜底丢弃预掷 /
	# 咬钩中退出存档都不会吞掉承诺（对抗审查 must-fix：恢复旧版"顺延到下一次真结算"语义）。
	var showcase := showcase_pending
	if showcase == "rod":
		luck += 4   # 高运气一竿：亲眼看见"更易上高阶鱼"
	var c := _roll_one(luck)
	if showcase == "bait":
		_force_catch_grade(c, mini(bait_level, 3), 0)   # 保底展示刚解锁的新星级
	elif showcase == "lure":
		_force_catch_grade(c, 0, 1)                     # 保底斑斓：亲眼看见变体杠杆
	c["_luck"] = luck
	c["_showcase"] = showcase
	return c


## 稀有咬钩判定：鎏金/七彩变体或神话品阶才驻留（≈0.5% 竿次，感官预算内）。
func _is_special_catch(c: Dictionary) -> bool:
	return int(c.get("var", 0)) >= 2 or FishData.tier_of(str(c["id"])) >= 5


## 亲手起钩：咬钩窗口内点「起钩！」——体重/卖价 ×1.1 并记「亲手」，随后立即结算。
## 只加成不惩罚：错过窗口照常自动上鱼（hand_catches 在 _do_catch 消费时才累计，满篓兜底不计）。
func _manual_hook() -> void:
	if _state != ST_BITE:
		return
	if _pending_catch.is_empty():
		_pending_catch = _roll_pending()
	_pending_catch["hand"] = true
	_pending_catch["w"] = snappedf(float(_pending_catch["w"]) * HAND_HOOK_MULT, 0.01)
	_pending_catch["v"] = maxi(1, int(round(float(_pending_catch["v"]) * HAND_HOOK_MULT)))
	Audio.play_ui("ui_click")
	_do_catch()


## 更新图鉴纪录（捕获数 +1、最大体重取大、巨物/完美徽章）。返回是否打破"既有"纪录：
## 该鱼种此前已钓 ≥5 条且新体重超过旧纪录才算（避免前期每条都播报）。
func _dex_record(id: String, w: float, is_big := false, is_perfect := false, variant := 0) -> bool:
	var vbit := (1 << variant) if variant > 0 else 0  # 记录见过的稀有变体（位掩码）
	if not dex.has(id):
		dex[id] = {"n": 1, "w": w, "big": is_big, "perf": is_perfect, "vmask": vbit,
			"fd": _today_key(), "wd": _today_key()}  # fd 首捕日期；wd 刷新最大体重的日期
		return false
	var r: Dictionary = dex[id]
	if vbit != 0 and (int(r.get("vmask", 0)) & vbit) != 0:
		scales[variant - 1] = int(scales[variant - 1]) + 1   # 重复变体折 1 枚同档鳞：已点亮格的重复不再空转
	var broke: bool = int(r["n"]) >= 5 and w > float(r["w"])
	r["n"] = int(r["n"]) + 1
	if w > float(r["w"]):   # 刷新个人最大体重，记下破纪录日期
		r["w"] = w
		r["wd"] = _today_key()
	if is_big:
		r["big"] = true
	if is_perfect:
		r["perf"] = true
	r["vmask"] = int(r.get("vmask", 0)) | vbit
	return broke


## 彩鳞定向兑换：花彩鳞点亮已收录鱼的缺失变体格（只补图鉴收集位，不发鱼）。
## 入口在鱼种详情卡的变体墙（ui_panels.fill_fish_detail）。
func _redeem_variant(id: String, vi: int) -> void:
	if not dex.has(id) or vi < 1 or vi > 3:
		return
	var r: Dictionary = dex[id]
	if int(r.get("vmask", 0)) & (1 << vi):
		return   # 已点亮
	var cost := FishData.scale_cost(FishData.tier_of(id))
	var sname: String = FishData.SCALE_NAMES[vi - 1]
	if int(scales[vi - 1]) < cost:
		Audio.play_ui("ui_error")
		_toast("%s不够（需 %d，现有 %d）" % [sname, cost, int(scales[vi - 1])], 1.8, Color(1.0, 0.5, 0.4))
		return
	scales[vi - 1] = int(scales[vi - 1]) - cost
	r["vmask"] = int(r.get("vmask", 0)) | (1 << vi)
	Audio.play_sfx("upgrade")
	_toast("✨ 兑换点亮：%s%s（−%d %s）" % [FishData.VARIANT_NAMES[vi],
		FishData.display_name(id), cost, sname], 2.4, FishData.variant_color(vi))
	_check_achievements()
	_update_hud()
	_save()
	_refresh_panel()


func _bag_capacity() -> int:
	return BAG_CAPS[clampi(bag_level - 1, 0, BAG_CAPS.size() - 1)]


func _bag_full() -> bool:
	return inventory.size() >= _bag_capacity()


## 满篓「警示态」：满篓且有钱在漏才亮（未签约=停产等人；签约但全是珍品=新渔获走折价兜底）。
## 合约稳态（有杂鱼可腾格）满↔差一格每竿抖动属正常运转，不亮警示——防止警示每竿闪烁贬值。
func _bag_alert() -> bool:
	if not _bag_full():
		return false
	if not _auto_sell_active():
		return true
	for f in inventory:
		if _auto_sell_eligible(f):
			return false
	return true


## 钓点：薄壳委托 Spots（实现见 spots.gd，行为不变）。
func _spot_pool() -> Array:
	return Spots.pool(self)


func _catch_luck() -> int:
	return Spots.catch_luck(self) + _relationship_buff_luck()


func _catch_value_mult() -> float:
	return Spots.catch_value_mult(self) * _relationship_buff_value_mult()


## 属性映射采用软上限曲线：早期每级有感，后期不让二级属性盖过鱼竿/鱼饵/鱼钩/窝料主轴。
func _stat_curve(value: float, softness := 120.0) -> float:
	return 1.0 - exp(-maxf(0.0, value) / softness)


func _reaction_wait_mult() -> float:
	var stats = _angler_stats()
	return 1.0 - 0.10 * _stat_curve(stats.reaction, 110.0)


func _tier_attr_mults() -> Dictionary:
	var stats = _angler_stats()
	var curve := _stat_curve(stats.ecology * 0.75 + stats.perception * 0.25, 125.0)
	return {
		0: 1.0 - 0.05 * curve,
		1: 1.0 - 0.02 * curve,
		2: 1.0 + 0.08 * curve,
		3: 1.0 + 0.16 * curve,
		4: 1.0 + 0.24 * curve,
		5: 1.0 + 0.32 * curve,
	}


func _effective_tier_weights(luck := 0) -> Dictionary:
	var weights := FishData.weights_for_rod(rod_level + luck)
	var mults := _tier_attr_mults()
	for tier in mults:
		weights[tier] = maxf(0.01, float(weights.get(tier, 0.0)) * float(mults[tier]))
	return weights


func _quality_attr_bonus() -> Array:
	var stats = _angler_stats()
	var curve := _stat_curve(stats.technique * 0.75 + stats.stability * 0.25, 120.0)
	return [0.0, 0.10 * curve, 0.06 * curve, 0.03 * curve]


func _variant_attr_bias() -> float:
	var stats = _angler_stats()
	return 1.20 * _stat_curve(stats.perception * 0.70 + stats.ecology * 0.30, 120.0)


func _double_chance() -> float:
	var stats = _angler_stats()
	var base := float(FishData.HOOKS[clampi(hook_level, 0, FishData.HOOKS.size() - 1)]["double"])
	var bonus := 0.12 * _stat_curve(stats.reaction * 0.70 + stats.technique * 0.30, 115.0)
	return clampf(base + bonus, 0.0, 0.70)


func _weight_power() -> float:
	var stats = _angler_stats()
	var curve := _stat_curve(stats.strength * 0.70 + stats.stability * 0.30, 125.0)
	return 2.0 - 0.35 * curve


func _roll_mods() -> Dictionary:
	return {
		"tier_mults": _tier_attr_mults(),
		"quality_bonus": _quality_attr_bonus(),
		"weight_power": _weight_power(),
	}


## 变体偏置累加器（P2 变体杠杆）：各收集杠杆贡献相加，喂给 FishData.roll_variant 抬高变体率。
## 目前来源：诱饵/窝料成长线（lure_level）+ 角色感知/生态二级属性。
## 以后加来源（钓点亲和/悬赏等）只在此 += 一行即可。
## 0 级窝料 → 0，与基线逐位一致；上不封顶交由 roll_variant 内部 clamp(0,10)。
func _variant_bias() -> float:
	return FishData.lure_vbias(lure_level) + _variant_attr_bias() + _relationship_buff_variant_bias()


## 钓一条鱼：限定当前钓点鱼池，应用钓点/事件增值系数。
## vbias<0（默认哨兵）→ 取当前各杠杆累加值 _variant_bias()（在线/离线都吃诱饵加成）；
## 传非负值则按显式覆盖（专注奖励等强制场景留口）。
func _roll_one(luck: int, vbias := -1.0) -> Dictionary:
	var vb := vbias if vbias >= 0.0 else _variant_bias()
	var c := FishData.roll_catch(rng, rod_level, bait_level, luck, _spot_pool(), vb, _roll_mods())
	var vm := _catch_value_mult()
	if vm != 1.0:
		c["v"] = max(1, int(round(float(c["v"]) * vm)))
	return c


## 上鱼音四档。此前所有「优良以上」的鱼共用一个 catch_rare——一条 ×12 的七彩
## 和一条 ★★ 的普通鱼听起来完全一样，219 鱼 × 4 变体的收集轴在听觉上只有两档。
## 门槛与 docs/audio_asset_rules.md 的「catch_rare 只给稀有及以上」对齐（★★ 降到 good）。
func _catch_sfx(tier: int, q: int, vr: int) -> String:
	if vr >= 2 or tier >= 4:        # 鎏金/七彩，或传说/神话
		return "catch_epic"
	if tier >= 2 or vr == 1 or q >= 3:   # 稀有/史诗，或斑斓，或极品★★★
		return "catch_rare"
	if q >= 2:                       # ★★
		return "catch_good"
	return "catch_common"


func _do_catch() -> void:
	Audio.stop_tension()   # 无论走哪条分支（满篓兜底也算）都要收掉张力循环
	if _bag_full():
		_try_auto_sell()   # 鱼贩合约：先按市价带走杂鱼腾格；腾不出（全是珍品）才走折价兜底
	if _bag_full():
		_overflow_catch()   # 兜底折价兑金（签约后篓全珍品时的常态路径；未签约在线到不了这里——满篓不咬钩）
		_begin_wait()
		return
	# 渔获已在咬钩瞬间预掷（_begin_bite → _roll_pending，试竿保底只窥视、在此处真结算才消费）。
	# 兜底重掷：①无预掷（测试直调 _do_catch）；②预掷后玩家又买了升级（保底口径变了 → 弃掷
	# 重掷当场兑现"下一竿保底"）。豁免弃掷：预掷已被玩家亲手起钩（×1.1 不没收）或亮过金环
	# 承诺（_bite_special：亲手拉起的必须就是金环所指的稀有）——此时保底原样顺延到下一竿。
	var c: Dictionary
	if not _pending_catch.is_empty() \
			and (str(_pending_catch.get("_showcase", "")) == showcase_pending \
				or bool(_pending_catch.get("hand", false)) or _bite_special):
		c = _pending_catch
	else:
		c = _roll_pending()
	_pending_catch = {}
	var luck := int(c.get("_luck", 0))
	var showcase := str(c.get("_showcase", ""))
	if showcase != "" and showcase_pending == showcase:
		showcase_pending = ""   # 保底在真实入篓这一刻才算兑现（满篓兜底提前 return 走不到这里）
	c.erase("_luck")
	c.erase("_showcase")
	var hand := bool(c.get("hand", false))
	if hand:
		hand_catches += 1
	var focus_up := _apply_focus_reward(c)   # 专注奖励：把这一竿强制升级（保底高星/鎏金）
	var tier := FishData.tier_of(c["id"])
	var q := int(c.get("q", 0))
	var vr := int(c.get("var", 0))
	var fname := FishData.variant_label(vr) + FishData.quality_label(q) + FishData.size_tag(c["id"], c["w"]) \
		+ FishData.display_name(c["id"])
	inventory.append(c)
	lifetime_catches += 1
	best_quality = maxi(best_quality, q)
	best_variant = maxi(best_variant, vr)
	var is_big := FishData.size_tag(c["id"], c["w"]) == "巨物·"
	if is_big:
		caught_giant = true
	var is_new_species := not dex.has(c["id"])   # 必须抢在 _dex_record 建条目之前问
	var broke_record := _dex_record(c["id"], float(c["w"]), is_big, q >= 3, vr)
	var col: Color = FishData.TIER_COLORS[tier]
	var catch_sfx := _catch_sfx(tier, q, vr)
	Audio.play_sfx(catch_sfx)
	# 巨物出水翻腾。epic 自带长尾旋律，再叠一层水声只会糊成一团。
	if is_big and catch_sfx != "catch_epic":
		Audio.play_sfx("sfx_fish_struggle")
	# 首捕 / 破纪录：延后 0.35s 让开水花峰值，否则被淹没。二者天然互斥——首捕时
	# dex.n=1，而破纪录要求该鱼种已钓 ≥5 条，所以不必在两者间取舍。
	var milestone := "sfx_new_species" if is_new_species else ("sfx_record" if broke_record else "")
	if milestone != "":
		get_tree().create_timer(0.35).timeout.connect(func() -> void: Audio.play_sfx(milestone))
	_popup("%s%s %.2fkg" % [("亲手 · " if hand else ""), fname, c["w"]],
		_scene_pt(painter.bobber_pos()) + Vector2(-22, -8),
		FishData.variant_color(vr) if vr >= 1 else col)
	painter.add_ripple(painter.bobber_pos(), 34.0)
	# 庆祝 toast 门槛（P1 感官治理）：斑斓收敛后仍≈1/40 竿，浮标彩色飘字已够仪式感，
	# toast 只留鎏金/七彩级惊喜；专注（安静）模式下庆祝类 toast 全部静默（订单进度等事务性提示保留）。
	if vr >= 2 and not focus_mode:
		_toast("✨ 变体！%s%s（%.2fkg，%s 金币）" % [FishData.variant_label(vr),
			FishData.display_name(c["id"]), c["w"], _coin_str(int(c["v"]))], 2.8, FishData.variant_color(vr))
	elif broke_record and not focus_mode:
		_toast("破纪录！%s %.2fkg，刷新个人最大" % [FishData.display_name(c["id"]), c["w"]],
			2.6, Color(0.95, 0.82, 0.45))
	elif (tier >= 3 or q >= 2) and not focus_mode:
		_toast("%s钓到 %s（%.2fkg，%s 金币）" % [
			(FishData.TIER_NAMES[tier] + "！") if tier >= 3 else "",
			fname, c["w"], _coin_str(int(c["v"]))], 2.4, col)
	elif not bool(daily_order.get("done", false)) and _order_matches(c) \
			and vr < 2 and (str(daily_order.get("kind", "")) == "perfect" or q < 3):
		# 与自动交单池同口径：珍稀（鎏金/七彩/★★★）不计入订单，进度提示也不该由它触发
		var need := int(daily_order.get("need", 1))
		var have := mini(_daily_order_indices().size(), need)
		_toast("订单进度：%s %d/%d" % [_order_short(), have, need],
			2.0, Color(0.96, 0.78, 0.38))
	var comp_win := Competition.on_catch(self, c)   # 巨物赛：本周目标鱼刷新最佳，冲过影子线夺金
	if comp_win > 0:
		Audio.play_sfx("sfx_competition_win")   # 一周一次的夺金，此前和卖一条杂鱼同一个 coin 音
		_toast("🏆 巨物赛夺金！%s %.2fkg 越过影子线，+%s 金币" % [
			FishData.display_name(str(c["id"])), float(c["w"]), _coin_str(comp_win)], 3.4, Color(1.0, 0.86, 0.32))
		_flash()
	if tier >= 5 or vr >= 3 or broke_record:   # 真·稀有（神话/七彩）或破个人纪录才庆祝闪光
		_flash()
	# 渔夫性格：钓到高星/七彩，举手欢呼一下（Task 4）
	if (q >= 2 or vr >= 3) and painter.has_method("fisher_cheer"):
		painter.fisher_cheer()
	# 鱼钩双钩：一定几率再上一条（受背包剩余格数限制）；鱼钩试竿 → 必双钩
	var double_chance := _double_chance()
	if double_chance > 0.0 and not _bag_full() \
			and (showcase == "hook" or rng.randf() < double_chance):
		var c2 := _roll_one(luck)
		inventory.append(c2)
		lifetime_catches += 1
		best_quality = maxi(best_quality, int(c2.get("q", 0)))
		best_variant = maxi(best_variant, int(c2.get("var", 0)))
		var ib2 := FishData.size_tag(c2["id"], c2["w"]) == "巨物·"
		if ib2:
			caught_giant = true
		var new_species2 := not dex.has(c2["id"])
		_dex_record(c2["id"], float(c2["w"]), ib2, int(c2.get("q", 0)) >= 3, int(c2.get("var", 0)))
		_popup("双钩 +%s" % FishData.display_name(c2["id"]),
			_scene_pt(painter.bobber_pos()) + Vector2(24, -22), Color(0.62, 0.86, 0.74))
		# 第二条鱼也走分级——双钩钓上七彩却只响一声普通水花，是原来最容易被察觉的哑点。
		Audio.play_sfx(_catch_sfx(FishData.tier_of(c2["id"]), int(c2.get("q", 0)), int(c2.get("var", 0))))
		if new_species2:
			get_tree().create_timer(0.45).timeout.connect(func() -> void: Audio.play_sfx("sfx_new_species"))
		var comp_win2 := Competition.on_catch(self, c2)   # 双钩第二条也参与巨物赛
		if comp_win2 > 0:
			Audio.play_sfx("sfx_competition_win")
			_toast("🏆 巨物赛夺金！%s %.2fkg，+%s 金币" % [
				FishData.display_name(str(c2["id"])), float(c2["w"]), _coin_str(comp_win2)], 3.4, Color(1.0, 0.86, 0.32))
			_flash()
	if _bag_full() and not _auto_sell_active():   # 签约后收鱼郎代劳腾格，这条建议每竿刷屏且已过时
		_toast("鱼篓满了，先去卖鱼或扩容～", 3.0, Color(1.0, 0.75, 0.4))
	_maybe_pet_steal()   # 桌面宠物：小概率叼走最廉价的一条（Task 4）
	if painter.has_method("pet_react") and not focus_mode and rng.randf() < 0.3:
		painter.pet_react("paw")  # 上鱼时偶尔扒拉一下鱼篓
	_check_achievements()
	_ensure_feature_unlocks()
	_update_hud()
	_refresh_panel()
	if showcase != "":  # 试竿反馈：升级是玩家刚刚的主动操作，回执不受安静模式抑制（事务性）
		_toast("🎣 试竿：%s %.2fkg" % [fname, float(c["w"])], 2.6, Color(0.72, 0.86, 0.78))
	if focus_up > 0:  # 专注奖励到手：用最醒目的 toast 收尾（最后调用者覆盖前面的飘字）
		var rname := FishData.variant_label(int(c.get("var", 0))) + FishData.quality_label(int(c.get("q", 0))) \
			+ FishData.display_name(str(c["id"]))
		_toast("🎁 专注奖励到手：%s（%.2fkg，%s 金币）" % [rname, float(c["w"]), _coin_str(int(c["v"]))],
			4.0, Color(0.74, 0.86, 0.98))
	if vr >= 2:
		_rare_ceremony(c)   # 稀有仪式：1/250、1/1250 竿的尖峰时刻，感官必须与杂鱼拉开量级
	_begin_wait()


## 稀有仪式（P0 好玩补丁）：鎏金/七彩入手 = 金光粒子 + 庆祝脉冲 + 水面号外 + 捕获卡。
## 直调 painter.catch_flash 绕过 1800s 冷却——0.4%/0.08% 的时刻本身就稀缺，不会贬值成骚扰。
## 专注模式全静默（存进 _capture_card_data 的仪式不补发，回来靠图鉴/鱼篓自己发现，符合"不打扰"）。
func _rare_ceremony(c: Dictionary) -> void:
	if focus_mode or not save_enabled:
		return   # save_enabled=false 的测试/截图实例不弹卡，避免污染回归与自查截图
	var vr := int(c.get("var", 0))
	var vcol := FishData.variant_color(vr)
	if painter.has_method("celebrate"):
		painter.celebrate(painter.bobber_pos(), vcol)
	if painter.has_method("catch_flash"):
		painter.catch_flash()
	if painter.has_method("newsflash"):
		painter.newsflash("号外！钓起%s%s %.2fkg · 全球约 1/%d 竿" % [FishData.variant_label(vr),
			FishData.display_name(str(c["id"])), float(c["w"]), FishData.variant_odds(vr)])
	# 音效由 _do_catch 统一播（catch_rare），此处不重复。
	# 弹卡只挑不打扰的时机：开场引导链（story/character/intro）不可顶掉（顶了永不重开）、
	# 玩家正用别的面板不硬抢、沉浸模式不弹（开面板会把整窗穿透切成拦截，违背"不打扰"）。
	# 跳过弹卡零损失：粒子/号外照放，鱼已入篓，图鉴与鱼篓自会再见到它。
	if _panel_kind == "" and display_mode != "immersive":
		_capture_card_data = c.duplicate()
		_open_panel("capture")


## 把捕获卡面板截成 PNG 存到 user://capture_cards/ 并打开文件夹——玩家自己发群 = 最轻的社交。
func _save_capture_card() -> void:
	if not is_instance_valid(_panel):
		return
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_panel):
		return
	var img := get_viewport().get_texture().get_image()
	# canvas_items 拉伸下视口图是窗口物理像素、面板坐标是画布逻辑坐标（ui_scale≠100% 时两者不同），
	# 必须过一遍视口最终变换（纯缩放，包围盒即精确结果）再裁剪
	var xf := get_viewport().get_final_transform()
	var r := Rect2i(xf * Rect2(_panel.global_position, _panel.size))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var dir := "user://capture_cards"
	DirAccess.make_dir_recursive_absolute(dir)
	var fn := "%s/%s_%d.png" % [dir, str(_capture_card_data.get("id", "fish")),
		int(Time.get_unix_time_from_system())]
	var err := img.get_region(r).save_png(fn)
	if err == OK:
		_toast("📸 捕获卡已保存", 2.2, Color(0.72, 0.86, 0.78))
		OS.shell_open(ProjectSettings.globalize_path(dir))
	else:
		_toast("保存失败（%d）" % err, 2.2, Color(1.0, 0.75, 0.4))


## 满篓兜底（调研 3.2「把痛点变成卖点」）：鱼篓满时把新鱼 c 与篓中最低价的
## 「可兑换鱼」（未上锁、非当前订单目标）比较，留下更值钱的那条，另一条按
## OVERFLOW_SELL_RATE 折价自动兑成金币。返回兜底金币（不改 coins/lifetime，调用方累计）。
## 篓里若全是收藏锁/订单鱼（无可兑换）则直接折价兑掉新鱼，绝不动玩家珍藏。
func _absorb_overflow(c: Dictionary) -> int:
	var worst_idx := -1
	var worst_v := 0
	for i in inventory.size():
		var f: Dictionary = inventory[i]
		if bool(f.get("lock", false)) or _order_matches(f):
			continue
		var fv := _sell_value(f)
		if worst_idx == -1 or fv < worst_v:
			worst_idx = i
			worst_v = fv
	var sold := c
	if worst_idx >= 0 and _sell_value(c) > worst_v:
		sold = inventory[worst_idx]   # 新鱼更值钱 → 收进篓，兑掉篓中最低价那条
		inventory[worst_idx] = c
	return maxi(1, int(ceil(_sell_value(sold) * OVERFLOW_SELL_RATE)))


## 满篓在线钓鱼：照常计入图鉴/累计（挂机仍推进收集），渔获经 _absorb_overflow 折价入金。
## 低干扰：只在浮标处给一个小飘字 + 涟漪，不发 toast、不响金币音，避免满篓久挂时刷屏吵闹。
func _overflow_catch() -> void:
	var luck := _catch_luck()
	var c := _roll_one(luck)
	lifetime_catches += 1
	var q := int(c.get("q", 0))
	var vr := int(c.get("var", 0))
	best_quality = maxi(best_quality, q)
	best_variant = maxi(best_variant, vr)
	var is_big := FishData.size_tag(c["id"], c["w"]) == "巨物·"
	if is_big:
		caught_giant = true
	_dex_record(c["id"], float(c["w"]), is_big, q >= 3, vr)
	var gain := _absorb_overflow(c)
	_add_coins_safe(gain)
	_add_lifetime_coins_safe(gain)
	painter.add_ripple(painter.bobber_pos(), 28.0)
	_popup("满篓兑 +%s" % _coin_str(gain), _scene_pt(painter.bobber_pos()) + Vector2(-22, -8),
		Color(0.85, 0.72, 0.42))
	_check_achievements()
	_ensure_feature_unlocks()
	_update_hud()
	_refresh_panel()


## —— 鱼贩合约（自动贩卖）：满篓时自动按市价带走一条「杂鱼」腾格，挂机不因满篓停产。——
## 护栏（守住"手动卖出珍品"的核心交互，VISION 决策 2026-07-07）：只碰 普通花色 + ≤★ +
## 稀有以下(tier≤2)、未上锁、非当前订单目标的鱼；变体/高星/史诗以上永远留给玩家手动处置。
func _auto_sell_active() -> bool:
	return auto_sell_bought and auto_sell_on


func _auto_sell_eligible(c: Dictionary) -> bool:
	if int(c.get("var", 0)) != 0 or int(c.get("q", 0)) > 1 or bool(c.get("lock", false)):
		return false
	if FishData.tier_of(str(c["id"])) > 2:
		return false
	if FishData.size_tag(str(c["id"]), float(c.get("w", 0.0))) == "巨物·":
		return false   # 巨物（破纪录体型）视同珍品，第六道护栏
	# 订单保护只在订单未交付时生效（与 _do_catch 的订单进度 toast 同口径；
	# 交付后不解除会让 tier/weight 类订单日冻住大片杂鱼、合约整天失效）
	if not bool(daily_order.get("done", false)) and _order_matches(c):
		return false
	return true


## 卖出篓中最便宜的一条可带走杂鱼（市价，同手动卖出）。成功腾出格子返回 true。
## 静音克制（不打扰）：只在浮标处小飘字，不 toast、不响金币音。
func _try_auto_sell() -> bool:
	if not _auto_sell_active():
		return false
	var idx := -1
	var idx_v := 0
	for i in inventory.size():
		var f: Dictionary = inventory[i]
		if not _auto_sell_eligible(f):
			continue
		var fv := _sell_value(f)
		if idx == -1 or fv < idx_v:
			idx = i
			idx_v = fv
	if idx < 0:
		return false
	var c: Dictionary = inventory[idx]
	inventory.remove_at(idx)
	_add_coins_safe(idx_v)
	_add_lifetime_coins_safe(idx_v)
	auto_sold_n += 1
	_add_auto_sold_value_safe(idx_v)
	_check_achievements()   # 财富线成就与其他卖鱼收入路径同口径，不延迟到下一竿
	_ensure_feature_unlocks()
	_popup("收鱼郎带走%s +%s" % [FishData.display_name(c["id"]), _coin_str(idx_v)],
		_scene_pt(painter.bobber_pos()) + Vector2(-22, -8), Color(0.72, 0.66, 0.52))
	_update_hud()
	_refresh_panel()
	return true


func _try_buy_autosell() -> void:
	if auto_sell_bought:
		return
	if coins < AUTO_SELL_COST:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= AUTO_SELL_COST
	auto_sell_bought = true
	auto_sell_on = true
	Audio.play_sfx("upgrade")
	_toast("与收鱼郎签下长约！满篓自动带走杂鱼；想留的杂鱼记得🔒上锁", 3.2, Color(0.85, 0.72, 0.42))
	_check_achievements()
	_ensure_feature_unlocks()
	_update_hud()
	_save()
	_refresh_panel()


func _toggle_autosell() -> void:
	if not auto_sell_bought:
		return
	auto_sell_on = not auto_sell_on
	Audio.play_ui("ui_click")
	_toast("鱼贩合约：%s" % ("生效中" if auto_sell_on else "已暂停"), 1.6, Color(0.85, 0.72, 0.42))
	_save()
	_refresh_panel()


# ============================ 反馈 / HUD ============================

func _setup_theme() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])
	# 衬线展示字体（设计令牌 --font-display）：标题与英雄数字用，呼应水彩卷轴气质。
	_serif = load("res://assets/fonts/NotoSerifSC-Bold.woff2")
	if _serif == null:
		_serif = _font  # 字体缺失时优雅回退系统字体，绝不崩
	_serif_num = FontVariation.new()
	_serif_num.base_font = _serif
	_serif_num.opentype_features = {"tnum": 1, "lnum": 1}  # 等宽数字（字体支持时）
	# 系统字体假粗体：无专用无衬线粗体时，用 embolden 加粗笔画，复刻 CD 的 weight 600
	_font_bold = FontVariation.new()
	_font_bold.base_font = _font
	_font_bold.variation_embolden = 0.6
	UIPanels.font_bold = _font_bold   # 供 ui_panels 的按钮/页签复用（CD weight 600-700）
	var th := Theme.new()
	th.default_font = _font
	th.default_font_size = 15
	ui_root.theme = th


func _update_hud() -> void:
	_ensure_day_stat()  # 跨天即时重置当日统计
	var bag := "鱼篓 %d/%d" % [inventory.size(), _bag_capacity()]
	if _bag_full():
		bag += "（满）"
	var mer := "　收鱼郎×1.5" if _merchant_active else ""
	var evt := ""
	if active_event != "" and EventData.hud_text(active_event) != "":
		evt = "　" + EventData.hud_text(active_event)
	var rel := ""
	if _relationship_buff_label() != "":
		rel = "　人情：" + _relationship_buff_label()
	var tm := "　🧪测试" if test_mode else ""   # 测试模式常驻角标（提醒当前改动不写档）
	coins_label.text = "金币 %s　%s%s%s%s%s" % [_coin_str(coins), bag, mer, evt, rel, tm]
	var col := Color(0.92, 0.92, 0.9)
	if _relationship_buff_label() != "":
		col = Color(0.86, 0.76, 0.45)
	elif active_event != "":
		col = EventData.color(active_event)
	elif _merchant_active:
		col = Color(0.98, 0.82, 0.40)
	elif _bag_full():
		col = Color(1.0, 0.78, 0.45)
	coins_label.add_theme_color_override("font_color", col)
	_refresh_unlocks()
	_update_spot_chip()
	_update_order_chip()
	if display_mode != "immersive":
		_update_framed_hud()   # 带框：刷新图标胶囊 + 状态标签 + 动作按钮


## HUD 当前钓点·事件小字（金币行上方，点开钓点页）。
func _build_spot_chip() -> void:
	spot_chip = Button.new()
	spot_chip.flat = true
	spot_chip.focus_mode = Control.FOCUS_NONE
	spot_chip.position = SCENE_OFF + Vector2(196, 126)
	spot_chip.add_theme_font_size_override("font_size", 14)
	spot_chip.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	spot_chip.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	spot_chip.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	spot_chip.add_theme_color_override("font_hover_color", Color(0.98, 0.90, 0.62))
	spot_chip.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		_catch_tab = 5 if _tab_unlocked(5) else _fallback_feature_tab()
		_open_panel("catch"))
	ui_root.add_child(spot_chip)


func _update_spot_chip() -> void:
	if spot_chip == null:
		return
	spot_chip.visible = _feature_unlocked("spots")
	var txt := SpotData.display_name(current_spot) + " · " + Weather.display_name(day_phase)
	var scenic := SpotData.scenic_name(current_spot, day_phase)
	if scenic != "":
		txt += " · " + scenic   # 命中招牌景观（如 河湾黎明 → 晨雾日出）
	var col := Color(0.86, 0.86, 0.82)
	if active_event != "" and EventData.hud_text(active_event) != "":
		txt += " · " + EventData.display_name(active_event)
		col = EventData.color(active_event)
	spot_chip.text = txt
	spot_chip.add_theme_color_override("font_color", col)


## HUD 订单进度小字（低调、可点开订单页）。Stardew/AC 式每日目标常驻可见。
func _build_order_chip() -> void:
	order_chip = Button.new()
	order_chip.flat = true
	order_chip.focus_mode = Control.FOCUS_NONE
	order_chip.position = SCENE_OFF + Vector2(196, 174)
	order_chip.add_theme_font_size_override("font_size", 13)
	order_chip.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	order_chip.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	order_chip.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	order_chip.add_theme_color_override("font_hover_color", Color(0.98, 0.90, 0.62))
	order_chip.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		_catch_tab = 2 if _tab_unlocked(2) else _fallback_feature_tab()
		_open_panel("catch"))
	ui_root.add_child(order_chip)


func _update_order_chip() -> void:
	if order_chip == null:
		return
	order_chip.visible = _feature_unlocked("tasks")
	_ensure_daily_order()
	if bool(daily_order.get("done", false)):
		order_chip.text = "今日订单 ✓ 已完成"
		order_chip.add_theme_color_override("font_color", Color(0.55, 0.78, 0.50))
		return
	var need := int(daily_order.get("need", 1))
	var have := mini(_daily_order_indices().size(), need)
	order_chip.text = "订单  %s  %d/%d" % [_order_short(), have, need]
	order_chip.add_theme_color_override("font_color",
		Color(0.95, 0.85, 0.5) if have >= need else Color(0.80, 0.73, 0.55))


## 面板开着时数据变了（上鱼/卖鱼/扩容），原地重建内容。
## 例外：鱼缸页签、旅行地图开着时不因后台上鱼而重建——否则游动的鱼/晨昏线每几秒被重置。
## 放入/捞出鱼等主动操作走 _rebuild_panel() 强制重建。
func _refresh_panel() -> void:
	if _dev_attrs_open:
		_refresh_dev_attrs_panel()
	if _panel_kind == "":
		return
	if _panel_kind == "catch" and _catch_tab == TANK_TAB:
		return
	if _panel_kind == "worldmap":
		return
	_open_panel(_panel_kind)


# 常驻 HUD 文字（金币行 / 钓点签 / 订单签）叠在水彩背景上，原先只设字色、
# 在湖泊/海岸等中明度底图上糊成一团。统一加暖墨描边 + 柔和投影把字「托」起来，
# 比飘字更强一档保证一眼可读，但仍是暖墨非纯黑，不破坏水彩的安静气质。
func _apply_hud_legibility() -> void:
	for node: Control in [coins_label, spot_chip, order_chip]:
		if node == null:
			continue
		node.add_theme_color_override("font_outline_color", Color(0.12, 0.09, 0.07, 0.82))
		node.add_theme_constant_override("outline_size", 5)
		node.add_theme_color_override("font_shadow_color", Color(0.06, 0.05, 0.04, 0.5))
		node.add_theme_constant_override("shadow_offset_x", 1)
		node.add_theme_constant_override("shadow_offset_y", 2)
		node.add_theme_constant_override("shadow_outline_size", 3)


# 把工程化的高饱和色调柔化为水彩气质：降饱和 + 提亮 + 轻混奶油色。
# 飘字/toast 统一过这道滤镜，整体色调与柔和场景一致。
func _soft(c: Color) -> Color:
	var s: float = c.s * 0.62
	var val: float = clampf(c.v * 0.95 + 0.08, 0.0, 1.0)
	var out := Color.from_hsv(c.h, s, val, 1.0)
	return out.lerp(Color(0.96, 0.92, 0.83), 0.14)


func _popup(text: String, pos: Vector2, color: Color) -> void:
	if focus_mode:
		return  # 专注模式下不弹频繁飘字
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _soft(color))
	# 飘字固定出现在浮漂处（水彩最密的右下角），描边/投影需与 HUD 同档才一眼可读
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.09, 0.07, 0.82))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_shadow_color", Color(0.06, 0.05, 0.04, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.position = pos
	l.z_index = 20
	ui_root.add_child(l)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", pos.y - 30.0, 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func _toast(text: String, duration: float, color := Color.WHITE) -> void:
	_msg_id += 1
	var id := _msg_id
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", _soft(color))
	toast_label.add_theme_color_override("font_outline_color", Color(0.16, 0.13, 0.10, 0.40))
	toast_label.add_theme_constant_override("outline_size", 4)
	toast_label.modulate.a = 1.0
	toast_label.visible = true
	await get_tree().create_timer(duration).timeout
	if _msg_id == id and is_instance_valid(toast_label):
		toast_label.visible = false


var _flash_cd := 0.0   # 庆祝闪光冷却（秒）：感官预算 ≤2 次/小时（balance_audit §3.7 / 标准 S17）


func _flash() -> void:
	# 上鱼庆祝光：交给场景画师做「限场景内、随羽化淡出」的柔和暖色脉冲，
	# 不再用铺满整窗的 ColorRect（那会连桌面壁纸区一起染黄、整窗大闪）。
	# 冷却 1800s + 专注模式静默：陪伴挂件的高显著动效必须稀缺，否则庆祝贬值成骚扰。
	if focus_mode or _flash_cd > 0.0:
		return
	_flash_cd = 1800.0
	if painter.has_method("catch_flash"):
		painter.catch_flash()


# ============================ 按钮 / 面板 ============================

var _spot_round_btns: Array = []   # 干净 spot 上显示的真实圆按钮（river 隐藏，用底图烤死的+命中区）


func _build_buttons() -> void:
	if painter.use_composite:
		# 所有钓场都是干净底图，统一用独立图标按钮（不再有底图烤死按钮 + 命中区的特例）
		_build_spot_buttons()
		_update_spot_buttons()
	else:
		_build_round_buttons()


# 干净 spot 底图没有烤死的按钮，这里补一组图标按钮，直接复用 Codex 的独立图标
# （ui_button_fish/rod/coin），与 river 底图烤死的那三个图标一模一样，跨钓点观感一致。
# river 用底图自带按钮 + 透明命中区，这组隐藏；切钓点时在 Spots.apply_visuals 里切显隐。
const SPOT_BTN_ICONS := {
	"catch": "res://assets/art/ui/ui_button_fish.png",
	"rod": "res://assets/art/ui/ui_button_rod.png",
	"set": "res://assets/art/ui/ui_button_coin.png",
}

func _build_spot_buttons() -> void:
	for k in []:   # 入口已全收进金币栏(点金币开面板)，主界面不再放独立按钮（撤鱼篓按钮）
		var b := TextureButton.new()
		b.texture_normal = load(SPOT_BTN_ICONS[k])
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(30, 30)
		b.size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.position = (btn_centers[k] as Vector2) + SCENE_OFF - Vector2(15, 15)
		b.visible = false
		b.mouse_entered.connect(func() -> void: b.modulate = Color(1.18, 1.14, 1.0))
		b.mouse_exited.connect(func() -> void: b.modulate = Color.WHITE)
		b.pressed.connect(func() -> void: Audio.play_ui("ui_click"))
		b.pressed.connect(_toggle_panel.bind(k))
		ui_root.add_child(b)
		_spot_round_btns.append(b)


func _update_spot_buttons() -> void:
	var clean: bool = painter.has_method("uses_clean_bg") and painter.uses_clean_bg()
	for b in _spot_round_btns:
		if is_instance_valid(b):
			b.visible = clean


## 读取 ui_layout.json（若 Codex 提供），覆盖按钮中心与落水点。
func _load_ui_layout() -> void:
	for path in UI_LAYOUT_PATHS:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary):
			continue
		var btns: Variant = data.get("buttons", {})
		if btns is Dictionary:
			for k in btn_centers.keys():
				var v: Variant = btns.get(k, btns.get("settings" if k == "set" else k, null))
				if v is Array and v.size() >= 2:
					btn_centers[k] = Vector2(float(v[0]), float(v[1]))
		var bp: Variant = data.get("bite_point", null)
		if bp is Array and bp.size() >= 2:
			painter.bite_point = Vector2(float(bp[0]), float(bp[1]))
		return


# 程序化回退模式：纸色圆按钮（只剩篓；升级/设置都并入鱼篓面板页签）。
func _build_round_buttons() -> void:
	var defs := []   # 入口已收进金币栏，主界面无独立圆按钮（程序化回退模式同步）
	var x := 436.0
	for d in defs:
		var b := _round_button(d[0])
		b.position = Vector2(x, 362) + SCENE_OFF
		b.pressed.connect(_toggle_panel.bind(d[1]))
		ui_root.add_child(b)
		x += 38.0


func _round_button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(32, 32)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.94, 0.88, 0.92)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.5, 0.5, 0.45, 0.5)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(1.0, 0.98, 0.92, 0.98)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_color_override("font_color", Color(0.3, 0.3, 0.28))
	return b


func _toggle_panel(kind: String) -> void:
	Audio.play_ui("ui_click")
	if _panel_kind == kind:
		_close_panel()
	else:
		_open_panel(kind)


var _catch_tab := 0  # 0=鱼篓 1=图鉴 2=订单 3=成就
var _bag_sort := 0   # 0=最新 1=价值 2=品阶 3=重量
var _bag_filter_order := false  # 只看订单目标鱼
var _sell_tier := 0   # 批量“卖掉XX及以下”的品阶上限（0=普通）
const BAG_SORT_NAMES := ["最新", "价值", "品阶", "重量"]


## 鱼图标：只加载已通过美术验收的专属图；未批准/缺失时回退到同品阶旧风格图标。
var _tier_icon_cache := {}
const APPROVED_FISH_ICON_IDS := {
	"whitebait": true,
	"topmouth": true,
	"loach": true,
	"crucian": true,
	"bighead": true,
	"yellowhead": true,
	"dace": true,
	"carp": true,
	"grass": true,
	"bream": true,
	"blackcarp": true,
	"bass": true,
	"fangbream": true,
	"barbel": true,
	"culter": true,
	"mandarin": true,
	"snakehead": true,
	"trout": true,
	"pike": true,
	"zander": true,
	"longsnout": true,
	"lenok": true,
	"koi": true,
	"salmon": true,
	"sturgeon": true,
	"taimen": true,
	"chinese_sturgeon": true,
	"kaluga": true,
}
const GENERIC_FISH_ICON_BY_TIER := [
	"whitebait",
	"carp",
	"bass",
	"snakehead",
	"koi",
	"chinese_sturgeon",
]
func _fish_icon(id: String, size := 42) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(size, size)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = _fish_texture(id)
	return tr


## 取鱼的贴图（未批准或专属图缺失则回退品阶通用图），供水族箱等需要裸 Texture2D 的地方复用。
func _fish_texture(id: String) -> Texture2D:
	if APPROVED_FISH_ICON_IDS.has(id):
		var path := "res://assets/art/fish/%s.png" % id
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return _generic_fish_texture(FishData.tier_of(id))


## 按品阶的通用鱼图标：使用旧有已批准水彩图标，最后才生成中性占位，按品阶缓存。
func _generic_fish_texture(tier: int) -> Texture2D:
	tier = clampi(tier, 0, FishData.TIER_COLORS.size() - 1)
	if _tier_icon_cache.has(tier):
		return _tier_icon_cache[tier]
	var approved_id := str(GENERIC_FISH_ICON_BY_TIER[tier])
	var asset := "res://assets/art/fish/%s.png" % approved_id
	var tex: Texture2D
	if ResourceLoader.exists(asset):
		tex = load(asset) as Texture2D
	else:
		tex = _make_generic_fish(Color(0.55, 0.53, 0.46))
	_tier_icon_cache[tier] = tex
	return tex


## 程序化小鱼剪影（品阶色 + 柔边 + 鱼尾 + 眼点），水彩淡墨气质，作缺图回退。
func _make_generic_fish(col: Color) -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := s * 0.52
	var cy := s * 0.5
	var rx := s * 0.30
	var ry := s * 0.19
	for y in s:
		for x in s:
			var a := 0.0
			# 鱼身：椭圆，向边缘柔化
			var dx := (x - cx) / rx
			var dy := (y - cy) / ry
			var d := dx * dx + dy * dy
			if d <= 1.0:
				a = clampf(0.9 - d * 0.45, 0.4, 0.9)
			# 鱼尾：左侧三角
			var tx := cx - rx * 0.78
			if x <= tx and x >= tx - s * 0.16:
				var span := (tx - x) / (s * 0.16)
				if absf(y - cy) <= span * s * 0.16:
					a = maxf(a, 0.75)
			if a > 0.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	# 眼点
	var ex := int(cx + rx * 0.45)
	var ey := int(cy - ry * 0.25)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var px := ex + ox
			var py := ey + oy
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, Color(0.12, 0.11, 0.10, 0.85))
	return ImageTexture.create_from_image(img)


func _tier_color(tier: int) -> Color:
	return FishData.TIER_COLORS[clampi(tier, 0, FishData.TIER_COLORS.size() - 1)]


func _ui_tier_color(tier: int, on_paper := false) -> Color:
	if tier == 0:
		return Color(0.38, 0.37, 0.33) if on_paper else Color(0.86, 0.84, 0.78)
	return _tier_color(tier)


## —— 面板：薄壳委托 UIPanels（实现见 ui_panels.gd，行为不变）——
func _open_panel(kind: String) -> void:
	if kind == "catch" and not _tab_unlocked(_catch_tab):
		_catch_tab = _fallback_feature_tab()
	UIPanels.open_panel(self, kind)


func _close_panel() -> void:
	var closing_relationship_visit := _panel_kind == "relationship_visit"
	UIPanels.close_panel(self)
	if closing_relationship_visit:
		_end_relationship_visit_session()


func _open_fish_detail(id: String) -> void:
	_detail_fish = id
	_open_panel("fishdetail")


func _set_catch_tab(tab: int) -> void:
	_catch_tab = tab if _tab_unlocked(tab) else _fallback_feature_tab()
	_open_panel("catch")


# ============================ 每日订单 ============================

## 订单/周目标/今日统计：薄壳委托 Orders（实现见 orders.gd，行为不变）。
func _today_key() -> String:
	return Orders.today_key()


func _ensure_day_stat() -> void:
	Orders.ensure_day_stat(self)


func _today_catches() -> int:
	return Orders.today_catches(self)


func _today_income() -> int:
	return Orders.today_income(self)


func _ensure_daily_order() -> void:
	Orders.ensure_daily_order(self)


func _make_daily_order(date_key: String) -> Dictionary:
	return Orders.make_daily_order(self, date_key)


func _rep_fish_of_tier(t: int, local: RandomNumberGenerator, pool: Array = []) -> String:
	return Orders.rep_fish_of_tier(t, local, pool)


func _order_matches(c: Dictionary) -> bool:
	return Orders.order_matches(self, c)


func _order_title() -> String:
	return Orders.order_title(self)


func _order_short() -> String:
	return Orders.order_short(self)


func _is_daily_order_target(id: String) -> bool:
	return Orders.is_daily_order_target(self, id)


func _daily_order_indices() -> Array:
	return Orders.daily_order_indices(self)


func _daily_order_reward(indices: Array) -> int:
	return Orders.daily_order_reward(self, indices)


func _try_complete_daily_order() -> void:
	Orders.try_complete_daily_order(self)


func _week_id() -> int:
	return Orders.week_id()


func _ensure_weekly() -> void:
	Orders.ensure_weekly(self)


func _ensure_competition() -> void:
	Competition.ensure(self)


func _make_weekly(wk: int) -> Dictionary:
	return Orders.make_weekly(self, wk)


func _weekly_progress() -> int:
	return Orders.weekly_progress(self)


func _weekly_desc() -> String:
	return Orders.weekly_desc(self)


func _try_claim_weekly() -> void:
	Orders.try_claim_weekly(self)



## 按当前排序返回背包显示用的真实索引序列。filter_order=true 时只保留符合当前订单的鱼
## （按 _order_matches，兼容指定鱼种/品阶/大物/完美各类订单，而非仅图标代表鱼）。
func _sorted_bag_indices(filter_order: bool) -> Array:
	var idxs: Array = []
	for i in inventory.size():
		if filter_order and not _order_matches(inventory[i]):
			continue
		idxs.append(i)
	match _bag_sort:
		1:  # 价值降序
			idxs.sort_custom(func(a, b): return _sell_value(inventory[a]) > _sell_value(inventory[b]))
		2:  # 品阶降序，同阶按价值
			idxs.sort_custom(func(a, b):
				var ta := FishData.tier_of(str(inventory[a]["id"]))
				var tb := FishData.tier_of(str(inventory[b]["id"]))
				if ta != tb:
					return ta > tb
				return _sell_value(inventory[a]) > _sell_value(inventory[b]))
		3:  # 重量降序
			idxs.sort_custom(func(a, b): return float(inventory[a]["w"]) > float(inventory[b]["w"]))
		_:  # 最新（后进先出）
			idxs.reverse()
	return idxs


func _toggle_lock(idx: int) -> void:
	if idx < 0 or idx >= inventory.size():
		return
	var c: Dictionary = inventory[idx]
	c["lock"] = not bool(c.get("lock", false))
	_refresh_panel()
	_save()


# 流动鱼贩在场时卖价 ×1.5（向上取整）。
# 音频薄壳：供早解析的全局类（如 Decor）经 g 调用，避开它们直接引用 Audio 自动加载。
func _play_sfx(n: String) -> void:
	Audio.play_sfx(n)


func _play_ui(n: String) -> void:
	Audio.play_ui(n)


func _sell_value(c: Dictionary) -> int:
	var v := float(c["v"]) * (1.0 + Decor.value_bonus(self))  # 陈列加成（封顶 +5%）
	if _merchant_active:
		v *= MERCHANT_MULT
	return int(ceil(v))


func _sell_one(idx: int) -> void:
	if idx < 0 or idx >= inventory.size():
		return
	if bool(inventory[idx].get("lock", false)):
		_toast("这条鱼已上锁收藏", 1.5, Color(0.95, 0.78, 0.42))
		return
	var c: Dictionary = inventory[idx]
	inventory.remove_at(idx)
	var v := _sell_value(c)
	_add_coins_safe(v)
	_add_lifetime_coins_safe(v)
	Audio.play_sfx("coin")
	_toast("卖出 %s +%s%s" % [FishData.display_name(c["id"]), _coin_str(v),
		"（鱼贩×1.5）" if _merchant_active else ""], 1.5, Color(0.85, 0.7, 0.35))
	_check_achievements()
	_ensure_feature_unlocks()
	_update_hud()
	_refresh_panel()
	_save()


func _sell_all() -> void:
	var total := 0
	var n := 0
	var keep: Array = []
	for c in inventory:
		if bool(c.get("lock", false)):
			keep.append(c)       # 收藏锁：跳过锁定的鱼
		else:
			total += _sell_value(c)
			n += 1
	if n == 0:
		return
	inventory = keep
	_add_coins_safe(total)
	_add_lifetime_coins_safe(total)
	Audio.play_sfx("coin")
	var msg := "卖出 %d 条鱼 +%s 金币%s" % [n, _coin_str(total), "（鱼贩×1.5）" if _merchant_active else ""]
	if not keep.is_empty():
		msg += "（%d 条收藏留着）" % keep.size()
	_toast(msg, 2.2, Color(0.85, 0.7, 0.35))
	_check_achievements()
	_ensure_feature_unlocks()
	_update_hud()
	_refresh_panel()
	_save()


## 卖杂鱼：卖出未上锁、非当前订单目标、非珍稀（鎏金/七彩/★★★）的鱼。
## 珍稀护栏与鱼贩合约/订单排除同口径——"一键卖杂鱼"不该卖掉失焦时钓到的七彩（对抗审查）。
func _sell_junk() -> void:
	var total := 0
	var n := 0
	var keep: Array = []
	for c in inventory:
		if bool(c.get("lock", false)) or _order_matches(c) \
				or int(c.get("var", 0)) >= 2 or int(c.get("q", 0)) >= 3:
			keep.append(c)
		else:
			total += _sell_value(c)
			n += 1
	if n == 0:
		return
	inventory = keep
	_add_coins_safe(total)
	_add_lifetime_coins_safe(total)
	Audio.play_sfx("coin")
	_toast("卖出杂鱼 %d 条 +%s 金币（订单鱼与收藏保留）" % [n, _coin_str(total)], 2.2, Color(0.85, 0.7, 0.35))
	_check_achievements()
	_update_hud()
	_refresh_panel()
	_save()


## 批量「卖掉≤某品阶及以下」：未上锁、非订单、非珍稀（鎏金/七彩/★★★）、
## 且品阶 ≤ 选定品阶的鱼（收藏锁保留）。按钮永远可点，空集合时给提示避免“点不动”错觉。
func _sell_below_tier(tier: int) -> void:
	var total := 0
	var n := 0
	var keep: Array = []
	for c in inventory:
		if bool(c.get("lock", false)) or _order_matches(c) \
				or int(c.get("var", 0)) >= 2 or int(c.get("q", 0)) >= 3 \
				or FishData.tier_of(str(c["id"])) > tier:
			keep.append(c)       # 锁/订单/珍稀/高于选定品阶：跳过
		else:
			total += _sell_value(c)
			n += 1
	if n == 0:
		_toast("没有可卖的%s及以下的鱼（订单鱼与收藏已保留）" % FishData.TIER_NAMES[tier], 2.0)
		return
	inventory = keep
	_add_coins_safe(total)
	_add_lifetime_coins_safe(total)
	Audio.play_sfx("coin")
	var msg := "卖出 %d 条%s及以下鱼 +%s 金币%s" % [n, FishData.TIER_NAMES[tier], _coin_str(total),
		"（鱼贩×1.5）" if _merchant_active else ""]
	_toast(msg, 2.2, Color(0.85, 0.7, 0.35))
	_check_achievements()
	_ensure_feature_unlocks()
	_update_hud()
	_refresh_panel()
	_save()


# ============================ 流动鱼贩 ============================

func _tick_merchant(delta: float) -> void:
	_merchant_t -= delta
	if _merchant_t > 0.0:
		return
	if _merchant_active:
		_merchant_active = false
		_merchant_t = rng.randf_range(MERCHANT_GAP.x, MERCHANT_GAP.y)
		_toast("收鱼郎走了，下次再来～", 2.4, Color(0.7, 0.66, 0.58))
	else:
		_merchant_active = true
		_merchant_t = rng.randf_range(MERCHANT_DUR.x, MERCHANT_DUR.y)
		_toast("收鱼郎来了！限时收购，全部卖价 ×1.5", 3.5, Color(0.98, 0.82, 0.40))
	_update_hud()
	_refresh_panel()


# ============================ 随机事件（EventData 驱动）============================

## 随机事件：薄壳委托 Events（实现见 events.gd，行为不变）。
func _eligible_events() -> Array:
	return Events.eligible(self)


func _tick_events(delta: float) -> void:
	Events.tick(self, delta)


func _fire_event(forced := "") -> void:
	Events.fire(self, forced)


# ============================ 多钓点 ============================

## 钓点控制：薄壳委托 Spots（实现见 spots.gd，行为不变）。
func _refresh_unlocks() -> void:
	Spots.refresh_unlocks(self)
	_ensure_feature_unlocks()


func _switch_spot(id: String) -> void:
	Spots.switch_to(self, id)


func _apply_spot_visuals() -> void:
	Spots.apply_visuals(self)
	_update_spot_buttons()
	Audio.set_ambience_scene(current_spot, day_phase)   # 切钓点 → 环境床随生态重铺


func _order_pool() -> Array:
	return Spots.order_pool(self)


func _best_spot_for(fish_id: String) -> String:
	return Spots.best_spot_for(self, fish_id)


func _try_expand_bag() -> void:
	if bag_level > BAG_COSTS.size():
		return
	var cost: int = BAG_COSTS[bag_level - 1]
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= cost
	bag_level += 1
	_record_equipment_spend(cost)
	Audio.play_sfx("upgrade")
	_toast("鱼篓扩到 %d 格！" % _bag_capacity(), 2.2, Color(0.5, 0.8, 1.0))
	_check_achievements()
	_update_hud()
	_refresh_panel()
	_save()


# ============================ 成就 ============================

## 判定单条成就是否达成（对照当前状态）。
func _ach_done(a: Dictionary) -> bool:
	match str(a["kind"]):
		"catches": return lifetime_catches >= int(a["n"])
		"coins": return lifetime_coins >= int(a["n"])
		"species": return dex.size() >= int(a["n"])
		"species_all": return dex.size() >= FishData.FISH.size()
		"tier": return _best_tier_caught() >= int(a["n"])
		"giant": return caught_giant
		"quality": return best_quality >= int(a["n"])
		"bag": return bag_level >= int(a["n"])
		"rod": return rod_level >= int(a["n"])
		"bait": return bait_level >= int(a["n"])
		"hook": return hook_level >= int(a["n"])
		"lure": return lure_level >= int(a["n"])
		"maxweight": return _dex_max_weight() >= float(a["n"])
		"display": return display.size() >= int(a["n"])
		"variant": return best_variant >= int(a["n"])
		"focus_minutes": return focus_minutes_total >= float(a["n"])
		"pet_steals": return pet_steals >= int(a["n"])
		"vgrid": return _vgrid_count() >= int(a["n"])
		"comp_wins": return int(competition.get("wins", 0)) >= int(a["n"])
	return false


## 已点亮的变体格总数（657 收集轴 = Σ 每鱼 vmask 置位数；vgrid 成就用）。
func _vgrid_count() -> int:
	var n := 0
	for id in dex:
		var vm := int(dex[id].get("vmask", 0))
		for vi in range(1, 4):
			if vm & (1 << vi):
				n += 1
	return n


## 图鉴里记录到的最大单条体重（用于重量里程碑成就）。
func _dex_max_weight() -> float:
	var m := 0.0
	for id in dex:
		m = maxf(m, float(dex[id]["w"]))
	return m


func _best_tier_caught() -> int:
	var best := -1
	for id in dex:
		best = maxi(best, FishData.tier_of(str(id)))
	return best


## 扫描所有未达成成就，新达成的发 toast + 发奖励。
## silent=true 用于载入老存档时静默补登已满足的成就（不发 toast / 不补发奖励）。
func _check_achievements(silent := false) -> void:
	for a in AchievementData.LIST:
		var id: String = a["id"]
		if achievements_done.has(id):
			continue
		if _ach_done(a):
			achievements_done[id] = true
			if silent:
				continue
			var reward := int(a.get("reward", 0))
			if reward > 0:
				_add_coins_safe(reward)
			Audio.play_sfx("sfx_achievement")   # 42 项成就此前只有 toast，全程无声
			var msg := "成就达成：%s" % a["name"]
			if reward > 0:
				msg += "（+%s 金币）" % _coin_str(reward)
			_toast(msg, 3.0, Color(0.98, 0.85, 0.45))


## 某竿级的平均一竿周期（等待均值 + 咬钩 0.9s）——装备页数字明牌与离线结算共用同一真值。
func _avg_wait_for(lv: int) -> float:
	return (5.25 * maxf(0.4, 1.0 - float(lv - 1) * 0.04) + 0.9) * _speed_wait_mult() * _reaction_wait_mult()


func _avg_wait_for_reel(lv: int) -> float:
	return (5.25 * maxf(0.4, 1.0 - float(rod_level - 1) * 0.04) + 0.9) \
		* AnglerEquipmentScript.reel_wait_mult(lv) * _reaction_wait_mult()


func _speed_wait_mult() -> float:
	return AnglerEquipmentScript.reel_wait_mult(reel_level)


func _reel_speed() -> float:
	return AnglerEquipmentScript.reel_stats(reel_level).speed


func _reel_speed_for(lv: int) -> float:
	return AnglerEquipmentScript.reel_stats(lv).speed


func _reel_upgrade_cost(count: int) -> float:
	return AnglerEquipmentScript.equipment_upgrade_cost("reel", reel_level, count)


func _gear_level(id: String) -> int:
	match id:
		"fish_line": return fish_line_level
		"bobber": return bobber_level
		"sonar": return sonar_level
		"notebook": return notebook_level
		"gloves": return gloves_level
		_: return 0


func _set_gear_level(id: String, level: int) -> void:
	level = maxi(0, level)
	match id:
		"fish_line": fish_line_level = level
		"bobber": bobber_level = level
		"sonar": sonar_level = level
		"notebook": notebook_level = level
		"gloves": gloves_level = level


func _gear_upgrade_cost(id: String, count: int) -> float:
	return AnglerEquipmentScript.equipment_upgrade_cost(id, _gear_level(id), count)


func _gear_stats(id: String, level := -1):
	var lv := _gear_level(id) if level < 0 else level
	return AnglerEquipmentScript.attr_equipment_stats(id, lv)


func _angler_stats():
	var stats = AnglerEquipmentScript.reel_stats(reel_level)
	for id in AnglerEquipmentScript.ATTR_EQUIPMENT_ORDER:
		stats.add(_gear_stats(str(id)))
	return stats


func _equipment_unlocked(id: String) -> bool:
	match id:
		"fish_line": return true
		"reel": return reel_level > 0
		_: return _gear_level(id) > 0


func _equipment_chain() -> Array:
	return AnglerEquipmentScript.equipment_order()


func _visible_equipment_chain() -> Array:
	var chain := _equipment_chain()
	var visible := []
	for i in chain.size():
		var id := str(chain[i])
		if _equipment_unlocked(id):
			visible.append(id)
			continue
		if i > 0 and _equipment_unlocked(str(chain[i - 1])):
			visible.append(id)
		break
	return visible


func _equipment_unlock_cost(id: String) -> float:
	return AnglerEquipmentScript.equipment_unlock_cost(id)


func _equipment_unlock_note(id: String) -> String:
	return AnglerEquipmentScript.equipment_unlock_note(id)


func _try_unlock_equipment(id: String) -> void:
	if _equipment_unlocked(id):
		return
	var chain := _equipment_chain()
	var idx := chain.find(id)
	if idx <= 0 or not _equipment_unlocked(str(chain[idx - 1])):
		return
	var cost := _equipment_unlock_cost(id)
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= cost
	if id == "reel":
		reel_level = 1
		_begin_wait()
	else:
		_set_gear_level(id, 1)
	_record_equipment_spend(cost)
	var name := "绕线轮" if id == "reel" else str(AnglerEquipmentScript.ATTR_EQUIPMENT[id]["name"])
	Audio.play_sfx("upgrade")
	_update_hud()
	_toast("%s 已解锁 Lv.1" % name, 2.4, Color(0.72, 0.92, 0.58))
	_save()
	_refresh_panel()


## 把一条渔获强制抬到保底品相/变体（重算卖价）。试竿保底与专注奖励共用的抬品逻辑。
func _force_catch_grade(c: Dictionary, min_q: int, min_var: int) -> void:
	var old_q := int(c.get("q", 0))
	var old_v := int(c.get("var", 0))
	var nq := maxi(old_q, min_q)
	var nv := maxi(old_v, min_var)
	if nq == old_q and nv == old_v:
		return
	var mult: float = FishData.QUALITY_MULTS[nq] / FishData.QUALITY_MULTS[old_q] \
		* FishData.VARIANT_MULTS[nv] / FishData.VARIANT_MULTS[old_v]
	c["q"] = nq
	c["var"] = nv
	c["v"] = maxi(1, int(round(float(c["v"]) * mult)))


func _rod_cost() -> float:
	# 陡成本曲线：让鱼竿成为真正的长期金币去向（旧 40×1.8^n 几乎零成本）。
	# 400×1.7^n：成本增速(1.7/级) 高于产出增速(~1.1~1.25/级)，回本时间平滑递增形成减速带，
	# 且不在等待封顶级(Lv16)附近产生回本悬崖（数值依据 docs/balance_audit_2026-07-06.md）。
	return _safe_econ_number(400.0 * pow(1.7, rod_level - 1))


func _try_upgrade_rod() -> void:
	var cost := _rod_cost()
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= cost
	rod_level += 1
	_record_equipment_spend(cost)
	showcase_pending = "rod"
	Audio.play_sfx("upgrade")
	_check_achievements()
	_update_hud()
	_toast("鱼竿 Lv.%d！咬钩 %.1fs→%.1fs · 卖价 +%d%%（下一竿试竿手感）" % [rod_level,
		_avg_wait_for(rod_level - 1), _avg_wait_for(rod_level), (rod_level - 1) * 8],
		2.8, Color(0.5, 0.8, 1.0))
	_refresh_panel()   # 升级页已是鱼篓面板「装备」页签，原地刷新即可


func _try_upgrade_reel(count := 1) -> void:
	count = maxi(1, count)
	var before_speed := _reel_speed()
	var before_interval := _avg_wait_for_reel(reel_level)
	var cost := _reel_upgrade_cost(count)
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= cost
	reel_level += count
	_record_equipment_spend(cost)
	_begin_wait()
	Audio.play_sfx("upgrade")
	_update_hud()
	_toast("绕线轮 Lv.%d！速度 %.1f→%.1f，一竿 %.2fs→%.2fs" % [
		reel_level, before_speed, _reel_speed(), before_interval, _avg_wait_for_reel(reel_level)],
		2.8, Color(0.58, 0.80, 0.98))
	_save()
	_refresh_panel()


func _try_downgrade_reel(count := 1) -> void:
	count = maxi(1, count)
	if reel_level <= 0:
		return
	var before_speed := _reel_speed()
	reel_level = maxi(0, reel_level - count)
	Audio.play_sfx("upgrade")
	_update_hud()
	_toast("绕线轮 Lv.%d，速度属性 %.0f→%.0f" % [reel_level, before_speed, _reel_speed()],
		2.2, Color(0.58, 0.80, 0.98))
	_save()
	_refresh_panel()


func _try_upgrade_attr_gear(id: String, count := 1) -> void:
	if not AnglerEquipmentScript.ATTR_EQUIPMENT.has(id):
		return
	count = maxi(1, count)
	var cost := _gear_upgrade_cost(id, count)
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	var before_level := _gear_level(id)
	var before_stats = _gear_stats(id)
	coins -= cost
	_set_gear_level(id, before_level + count)
	_record_equipment_spend(cost)
	Audio.play_sfx("upgrade")
	_update_hud()
	var info: Dictionary = AnglerEquipmentScript.ATTR_EQUIPMENT[id]
	_toast("%s Lv.%d！%s" % [
		str(info["name"]), _gear_level(id), _gear_delta_text(before_stats, _gear_stats(id))],
		2.6, Color(0.72, 0.92, 0.58))
	_save()
	_refresh_panel()


func _gear_delta_text(before, after) -> String:
	var labels := {
		"technique": "技巧",
		"stability": "稳定",
		"reaction": "反应",
		"perception": "感知",
		"ecology": "生态",
		"tracking": "追踪",
		"strength": "力量",
	}
	var parts: Array[String] = []
	for key in labels.keys():
		var b := float(before.get(str(key)))
		var a := float(after.get(str(key)))
		if not is_equal_approx(b, a):
			parts.append("%s %.1f→%.1f" % [labels[key], b, a])
	return "，".join(parts)


func _try_upgrade_bait() -> void:
	if bait_level >= FishData.BAITS.size() - 1:
		return
	var nxt: Dictionary = FishData.BAITS[bait_level + 1]
	var cost := int(nxt["cost"])
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	var old_p1 := float((FishData.BAITS[bait_level]["probs"] as Array)[1])
	coins -= cost
	bait_level += 1
	_record_equipment_spend(cost)
	showcase_pending = "bait"
	Audio.play_sfx("upgrade")
	_check_achievements()
	_update_hud()
	_toast("换上%s！★率 %d%%→%d%%（下一竿保底新星级）" % [nxt["name"],
		int(old_p1 * 100.0), int(float((nxt["probs"] as Array)[1]) * 100.0)], 2.8, Color(0.6, 0.85, 0.5))
	_save()
	_refresh_panel()   # 升级页已是鱼篓面板「装备」页签，原地刷新即可


func _try_upgrade_hook() -> void:
	if hook_level >= FishData.HOOKS.size() - 1:
		return
	var nxt: Dictionary = FishData.HOOKS[hook_level + 1]
	var cost := int(nxt["cost"])
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= cost
	hook_level += 1
	_record_equipment_spend(cost)
	showcase_pending = "hook"
	Audio.play_sfx("upgrade")
	_check_achievements()
	_update_hud()
	_toast("换上%s！双钩率 %d%%（下一竿必双钩）" % [nxt["name"],
		int(float(nxt["double"]) * 100.0)], 2.8, Color(0.6, 0.85, 0.5))
	_save()
	_refresh_panel()   # 升级页已是鱼篓面板「装备」页签，原地刷新即可


func _try_upgrade_lure() -> void:
	if lure_level >= FishData.LURES.size() - 1:
		return
	var nxt: Dictionary = FishData.LURES[lure_level + 1]
	var cost := int(nxt["cost"])
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= cost
	lure_level += 1
	_record_equipment_spend(cost)
	showcase_pending = "lure"
	Audio.play_sfx("upgrade")
	_check_achievements()
	_update_hud()
	_toast("撒下%s！七彩几率 ×%.1f（下一竿保底斑斓）" % [nxt["name"],
		1.0 + float(nxt["vbias"])], 2.8, Color(0.78, 0.62, 0.95))
	_save()
	_refresh_panel()   # 升级页已是鱼篓面板「装备」页签，原地刷新即可


func _set_opacity(val: float) -> void:
	_opacity = val
	painter.modulate.a = val
	coins_label.modulate.a = val


## 水彩纸纹开关：纯设值 + 应用到 painter（每帧自重绘，立即可见）；存档/刷新由调用方负责（同 _set_opacity）。
func _set_paper_grain(on: bool) -> void:
	paper_grain = on
	if painter != null:
		painter.paper_grain = on


## 帧率上限：非法值回落到 30；纯设值 + 应用，存档/刷新由调用方负责（同 _set_opacity）。
func _set_max_fps(val: int) -> void:
	max_fps = val if val in FPS_OPTIONS else 120
	Engine.max_fps = max_fps


## 屏幕可用区能容纳的最大缩放（留 2% 边距，避免顶满屏幕）。
func _max_scale_for_screen() -> float:
	if DisplayServer.get_name() == "headless":
		return UI_SCALE_MAX
	var st := _stage_size()
	var fit := minf(st.x / ART.x, st.y / ART.y) * 0.98
	return clampf(fit, UI_SCALE_MIN, UI_SCALE_MAX)


## 界面缩放（设置页「快捷跳档」按钮 / 存档载入走这里）：设值 + 整窗等比改尺寸 +
## 以原中心为锚夹到屏幕。canvas_items 拉伸 → 成品图整体缩放，含小字一起变大，布局不变、不溢出。
## 沉浸模式的羽化/穿透按设计空间标定，不在此缩放（避免裁切错位）。自由拖拽缩放见 _build_resize_grips。
func _set_ui_scale(val: float) -> void:
	if DisplayServer.get_name() == "headless" or display_mode == "immersive":
		ui_scale = clampf(val, UI_SCALE_MIN, UI_SCALE_MAX)
		return
	_ensure_widget_pos()
	var center := (_widget_pos as Vector2) + _widget_size() * 0.5
	ui_scale = clampf(val, UI_SCALE_MIN, _max_scale_for_screen())
	_widget_pos = _clamp_widget_pos(center - _widget_size() * 0.5)
	_layout_widget()


## 自绘缩放手柄：无边框窗口没有系统边框可拖，于是在画布四边四角放隐形热区 Control。
## canvas_items 拉伸下画布恒为 WIN(1040×720)，故热区用固定 WIN 坐标即可永远贴着窗口边。
func _build_resize_grips() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var t := 6.0    # 边热区厚度
	var c := 16.0   # 角热区边长
	var w := ART.x
	var h := ART.y
	# [pos_x, pos_y, size_x, size_y, 光标, 锚点归一化(拖动不动点), 驱动轴向]
	var defs := [
		[0.0, c, t, h - 2 * c,        Control.CURSOR_HSIZE,     Vector2(1, 0.5), Vector2(-1, 0)],   # 左
		[w - t, c, t, h - 2 * c,      Control.CURSOR_HSIZE,     Vector2(0, 0.5), Vector2(1, 0)],    # 右
		[c, 0.0, w - 2 * c, t,        Control.CURSOR_VSIZE,     Vector2(0.5, 1), Vector2(0, -1)],   # 上
		[c, h - t, w - 2 * c, t,      Control.CURSOR_VSIZE,     Vector2(0.5, 0), Vector2(0, 1)],    # 下
		[0.0, 0.0, c, c,              Control.CURSOR_FDIAGSIZE, Vector2(1, 1), Vector2(-1, -1)],    # 左上
		[w - c, 0.0, c, c,            Control.CURSOR_BDIAGSIZE, Vector2(0, 1), Vector2(1, -1)],     # 右上
		[0.0, h - c, c, c,            Control.CURSOR_BDIAGSIZE, Vector2(1, 0), Vector2(-1, 1)],     # 左下
		[w - c, h - c, c, c,          Control.CURSOR_FDIAGSIZE, Vector2(0, 0), Vector2(1, 1)],      # 右下
	]
	for d in defs:
		var grip := Control.new()
		grip.mouse_filter = Control.MOUSE_FILTER_STOP
		grip.mouse_default_cursor_shape = d[4]
		grip.set_meta("base_pos", Vector2(d[0], d[1]))
		grip.set_meta("base_size", Vector2(d[2], d[3]))
		grip.gui_input.connect(_on_grip_input.bind(d[5], d[6], d[4]))
		ui_root.add_child(grip)
		_resize_grips.append(grip)
	_layout_resize_grips()


func _layout_resize_grips() -> void:
	if _resize_grips.is_empty():
		return
	for grip in _resize_grips:
		if not is_instance_valid(grip):
			continue
		var bp: Vector2 = grip.get_meta("base_pos")
		var bs: Vector2 = grip.get_meta("base_size")
		grip.position = _widget_point(bp)
		grip.size = bs * ui_scale


## 手柄被按下 → 记录锚点/轴向/起始几何，进入缩放拖拽（后续移动/松手在 _input 全局处理）。
func _on_grip_input(event: InputEvent, anchor_norm: Vector2, dir: Vector2, cursor: int) -> void:
	if _rz_active or display_mode == "immersive" or _panel_kind != "":
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_rz_active = true
		_rz_anchor = anchor_norm
		_rz_dir = dir
		_rz_start_mouse = Vector2i(get_viewport().get_mouse_position())
		_rz_start_pos = Vector2i(_widget_pos as Vector2)
		_rz_start_size = Vector2i(_widget_size())
		Input.set_default_cursor_shape(cursor)


## 拖拽缩放：按驱动轴推算等比缩放，锚点（拖动不动的那角/边）屏幕坐标保持不变。
## 我们自己接管鼠标 → 无系统模态循环，实时改尺寸不打架。
func _apply_grip_resize(_mouse_global: Vector2i) -> void:
	var delta := get_viewport().get_mouse_position() - Vector2(_rz_start_mouse)
	var raw_w := float(_rz_start_size.x) + _rz_dir.x * delta.x
	var raw_h := float(_rz_start_size.y) + _rz_dir.y * delta.y
	var sc := ui_scale
	if _rz_dir.x != 0.0 and _rz_dir.y != 0.0:
		sc = maxf(raw_w / ART.x, raw_h / ART.y)   # 角：取较大轴，跟手
	elif _rz_dir.x != 0.0:
		sc = raw_w / ART.x
	else:
		sc = raw_h / ART.y
	sc = clampf(sc, UI_SCALE_MIN, _max_scale_for_screen())
	ui_scale = sc
	var new_size := Vector2(ART) * sc
	var anchor_global := Vector2(_rz_start_pos) + Vector2(_rz_start_size) * _rz_anchor
	_widget_pos = _clamp_widget_pos(anchor_global - new_size * _rz_anchor)
	_layout_widget()


## 专注/安静模式：停小动物事件 + 抑制飘字（_popup 已守卫）+ 场景轻微变暗。
func _set_focus(on: bool) -> void:
	focus_mode = on
	if painter.has_method("set_quiet"):
		painter.set_quiet(on)
	_set_opacity(_opacity)  # 重新应用，叠加 focus 暗化
	if on:
		painter.modulate.a = _opacity * 0.8


# ============================ 专注奖励（Task 5）============================

## 每帧推进专注/无操作计时；失焦累计连续专注，达阈值发奖励；并同步渔夫情绪上下文。
func _tick_focus(delta: float) -> void:
	_focus_grace_t = maxf(0.0, _focus_grace_t - delta)
	if _window_focused:
		_idle_t += delta            # 看着它发呆 → 渔夫会打盹
	else:
		_focus_away_t += delta      # 你在别处忙 → 累计专注
		focus_minutes_total += delta / 60.0
		_check_focus_thresholds()
	_update_fisher_context()


## 跨越 25/50 分钟阈值则发奖励（每段每档只发一次，且受每日封顶约束）。
func _check_focus_thresholds() -> void:
	_ensure_focus_day()
	if focus_reward_today >= FOCUS_REWARD_DAILY_CAP:
		return
	if _focus_granted < 1 and _focus_away_t >= FOCUS_T1:
		_focus_granted = 1
		_grant_focus_reward(1)
	if _focus_granted < 2 and _focus_away_t >= FOCUS_T2 and focus_reward_today < FOCUS_REWARD_DAILY_CAP:
		_focus_granted = 2
		_grant_focus_reward(2)


func _grant_focus_reward(level: int) -> void:
	# 每日额度按「兑现」计（在 _apply_focus_reward），发放不占额——同段 T1+T2 合并只算 1 次，
	# 修掉"满篓停竿吞掉 25 分钟档、额度双扣只兑一半"的坑（balance_audit §3.5）。
	focus_pending = maxi(focus_pending, level)
	var mins := 25 if level == 1 else 50
	# 风铃。玩家此刻正背着窗口做别的事，这一声要能被听见、又不至于打断——
	# 素材已刻意做到近乎不可闻（peak 0.20，全曲最低）。
	Audio.play_sfx("sfx_focus_reward")
	_toast("专注 %d 分钟，下一竿留了份惊喜给你 ✨" % mins, 4.0, Color(0.74, 0.86, 0.98))
	_check_achievements()
	_save()


## 当前若有待兑专注奖励，就把这一竿强制升级（保底高星 / 50 分钟再保底鎏金）。返回消费的等级。
func _apply_focus_reward(c: Dictionary) -> int:
	if focus_pending <= 0:
		return 0
	var level := focus_pending
	focus_pending = 0
	_ensure_focus_day()
	focus_reward_today += 1   # 额度按实际兑现计（T1、T2 各占一次；仅停竿未兑时两档合并为一次）
	if level >= 2:
		# 段满额兑清 → 重新起算：否则 away_t 只增不消，挂一整天后奖励永久停发（对抗审查 must-fix）
		_focus_away_t = 0.0
		_focus_granted = 0
	var old_q := int(c.get("q", 0))
	var old_v := int(c.get("var", 0))
	var new_q := maxi(old_q, 2)                       # 保底极品★★
	var new_var := maxi(old_v, 2) if level >= 2 else old_v  # 50 分钟再保底鎏金
	var mult: float = FishData.QUALITY_MULTS[new_q] / FishData.QUALITY_MULTS[old_q] \
		* FishData.VARIANT_MULTS[new_var] / FishData.VARIANT_MULTS[old_v]
	c["q"] = new_q
	c["var"] = new_var
	c["v"] = maxi(1, int(round(float(c["v"]) * mult)))
	_save()
	return level


func _ensure_focus_day() -> void:
	var today := _today_key()
	if focus_reward_date != today:
		focus_reward_date = today
		focus_reward_today = 0
		# 跨日顺带重开专注段：过夜挂机 away_t 已饱和（granted=2），不重开则新一天永远不发
		_focus_away_t = 0.0
		_focus_granted = 0


## 宽限窗外的主动操作 → 当前专注段折算保留 80%（S18：中断不没收全部进度——正常用电脑
## 总会碰到挂件）。阈值旗标按折算后时长重算：跌回阈值下可再次攒到（每日封顶仍兜底）。
## 不清待兑奖励：已挣到的留着下一竿兑。
func _fold_focus_streak() -> void:
	_focus_away_t *= 0.8
	# 折算跌回阈值下时允许重新攒到（每日封顶兜底）；只降不升——从不篡改"已发放"的事实
	if _focus_away_t < FOCUS_T1:
		_focus_granted = 0
	elif _focus_away_t < FOCUS_T2:
		_focus_granted = mini(_focus_granted, 1)


## 把昼夜/久未操作等上下文喂给绘制层，驱动渔夫情绪动画（Task 4）。
func _update_fisher_context() -> void:
	if painter.has_method("set_fisher_context"):
		painter.set_fisher_context(day_phase == "night", _idle_t > 45.0 and _window_focused)


# ============================ 桌面宠物（Task 4）============================

## 上鱼后的趣味事件：小概率让宠物叼走鱼。安静模式不打扰；
## 测试/截图实例（save_enabled=false）不触发随机偷鱼，避免污染钓鱼数量断言。
func _maybe_pet_steal() -> void:
	if focus_mode or not save_enabled:
		return
	if rng.randf() >= PET_STEAL_CHANCE:
		return
	var id := _pet_steal_cheapest()
	if id != "" and painter.has_method("pet_react"):
		Audio.play_sfx("sfx_cat_steal")   # 全游戏最有性格的时刻，此前是哑的
		painter.pet_react("steal")


## 叼走鱼篓里最廉价且「可舍弃」（未上锁、非订单目标、卖价 ≤ 上限）的一条。返回鱼 id（没合适的返回 ""）。
func _pet_steal_cheapest() -> String:
	var worst := -1
	var worst_v := 0
	for i in inventory.size():
		var f: Dictionary = inventory[i]
		if bool(f.get("lock", false)) or _order_matches(f):
			continue
		var fv := _sell_value(f)
		if worst == -1 or fv < worst_v:
			worst = i
			worst_v = fv
	if worst < 0 or worst_v > PET_STEAL_MAX_VALUE:
		return ""   # 没有可舍弃的廉价鱼 → 绝不动珍藏
	var c: Dictionary = inventory[worst]
	inventory.remove_at(worst)
	pet_steals += 1
	_toast("🐱 小馋猫叼走了一条%s当点心～" % FishData.display_name(str(c["id"])), 2.6, Color(0.95, 0.80, 0.5))
	_check_achievements()
	_update_hud()
	_rebuild_panel()
	_save()
	return str(c["id"])


## 从鱼篓/图鉴把鱼放进水族箱后用：强制重建面板（含会游动的水族箱视图）。
func _rebuild_panel() -> void:
	if _panel_kind != "":
		_open_panel(_panel_kind)


# ============================ 存档 / 离线 ============================

func _save() -> void:
	if not save_enabled or not _initial_load_complete:
		return
	_ensure_daily_order()
	SaveSystem.write_atomic(save_path, SaveSystem.collect(self))


func _load_save() -> void:
	if not save_enabled:
		return
	# 主档解析失败（截断/损坏）时回退到 .bak，最大限度保住进度
	var data: Variant = SaveSystem.read_file(save_path)
	if data == null:
		data = SaveSystem.read_file(save_path + ".bak")
		if data != null:
			push_warning("主存档损坏，已从 .bak 恢复")
	if not (data is Dictionary):
		return
	SaveSystem.apply(self, data)
	# 老存档（v4 及更早，无 ach 字段）静默补登已满足的成就，避免回屏刷屏
	if not (data.get("ach", null) is Array):
		_check_achievements(true)
	# 离线渔获：按时长估算上鱼数，逐条入篓直到装满
	var elapsed: float = Time.get_unix_time_from_system() - float(data.get("ts", 0))
	# 在场事件 buff（40~110s）按真实离开时长先行衰减，过期即清——不给整段离线渔获盖增值章；
	# 清空后 _ready 里 active_event=="" 分支会照常重排首个事件
	if active_event != "":
		_event_buff_t -= maxf(elapsed, 0.0)
		if _event_buff_t <= 0.0:
			active_event = ""
			_event_buff_t = 0.0
	var rel_buff: Dictionary = relationship_state.get("buff", {})
	if not rel_buff.is_empty():
		rel_buff["t"] = float(rel_buff.get("t", 0.0)) - maxf(elapsed, 0.0)
		relationship_state["buff"] = rel_buff if float(rel_buff.get("t", 0.0)) > 0.0 else {}
	var raw_elapsed := maxf(elapsed, 0.0)
	elapsed = clampf(elapsed, 0.0, _offline_cap())
	if elapsed > 30.0:
		var caught := _offline_catch(elapsed)
		_check_achievements()   # 离线跨过的断点（species/vgrid/catches）当场入账，与小结同帧
		if caught > 0:
			# 时长如实显示真实离开时间；被上限截断时把规则挑明（"离开 63h 只结 12h"是明规则不是暗坑）
			_offline_report["dur"] = _fmt_dur(raw_elapsed) \
				+ ("（按上限结算 %s）" % _fmt_dur(elapsed) if raw_elapsed > elapsed + 60.0 else "")
			_offline_report["full"] = _bag_full()
		elif _bag_full():
			_pending_offline = "离线 %s，鱼篓是满的，一条都装不下啦" % _fmt_dur(elapsed)


## 离线上限：基础 12h；图鉴 ≥145 种（溶洞站里程碑）扩到 24h（周末 63h 仍截断——防经济失控）。
func _offline_cap() -> float:
	return OFFLINE_CAP_EXT if dex.size() >= 145 else OFFLINE_CAP_BASE


## 把离线时长按昼夜时段切片（从回屏时刻往回按本地时钟推），返回 [{"phase", "sec"}]（近段在前）。
## 无头验证钉死 Weather.force_phase 时整段归入该时段（保持测试相位无关）。
func _offline_phase_slices(elapsed: float) -> Array:
	if Weather.force_phase != "":
		return [{"phase": Weather.force_phase, "sec": elapsed}]
	var td := Time.get_time_dict_from_system()
	var hour := int(td["hour"])
	var seg := float(int(td["minute"]) * 60 + int(td["second"]))  # 当前小时已流逝的秒数
	if seg <= 0.0:
		seg = 3600.0
		hour = (hour + 23) % 24
	var remain := elapsed
	var out: Array = []
	while remain > 0.0:
		var use := minf(remain, seg)
		var ph := Weather.phase_for_hour(hour)
		if not out.is_empty() and str(out[-1]["phase"]) == ph:
			out[-1]["sec"] = float(out[-1]["sec"]) + use
		else:
			out.append({"phase": ph, "sec": use})
		remain -= use
		hour = (hour + 23) % 24
		seg = 3600.0
	return out


## 离线钓鱼：上鱼数 = 时长/平均间隔×效率，按昼夜时段切片逐段掷池（夜行限定鱼在夜段真的会来，
## 夜段给一半运气 +1——惊喜照常、幅度减半；限定鱼每次结算每种至多 2 条防整夜刷限定）。
## 鱼篓装满后不再截断（调研 3.2）：多出的鱼经 _absorb_overflow 折价兑成金币兜底。
## 小结覆盖全量渔获（含溢出段——原先 98% 的离线渔获不进小结，惊喜白出）。
## 返回本次产生收益的总条数（入篓 + 兜底）。
func _offline_catch(elapsed: float) -> int:
	var avg_interval := _avg_wait_for(rod_level)
	var cap := _bag_capacity()
	var phase_before := day_phase
	var total_est := 0
	var overflow_v := 0
	var top: Dictionary = {}
	var notable: Array = []
	var lim_counts := {}
	var oid := 0   # 本次结算的临时序号：结算尾部按"仍在篓中"回填 folded（_absorb_overflow 会换鱼入篓，
				   # 折价路径 ≠ 真的被卖掉——按调用前满篓判定会把换进篓的珍稀错标"已兑金"）
	for s in _offline_phase_slices(elapsed):
		var est_i := int(float(s["sec"]) / avg_interval * OFFLINE_EFFICIENCY)
		if est_i <= 0:
			continue
		day_phase = str(s["phase"])   # 该段按真实时段掷池/定价（_roll_one 经 Spots 读 day_phase）
		var luck_i := 1 if day_phase == "night" else 0
		for i in est_i:
			var c := _roll_one(luck_i)
			var lid := str(c["id"])
			if not FishData.limited_of(lid).is_empty():
				if int(lim_counts.get(lid, 0)) >= 2:
					# 超上限：改抽非限定。重抽后仍复查（当前白昼池恰好无限定鱼，但这是数据巧合——
					# P2 计划加 ~33 种含昼/晨昏限定，不复查护栏会静默失效），3 次仍限定则计数放行防死循环
					for retry in 3:
						day_phase = "day"
						c = _roll_one(0)
						day_phase = str(s["phase"])
						lid = str(c["id"])
						if FishData.limited_of(lid).is_empty():
							break
					if not FishData.limited_of(lid).is_empty():
						lim_counts[lid] = int(lim_counts.get(lid, 0)) + 1
				else:
					lim_counts[lid] = int(lim_counts.get(lid, 0)) + 1
			c["_oid"] = oid
			oid += 1
			total_est += 1
			var ib := FishData.size_tag(c["id"], c["w"]) == "巨物·"
			_dex_record(c["id"], float(c["w"]), ib, int(c.get("q", 0)) >= 3, int(c.get("var", 0)))
			lifetime_catches += 1
			best_quality = maxi(best_quality, int(c.get("q", 0)))
			best_variant = maxi(best_variant, int(c.get("var", 0)))
			if ib:
				caught_giant = true
			if inventory.size() >= cap:
				overflow_v += _absorb_overflow(c)   # 折价路径：更贵的 c 会换进篓、卖掉篓中最廉价那条
			else:
				inventory.append(c)
			if top.is_empty() or int(c["v"]) > int(top["v"]):
				top = c
			if FishData.tier_of(c["id"]) >= 3 or int(c.get("q", 0)) >= 2 or int(c.get("var", 0)) >= 1:
				notable.append(c.duplicate())   # 副本自带 _oid，尾部统一回填 folded
	day_phase = phase_before
	_add_coins_safe(overflow_v)
	_add_lifetime_coins_safe(overflow_v)
	# —— 按最终篓内容回填：谁真的留下了、离线新增的在篓价值是多少 ——
	var kept := {}
	var stored_v := 0
	for f in inventory:
		if f.has("_oid"):
			kept[int(f["_oid"])] = true
			stored_v += int(f["v"])
	var top_folded := false
	if not top.is_empty():
		top_folded = not kept.has(int(top.get("_oid", -1)))
		top = top.duplicate()
		top.erase("_oid")
	notable.sort_custom(func(a, b): return int(a["v"]) > int(b["v"]))
	var notable_n := notable.size()   # 珍稀真实总数（截断前）——UI 标题用
	if notable.size() > 6:
		notable.resize(6)             # 截断长度与小结 UI 显示上限一致
	for nc in notable:
		nc["folded"] = not kept.has(int(nc.get("_oid", -1)))
		nc.erase("_oid")
	for f in inventory:
		f.erase("_oid")   # 清临时键（collect 走字段白名单本不会入档，防御性清理）
	_offline_report["overflow_n"] = total_est - kept.size()
	_offline_report["overflow_v"] = overflow_v
	if total_est > 0:
		_offline_report["count"] = kept.size()     # 离线新增且仍在篓（含折价路径换入的）
		_offline_report["value"] = stored_v
		_offline_report["top"] = top
		_offline_report["top_folded"] = top_folded
		_offline_report["notable"] = notable
		_offline_report["notable_n"] = notable_n
	return total_est


func _fmt_dur(sec: float) -> String:
	var h := int(sec) / 3600
	var m := (int(sec) % 3600) / 60
	if h > 0:
		return "%d 小时 %d 分" % [h, m]
	return "%d 分钟" % max(1, m)


# ============================ 测试模式 · 薄壳（逻辑见 test_mode.gd）============================
# 这两个方法承载 TestMode 需要的 Orders/SaveSystem 调用：放在 main（运行期才编译，autoload 已就绪）
# 而非 test_mode.gd（被工具早期引用），避开 Audio autoload 早解析坑。

## 退出测试模式：从磁盘重载正式档（不做离线结算，避免误弹离线小结），并把场景昼夜重置回真实时钟。
func _test_reload_real_save() -> void:
	var data: Variant = SaveSystem.read_file(save_path)
	if data == null:
		data = SaveSystem.read_file(save_path + ".bak")
	if data is Dictionary:
		SaveSystem.apply(self, data)
	_ensure_daily_order()
	_ensure_weekly()
	_ensure_competition()
	# 昼夜回真实时钟 + 重解析钓点/时段底图（即刻结束慢 crossfade）
	_forced_phase = ""
	day_phase = Weather.current_phase()
	if painter:
		painter.debug_tod = -1.0
		if "_spot_phase" in painter:
			painter._spot_phase = ""
	_apply_spot_visuals()
	_apply_phase()
	if painter and "_spot_fade" in painter:
		painter._spot_fade = 1.0
		painter._spot_prev = null
		painter.queue_redraw()
	_update_hud()


## 测试：重置今日订单。用扰动种子绕开「当日确定性种子」，每次产出可能不同的新单（仍归属今天）。
func _test_reroll_order() -> void:
	_test_order_nonce += 1
	var today := Orders.today_key()
	var od := Orders.make_daily_order(self, "%s#%d" % [today, _test_order_nonce])
	od["date"] = today
	daily_order = od


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save()
			get_tree().quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_focused = false   # 你切去别的程序 → 开始累计专注
			_cancel_window_gestures()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focused = true    # 切回挂件 → 开 60s 宽限窗（窗内操作不折算专注段）
			_focus_grace_t = 60.0
			_idle_t = 0.0
			_queue_window_region_sync()
		NOTIFICATION_WM_SIZE_CHANGED, NOTIFICATION_WM_DPI_CHANGE:
			_queue_window_region_sync()


func _cancel_window_gestures() -> void:
	_drag_pending = false
	_dragging = false
	_rz_active = false
	_panel_dragging = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _quit_game() -> void:
	_save()
	get_tree().quit()


## 开启新存档（开发期：清空磁盘存档 + 全状态复位到默认开局 + 落盘 + 重看引导）。
## 复用 SaveSystem 迁移默认：空字典经 apply 即把每个字段取默认值；其余运行态镜像 _ready 的载入后初始化。
func _new_save() -> void:
	# 删磁盘存档（主档 / .bak / .tmp）
	for p in [save_path, save_path + ".bak", save_path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	# 若处于测试模式：先退出（恢复写档），新档应是正式可存的全新档
	if test_mode:
		test_mode = false
		_forced_phase = ""
		test_speed = 1.0
		if painter:
			painter.debug_tod = -1.0
		save_enabled = true
		_rebuild_bottom_nav()
	# 全状态复位为默认（空字典 → apply 内每个 .get(key, default) 取默认）
	SaveSystem.apply(self, {})
	seen_intro = false        # 全新档：重看引导
	chosen_character = false  # 【新增】全新档：重新走"看故事→选角色"流程
	# 复位瞬态运行状态（镜像 _ready 载入后的初始化）
	_offline_report = {}
	_pending_offline = ""
	_merchant_active = false
	_merchant_t = rng.randf_range(MERCHANT_FIRST.x, MERCHANT_FIRST.y)
	_focus_away_t = 0.0
	_focus_granted = 0
	_idle_t = 0.0
	_refresh_unlocks()
	_ensure_daily_order()
	_ensure_weekly()
	day_phase = Weather.current_phase()
	if painter and painter.has_method("set_phase_tint"):
		painter.set_phase_tint(Weather.tint(day_phase), day_phase)
	_apply_spot_visuals()
	if active_event == "":
		_event_next_t = rng.randf_range(EVENT_FIRST.x, EVENT_FIRST.y)
	_begin_wait()
	_save()                   # 落盘全新档
	_update_hud()
	_close_panel()            # 关掉设置页
	_toast("已开启新存档 · 进度已清空", 2.6, DT.GOLD)
	if lifetime_catches == 0 and DisplayServer.get_name() != "headless":
		_open_panel("story")  # 【修改】全新档重新开局：同样先看开场故事，而不是直接跳 intro
