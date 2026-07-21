extends SceneTree
## 开发工具：引擎内视口截图（读渲染纹理，带 alpha，可验证透明）。
## 运行: godot_console --path . -s tools/dev_screenshot.gd   （注意：不能 --headless，无视口）

const OUT_DIR := "res://docs/img"
const RelationshipDataScript := preload("res://relationship_data.gd")

var _main: Node


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_main = load("res://main.tscn").instantiate()
	_main.save_enabled = false  # 截图实例不读不写真实存档
	root.add_child(_main)
	for i in 30:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main.seen_intro = true
	_main._close_panel()  # 关掉首启引导，场景展示图保持干净

	# 1) 场景 + 按钮 + 一次上鱼反馈
	_main.coins = 1234
	_main._update_hud()
	_main._toast("传说！钓到 锦鲤（3.20kg）", 3.0, FishData.TIER_COLORS[4])
	_main._popup("锦鲤 3.20kg", _main.painter.position + _main.painter.bobber_pos() + Vector2(-22, -8), FishData.TIER_COLORS[4])
	await _settle(2)
	_snap("scene.png")

	# 2) 背包页签（先钓几条入包）
	for i in 6:
		_main._do_catch()
	_main._catch_tab = 0
	_main._open_panel("catch")
	await _settle(2)
	_snap("panel_bag.png")

	# 限定鱼提前入图鉴：让图鉴列表显示🌙徽标、详情卡能展示限定说明
	_main.dex["oarfish"] = {"n": 8, "w": 120.0, "big": true, "perf": false,
		"vmask": (1 << 2), "fd": "2026-06-01", "wd": "2026-06-18"}
	_main.dex["wels_catfish"] = {"n": 11, "w": 42.0, "big": true, "perf": false,
		"vmask": 0, "fd": "2026-06-02", "wd": "2026-06-15"}

	# 2b) 图鉴页签
	_main._catch_tab = 1
	_main._open_panel("catch")
	await _settle(2)
	_snap("panel_dex.png")

	# 2c) 鱼种详情卡（点鲤鱼，带真实照片）
	# 注入一条混合变体纪录：验证个人纪录卡 + 变体墙已集/未集混合态（斑斓✓ 鎏金✗ 七彩✓）
	_main.dex["carp"] = {"n": 14, "w": 3.2, "big": true, "perf": true,
		"vmask": (1 << 1) | (1 << 3), "fd": "2026-06-19", "wd": "2026-06-19"}
	_main._detail_fish = "carp"
	_main._open_panel("fishdetail")
	await _settle(2)
	_snap("panel_fishdetail.png")
	# 详情卡内容超一屏：滚到底再截一张，把关个人纪录卡 + 变体墙
	var _dsc := _find_detail_scroll(_main)
	if _dsc != null:
		_dsc.scroll_vertical = 100000
		await _settle(3)
		_snap("panel_fishdetail_lower.png")

	# 2d) 限定鱼详情卡（皇带鱼）：夜晚时段 → 限定说明显示"可遇"，滚到底看🌙限定卡
	_main.day_phase = "night"
	_main._detail_fish = "oarfish"
	_main._open_panel("fishdetail")
	await _settle(2)
	var _dsc2 := _find_detail_scroll(_main)
	if _dsc2 != null:
		_dsc2.scroll_vertical = 100000
		await _settle(3)
	_snap("panel_fishdetail_limited.png")
	_main.day_phase = Weather.current_phase()

	# 2e) 任务页（含本周巨物赛卡）
	_main._catch_tab = 2
	_main._open_panel("catch")
	await _settle(2)
	_snap("panel_tasks.png")

	# 2f) 河湾人情簿：五位 NPC 的独立好感与终章方向（首阶段总览）。
	_main.relationship_state = RelationshipDataScript.default_state()
	_main.relationship_state["npc"]["zhou_uncle"]["favor"] = 4
	_main.relationship_state["npc"]["zhou_uncle"]["story_seen"] = 3
	_main.relationship_state["visits"]["lin_aunt"] = RelationshipDataScript.make_visit("lin_aunt", "story", Time.get_unix_time_from_system(), 0)
	_main.relationship_state["visits"]["zhou_uncle"] = RelationshipDataScript.make_visit("zhou_uncle", "task", Time.get_unix_time_from_system())
	_main.relationship_state["visits"]["tang"] = RelationshipDataScript.make_visit("tang", "buff", Time.get_unix_time_from_system())
	_main.relationship_state["visits"]["xiaoman"] = RelationshipDataScript.make_visit("xiaoman", "hint", Time.get_unix_time_from_system())
	_main.relationship_state["visits"]["ma"] = RelationshipDataScript.make_visit("ma", "hint", Time.get_unix_time_from_system())
	_main.feature_unlocks["relations"] = true
	_main._update_relationship_visit_bar()
	_main._close_panel()
	await _settle(2)
	_snap("relationship_visit_heads.png")
	_main._catch_tab = 9
	_main._open_panel("catch")
	await _settle(2)
	_snap("panel_relations.png")

	# 2g) 一次性人物近况面板：确认后记录已读等级，不重复投放。
	_main.inventory = [
		{"id": "crucian", "w": 0.36, "v": 8, "q": 0},
		{"id": "carp", "w": 5.80, "v": 33, "q": 1},
		{"id": "sardine", "w": 0.06, "v": 4, "q": 0},
		{"id": "oarfish", "w": 18.0, "v": 900, "q": 2, "lock": true},
	]
	_main._open_relationship_visit("lin_aunt")
	await _settle(2)
	_snap("panel_relationship_visit.png")
	_main._close_panel()
	_main.relationship_state["visits"]["lin_aunt"] = RelationshipDataScript.make_visit("lin_aunt", "hint", Time.get_unix_time_from_system())
	_main._open_relationship_visit("lin_aunt")
	_main._set_relationship_visit_reply("我挑一条。", "picker")
	_main._open_panel("relationship_visit")
	await _settle(2)
	_snap("panel_relationship_gift.png")
	_main._close_panel()
	_main._open_relationship_visit("zhou_uncle")
	_main._set_relationship_visit_reply("给你看看。", "picker")
	_main._open_panel("relationship_visit")
	await _settle(2)
	_snap("panel_relationship_task.png")
	_main._close_panel()
	_main._open_relationship_visit("tang")
	await _settle(2)
	_snap("panel_relationship_buff.png")
	_main._close_panel()
	_main.relationship_state["npc"]["ma"]["favor"] = RelationshipDataScript.FAVOR_LEVELS.size() - 1
	_main.relationship_state["visits"]["ma"] = RelationshipDataScript.make_visit("ma", "finale", Time.get_unix_time_from_system())
	_main.inventory.append({"id": "catfish", "w": 7.2, "v": 88, "q": 1})
	_main._open_relationship_visit("ma")
	await _settle(2)
	_snap("panel_relationship_finale.png")
	_main._close_panel()
	_main._open_relationship_visit("lin_aunt")
	_main._set_relationship_visit_reply("好，我记住了。", "feedback")
	_main._show_relationship_feedback("好，那我就放心了。\n已记录：河边第一壶茶", "good")
	await _settle(2)
	_snap("panel_relationship_feedback.png")
	_main._finish_relationship_visit_feedback()
	_main.relationship_state["visits"] = {}
	_main.relationship_state["buff"] = {}
	_main._update_relationship_visit_bar()

	# 2h) 比赛目标鱼详情卡（展示🏆 banner）：让目标鱼已发现、本周最佳到位，滚到底
	var _cfish := str(_main.competition.get("fish", ""))
	if _cfish != "" and FishData.FISH.has(_cfish):
		# 不直接引用 Competition 类：-s 工具脚本顶层类引用会在 autoload 前早编译整条依赖图 → Audio not found。
		# 影子线 = wmax×0.55，这里设到其 80% 展示"接近达标"的进度态。
		_main.competition["best"] = float(FishData.FISH[_cfish]["wmax"]) * 0.55 * 0.8
		if not _main.dex.has(_cfish):
			_main.dex[_cfish] = {"n": 3, "w": float(_main.competition["best"]), "big": false,
				"perf": false, "vmask": 0, "fd": "2026-06-10", "wd": "2026-06-17"}
		_main._detail_fish = _cfish
		_main._open_panel("fishdetail")
		await _settle(2)
		var _bsc := _find_detail_scroll(_main)
		if _bsc != null:
			_bsc.scroll_vertical = 100000
			await _settle(3)
		_snap("panel_fishdetail_comp.png")

	# 3) 升级面板
	_main._open_panel("rod")
	await _settle(2)
	_snap("panel_rod.png")

	# 3a) 设置页（含帧率 30/60/90/120 选择器）
	_main.max_fps = 60
	_main._catch_tab = 8
	_main._open_panel("catch")
	await _settle(2)
	_snap("panel_settings.png")
	_main.test_mode = true
	_main.reel_level = 50
	_main.rod_level = 4
	_main.bait_level = 2
	_main.hook_level = 2
	_main.lure_level = 2
	_main._close_panel()
	_main._set_dev_attrs_open(true)
	await _settle(2)
	_snap("panel_stats_debug.png")
	_main._set_dev_attrs_open(false)
	_main._set_relationship_debug_open(true)
	_main.relationship_state["visits"]["lin_aunt"] = RelationshipDataScript.make_visit("lin_aunt", "hint", Time.get_unix_time_from_system())
	_main.relationship_state["visits"]["zhou_uncle"] = RelationshipDataScript.make_visit("zhou_uncle", "task", Time.get_unix_time_from_system())
	_main.relationship_state["npc"]["zhou_uncle"]["favor"] = 5
	_main._refresh_relationship_debug_panel()
	await _settle(2)
	_snap("panel_relationship_debug.png")
	_main._set_relationship_debug_open(false)
	_main.test_mode = false

	# 3b) 多钓点：解锁全部 → 钓点页签 + 切到静水湖泊看 HUD 钓点角标
	_main.lifetime_catches = 400
	_main._refresh_unlocks()
	_main._catch_tab = 5
	_main._open_panel("catch")
	await _settle(2)
	_snap("panel_spot.png")
	# 旅行地图：走过几站再拍，才看得到针脚线把站点串起来（晨昏线按拍摄时刻的真实 UTC）
	_main.seen_spots = ["river_bend", "still_lake", "mountain_stream", "urban_pond", "coast_pier"]
	_main.current_spot = "coast_pier"
	_main._open_panel("worldmap")
	await _settle(8)
	_snap("panel_worldmap.png")
	_main._close_panel()
	_main.current_spot = "river_bend"
	# 鱼缸页（活水族箱）：放几条含变体的鱼进缸，展示游动 + 鎏金/七彩光晕 + 上架列表
	for i in 4:
		_main._do_catch()
	_main.display = [
		{"id": "koi", "w": 6.2, "v": 1600, "q": 2, "lock": false, "var": 3},
		{"id": "kaluga", "w": 120.0, "v": 9000, "q": 1, "lock": false, "var": 2},
		{"id": "mandarin", "w": 2.4, "v": 180, "q": 0, "lock": false, "var": 1},
		{"id": "bass", "w": 2.1, "v": 110, "q": 1, "lock": false, "var": 0},
	]
	_main._catch_tab = 6
	_main._open_panel("catch")
	await _settle(30)  # 让缸里的鱼游开、光晕脉动起来再拍
	_snap("panel_decor.png")
	_main._close_panel()
	_main._switch_spot("still_lake")
	_main._fire_event("morning_fog")  # 让 HUD 角标显示「静水湖泊 · 晨雾」
	_main._update_hud()
	await _settle(2)
	_snap("scene_lake.png")
	_main.active_event = ""
	_main._switch_spot("coast_pier")
	_main._fire_event("tide_in")  # 「海岸码头 · 涨潮」
	_main._update_hud()
	await _settle(2)
	_snap("scene_coast.png")
	_main.active_event = ""
	_main._switch_spot("river_bend")
	# 昼夜：强制黄昏，验证时段底图 + 场景染色 + HUD「· 黄昏」
	_main.day_phase = "dusk"
	_main._apply_phase()
	_finish_spot_fade()   # 截图工具：跳过 90s 慢淡入，直接呈现目标时段底图
	_main._update_hud()
	await _settle(2)
	_snap("scene_dusk.png")
	_main.day_phase = Weather.current_phase()
	_main._apply_phase()
	_finish_spot_fade()
	_main._update_hud()

	# 4) 动态层：强制小动物事件（中段全亮）+ 涟漪帧动画
	_main._close_panel()
	_main.painter._start_wild("rabbit")
	_main.painter._wild_t = _main.painter._wild_dur * 0.5
	_main.painter.add_ripple(_main.painter.bobber_pos(), 28.0)
	await _settle(4)
	_snap("scene_dynamic.png")

	# 4b) 渔夫情绪 + 桌面宠物：触发欢呼 + 宠物扒拉，拍一帧（Task 4）
	_main.painter.fisher_cheer()
	_main.painter.pet_react("paw")
	await _settle(6)
	_snap("scene_pet_cheer.png")

	# 5) 动效校验：间隔 3 秒拍两帧，供外部做像素差对比（证明肉眼可见的动态）
	await _settle(6)
	_snap("motion_a.png")
	await _settle(90)  # 30fps × 90 帧 = 3 秒
	_snap("motion_b.png")

	# 6) UI 对位校验：按钮命中区/落水点画红色标记，美术更新后跑一遍核对是否错位
	for k in _main.btn_centers.keys():
		var m := ColorRect.new()
		m.color = Color(1, 0, 0, 0.4)
		m.size = Vector2(30, 32)
		m.position = (_main.btn_centers[k] as Vector2) - Vector2(15, 16)
		_main.ui_root.add_child(m)
	var bp := ColorRect.new()
	bp.color = Color(0, 1, 0, 0.5)
	bp.size = Vector2(8, 8)
	bp.position = _main.painter.bite_point - Vector2(4, 4)
	_main.ui_root.add_child(bp)
	await _settle(2)
	_snap("ui_align_check.png")

	quit()


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


## 递归找详情卡的滚动容器（custom_minimum_size.y == 404，见 ui_panels.fill_fish_detail）。
func _find_detail_scroll(n: Node) -> ScrollContainer:
	for c in n.get_children():
		if c is ScrollContainer and is_equal_approx((c as ScrollContainer).custom_minimum_size.y, 404.0):
			return c
		var r := _find_detail_scroll(c)
		if r != null:
			return r
	return null


## 立即结束昼夜底图 crossfade（截图工具需要静帧呈现目标时段，不等 90s 慢淡入）。
func _finish_spot_fade() -> void:
	var p: Node2D = _main.painter
	if "_spot_fade" in p:
		p._spot_fade = 1.0
		p._spot_prev = null
		p.queue_redraw()


func _snap(filename: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + filename)
	print("SNAP %s size=%s" % [filename, str(img.get_size())])
