extends Node2D
class_name CornerFishing
## 角落垂钓 · 主控
## 职责：透明角落窗形态 + 挂机钓鱼状态机 + 经济 + 即时反馈（后续接存档/离线/面板）。

@onready var painter: Node2D = $ScenePainter
@onready var ui_root: Control = $HUD/Root
@onready var coins_label: Label = $HUD/Root/Coins
@onready var toast_label: Label = $HUD/Root/Toast

# 窗口比美术画布(520x400)更大，多出的空间透明、留给弹出面板自由展开；
# 场景靠 SCENE_OFF 偏移钉在窗口右下角（视觉上仍是角落小挂件）。
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
const UI_LAYOUT_PATHS := ["res://ui_layout.json", "res://assets/art/ui/ui_layout.json"]
var btn_centers := {
	"catch": Vector2(452, 371),
}

# —— 钓鱼状态机 ——
enum {ST_WAIT, ST_BITE}
var _state := ST_WAIT
var _state_t := 0.0
var _started := false

# —— 存档数据 ——
var coins := 0
var rod_level := 1
var bag_level := 1
var bait_level := 0  # FishData.BAITS 下标，金币永久升级
var hook_level := 0  # FishData.HOOKS 下标，决定双钩几率
var lure_level := 0  # FishData.LURES 下标，决定稀有变体偏置（vbias），金币永久升级
var inventory: Array = []  # 每条 {"id", "w", "v", "q"(星级)}，一条鱼占一格
var display: Array = []     # 陈列架上的鱼（离开鱼篓、永久展示），最多 Decor.NUM_SLOTS 件
var lifetime_coins := 0    # 累计卖鱼所得
var lifetime_catches := 0
var dex := {}  # id -> {"n": 累计捕获数, "w": 最大体重纪录}（图鉴纪录轴）
var best_quality := 0      # 历史最高星级（成就用）
var best_variant := 0      # 历史最高稀有变体（成就用：斑斓/鎏金/七彩）
var caught_giant := false  # 是否钓到过「巨物」（成就用）
var achievements_done := {}  # id -> true，已达成的成就（toast 只触发一次）

# 背包容量与扩容费用（bag_level 1 起步；费用 = 升到下一级）。
# 调研定标：起始 20 格（Melvor 同款），整档 +5 格，费用走 1-2-5 阶梯（首扩几分钟产出可买）。
const BAG_CAPS := [20, 25, 30, 35, 40, 45, 50, 55]
const BAG_COSTS := [100, 250, 600, 1500, 4000, 10000, 25000]

var save_enabled := true
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
var max_fps := 30                # 帧率上限：默认 30 挂件省电，可在设置调到 60/90/120
const UI_SCALE_OPTIONS := [1.0, 1.25, 1.5]   # 设置里「快捷跳档」按钮（自由拖拽不受这三个值限制）
const UI_SCALE_MIN := 0.5                    # 自由缩放下限：0.5=520×360，桌面角落挂件可缩到很小；再小手柄/字就难用
const UI_SCALE_MAX := 2.5                    # 自由缩放绝对上限（实际还会再夹到屏幕可用区）
var ui_scale := 1.0              # 当前界面缩放倍率（连续值）；带框模式整窗等比缩放
var _win_resize_guard := false   # 程序内主动改窗口尺寸时置位（仅 _set_ui_scale 用，保留以防误触发监听）
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
const OFFLINE_CAP := 8.0 * 3600.0     # 离线最多结算 8 小时
const OFFLINE_EFFICIENCY := 0.5       # 离线效率 50%
const OVERFLOW_SELL_RATE := 0.5       # 满篓兜底：自动折价兑换比例（调研 3.2，避免满篓硬截断惩罚挂机）
var _save_t := 10.0
var _pending_offline := ""               # 仅"满篓没钓到"等无渔获情况用 toast
var _offline_report := {}                # 离线小结：{dur,count,full,value,top,notable[]}

# —— 窗口拖动（默认右下角，可拖到任意位置）——
var _dragging := false
var _drag_grab := Vector2i.ZERO
var _saved_win_pos = null   # Variant：Vector2i 或 null（无存档位置则用右下角默认）
var _panel_dragging := false
var _panel_drag_offset := Vector2.ZERO
var _panel_saved_pos = null  # Variant：Vector2 或 null，记住弹出面板被拖到的位置

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
var test_mode := false           # 是否在测试模式（运行态，不存档；重启天然回正式档）
var _forced_phase := ""          # 非空＝测试强制时段，_tick_phase 不再被真实时钟覆盖
var test_speed := 1.0            # 测试提速：钓鱼等待/咬钩时长除以此值（1=正常）
var _test_order_nonce := 0       # 测试重置订单的扰动子（绕开当日确定性种子）
var _test_pick_fish := ""        # 测试台「给鱼」记住的鱼种/星级/变体（重建面板不丢选择）
var _test_pick_q := 0
var _test_pick_var := 0

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
var _focus_away_t := 0.0               # 当前连续失焦累计秒（切回/操作即清零）
var _focus_t1_done := false            # 本段是否已发 25 分钟奖励
var _focus_t2_done := false            # 本段是否已发 50 分钟奖励
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


func _ready() -> void:
	rng.randomize()
	Engine.max_fps = max_fps  # 默认 30 挂件省电；存档载入后按玩家设置覆盖
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
	_setup_window()
	_load_ui_layout()
	_load_save()
	_refresh_unlocks()  # 载入期静默补登已满足解锁的钓点
	_ensure_daily_order()
	_ensure_weekly()
	_ensure_competition()
	_build_buttons()
	# 先确定昼夜时段并喂给 painter（决定时段底图），再切钓点底图，避免开局触发 90s 慢淡入
	day_phase = Weather.current_phase()
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


# ============================ 窗体形态 ============================

func _setup_window() -> void:
	if DisplayServer.get_name() == "headless":
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
		_update_passthrough()
	else:
		# 带框普通窗口：不透明、带边框标题栏、不置顶、不穿透、居中
		RenderingServer.set_default_clear_color(FRAMED_BG)
		w.transparent_bg = false
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)
		w.borderless = false
		w.always_on_top = false
		UIPanels.set_interactive_full(self, true)  # 整窗矩形穿透：复位窗口区域、永不裁椭圆
		await get_tree().process_frame
		var scr := DisplayServer.screen_get_usable_rect()
		var ws := DisplayServer.window_get_size()
		DisplayServer.window_set_position(scr.position + (Vector2i(scr.size) - ws) / 2)


# —— 显示模式布置 ——
var auto_cast := true            # 自动垂钓开关（默认开=原自动行为；关=手动起竿/起钩）
var _action_btn: Button = null   # 带框模式底部「起竿/起钩」按钮
# 带框 HUD 引用（胶囊 + 状态标签）
var _chip_coin: Label = null
var _chip_bag: Label = null
var _chip_dex: Label = null
var _flag_box: VBoxContainer = null
var _nav_badges := {}   # 导航徽章 {tab: PanelContainer}（鱼篓满/任务可交付）
var _nav_bar: PanelContainer = null   # 底栏容器（背景随面板开关切透明/暗，避免与 sheet 断裂）

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
		# 场景向四周各溢出 FRAMED_OVERSCAN 像素：原本左/右/底边正好压在窗口边缘，
		# 在分数 DPI / 分数缩放的显示器上，那一列会被线性采样拉成一条浅"描边"接缝
		# （双屏中只有缩放为分数的那台出现）。把边缘推到屏外 → 可见边永远是内部内容，无缝。
		var os := FRAMED_OVERSCAN
		var s := (float(WIN.x) + 2.0 * os) / ART.x   # 横向铺满窗宽 + 两侧各溢出 os
		painter.scale = Vector2(s, s)
		# 底对齐窗口底（场景铺到导航后面，底栏浮在场景上、无深色板）；左/底各溢出 os。
		painter.position = Vector2(-os, float(WIN.y) + os - ART.y * s)


## 场景内 art 坐标 → 屏幕坐标（含带框缩放/偏移），飘字/落水定位用。
func _scene_pt(art: Vector2) -> Vector2:
	return painter.position + art * painter.scale


func _setup_immersive_hud() -> void:
	coins_label.position = SCENE_OFF + Vector2(196, 150)
	coins_label.mouse_filter = Control.MOUSE_FILTER_STOP
	coins_label.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_catch_tab = 0
			_toggle_panel("catch"))
	toast_label.position = SCENE_OFF + Vector2(198, 204)
	_build_spot_chip()
	_build_order_chip()


# —— 带框 App 外壳：底部导航 console + 起竿按钮 + 顶部 HUD ——
func _build_framed_chrome() -> void:
	coins_label.visible = false   # 带框用图标胶囊替代纯文字 HUD
	toast_label.position = Vector2((float(WIN.x) - 440) * 0.5, float(WIN.y) - FRAMED_CONSOLE_H - 120)
	_build_hud_chips()
	_build_status_flags()
	_build_bottom_nav()
	_build_action_button()


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
	box.position = Vector2(16, 12)
	box.add_theme_constant_override("separation", 8)
	ui_root.add_child(box)
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


## 照抄 CD coinStr：≥10万 "Nk"(整) / ≥1万 "N.Nk"(一位) / 否则千分位逗号(toLocaleString)
func _coin_str(n: int) -> String:
	if n >= 100000:
		return "%dk" % int(n / 1000.0)
	if n >= 10000:
		return "%.1fk" % (n / 1000.0)
	return _commas(n)


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
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_left = 0
	box.offset_right = -16
	box.offset_top = 12
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
	# 鱼贩：.flag.merchant bg merchant color ink-on-gold
	if _merchant_active:
		_flag_box.add_child(_make_flag_pill("🐟 鱼贩 ×1.5",
			DT.MERCHANT, DT.INK_ON_GOLD, 12, 9))


func _update_framed_hud() -> void:
	if is_instance_valid(_chip_coin):
		_chip_coin.text = _coin_str(coins)
	if is_instance_valid(_chip_bag):
		_chip_bag.text = "%d/%d" % [inventory.size(), _bag_capacity()]
		_chip_bag.add_theme_color_override("font_color",
			Color(1.0, 0.780, 0.451) if _bag_full() else Color(0.925, 0.910, 0.878))
	if is_instance_valid(_chip_dex):
		_chip_dex.text = "%d/%d" % [dex.size(), FishData.FISH.size()]
	# 导航徽章：鱼篓满「满」 / 任务可交付「!」
	if _nav_badges.has(0) and is_instance_valid(_nav_badges[0]):
		var b0: PanelContainer = _nav_badges[0]
		b0.visible = _bag_full()
		b0.get_node("L").text = "满"
	if _nav_badges.has(2) and is_instance_valid(_nav_badges[2]):
		var b2: PanelContainer = _nav_badges[2]
		var need := int(daily_order.get("need", 1))
		b2.visible = not bool(daily_order.get("done", false)) and _daily_order_indices().size() >= need
		b2.get_node("L").text = "!"
	_update_status_flags()
	_update_action_button()


func _build_bottom_nav() -> void:
	var bar := PanelContainer.new()
	bar.name = "BottomNav"
	bar.position = Vector2(0, float(WIN.y) - FRAMED_CONSOLE_H)
	bar.custom_minimum_size = Vector2(float(WIN.x), FRAMED_CONSOLE_H)
	bar.size = Vector2(float(WIN.x), FRAMED_CONSOLE_H)
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
	# 5 个导航项：图标在上、文字在下（CD 布局）。[label, catch_tab, icon]
	var navs := [
		["鱼篓", 0, "res://assets/art/ui/nav_basket.png"],
		["装备", 7, "res://assets/art/ui/nav_equip.png"],
		["图鉴", 1, "res://assets/art/ui/nav_dex.png"],
		["任务", 2, "res://assets/art/ui/nav_orders.png"],     # 一套水彩导航图标（已就位）；文件缺失时自动只显文字、不显乱占位
		["钓点", 5, "res://assets/art/ui/nav_spots.png"],
		["鱼缸", 6, "res://assets/art/ui/nav_fishtank.png"],
		["设置", 8, "res://assets/art/ui/nav_settings.png"],
	]
	for n in navs:
		var tab: int = n[1]
		var item := VBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.alignment = BoxContainer.ALIGNMENT_CENTER
		item.add_theme_constant_override("separation", 2)
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# 图标：用 CenterContainer 保证水平居中；TextureRect 固定尺寸 + 等比不变形（不再用绝对定位）
		var icon_box := CenterContainer.new()
		icon_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(n[2]):
			var ic := TextureRect.new()
			ic.texture = load(n[2])
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
		item.add_child(icon_box)
		var lbl := Label.new()
		lbl.text = n[0]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # 满宽 → 文字真正居中在该 tab 下方
		lbl.add_theme_font_override("font", _font_bold)
		lbl.add_theme_font_size_override("font_size", 11)   # CD .nav button 11
		lbl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
		lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.04, 0.92))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(lbl)
		item.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Audio.play_ui("ui_click")
				if _panel_kind == "catch" and _catch_tab == tab:
					_close_panel()
				else:
					_catch_tab = tab
					_open_panel("catch"))
		item.mouse_entered.connect(func() -> void: item.modulate = Color(1.18, 1.18, 1.18))
		item.mouse_exited.connect(func() -> void: item.modulate = Color(1, 1, 1))
		row.add_child(item)
	# 「自动垂钓」开关已移入设置页（见 ui_panels.fill_settings），底栏只留导航图标。


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
	b.position = Vector2((float(WIN.x) - 220) * 0.5, float(WIN.y) - FRAMED_CONSOLE_H - 66)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font_bold)       # weight 700 → embolden（落地变通）
	b.add_theme_font_size_override("font_size", 15)     # CD .action 15
	b.pressed.connect(_on_action_pressed)
	ui_root.add_child(b)
	_action_btn = b
	_update_action_button()


func _action_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 11
	sb.content_margin_bottom = 11
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	return sb


func _on_action_pressed() -> void:
	if _bag_full():
		_catch_tab = 0
		_open_panel("catch")   # 满篓 → 直接开鱼篓去兑换
		return
	# 手动钓鱼（自动关时的起竿/起钩）task 11 接入；自动模式下点它无操作。


func _update_action_button() -> void:
	if not is_instance_valid(_action_btn):
		return
	# 照抄 CD .action 各态：normal=bronze / full=bag-full / bite=rust / wait(自动)=灰
	_action_btn.visible = true
	var txt := "起竿"
	var bg := DT.BRONZE
	var fg := DT.INK_ON_GOLD
	if _bag_full():
		txt = "鱼篓满了 · 去兑换"
		bg = DT.BAG_FULL
	elif auto_cast:
		txt = "· 自动垂钓中 ·"
		bg = Color(0.235, 0.251, 0.220, 0.82)   # .action.wait rgba(60,64,56,.82)
		fg = DT.TEXT_MUTED_GLASS
	elif _state == ST_BITE:
		txt = "起钩！"
		bg = DT.RUST
		fg = Color(1.0, 0.969, 0.937)            # #fff7ef
	else:
		txt = "起竿"
		bg = DT.BRONZE
	_action_btn.text = txt
	_action_btn.add_theme_color_override("font_color", fg)
	_action_btn.add_theme_stylebox_override("normal", _action_style(bg))
	_action_btn.add_theme_stylebox_override("hover", _action_style(bg.lightened(0.10)))
	_action_btn.add_theme_stylebox_override("pressed", _action_style(bg.darkened(0.10)))


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
	DisplayServer.window_set_mouse_passthrough(pts)


# 任意操作刷新"无操作"计时；点击/按键还会清掉当前这段专注（你回来动手了）。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey:
		if event.is_pressed():
			_idle_t = 0.0
			_reset_focus_streak()
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


# 拖动窗口：在场景空白处按住左键拖拽（按钮/面板会先消费事件，不会误触发）。
func _unhandled_input(event: InputEvent) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 两种模式都允许「按住场景空白处拖动窗口」（带框也常没标题栏可拖；面板/导航会先消费点击）。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_grab = DisplayServer.mouse_get_position() - DisplayServer.window_get_position()
		elif _dragging:
			_dragging = false
			_save()
	elif event is InputEventMouseMotion and _dragging:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() - _drag_grab)


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
	_tick_phase()
	_tick_focus(delta)
	_state_t -= delta
	match _state:
		ST_WAIT:
			painter.dip = lerpf(painter.dip, 0.0, delta * 6.0)
			if _state_t <= 0.0 and not _bag_full():
				_begin_bite()
		ST_BITE:
			painter.dip = lerpf(painter.dip, 1.0, delta * 10.0)
			if _state_t <= 0.0:
				_do_catch()


func _begin_wait() -> void:
	_state = ST_WAIT
	var w := rng.randf_range(3.5, 7.0) * maxf(0.4, 1.0 - float(rod_level - 1) * 0.06)
	w *= SpotData.wait_mult(current_spot)          # 钓点常驻系数（阶段④起生效）
	w *= Weather.wait_mult(day_phase)              # 昼夜时段（金色时段咬钩更勤）
	if active_event != "":
		w *= EventData.wait_mult(active_event)      # 事件期间咬钩节奏变化
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
	_state_t = maxf(0.12, 0.9 / test_speed)         # 测试提速：test_speed=1 时不变
	painter.add_ripple(painter.bobber_pos(), 22.0)
	Audio.play_sfx("bite")
	_update_action_button()


## 更新图鉴纪录（捕获数 +1、最大体重取大、巨物/完美徽章）。返回是否打破"既有"纪录：
## 该鱼种此前已钓 ≥5 条且新体重超过旧纪录才算（避免前期每条都播报）。
func _dex_record(id: String, w: float, is_big := false, is_perfect := false, variant := 0) -> bool:
	var vbit := (1 << variant) if variant > 0 else 0  # 记录见过的稀有变体（位掩码）
	if not dex.has(id):
		dex[id] = {"n": 1, "w": w, "big": is_big, "perf": is_perfect, "vmask": vbit,
			"fd": _today_key(), "wd": _today_key()}  # fd 首捕日期；wd 刷新最大体重的日期
		return false
	var r: Dictionary = dex[id]
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


func _bag_capacity() -> int:
	return BAG_CAPS[clampi(bag_level - 1, 0, BAG_CAPS.size() - 1)]


func _bag_full() -> bool:
	return inventory.size() >= _bag_capacity()


## 钓点：薄壳委托 Spots（实现见 spots.gd，行为不变）。
func _spot_pool() -> Array:
	return Spots.pool(self)


func _catch_luck() -> int:
	return Spots.catch_luck(self)


func _catch_value_mult() -> float:
	return Spots.catch_value_mult(self)


## 变体偏置累加器（P2 变体杠杆）：各收集杠杆贡献相加，喂给 FishData.roll_variant 抬高变体率。
## 目前来源：诱饵/窝料成长线（lure_level）。以后加来源（钓点亲和/悬赏等）只在此 += 一行即可。
## 0 级窝料 → 0，与基线逐位一致；上不封顶交由 roll_variant 内部 clamp(0,10)。
func _variant_bias() -> float:
	return FishData.lure_vbias(lure_level)


## 钓一条鱼：限定当前钓点鱼池，应用钓点/事件增值系数。
## vbias<0（默认哨兵）→ 取当前各杠杆累加值 _variant_bias()（在线/离线都吃诱饵加成）；
## 传非负值则按显式覆盖（专注奖励等强制场景留口）。
func _roll_one(luck: int, vbias := -1.0) -> Dictionary:
	var vb := vbias if vbias >= 0.0 else _variant_bias()
	var c := FishData.roll_catch(rng, rod_level, bait_level, luck, _spot_pool(), vb)
	var vm := _catch_value_mult()
	if vm != 1.0:
		c["v"] = max(1, int(round(float(c["v"]) * vm)))
	return c


func _do_catch() -> void:
	if _bag_full():
		_overflow_catch()   # 满篓不空转：钓一条折价兑成金币，挂机永不停产
		_begin_wait()
		return
	var luck := _catch_luck()
	var c := _roll_one(luck)
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
	var broke_record := _dex_record(c["id"], float(c["w"]), is_big, q >= 3, vr)
	var col: Color = FishData.TIER_COLORS[tier]
	Audio.play_sfx("catch_rare" if (tier >= 2 or q >= 2 or vr >= 1) else "catch_common")
	_popup("%s %.2fkg" % [fname, c["w"]], _scene_pt(painter.bobber_pos()) + Vector2(-22, -8),
		FishData.variant_color(vr) if vr >= 1 else col)
	painter.add_ripple(painter.bobber_pos(), 34.0)
	if vr >= 1:
		_toast("✨ 变体！%s%s（%.2fkg，%d 金币）" % [FishData.variant_label(vr),
			FishData.display_name(c["id"]), c["w"], c["v"]], 2.8, FishData.variant_color(vr))
	elif broke_record:
		_toast("破纪录！%s %.2fkg，刷新个人最大" % [FishData.display_name(c["id"]), c["w"]],
			2.6, Color(0.95, 0.82, 0.45))
	elif tier >= 3 or q >= 2:
		_toast("%s钓到 %s（%.2fkg，%d 金币）" % [
			(FishData.TIER_NAMES[tier] + "！") if tier >= 3 else "",
			fname, c["w"], c["v"]], 2.4, col)
	elif not bool(daily_order.get("done", false)) and _order_matches(c):
		var need := int(daily_order.get("need", 1))
		var have := mini(_daily_order_indices().size(), need)
		_toast("订单进度：%s %d/%d" % [_order_short(), have, need],
			2.0, Color(0.96, 0.78, 0.38))
	var comp_win := Competition.on_catch(self, c)   # 巨物赛：本周目标鱼刷新最佳，冲过影子线夺金
	if comp_win > 0:
		Audio.play_sfx("coin")
		_toast("🏆 巨物赛夺金！%s %.2fkg 越过影子线，+%d 金币" % [
			FishData.display_name(str(c["id"])), float(c["w"]), comp_win], 3.4, Color(1.0, 0.86, 0.32))
		_flash()
	if tier >= 5 or vr >= 3 or broke_record:   # 真·稀有（神话/七彩）或破个人纪录才庆祝闪光
		_flash()
	# 渔夫性格：钓到高星/七彩，举手欢呼一下（Task 4）
	if (q >= 2 or vr >= 3) and painter.has_method("fisher_cheer"):
		painter.fisher_cheer()
	# 鱼钩双钩：一定几率再上一条（受背包剩余格数限制）
	if hook_level > 0 and not _bag_full() \
			and rng.randf() < float(FishData.HOOKS[hook_level]["double"]):
		var c2 := _roll_one(luck)
		inventory.append(c2)
		lifetime_catches += 1
		best_quality = maxi(best_quality, int(c2.get("q", 0)))
		best_variant = maxi(best_variant, int(c2.get("var", 0)))
		var ib2 := FishData.size_tag(c2["id"], c2["w"]) == "巨物·"
		if ib2:
			caught_giant = true
		_dex_record(c2["id"], float(c2["w"]), ib2, int(c2.get("q", 0)) >= 3, int(c2.get("var", 0)))
		_popup("双钩 +%s" % FishData.display_name(c2["id"]),
			_scene_pt(painter.bobber_pos()) + Vector2(24, -22), Color(0.62, 0.86, 0.74))
		Audio.play_sfx("catch_common")
		var comp_win2 := Competition.on_catch(self, c2)   # 双钩第二条也参与巨物赛
		if comp_win2 > 0:
			Audio.play_sfx("coin")
			_toast("🏆 巨物赛夺金！%s %.2fkg，+%d 金币" % [
				FishData.display_name(str(c2["id"])), float(c2["w"]), comp_win2], 3.4, Color(1.0, 0.86, 0.32))
			_flash()
	if _bag_full():
		_toast("鱼篓满了，先去卖鱼或扩容～", 3.0, Color(1.0, 0.75, 0.4))
	_maybe_pet_steal()   # 桌面宠物：小概率叼走最廉价的一条（Task 4）
	if painter.has_method("pet_react") and not focus_mode and rng.randf() < 0.3:
		painter.pet_react("paw")  # 上鱼时偶尔扒拉一下鱼篓
	_check_achievements()
	_update_hud()
	_refresh_panel()
	if focus_up > 0:  # 专注奖励到手：用最醒目的 toast 收尾（最后调用者覆盖前面的飘字）
		var rname := FishData.variant_label(int(c.get("var", 0))) + FishData.quality_label(int(c.get("q", 0))) \
			+ FishData.display_name(str(c["id"]))
		_toast("🎁 专注奖励到手：%s（%.2fkg，%d 金币）" % [rname, float(c["w"]), int(c["v"])],
			4.0, Color(0.74, 0.86, 0.98))
	_begin_wait()


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
	coins += gain
	lifetime_coins += gain
	painter.add_ripple(painter.bobber_pos(), 28.0)
	_popup("满篓兑 +%d" % gain, _scene_pt(painter.bobber_pos()) + Vector2(-22, -8),
		Color(0.85, 0.72, 0.42))
	_check_achievements()
	_update_hud()
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
	var tm := "　🧪测试" if test_mode else ""   # 测试模式常驻角标（提醒当前改动不写档）
	coins_label.text = "金币 %d　%s%s%s%s" % [coins, bag, mer, evt, tm]
	var col := Color(0.92, 0.92, 0.9)
	if active_event != "":
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
		_catch_tab = 5
		_open_panel("catch"))
	ui_root.add_child(spot_chip)


func _update_spot_chip() -> void:
	if spot_chip == null:
		return
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
		_catch_tab = 2
		_open_panel("catch"))
	ui_root.add_child(order_chip)


func _update_order_chip() -> void:
	if order_chip == null:
		return
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
## 例外：鱼缸页签开着时不因后台上鱼而重建——否则游动的鱼每几秒被重置。
## 放入/捞出鱼等主动操作走 _rebuild_panel() 强制重建。
func _refresh_panel() -> void:
	if _panel_kind == "":
		return
	if _panel_kind == "catch" and _catch_tab == TANK_TAB:
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


func _flash() -> void:
	# 上鱼庆祝光：交给场景画师做「限场景内、随羽化淡出」的柔和暖色脉冲，
	# 不再用铺满整窗的 ColorRect（那会连桌面壁纸区一起染黄、整窗大闪）。
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
	UIPanels.open_panel(self, kind)


func _close_panel() -> void:
	UIPanels.close_panel(self)


func _open_fish_detail(id: String) -> void:
	_detail_fish = id
	_open_panel("fishdetail")


func _set_catch_tab(tab: int) -> void:
	_catch_tab = tab
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
	coins += v
	lifetime_coins += v
	Audio.play_sfx("coin")
	_toast("卖出 %s +%d%s" % [FishData.display_name(c["id"]), v,
		"（鱼贩×1.5）" if _merchant_active else ""], 1.5, Color(0.85, 0.7, 0.35))
	_check_achievements()
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
	coins += total
	lifetime_coins += total
	Audio.play_sfx("coin")
	var msg := "卖出 %d 条鱼 +%d 金币%s" % [n, total, "（鱼贩×1.5）" if _merchant_active else ""]
	if not keep.is_empty():
		msg += "（%d 条收藏留着）" % keep.size()
	_toast(msg, 2.2, Color(0.85, 0.7, 0.35))
	_check_achievements()
	_update_hud()
	_refresh_panel()
	_save()


## 卖杂鱼：卖出未上锁且非当前订单目标的鱼，保留订单进度与收藏。
func _sell_junk() -> void:
	var total := 0
	var n := 0
	var keep: Array = []
	for c in inventory:
		if bool(c.get("lock", false)) or _order_matches(c):
			keep.append(c)
		else:
			total += _sell_value(c)
			n += 1
	if n == 0:
		return
	inventory = keep
	coins += total
	lifetime_coins += total
	Audio.play_sfx("coin")
	_toast("卖出杂鱼 %d 条 +%d 金币（订单鱼与收藏保留）" % [n, total], 2.2, Color(0.85, 0.7, 0.35))
	_check_achievements()
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
	return false


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
				coins += reward
			var msg := "成就达成：%s" % a["name"]
			if reward > 0:
				msg += "（+%d 金币）" % reward
			_toast(msg, 3.0, Color(0.98, 0.85, 0.45))


func _rod_cost() -> int:
	# 陡成本曲线：让鱼竿成为真正的长期金币去向（旧 40×1.8^n 几乎零成本）。
	# 成本增速(2.0/级) 高于产出增速(~1.25/级)，回本时间随等级递增、后期形成自然墙。
	return int(round(200.0 * pow(2.0, rod_level - 1)))


func _try_upgrade_rod() -> void:
	var cost := _rod_cost()
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= cost
	rod_level += 1
	Audio.play_sfx("upgrade")
	_check_achievements()
	_update_hud()
	_toast("鱼竿升到 Lv.%d！" % rod_level, 2.0, Color(0.5, 0.8, 1.0))
	_refresh_panel()   # 升级页已是鱼篓面板「装备」页签，原地刷新即可


func _try_upgrade_bait() -> void:
	if bait_level >= FishData.BAITS.size() - 1:
		return
	var nxt: Dictionary = FishData.BAITS[bait_level + 1]
	var cost := int(nxt["cost"])
	if coins < cost:
		Audio.play_ui("ui_error")
		_toast("金币不足", 1.5, Color(1.0, 0.5, 0.4))
		return
	coins -= cost
	bait_level += 1
	Audio.play_sfx("upgrade")
	_check_achievements()
	_update_hud()
	_toast("换上了%s，星级渔获概率提升！" % nxt["name"], 2.4, Color(0.6, 0.85, 0.5))
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
	Audio.play_sfx("upgrade")
	_check_achievements()
	_update_hud()
	_toast("换上了%s，双钩几率提升！" % nxt["name"], 2.4, Color(0.6, 0.85, 0.5))
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
	Audio.play_sfx("upgrade")
	_check_achievements()
	_update_hud()
	_toast("撒下%s，稀有变体几率提升！" % nxt["name"], 2.4, Color(0.78, 0.62, 0.95))
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
	max_fps = val if val in FPS_OPTIONS else 30
	Engine.max_fps = max_fps


## 屏幕可用区能容纳的最大缩放（留 2% 边距，避免顶满屏幕）。
func _max_scale_for_screen() -> float:
	if DisplayServer.get_name() == "headless":
		return UI_SCALE_MAX
	var u := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var fit := minf(float(u.size.x) / float(WIN.x), float(u.size.y) / float(WIN.y)) * 0.98
	return clampf(fit, UI_SCALE_MIN, UI_SCALE_MAX)


## 界面缩放（设置页「快捷跳档」按钮 / 存档载入走这里）：设值 + 整窗等比改尺寸 +
## 以原中心为锚夹到屏幕。canvas_items 拉伸 → 成品图整体缩放，含小字一起变大，布局不变、不溢出。
## 沉浸模式的羽化/穿透按设计空间标定，不在此缩放（避免裁切错位）。自由拖拽缩放见 _build_resize_grips。
func _set_ui_scale(val: float) -> void:
	if DisplayServer.get_name() == "headless" or display_mode != "framed":
		ui_scale = clampf(val, UI_SCALE_MIN, UI_SCALE_MAX)
		return
	ui_scale = clampf(val, UI_SCALE_MIN, _max_scale_for_screen())
	var old_size := DisplayServer.window_get_size()
	var center := Vector2(DisplayServer.window_get_position()) + Vector2(old_size) * 0.5   # 以原中心为锚
	var new_size := Vector2i(Vector2(WIN) * ui_scale)
	_win_resize_guard = true
	DisplayServer.window_set_size(new_size)
	_win_resize_guard = false
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var pos := Vector2i(center - Vector2(new_size) * 0.5)
	pos.x = clampi(pos.x, usable.position.x, usable.position.x + maxi(0, usable.size.x - new_size.x))
	pos.y = clampi(pos.y, usable.position.y, usable.position.y + maxi(0, usable.size.y - new_size.y))
	DisplayServer.window_set_position(pos)
	_saved_win_pos = null
	UIPanels.set_interactive_full(self, true)   # 整窗交互区跟随新尺寸


## 自绘缩放手柄：无边框窗口没有系统边框可拖，于是在画布四边四角放隐形热区 Control。
## canvas_items 拉伸下画布恒为 WIN(1040×720)，故热区用固定 WIN 坐标即可永远贴着窗口边。
func _build_resize_grips() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var t := 6.0    # 边热区厚度
	var c := 16.0   # 角热区边长
	var w := float(WIN.x)
	var h := float(WIN.y)
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
		grip.position = Vector2(d[0], d[1])
		grip.size = Vector2(d[2], d[3])
		grip.mouse_filter = Control.MOUSE_FILTER_STOP
		grip.mouse_default_cursor_shape = d[4]
		grip.gui_input.connect(_on_grip_input.bind(d[5], d[6], d[4]))
		ui_root.add_child(grip)


## 手柄被按下 → 记录锚点/轴向/起始几何，进入缩放拖拽（后续移动/松手在 _input 全局处理）。
func _on_grip_input(event: InputEvent, anchor_norm: Vector2, dir: Vector2, cursor: int) -> void:
	if _rz_active or display_mode != "framed":
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_rz_active = true
		_rz_anchor = anchor_norm
		_rz_dir = dir
		_rz_start_mouse = DisplayServer.mouse_get_position()
		_rz_start_pos = DisplayServer.window_get_position()
		_rz_start_size = DisplayServer.window_get_size()
		Input.set_default_cursor_shape(cursor)


## 拖拽缩放：按驱动轴推算等比缩放，锚点（拖动不动的那角/边）屏幕坐标保持不变。
## 我们自己接管鼠标 → 无系统模态循环，实时改尺寸不打架。
func _apply_grip_resize(mouse_global: Vector2i) -> void:
	var delta := Vector2(mouse_global - _rz_start_mouse)
	var raw_w := float(_rz_start_size.x) + _rz_dir.x * delta.x
	var raw_h := float(_rz_start_size.y) + _rz_dir.y * delta.y
	var sc := ui_scale
	if _rz_dir.x != 0.0 and _rz_dir.y != 0.0:
		sc = maxf(raw_w / float(WIN.x), raw_h / float(WIN.y))   # 角：取较大轴，跟手
	elif _rz_dir.x != 0.0:
		sc = raw_w / float(WIN.x)
	else:
		sc = raw_h / float(WIN.y)
	sc = clampf(sc, UI_SCALE_MIN, _max_scale_for_screen())
	ui_scale = sc
	var new_size := Vector2i(Vector2(WIN) * sc)
	var anchor_global := Vector2(_rz_start_pos) + Vector2(_rz_start_size) * _rz_anchor
	var new_pos := Vector2i(anchor_global - Vector2(new_size) * _rz_anchor)
	_win_resize_guard = true
	DisplayServer.window_set_size(new_size)
	DisplayServer.window_set_position(new_pos)
	_win_resize_guard = false
	UIPanels.set_interactive_full(self, true)


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
	if not _focus_t1_done and _focus_away_t >= FOCUS_T1:
		_focus_t1_done = true
		_grant_focus_reward(1)
	if not _focus_t2_done and _focus_away_t >= FOCUS_T2 and focus_reward_today < FOCUS_REWARD_DAILY_CAP:
		_focus_t2_done = true
		_grant_focus_reward(2)


func _grant_focus_reward(level: int) -> void:
	focus_pending = maxi(focus_pending, level)
	focus_reward_today += 1
	var mins := 25 if level == 1 else 50
	_toast("专注 %d 分钟，下一竿留了份惊喜给你 ✨" % mins, 4.0, Color(0.74, 0.86, 0.98))
	_check_achievements()
	_save()


## 当前若有待兑专注奖励，就把这一竿强制升级（保底高星 / 50 分钟再保底鎏金）。返回消费的等级。
func _apply_focus_reward(c: Dictionary) -> int:
	if focus_pending <= 0:
		return 0
	var level := focus_pending
	focus_pending = 0
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


## 切回窗口 / 主动操作 → 当前这段专注清零（不清待兑奖励：已挣到的留着下一竿兑）。
func _reset_focus_streak() -> void:
	_focus_away_t = 0.0
	_focus_t1_done = false
	_focus_t2_done = false


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
	if not save_enabled:
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
	elapsed = clampf(elapsed, 0.0, OFFLINE_CAP)
	if elapsed > 30.0:
		var caught := _offline_catch(elapsed)
		if caught > 0:
			_offline_report["dur"] = _fmt_dur(elapsed)
			_offline_report["full"] = _bag_full()
		elif _bag_full():
			_pending_offline = "离线 %s，鱼篓是满的，一条都装不下啦" % _fmt_dur(elapsed)


## 离线钓鱼：上鱼数 = 时长/平均间隔×效率。鱼篓装满后不再截断（调研 3.2），
## 多出的鱼经 _absorb_overflow 折价兑成金币兜底——挂一夜回来一定有收益。
## 汇总成 _offline_report 供回屏小结展示。返回本次产生收益的总条数（入篓 + 兜底）。
func _offline_catch(elapsed: float) -> int:
	var wait_factor: float = maxf(0.4, 1.0 - float(rod_level - 1) * 0.06)
	var avg_interval := 5.25 * wait_factor + 0.9
	var est := int(elapsed / avg_interval * OFFLINE_EFFICIENCY)
	if est <= 0:
		return 0
	var cap := _bag_capacity()
	var stored := mini(est, maxi(0, cap - inventory.size()))  # 先填满空格
	var overflow := est - stored                              # 其余折价兜底
	var total_v := 0
	var top: Dictionary = {}
	var notable: Array = []
	# —— 入篓部分（正常展示）——
	for i in stored:
		var c := _roll_one(0)  # 离线也按当前钓点鱼池 + 钓点增值，含稀有变体
		inventory.append(c)
		var ib := FishData.size_tag(c["id"], c["w"]) == "巨物·"
		_dex_record(c["id"], float(c["w"]), ib, int(c.get("q", 0)) >= 3, int(c.get("var", 0)))
		lifetime_catches += 1
		best_quality = maxi(best_quality, int(c.get("q", 0)))
		best_variant = maxi(best_variant, int(c.get("var", 0)))
		if ib:
			caught_giant = true
		total_v += int(c["v"])
		if top.is_empty() or int(c["v"]) > int(top["v"]):
			top = c
		if FishData.tier_of(c["id"]) >= 3 or int(c.get("q", 0)) >= 2 or int(c.get("var", 0)) >= 1:
			notable.append(c)
	# —— 满篓兜底部分（折价兑金；稀有仍会被换进篓、踢出最廉价那条）——
	var overflow_v := 0
	for i in overflow:
		var c := _roll_one(0)
		var ib := FishData.size_tag(c["id"], c["w"]) == "巨物·"
		_dex_record(c["id"], float(c["w"]), ib, int(c.get("q", 0)) >= 3, int(c.get("var", 0)))
		lifetime_catches += 1
		best_quality = maxi(best_quality, int(c.get("q", 0)))
		best_variant = maxi(best_variant, int(c.get("var", 0)))
		if ib:
			caught_giant = true
		overflow_v += _absorb_overflow(c)
	coins += overflow_v
	lifetime_coins += overflow_v
	_offline_report["overflow_n"] = overflow
	_offline_report["overflow_v"] = overflow_v
	if stored > 0 or overflow > 0:
		_offline_report["count"] = stored          # 入篓条数（满篓溢出走 overflow_n/v）
		_offline_report["value"] = total_v
		_offline_report["top"] = top
		_offline_report["notable"] = notable
	return stored + overflow


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
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focused = true    # 切回挂件 → 当前这段专注清零
			_reset_focus_streak()
			_idle_t = 0.0


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
	_focus_t1_done = false
	_focus_t2_done = false
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
