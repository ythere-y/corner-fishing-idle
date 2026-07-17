class_name UIPanels
## 面板/卡片/页签 UI 构建（从 main.gd 拆出，瘦身 + 为并行铺路）。
## 纯静态函数，状态仍在主节点 g 上（_panel/_catch_tab/_bag_sort 等）；main 留薄壳 wrapper。
## 约定与 SaveSystem 一致：第一参数 g = 主节点；样式工厂函数无需 g。
## 行为与原 main.gd 内嵌实现完全一致（仅做位置迁移 + g. 前缀）。

const CARD_SIZE := Vector2(520, 476)

static var font_bold: Font = null   # 由 main._setup_theme 注入：系统字体假粗体（CD 按钮/页签 weight 600-700）
const RelationshipDataScript := preload("res://relationship_data.gd")


# ============================ 面板开关 ============================

static func open_panel(g: CornerFishing, kind: String) -> void:
	var was_open := is_instance_valid(g._panel)   # 区分"首次打开"vs"切页签重建"
	# 「视图签名」相同 = 同一屏内容（仅数据变了）的重建，例如挂机每隔几秒上鱼触发的
	# _refresh_panel。此时记下旧滚动位置，建好新内容后还原——否则正在浏览的长列表
	# 会被反复弹回顶部（拖动条"自动回弹"）。切页签/换详情鱼则签名变了，从顶部开始。
	var sig := _view_sig(g, kind)
	var keep_scroll := -1
	if was_open:
		g._panel_saved_pos = g._panel.position
		if sig == g._panel_view_sig:
			var old_sc := _find_scroll(g._panel)
			if old_sc != null:
				keep_scroll = old_sc.scroll_vertical
	# 重建面板时保持「全窗可交互」穿透不变——不要切回羽化椭圆。
	# 否则透明窗会被裁成椭圆一帧 → 点任意按钮都闪一下、露出场景羽化弧边。
	close_panel(g, true)
	# 【修改】新增 story / character 两个开场专用面板标题（背包客人设开场流程）；intro 标题随新项目名调整。
	var titles := {"catch": "垂钓手册", "rod": "鱼竿 · 升级", "set": "设置", "offline": "离线小结",
		"intro": "欢迎来到背包钓鱼手记", "story": "在开始之前……", "character": "这次是谁在路上？",
		"worldmap": "旅行地图", "capture": "号外 · 稀有入手！", "relationship_visit": "到访"}
	var title_str := str(titles.get(kind, ""))
	if kind == "fishdetail":
		title_str = FishData.display_name(str(g._detail_fish)) + " · 详情"
	elif kind == "relationship_visit":
		var npc := RelationshipDataScript.get_npc(str(g.selected_relationship_visit_id))
		title_str = "到访 · %s" % str(npc.get("name", "熟人"))
	elif kind == "catch" and g.display_mode != "immersive":
		title_str = _section_name(g._catch_tab)   # 带框 sheet 标题=区名（CD）
	var card := make_card(g, title_str)
	# 恢复拖拽位置；开场/离线这类引导面板保持居中。
	# 【修改】story/character 同样是开场引导性质的固定面板，不恢复上次拖拽位置。
	if kind != "offline" and kind != "intro" \
			and kind != "story" and kind != "character" and g._panel_saved_pos != null:
		card.position = clamp_panel_position(g, g._panel_saved_pos, card.custom_minimum_size)
	var v: VBoxContainer = card.get_node("M/V")
	match kind:
		"catch": fill_bag_panel(g, v)
		"rod": fill_upgrades(g, v)
		"set": fill_settings(g, v)
		"offline": fill_offline_report(g, v)
		"intro": fill_intro(g, v)
		"story": fill_story(g, v)          # 【新增】开场世界观动画
		"character": fill_character(g, v)  # 【新增】选择背包客角色
		"fishdetail": fill_fish_detail(g, v)
		"worldmap": fill_world_map(g, v)   # 旅行地图（离线：晨昏线 + 旅程）
		"capture": fill_capture_card(g, v)  # 稀有捕获卡（P0 好玩补丁）
		"relationship_visit": fill_relationship_visit(g, v)
	g.ui_root.add_child(card)
	g._panel = card
	g._panel_kind = kind
	g._panel_view_sig = sig
	if keep_scroll > 0:
		_restore_scroll(g, card, keep_scroll)
	set_interactive_full(g, true)
	if g.display_mode != "immersive":
		g._set_nav_solid(true)   # 底栏变暗，与 sheet 连成一片（无断裂）


static func close_panel(g: CornerFishing, keep_interactive := false) -> void:
	if is_instance_valid(g._panel):
		g._panel_saved_pos = g._panel.position
		g._panel.queue_free()
	g._panel = null
	g._panel_kind = ""
	g._panel_dragging = false
	# keep_interactive=true 用于「重建面板」过渡，避免穿透 全窗→椭圆→全窗 抖动闪屏。
	# 真正关闭面板（× 按钮）走默认 false，恢复羽化椭圆穿透（窗外可穿透到桌面）。
	if not keep_interactive:
		set_interactive_full(g, false)
		if g.display_mode != "immersive":
			g._set_nav_solid(false)   # 真关闭 → 底栏恢复透明（浮场景）


# 同一签名 = 同一屏内容；签名变了（切页签 / 换详情鱼 / 改图鉴品阶筛选 / 改背包排序或订单过滤）
# 应从顶部开始而非沿用旧滚动位置。_dex_tier 是 ui_panels 的静态筛选状态。
static func _view_sig(g: CornerFishing, kind: String) -> String:
	if kind == "catch":
		return "catch:%d:%d:%d:%s" % [g._catch_tab, _dex_tier, g._bag_sort, str(g._bag_filter_order)]
	if kind == "fishdetail":
		return "fishdetail:%s" % g._detail_fish
	if kind == "relationship_visit":
		return "relationship_visit:%s" % str(g.selected_relationship_visit_id)
	return kind


# 深度优先找面板里的主滚动容器（每屏内容只有一个 ScrollContainer）。
static func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for c in node.get_children():
		var r := _find_scroll(c)
		if r != null:
			return r
	return null


# 还原滚动位置：ScrollContainer 在内容尺寸算出来前设 scroll_vertical 会被夹回 0，
# 等两帧布局完成再设。以协程方式跑（调用处不 await），不阻塞面板构建。
static func _restore_scroll(g: CornerFishing, root: Node, value: int) -> void:
	var tree := g.get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(root):
		return
	var sc := _find_scroll(root)
	if sc != null:
		sc.scroll_vertical = value


static func set_interactive_full(g: CornerFishing, full: bool) -> void:
	g._set_window_interaction(full)


# ============================ 样式工厂 ============================

static func panel_bg_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DT.GLASS
	sb.set_corner_radius_all(DT.R_PANEL)
	sb.set_border_width_all(1)
	sb.border_color = DT.GLASS_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.32)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)  # --shadow-panel：软、纯垂直
	return sb


static func paper_style(alpha := 0.88) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DT.PAPER_SOLID.r, DT.PAPER_SOLID.g, DT.PAPER_SOLID.b, alpha)
	sb.set_corner_radius_all(DT.R_CARD)
	sb.set_border_width_all(1)
	sb.border_color = DT.PAPER_BORDER
	return sb


static func dark_row_style(alpha := 0.52) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DT.GLASS_ROW.r, DT.GLASS_ROW.g, DT.GLASS_ROW.b, alpha)
	sb.set_corner_radius_all(DT.R_CELL)
	sb.set_border_width_all(1)
	sb.border_color = DT.GLASS_ROW_BORDER
	return sb


static func button_style(primary := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DT.BRONZE if primary else DT.BTN_SEC_BG
	sb.set_corner_radius_all(DT.R_ROW)
	sb.set_border_width_all(0)
	return sb


static func apply_button_skin(b: Button, primary := false) -> void:
	b.focus_mode = Control.FOCUS_NONE
	if font_bold != null:
		b.add_theme_font_override("font", font_bold)   # CD .btn weight 700
	var normal := button_style(primary)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = DT.BRONZE_HOVER if primary else DT.BTN_SEC_BG_HOVER
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = DT.BRONZE_PRESS if primary else Color(0.25, 0.25, 0.22, 0.95)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = DT.BTN_DISABLED_BG
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", DT.INK_ON_GOLD if primary else DT.BTN_SEC_FG)
	b.add_theme_color_override("font_disabled_color", DT.TEXT_FAINT_GLASS)
	b.pressed.connect(func() -> void: Audio.play_ui("ui_click"))


# CD .seg .tab —— pill 页签：未选=暗行+次字；选中=铜底深字（accent 可传品阶色）
static func apply_tab_skin(b: Button, active: bool, accent := DT.BRONZE) -> void:
	b.focus_mode = Control.FOCUS_NONE
	if font_bold != null:
		b.add_theme_font_override("font", font_bold)   # CD .seg .tab weight 600
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(DT.R_CHIP)
	normal.content_margin_left = 11
	normal.content_margin_right = 11
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	normal.bg_color = accent if active else DT.GLASS_ROW
	if not active:
		normal.set_border_width_all(1)
		normal.border_color = Color(0, 0, 0, 0)
	var hover := normal.duplicate() as StyleBoxFlat
	if not active:
		hover.bg_color = DT.GLASS_ROW_HOVER
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", normal)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", DT.INK_ON_GOLD if active else DT.TEXT_MUTED_GLASS)
	b.add_theme_font_size_override("font_size", DT.FS_XS)
	b.pressed.connect(func() -> void: Audio.play_ui("ui_click"))


# CD .pill —— 小状态标签（非按钮）
static func make_pill(text: String, bg: Color, fg: Color, fs := DT.FS_2XS) -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(DT.R_CHIP)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", fg)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	return pc


# CD .progress —— 细进度条（圆角，金色填充）
static func make_progress(frac: float, fill := DT.GOLD, h := 7) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = clampf(frac, 0.0, 1.0)
	pb.custom_minimum_size = Vector2(0, h)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = DT.GLASS_ROW
	bgs.set_corner_radius_all(DT.R_CHIP)
	var fgs := StyleBoxFlat.new()
	fgs.bg_color = fill
	fgs.set_corner_radius_all(DT.R_CHIP)
	pb.add_theme_stylebox_override("background", bgs)
	pb.add_theme_stylebox_override("fill", fgs)
	return pb


# ============================ 卡片骨架 ============================

## CD 式 sheet（带框模式）：覆盖舞台（底部导航以上）、从下方滑出、不可拖，内容居中列。
static func _make_sheet(g: CornerFishing, title: String) -> Control:
	var stage_h := float(g.WIN.y) - g.FRAMED_CONSOLE_H
	var p := PanelContainer.new()
	p.z_index = 50
	p.custom_minimum_size = Vector2(float(g.WIN.x), stage_h)
	p.size = Vector2(float(g.WIN.x), stage_h)
	p.position = Vector2(0, stage_h)   # 起始在舞台下方；open_panel 里 tween 滑上来
	var sb := StyleBoxFlat.new()
	sb.bg_color = DT.GLASS
	sb.corner_radius_top_left = DT.R_PANEL
	sb.corner_radius_top_right = DT.R_PANEL
	sb.border_width_top = 1
	sb.border_color = DT.GLASS_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, -4)
	p.add_theme_stylebox_override("panel", sb)
	var m := MarginContainer.new()
	m.name = "M"
	m.add_theme_constant_override("margin_left", 28)   # 铺满整宽（CD 式 full-bleed），只留舒适内边距
	m.add_theme_constant_override("margin_right", 28)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 18)
	p.add_child(m)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	# 头：衬线标题 + 关闭（sheet 不可拖）
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(0, 30)
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_STOP
	hb.mouse_default_cursor_shape = Control.CURSOR_MOVE
	hb.gui_input.connect(func(e: InputEvent) -> void: panel_drag_input(g, e, p))
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", DT.FS_TITLE)
	tl.add_theme_font_override("font", g._serif)
	tl.add_theme_color_override("font_color", DT.TEXT_TITLE)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)
	var cb := Button.new()
	cb.text = "×"
	cb.flat = true
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size = Vector2(30, 30)
	cb.add_theme_font_size_override("font_size", 18)
	cb.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	cb.pressed.connect(func() -> void: Audio.play_ui("ui_click"))
	cb.pressed.connect(g._close_panel)
	hb.add_child(cb)
	v.add_child(hb)
	return p


## 面板滑入动画：从舞台下方滑到顶部（CD .sheet 展开动画）。
static func _animate_sheet_in(g: CornerFishing, sheet: Control) -> void:
	var stage_h := float(g.WIN.y) - g.FRAMED_CONSOLE_H
	sheet.position = Vector2(0, stage_h)
	var tw := g.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(sheet, "position:y", 0.0, 0.30)


## 带框 sheet 标题（区名）：_catch_tab → 区名
static func _section_name(tab: int) -> String:
	match tab:
		0: return "鱼篓"
		1: return "图鉴"
		2: return "任务"
		5: return "钓点"
		6: return "鱼缸"
		7: return "装备"
		8: return "设置"
		9: return "人情"
		_: return "垂钓手册"


static func make_card(g: CornerFishing, title: String) -> Control:
	if g.display_mode != "immersive":
		return _make_framed_modal(g, title)
	var p := PanelContainer.new()
	p.z_index = 50
	p.position = ((Vector2(g.WIN) - CARD_SIZE) * 0.5).round()
	p.custom_minimum_size = CARD_SIZE
	p.add_theme_stylebox_override("panel", panel_bg_style())
	var m := MarginContainer.new()
	m.name = "M"
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_bottom", 16)
	p.add_child(m)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_STOP
	hb.custom_minimum_size = Vector2(0, 26)
	hb.add_theme_constant_override("separation", 8)
	hb.gui_input.connect(func(e: InputEvent) -> void: panel_drag_input(g, e, p))
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 20)
	tl.add_theme_font_override("font", g._serif)  # 面板标题用衬线（设计令牌 --font-display）
	tl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)
	var cb := Button.new()
	cb.text = "×"
	cb.flat = true
	cb.focus_mode = Control.FOCUS_NONE
	cb.tooltip_text = "关闭"
	cb.custom_minimum_size = Vector2(28, 26)
	cb.add_theme_font_size_override("font_size", 18)
	cb.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66))
	cb.pressed.connect(func() -> void: Audio.play_ui("ui_click"))
	cb.pressed.connect(g._close_panel)
	hb.add_child(cb)
	v.add_child(hb)
	return p


static func _make_framed_modal(g: CornerFishing, title: String) -> Control:
	var modal_size := Vector2(680, 640)
	var stage_size := g._stage_size()
	var p := PanelContainer.new()
	p.z_index = 50
	p.position = ((stage_size - modal_size) * 0.5).round()
	p.custom_minimum_size = modal_size
	p.size = modal_size
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", panel_bg_style())
	var m := MarginContainer.new()
	m.name = "M"
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_bottom", 16)
	p.add_child(m)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(0, 30)
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_STOP
	hb.mouse_default_cursor_shape = Control.CURSOR_MOVE
	hb.gui_input.connect(func(e: InputEvent) -> void: panel_drag_input(g, e, p))
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", DT.FS_TITLE)
	tl.add_theme_font_override("font", g._serif)
	tl.add_theme_color_override("font_color", DT.TEXT_TITLE)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)
	var cb := Button.new()
	cb.text = "×"
	cb.flat = true
	cb.focus_mode = Control.FOCUS_NONE
	cb.tooltip_text = "关闭"
	cb.custom_minimum_size = Vector2(30, 30)
	cb.add_theme_font_size_override("font_size", 18)
	cb.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	cb.pressed.connect(func() -> void: Audio.play_ui("ui_click"))
	cb.pressed.connect(g._close_panel)
	hb.add_child(cb)
	v.add_child(hb)
	return p


static func clamp_panel_position(g: CornerFishing, pos: Vector2, size: Vector2) -> Vector2:
	var max_pos := g._stage_size() - size
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, max_pos.x)),
		clampf(pos.y, 0.0, maxf(0.0, max_pos.y)))


static func panel_drag_input(g: CornerFishing, event: InputEvent, panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			g._panel_dragging = true
			g._panel_drag_offset = panel.get_global_mouse_position() - panel.position
		else:
			g._panel_dragging = false
			g._panel_saved_pos = panel.position
	elif event is InputEventMouseMotion and g._panel_dragging:
		panel.position = clamp_panel_position(g, panel.get_global_mouse_position() - g._panel_drag_offset,
			panel.custom_minimum_size)


# ============================ 鱼篓主面板 + 页签 ============================

static func fill_bag_panel(g: CornerFishing, v: VBoxContainer) -> void:
	# 顶部页签仅沉浸模式保留；带框模式由底部导航唯一切区（CD：sheet 无顶部页签，标题=区名）。
	if g.display_mode == "immersive":
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", DT.CHIP_GAP)
		var defs := g._feature_nav_defs()
		for d in defs:
			var id: int = int(d["tab"])
			var tb := Button.new()
			tb.text = str(d["label"])
			tb.add_theme_font_size_override("font_size", DT.FS_XS)
			apply_tab_skin(tb, id == g._catch_tab)
			if id != g._catch_tab:
				tb.pressed.connect(g._set_catch_tab.bind(id))
			tabs.add_child(tb)
		v.add_child(tabs)
	match g._catch_tab:
		0: fill_bag_tab(g, v)
		1: fill_dex_tab(g, v)
		2: fill_tasks_tab(g, v)
		3: fill_ach_tab(g, v)
		4: fill_stats_tab(g, v)
		5: fill_spot_tab(g, v)
		6: fill_decor_tab(g, v)
		7: fill_upgrades(g, v)   # 装备：鱼竿/鱼饵/鱼钩升级（原主界面「竿」面板）
		9: fill_relationship_tab(g, v)
		_: fill_settings(g, v)   # 8 设置：音量/专注/不透明度/退出（原主界面「设」面板）


## 河湾人情簿第一阶段：展示五条独立关系和终章方向；到访、送礼、Buff 在后续阶段接入。
static func fill_relationship_tab(g: CornerFishing, v: VBoxContainer) -> void:
	var intro := Label.new()
	intro.text = "河湾的人情不是货币。熟人会在你挂机时留下消息；到访时才能交谈、送礼或接下委托。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 12)
	intro.add_theme_color_override("font_color", DT.INK_SOFT)
	v.add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var npc_state: Dictionary = g.relationship_state.get("npc", {})
	for npc in RelationshipDataScript.NPCS:
		var id := str(npc["id"])
		var state: Dictionary = npc_state.get(id, {})
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", paper_style())
		list.add_child(card)
		var mg := MarginContainer.new()
		mg.add_theme_constant_override("margin_left", 12)
		mg.add_theme_constant_override("margin_right", 12)
		mg.add_theme_constant_override("margin_top", 9)
		mg.add_theme_constant_override("margin_bottom", 9)
		card.add_child(mg)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		mg.add_child(row)
		var avatar := ColorRect.new()
		avatar.color = npc["color"]
		avatar.custom_minimum_size = Vector2(30, 30)
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(avatar)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 2)
		row.add_child(text)
		var title := Label.new()
		title.text = "%s · %s" % [str(npc["name"]), str(npc["role"])]
		title.add_theme_font_override("font", font_bold)
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", DT.INK)
		text.add_child(title)
		var favor := Label.new()
		favor.text = "好感：%s　偏好：%s　近况：%d/6" % [
			RelationshipDataScript.favor_name(int(state.get("favor", 0))), str(npc["likes"]),
			clampi(int(state.get("story_seen", -1)) + 1, 0, RelationshipDataScript.STORY_LEVEL_MAX + 1),
		]
		favor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		favor.add_theme_font_size_override("font_size", 11)
		favor.add_theme_color_override("font_color", DT.INK_SOFT)
		text.add_child(favor)
		var note := Label.new()
		if bool(state.get("finale_done", false)):
			note.text = "永久解锁：%s\n%s" % [
				RelationshipDataScript.finale_reward_name(id),
				RelationshipDataScript.finale_reward_description(id),
			]
		else:
			note.text = "终章：%s\n奖励：%s" % [
				str(npc["finale"]), RelationshipDataScript.finale_reward_name(id)]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", DT.BRONZE)
		text.add_child(note)


static func fill_relationship_visit(g: CornerFishing, v: VBoxContainer) -> void:
	g._ensure_relationship_state()
	var visits: Dictionary = g.relationship_state.get("visits", {})
	var npc_id := str(g.selected_relationship_visit_id)
	var npc := RelationshipDataScript.get_npc(npc_id)
	var visit: Dictionary = visits.get(npc_id, {})
	if npc.is_empty() or visit.is_empty():
		var empty := Label.new()
		empty.text = "这条到访消息已经不在了。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", DT.INK_SOFT)
		v.add_child(empty)
		return

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", paper_style())
	v.add_child(head)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 14)
	mg.add_theme_constant_override("margin_right", 14)
	mg.add_theme_constant_override("margin_top", 12)
	mg.add_theme_constant_override("margin_bottom", 12)
	head.add_child(mg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	mg.add_child(row)
	var avatar := ColorRect.new()
	avatar.color = npc["color"]
	avatar.custom_minimum_size = Vector2(38, 38)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(avatar)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	row.add_child(text)
	var title := Label.new()
	title.text = RelationshipDataScript.visit_title(npc, visit)
	title.add_theme_font_override("font", font_bold)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", DT.INK)
	text.add_child(title)
	var meta := Label.new()
	var favor := int(g.relationship_state.get("npc", {}).get(npc_id, {}).get("favor", 0))
	meta.text = "%s · 好感 %s · 偏好：%s" % [
		RelationshipDataScript.visit_kind_label(str(visit.get("kind", "hint"))),
		RelationshipDataScript.favor_name(favor),
		str(npc["likes"]),
	]
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", DT.INK_SOFT)
	text.add_child(meta)

	var body := Label.new()
	body.text = RelationshipDataScript.visit_body(npc, visit)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", DT.INK_SOFT)
	v.add_child(body)

	var finale := Label.new()
	finale.text = "终章方向：%s" % str(npc["finale"])
	finale.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	finale.add_theme_font_size_override("font_size", 12)
	finale.add_theme_color_override("font_color", DT.BRONZE)
	v.add_child(finale)

	if str(visit.get("kind", "hint")) == "buff":
		fill_relationship_buff_accept(g, v, npc_id)
		return
	if str(visit.get("kind", "hint")) == "task":
		fill_relationship_task_delivery(g, v, npc_id)
		return
	if str(visit.get("kind", "hint")) == "finale":
		fill_relationship_finale_delivery(g, v, npc_id)
		return
	if str(visit.get("kind", "hint")) == "story":
		fill_relationship_story_ack(g, v)
		return

	var gift_title := Label.new()
	gift_title.text = "选择鱼篓中的一条鱼送礼。灰色也可以点，但不合口味会被拒绝，并错过这次送礼机会。"
	gift_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gift_title.add_theme_font_size_override("font_size", 12)
	gift_title.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(gift_title)
	if g.inventory.is_empty():
		v.add_child(_empty_note("鱼篓是空的。\n这次只能先聊聊。"))
	else:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 248)
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(sc)
		var grid := GridContainer.new()
		grid.columns = 8 if g.display_mode != "immersive" else 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", DT.SP_3)
		grid.add_theme_constant_override("v_separation", DT.SP_3)
		sc.add_child(grid)
		for i in g._sorted_bag_indices(false):
			grid.add_child(gift_fish_cell(g, npc_id, g.inventory[i], i))
	var close := Button.new()
	close.text = "稍后"
	close.focus_mode = Control.FOCUS_NONE
	apply_button_skin(close, false)
	close.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._close_panel())
	v.add_child(close)


static func fill_relationship_story_ack(g: CornerFishing, v: VBoxContainer) -> void:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	var accept := Button.new()
	accept.text = "记下了"
	accept.focus_mode = Control.FOCUS_NONE
	apply_button_skin(accept, true)
	accept.pressed.connect(func() -> void: g._complete_relationship_story())
	actions.add_child(accept)
	var later := Button.new()
	later.text = "稍后"
	later.focus_mode = Control.FOCUS_NONE
	apply_button_skin(later, false)
	later.pressed.connect(func() -> void: g._close_panel())
	actions.add_child(later)


static func fill_relationship_buff_accept(g: CornerFishing, v: VBoxContainer, npc_id: String) -> void:
	var lines := RelationshipDataScript.buff_dialogue(npc_id)
	var chat := PanelContainer.new()
	chat.add_theme_stylebox_override("panel", dark_row_style(0.42))
	v.add_child(chat)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 12)
	mg.add_theme_constant_override("margin_right", 12)
	mg.add_theme_constant_override("margin_top", 10)
	mg.add_theme_constant_override("margin_bottom", 10)
	chat.add_child(mg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	mg.add_child(box)
	for line in lines:
		var l := Label.new()
		l.text = str(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
		box.add_child(l)
	var effect := Label.new()
	effect.text = "接受后获得 10 分钟「%s」。同一时间只保留一份人情帮忙，新的会覆盖旧的。" % RelationshipDataScript.buff_name(npc_id)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_font_size_override("font_size", 12)
	effect.add_theme_color_override("font_color", DT.BRONZE)
	v.add_child(effect)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	var accept := Button.new()
	accept.text = "接受帮忙"
	accept.focus_mode = Control.FOCUS_NONE
	apply_button_skin(accept, true)
	accept.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._accept_relationship_buff())
	actions.add_child(accept)
	var later := Button.new()
	later.text = "稍后"
	later.focus_mode = Control.FOCUS_NONE
	apply_button_skin(later, false)
	later.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._close_panel())
	actions.add_child(later)


static func fill_relationship_task_delivery(g: CornerFishing, v: VBoxContainer, npc_id: String) -> void:
	var title := Label.new()
	title.text = "%s。选择一条合格的鱼交付；灰色鱼点了会被拒绝，但委托会继续保留。" % RelationshipDataScript.task_title(npc_id)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(title)
	if g.inventory.is_empty():
		v.add_child(_empty_note("鱼篓是空的。\n先去钓到合适的鱼再回来。"))
	else:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 248)
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(sc)
		var grid := GridContainer.new()
		grid.columns = 8 if g.display_mode != "immersive" else 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", DT.SP_3)
		grid.add_theme_constant_override("v_separation", DT.SP_3)
		sc.add_child(grid)
		for i in g._sorted_bag_indices(false):
			var ok := RelationshipDataScript.task_match(npc_id, g.inventory[i])
			var tip := "符合委托，点击交付" if ok else "不符合委托，点击会被拒绝但委托保留"
			grid.add_child(relationship_fish_cell(g, g.inventory[i], i, ok, "交付" if ok else "会拒收", tip,
				func(real_idx: int) -> void: g._complete_relationship_task(real_idx)))
	var close := Button.new()
	close.text = "稍后"
	close.focus_mode = Control.FOCUS_NONE
	apply_button_skin(close, false)
	close.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._close_panel())
	v.add_child(close)


static func fill_relationship_finale_delivery(g: CornerFishing, v: VBoxContainer, npc_id: String) -> void:
	var title := Label.new()
	var consumes := RelationshipDataScript.finale_consumes_catch(npc_id)
	title.text = "%s需要河湾之外的渔获。合格鱼会高亮；%s" % [
		"终章收购" if consumes else "终章纪录",
		"确认后会消耗这条鱼。" if consumes else "确认后只登记纪录，不会消耗这条鱼；锁定鱼也可登记。",
	]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", DT.BRONZE)
	v.add_child(title)
	var reward := Label.new()
	reward.text = "完成后永久解锁「%s」：%s" % [
		RelationshipDataScript.finale_reward_name(npc_id),
		RelationshipDataScript.finale_reward_description(npc_id),
	]
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward.add_theme_font_size_override("font_size", 12)
	reward.add_theme_color_override("font_color", DT.INK_SOFT)
	v.add_child(reward)
	if g.inventory.is_empty():
		v.add_child(_empty_note("鱼篓是空的。\n去其他地点带回合适的鱼。"))
	else:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 248)
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(sc)
		var grid := GridContainer.new()
		grid.columns = 8 if g.display_mode != "immersive" else 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", DT.SP_3)
		grid.add_theme_constant_override("v_separation", DT.SP_3)
		sc.add_child(grid)
		for i in g._sorted_bag_indices(false):
			var ok := RelationshipDataScript.finale_match(npc_id, g.inventory[i])
			var action := "交付" if consumes else "登记"
			var tip := "符合终章，点击%s" % action if ok else "不符合终章，点击会被拒绝但终章保留"
			grid.add_child(relationship_fish_cell(g, g.inventory[i], i, ok, action if ok else "会拒收", tip,
				func(real_idx: int) -> void: g._complete_relationship_finale(real_idx)))
	var close := Button.new()
	close.text = "稍后"
	close.focus_mode = Control.FOCUS_NONE
	apply_button_skin(close, false)
	close.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._close_panel())
	v.add_child(close)


static func gift_fish_cell(g: CornerFishing, npc_id: String, c: Dictionary, idx: int) -> Control:
	var accepted := RelationshipDataScript.gift_match(npc_id, c)
	var tip := "合口味，点击送出" if accepted else "不合口味，点击会被拒绝并错失本次机会"
	return relationship_fish_cell(g, c, idx, accepted, "送出" if accepted else "会拒收", tip,
		func(real_idx: int) -> void: g._relationship_gift(real_idx))


static func relationship_fish_cell(g: CornerFishing, c: Dictionary, idx: int, accepted: bool,
		action_label: String, tip: String, on_click: Callable) -> Control:
	var id := str(c["id"])
	var tier := FishData.tier_of(id)
	var vr := int(c.get("var", 0))
	var edge := FishData.variant_color(vr) if vr >= 1 else g._ui_tier_color(tier, false)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(0, 106)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := dark_row_style(0.48 if accepted else 0.22)
	sb.set_border_width_all(2)
	sb.border_color = Color(edge.r, edge.g, edge.b, 0.85 if accepted else 0.24)
	cell.add_theme_stylebox_override("panel", sb)
	cell.modulate = Color(1, 1, 1, 1) if accepted else Color(0.52, 0.52, 0.52, 0.82)
	cell.tooltip_text = "%s · %.2fkg · %s" % [
		FishData.display_name(id), float(c["w"]), tip,
	]
	cell.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(idx))
	var mg := MarginContainer.new()
	mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mg.add_theme_constant_override("margin_left", 6)
	mg.add_theme_constant_override("margin_right", 6)
	mg.add_theme_constant_override("margin_top", 6)
	mg.add_theme_constant_override("margin_bottom", 6)
	cell.add_child(mg)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	mg.add_child(box)
	var icon := g._fish_icon(id, 46)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var nm := Label.new()
	nm.text = ("◆" + FishData.display_name(id)) if vr >= 1 else FishData.display_name(id)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_font_override("font", g._font_bold)
	nm.add_theme_font_size_override("font_size", DT.FS_2XS + 1)
	nm.add_theme_color_override("font_color", edge if accepted else DT.TEXT_FAINT_GLASS)
	box.add_child(nm)
	var meta := Label.new()
	var parts: Array[String] = []
	var q := int(c.get("q", 0))
	if q > 0:
		parts.append("★".repeat(q))
	var sztag := FishData.size_tag(id, c["w"]).replace("·", "").strip_edges()
	if sztag != "":
		parts.append(sztag)
	parts.append("%.2fkg" % float(c["w"]))
	meta.text = " ".join(parts)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.clip_text = true
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_font_size_override("font_size", DT.FS_MICRO)
	meta.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS if accepted else DT.TEXT_FAINT_GLASS)
	box.add_child(meta)
	var state := Label.new()
	state.text = action_label
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state.add_theme_font_override("font", g._font_bold)
	state.add_theme_font_size_override("font_size", DT.FS_XS)
	state.add_theme_color_override("font_color", DT.GOLD_BRIGHT if accepted else DT.TEXT_FAINT_GLASS)
	box.add_child(state)
	return cell


## 开发期属性页：独立于玩家面板，展示属性层如何影响最终钓鱼结果。
static func fill_debug_attributes(g: CornerFishing, v: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", 3)
	v.add_child(box)

	var head := PanelContainer.new()
	head.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_theme_stylebox_override("panel", dark_row_style(0.58))
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 6)
	hm.add_theme_constant_override("margin_right", 6)
	hm.add_theme_constant_override("margin_top", 3)
	hm.add_theme_constant_override("margin_bottom", 3)
	head.add_child(hm)
	var hb := VBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	hm.add_child(hb)
	var title := Label.new()
	title.text = "测试属性面板"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", DT.GOLD_BRIGHT)
	hb.add_child(title)
	var note := Label.new()
	note.text = "实时数值：当前装备 / 钓点 / 时段 / 事件；角色属性已映射到钓鱼结果。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 8)
	note.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	hb.add_child(note)
	box.add_child(head)

	var base_no_reel := g._avg_wait_for_reel(0)
	var cur_interval := g._avg_wait_for_reel(g.reel_level)
	var speed_gain := 1.0 - cur_interval / maxf(0.01, base_no_reel)
	var weights := g._effective_tier_weights(g._catch_luck())
	var total := 0.0
	for t in weights:
		total += float(weights[t])
	var pool_counts := _tier_counts(g._spot_pool())

	var bait: Dictionary = FishData.BAITS[g.bait_level]
	var qprobs := FishData.quality_probs(g.bait_level, g._quality_attr_bonus())
	var qp := _quality_distribution(qprobs)
	var qcols := [DT.TEXT_FAINT_GLASS, Color(0.72, 0.92, 0.58), Color(0.95, 0.82, 0.42), Color(0.96, 0.62, 0.92)]

	var lure: Dictionary = FishData.LURES[g.lure_level]
	var vb := g._variant_bias()
	var vp := _variant_distribution(vb)
	var hook: Dictionary = FishData.HOOKS[g.hook_level]
	var double_p := g._double_chance()
	var stats = g._angler_stats()

	var consumables := _debug_group(box, "消耗品（可编辑）", Color(0.88, 0.76, 0.50))
	var coins_row := HBoxContainer.new()
	coins_row.add_theme_constant_override("separation", 5)
	consumables.add_child(coins_row)
	_debug_compact_label(coins_row, "金币", DT.TEXT_ON_GLASS, 42)
	_debug_compact_label(coins_row, _compact_cost(g.coins), DT.GOLD, 70)
	var double_btn := _debug_tiny_button("×2")
	double_btn.pressed.connect(func() -> void:
		g.coins = g._safe_econ_number(maxf(1.0, float(g.coins) * 2.0))
		_debug_source_changed(g))
	coins_row.add_child(double_btn)
	var half_btn := _debug_tiny_button("÷2")
	half_btn.pressed.connect(func() -> void:
		g.coins = maxf(0.0, floor(float(g.coins) * 0.5))
		_debug_source_changed(g))
	coins_row.add_child(half_btn)

	var source := _debug_group(box, "来源层（可编辑）", Color(0.88, 0.76, 0.50))
	var source_list := VBoxContainer.new()
	source_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_list.add_theme_constant_override("separation", 2)
	source.add_child(source_list)
	_debug_level_editor(source_list, "鱼竿", "Lv.%d" % g.rod_level, DT.GOLD, func(delta: int) -> void:
		g.rod_level = maxi(1, g.rod_level + delta)
		g._begin_wait()
		_debug_source_changed(g))
	_debug_level_editor(source_list, "绕线轮", "Lv.%d" % g.reel_level, Color(0.58, 0.80, 0.98), func(delta: int) -> void:
		g.reel_level = maxi(0, g.reel_level + delta)
		g._begin_wait()
		_debug_source_changed(g))
	_debug_level_editor(source_list, "鱼线", "Lv.%d" % g.fish_line_level, Color(0.72, 0.92, 0.58), func(delta: int) -> void:
		g.fish_line_level = maxi(0, g.fish_line_level + delta)
		_debug_source_changed(g))
	_debug_level_editor(source_list, "浮漂", "Lv.%d" % g.bobber_level, Color(0.42, 0.78, 0.86), func(delta: int) -> void:
		g.bobber_level = maxi(0, g.bobber_level + delta)
		_debug_source_changed(g))
	_debug_select_editor(source_list, "鱼饵", g.bait_level, FishData.BAITS, Color(0.72, 0.92, 0.58), func(idx: int) -> void:
		g.bait_level = idx
		_debug_source_changed(g))
	_debug_select_editor(source_list, "鱼钩", g.hook_level, FishData.HOOKS, Color(0.62, 0.86, 0.74), func(idx: int) -> void:
		g.hook_level = idx
		_debug_source_changed(g))
	_debug_select_editor(source_list, "窝料", g.lure_level, FishData.LURES, Color(0.78, 0.62, 0.95), func(idx: int) -> void:
		g.lure_level = idx
		_debug_source_changed(g))
	_debug_level_editor(source_list, "探鱼器", "Lv.%d" % g.sonar_level, Color(0.78, 0.62, 0.95), func(delta: int) -> void:
		g.sonar_level = maxi(0, g.sonar_level + delta)
		_debug_source_changed(g))
	_debug_level_editor(source_list, "笔记", "Lv.%d" % g.notebook_level, Color(0.78, 0.62, 0.95), func(delta: int) -> void:
		g.notebook_level = maxi(0, g.notebook_level + delta)
		_debug_source_changed(g))
	_debug_level_editor(source_list, "手套", "Lv.%d" % g.gloves_level, Color(0.88, 0.72, 0.48), func(delta: int) -> void:
		g.gloves_level = maxi(0, g.gloves_level + delta)
		_debug_source_changed(g))
	_debug_pet_editor(source_list, "宠物", str(g._dev_pet_state), func(state: String) -> void:
		g._dev_pet_state = state
		if g.painter and state != "无" and g.painter.has_method("pet_react"):
			g.painter.pet_react("paw" if state == "互动" else "steal")
		_debug_source_changed(g))

	_debug_flow(box, "来源层 -> 角色属性 -> 钓鱼属性")
	var lower_stack := VBoxContainer.new()
	lower_stack.add_theme_constant_override("separation", 3)
	box.add_child(lower_stack)
	var role := _debug_group(lower_stack, "角色属性", Color(0.58, 0.80, 0.98))
	var role_grid := _debug_kv_grid(role, 3)
	_debug_kv(role_grid, "速度", "%.1f" % stats.speed, Color(0.58, 0.80, 0.98), "绕线轮 Lv.%d" % g.reel_level)
	_debug_kv(role_grid, "幸运", "%+d" % g._catch_luck(), DT.GOLD, "当前事件/时段等临时 luck")
	_debug_kv(role_grid, "技巧", "%.1f" % stats.technique, Color(0.72, 0.92, 0.58), "鱼线/手套")
	_debug_kv(role_grid, "体力", "0", Color(0.62, 0.86, 0.74), "预留：影响长线效率")
	_debug_kv(role_grid, "力量", "%.1f" % stats.strength, Color(0.88, 0.72, 0.48), "钓鱼手套")
	_debug_kv(role_grid, "生态", "%.1f" % stats.ecology, Color(0.78, 0.62, 0.95), "探鱼器/钓鱼笔记")
	_debug_kv(role_grid, "稳定", "%.1f" % stats.stability, Color(0.72, 0.92, 0.58), "鱼线")
	_debug_kv(role_grid, "反应", "%.1f" % stats.reaction, Color(0.42, 0.78, 0.86), "浮漂")
	_debug_kv(role_grid, "感知", "%.1f" % stats.perception, Color(0.78, 0.62, 0.95), "浮漂/探鱼器")
	_debug_kv(role_grid, "追踪", "%.1f" % stats.tracking, Color(0.78, 0.62, 0.95), "钓鱼笔记")

	var fish_core := _debug_group(lower_stack, "钓鱼属性 · 节奏/品阶", DT.GOLD)
	var rhythm_grid := _debug_kv_grid(fish_core, 3)
	_debug_kv(rhythm_grid, "一竿", "%.2fs" % cur_interval, Color(0.42, 0.78, 0.86), "无绕线轮 %.2fs" % base_no_reel)
	_debug_kv(rhythm_grid, "倍率", "%.0f%%" % (g._speed_wait_mult() * g._reaction_wait_mult() * 100.0), Color(0.58, 0.80, 0.98), "速度+反应换算")
	_debug_kv(rhythm_grid, "缩短", "%.1f%%" % (speed_gain * 100.0), Color(0.42, 0.78, 0.86), "相对无绕线轮")
	_debug_kv(rhythm_grid, "双钩", "%.1f%%" % (double_p * 100.0), Color(0.62, 0.86, 0.74), "%s + 反应/技巧" % hook["name"])
	_debug_kv(rhythm_grid, "期望", "%.2f条" % (1.0 + double_p), Color(0.62, 0.86, 0.74), "单竿期望收获")
	_debug_kv(rhythm_grid, "鱼饵", str(bait["name"]), Color(0.72, 0.92, 0.58), "星级来源")
	_debug_kv(rhythm_grid, "体型", "k^%.2f" % g._weight_power(), Color(0.88, 0.72, 0.48), "力量/稳定降低指数，大鱼尾部略增")

	_debug_subtitle(fish_core, "品阶")
	var tier_grid := _debug_kv_grid(fish_core, 3)
	for tier in range(6):
		var p := float(weights.get(tier, 0.0)) / maxf(0.01, total)
		_debug_kv(tier_grid, "%sT%d" % [FishData.TIER_NAMES[tier], tier], "%.2f%%" % (p * 100.0),
			DT.tier_color(tier), "当前钓点池内 %d 种" % int(pool_counts.get(tier, 0)))

	var fish_loot := _debug_group(lower_stack, "钓鱼属性 · 星级/刷宝", DT.GOLD)
	var loot_grid := _debug_kv_grid(fish_loot, 3)
	for q in range(qp.size()):
		var qlabel: String = "普通" if q == 0 else "★".repeat(q)
		_debug_kv(loot_grid, qlabel, "%.2f%%" % (float(qp[q]) * 100.0), qcols[q],
			"%s + 技巧/稳定 · 卖价 x%.1f" % [bait["name"], float(FishData.QUALITY_MULTS[q])])
	for vi in range(vp.size()):
		var vlabel: String = "普鱼" if vi == 0 else FishData.VARIANT_NAMES[vi]
		_debug_kv(loot_grid, vlabel, "%.3f%%" % (float(vp[vi]) * 100.0), DT.VARIANT[vi],
			"%s + 感知/生态 · 卖价 x%.1f · vbias %.2f" % [lure["name"], float(FishData.VARIANT_MULTS[vi]), vb])


static func fill_relationship_debug_panel(g: CornerFishing, v: VBoxContainer) -> void:
	g._ensure_relationship_state()
	var title := Label.new()
	title.text = "人情模块"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", DT.GOLD_BRIGHT)
	v.add_child(title)
	var note := Label.new()
	var buff: Dictionary = g.relationship_state.get("buff", {})
	note.text = "到访 %d/5 · Buff %s · 测试改动仅本会话生效" % [
		(g.relationship_state.get("visits", {}) as Dictionary).size(),
		RelationshipDataScript.buff_name(str(buff.get("npc", ""))) if not buff.is_empty() else "无",
	]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(note)
	var top := _test_row(v)
	_test_seg(top, "开放人情", false, func() -> void: TestMode.set_relationships_unlocked(g, true))
	_test_seg(top, "打开人情簿", false, func() -> void: TestMode.open_relationship_book(g))
	_test_seg(top, "清空到访", false, func() -> void: TestMode.clear_relationship_visits(g))
	_test_seg(top, "清除Buff", false, func() -> void: TestMode.clear_relationship_buff(g))
	for npc in RelationshipDataScript.NPCS:
		var id := str(npc["id"])
		var captured_id := id
		var state: Dictionary = (g.relationship_state.get("npc", {}) as Dictionary).get(id, {})
		_test_head(v, "%s · %s · %s" % [
			str(npc["name"]),
			RelationshipDataScript.favor_name(int(state.get("favor", 0))),
			("终章已完成" if bool(state.get("finale_done", false)) else "终章未完成") \
				+ " · 近况%d/6" % clampi(int(state.get("story_seen", -1)) + 1, 0, 6),
		])
		var row1 := _test_row(v)
		_test_seg(row1, "近况", false, func() -> void: TestMode.summon_relationship_visit(g, captured_id, "story"))
		_test_seg(row1, "闲谈", false, func() -> void: TestMode.summon_relationship_visit(g, captured_id, "hint"))
		_test_seg(row1, "委托", false, func() -> void: TestMode.summon_relationship_visit(g, captured_id, "task"))
		_test_seg(row1, "Buff", false, func() -> void: TestMode.summon_relationship_visit(g, captured_id, "buff"))
		_test_seg(row1, "终章", false, func() -> void: TestMode.summon_relationship_visit(g, captured_id, "finale"))
		var row2 := _test_row(v)
		_test_seg(row2, "打开面板", false, func() -> void: TestMode.open_relationship_visit(g, captured_id))
		_test_seg(row2, "给偏好鱼", false, func() -> void: TestMode.give_relationship_gift_fish(g, captured_id))
		_test_seg(row2, "给终章鱼", false, func() -> void: TestMode.give_relationship_finale_fish(g, captured_id))
		var row3 := _test_row(v)
		_test_seg(row3, "好感-1", false, func() -> void: TestMode.adjust_relationship_favor(g, captured_id, -1))
		_test_seg(row3, "好感+1", false, func() -> void: TestMode.adjust_relationship_favor(g, captured_id, 1))
		_test_seg(row3, "设至交", false, func() -> void: TestMode.set_relationship_favor(g, captured_id, RelationshipDataScript.FAVOR_LEVELS.size() - 1))
		_test_seg(row3, "重置终章", false, func() -> void: TestMode.set_relationship_finale_done(g, captured_id, false))
		_test_seg(row3, "完成终章", false, func() -> void: TestMode.set_relationship_finale_done(g, captured_id, true))
		var row4 := _test_row(v)
		_test_seg(row4, "重置近况", false, func() -> void: TestMode.set_relationship_story_seen(g, captured_id, -1))
		_test_seg(row4, "读完近况", false, func() -> void: TestMode.set_relationship_story_seen(g, captured_id, RelationshipDataScript.STORY_LEVEL_MAX))


static func _debug_group(box: BoxContainer, title: String, col: Color) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pc.add_theme_stylebox_override("panel", dark_row_style(0.38))
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 6)
	mg.add_theme_constant_override("margin_right", 6)
	mg.add_theme_constant_override("margin_top", 3)
	mg.add_theme_constant_override("margin_bottom", 3)
	pc.add_child(mg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	mg.add_child(vb)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", col)
	vb.add_child(l)
	box.add_child(pc)
	return vb


static func _debug_level_editor(box: VBoxContainer, label: String, value: String, col: Color, on_delta: Callable) -> void:
	var row := _debug_edit_row(box, label, value, col)
	for d in [-10, -1, 1, 10]:
		var delta := int(d)
		var b := _debug_tiny_button("%+d" % delta)
		b.pressed.connect(func() -> void: on_delta.call(delta))
		row.add_child(b)


static func _debug_select_editor(box: VBoxContainer, label: String, current: int, items: Array, col: Color, on_select: Callable) -> void:
	var row := _debug_edit_row(box, label, "", col)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(104, 18)
	ob.add_theme_font_size_override("font_size", 9)
	for i in items.size():
		var it: Dictionary = items[i]
		ob.add_item(str(it.get("name", "选项%d" % i)), i)
	ob.select(clampi(current, 0, maxi(0, items.size() - 1)))
	ob.item_selected.connect(func(idx: int) -> void: on_select.call(idx))
	row.add_child(ob)


static func _debug_pet_editor(box: VBoxContainer, label: String, current: String, on_select: Callable) -> void:
	var row := _debug_edit_row(box, label, "", DT.TEXT_MUTED_GLASS)
	var states := ["无", "待机", "互动", "叼鱼"]
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(104, 18)
	ob.add_theme_font_size_override("font_size", 9)
	for i in states.size():
		ob.add_item(states[i], i)
		if states[i] == current:
			ob.select(i)
	ob.item_selected.connect(func(idx: int) -> void: on_select.call(states[idx]))
	row.add_child(ob)


static func _debug_edit_row(box: VBoxContainer, label: String, value: String, col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	box.add_child(row)
	var nm := Label.new()
	nm.text = label
	nm.custom_minimum_size = Vector2(42, 18)
	nm.add_theme_font_size_override("font_size", 9)
	nm.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	row.add_child(nm)
	if value != "":
		var val := Label.new()
		val.text = value
		val.custom_minimum_size = Vector2(42, 18)
		val.add_theme_font_size_override("font_size", 9)
		val.add_theme_color_override("font_color", col)
		row.add_child(val)
	return row


static func _debug_compact_label(row: HBoxContainer, text: String, col: Color, width := 48) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", col)
	row.add_child(l)


static func _debug_tiny_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 18)
	b.add_theme_font_size_override("font_size", 9)
	return b


static func _debug_source_changed(g: CornerFishing) -> void:
	g._check_achievements()
	g._update_hud()
	g.call_deferred("_refresh_panel")


static func _debug_flow(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	box.add_child(l)


static func _debug_subtitle(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	box.add_child(l)


static func _debug_kv_grid(box: VBoxContainer, pairs_per_row := 3) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = pairs_per_row * 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 1)
	box.add_child(grid)
	return grid


static func _debug_kv(grid: GridContainer, label: String, value: String, col: Color, detail := "") -> void:
	var nm := Label.new()
	nm.text = label
	nm.tooltip_text = detail
	nm.custom_minimum_size = Vector2(46, 0)
	nm.add_theme_font_size_override("font_size", 9)
	nm.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	grid.add_child(nm)
	var val := Label.new()
	val.text = value
	val.tooltip_text = detail
	val.custom_minimum_size = Vector2(46, 0)
	val.add_theme_font_size_override("font_size", 9)
	val.add_theme_color_override("font_color", col)
	grid.add_child(val)


static func _tier_counts(pool: Array) -> Dictionary:
	var out := {}
	for tier in range(6):
		out[tier] = 0
	for id in pool:
		var t := FishData.tier_of(str(id))
		out[t] = int(out.get(t, 0)) + 1
	return out


static func _quality_distribution(probs: Array) -> Array:
	var p1 := float(probs[1])
	var p2 := float(probs[2])
	var p3 := float(probs[3])
	return [
		1.0 - p1,
		p1 * (1.0 - p2),
		p1 * p2 * (1.0 - p3),
		p1 * p2 * p3,
	]


static func _variant_distribution(vbias: float) -> Array:
	var p3 := float(FishData.VARIANT_PROBS[3]) * FishData.variant_scale(3, vbias)
	var p2 := float(FishData.VARIANT_PROBS[2]) * FishData.variant_scale(2, vbias)
	var p1 := float(FishData.VARIANT_PROBS[1]) * FishData.variant_scale(1, vbias)
	return [maxf(0.0, 1.0 - p1 - p2 - p3), p1, p2, p3]


## 统计页：长期成长看板（只读）。
static func fill_stats_tab(g: CornerFishing, v: VBoxContainer) -> void:
	var big_id := ""
	var big_w := 0.0
	for id in g.dex:
		if float(g.dex[id]["w"]) > big_w:
			big_w = float(g.dex[id]["w"])
			big_id = str(id)
	var biggest := "—"
	if big_id != "":
		biggest = "%s %.2fkg" % [FishData.display_name(big_id), big_w]
	# 🏆 英雄数字（设计令牌 --fs-numeral）：史上最大体重，衬线 + 等宽大号，仪式感。
	if big_id != "":
		var hero := PanelContainer.new()
		hero.add_theme_stylebox_override("panel", paper_style(0.95))
		var hm := MarginContainer.new()
		for s in ["left", "right"]:
			hm.add_theme_constant_override("margin_" + s, 10)
		for s in ["top", "bottom"]:
			hm.add_theme_constant_override("margin_" + s, 7)
		hero.add_child(hm)
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 10)
		hm.add_child(hr)
		hr.add_child(g._fish_icon(big_id, 52))
		var hinfo := VBoxContainer.new()
		hinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hinfo.add_theme_constant_override("separation", 1)
		var hd := Label.new()
		hd.text = "🏆 个人最佳 · 史上最大一条"
		hd.add_theme_font_size_override("font_size", 12)
		hd.add_theme_color_override("font_color", Color(0.80, 0.62, 0.26))
		hinfo.add_child(hd)
		var ht := FishData.tier_of(big_id)
		var wrow := HBoxContainer.new()
		wrow.add_theme_constant_override("separation", 3)
		var wnum := Label.new()
		wnum.text = "%.2f" % big_w
		wnum.add_theme_font_override("font", g._serif_num)
		wnum.add_theme_font_size_override("font_size", 30)
		wnum.add_theme_color_override("font_color", g._ui_tier_color(ht, true))
		wnum.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		wrow.add_child(wnum)
		var wunit := Label.new()
		wunit.text = "kg"
		wunit.add_theme_font_size_override("font_size", 13)
		wunit.add_theme_color_override("font_color", Color(0.46, 0.43, 0.37))
		wunit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		wrow.add_child(wunit)
		hinfo.add_child(wrow)
		var hnm := Label.new()
		hnm.text = "%s%s" % [FishData.TIER_NAMES[ht], FishData.display_name(big_id)]
		hnm.add_theme_font_size_override("font_size", 13)
		hnm.add_theme_color_override("font_color", g._ui_tier_color(ht, true))
		hinfo.add_child(hnm)
		hr.add_child(hinfo)
		v.add_child(hero)
	var q := g.best_quality
	var q_txt: String = (str(FishData.QUALITY_NAMES[clampi(q, 0, 3)]) + "★".repeat(q)) if q > 0 else "普通"
	var rows := [
		["今日渔获", "%d 条" % g._today_catches()],
		["今日卖鱼收入", "%s 金币" % g._coin_str(g._today_income())],
		["终身渔获", "%d 条" % g.lifetime_catches],
		["终身卖鱼收入", "%s 金币" % g._coin_str(g.lifetime_coins)],
		["当前金币", g._coin_str(g.coins)],
		["图鉴收集", "%d / %d 种" % [g.dex.size(), FishData.FISH.size()]],
		["成就达成", "%d / %d" % [g.achievements_done.size(), AchievementData.LIST.size()]],
		["最高品相", q_txt],
		["最大渔获", biggest],
		["巨物纪录", "已钓到" if g.caught_giant else "尚无"],
		["累计专注", "%d 分钟" % int(g.focus_minutes_total)],
		["亲手起钩", "%d 条" % g.hand_catches],
		["猫税", "被叼走 %d 条" % g.pet_steals],
		["鱼贩合约", ("带走 %d 条 · +%s 金币" % [g.auto_sold_n, g._coin_str(g.auto_sold_v)]) if g.auto_sell_bought else "未签约"],
		["鱼篓容量", "%d 格" % g._bag_capacity()],
		["当前装备", "鱼竿 Lv.%d · %s · %s · %s" % [
			g.rod_level, FishData.BAITS[g.bait_level]["name"], FishData.HOOKS[g.hook_level]["name"],
			FishData.LURES[g.lure_level]["name"]]],
	]
	var sc0 := ScrollContainer.new()
	sc0.custom_minimum_size = Vector2(0, 360)
	sc0.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	for r in rows:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", paper_style(0.86))
		var mg := MarginContainer.new()
		for s in ["left", "right"]:
			mg.add_theme_constant_override("margin_" + s, 10)
		for s in ["top", "bottom"]:
			mg.add_theme_constant_override("margin_" + s, 5)
		panel.add_child(mg)
		var row := HBoxContainer.new()
		mg.add_child(row)
		var nm := Label.new()
		nm.text = str(r[0])
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.add_theme_color_override("font_color", Color(0.46, 0.43, 0.37))
		row.add_child(nm)
		var val := Label.new()
		val.text = str(r[1])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_color_override("font_color", Color(0.26, 0.25, 0.22))
		row.add_child(val)
		list.add_child(panel)
	sc0.add_child(list)
	v.add_child(sc0)


# ============================ 钓点页 ============================

static func spot_species_progress(g: CornerFishing, sid: String) -> Array:
	var pool: Array = SpotData.pool_for(sid)
	var got := 0
	for fid in pool:
		if g.dex.has(fid):
			got += 1
	return [got, pool.size()]


# ============================ 旅行地图（离线：晨昏线 + 旅程）============================

## 手记里的世界地图页：一张会走的晨昏线 + 你踩点点亮的十站。零联网、零后端。
static func fill_world_map(g: CornerFishing, v: VBoxContainer) -> void:
	v.add_theme_constant_override("separation", DT.SP_2)
	var wm := WorldMap.new()
	wm.name = "WorldMap"
	wm.setup(g)
	v.add_child(wm)

	var tip := Label.new()
	tip.text = "点亮的是你钓过鱼的地方。悬停看站名，点已解锁的站可直接前往。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", DT.FS_2XS)
	tip.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(tip)

	# 有意为之的语义澄清：晨昏线走 UTC 天文真实，而游戏昼夜跟着你本机的钟。
	var note := Label.new()
	note.text = "地图是此刻的地球；你的夜晚，是你自己的夜晚。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", DT.FS_2XS)
	note.add_theme_font_override("font", g._serif)
	note.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
	v.add_child(note)

	var back := Button.new()
	back.text = "← 返回钓点"
	back.custom_minimum_size = Vector2(0, 32)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button_skin(back, false)
	back.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._set_catch_tab(5))
	v.add_child(back)


static func fill_spot_tab(g: CornerFishing, v: VBoxContainer) -> void:
	var mapb := Button.new()
	mapb.text = "🗺  打开旅行地图"
	mapb.custom_minimum_size = Vector2(0, 34)
	mapb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button_skin(mapb, true)
	mapb.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._open_panel("worldmap"))
	v.add_child(mapb)
	var stat := Label.new()
	stat.text = "钓点 · 已解锁 %d/%d" % [g.unlocked_spots.size(), SpotData.SPOTS.size()]
	stat.add_theme_font_size_override("font_size", DT.FS_XS)
	stat.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(stat)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 326)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 填满 sheet 高度
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", DT.ROW_GAP)
	for sid in SpotData.SPOT_ORDER:
		list.add_child(spot_card(g, sid))
	sc.add_child(list)
	v.add_child(sc)


static func spot_card(g: CornerFishing, sid: String) -> Control:
	var unlocked := sid in g.unlocked_spots
	var is_cur := sid == g.current_spot
	var s: Dictionary = SpotData.get_spot(sid)
	var cell := PanelContainer.new()
	cell.clip_contents = true
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := dark_row_style(0.5)
	sb.set_corner_radius_all(DT.R_CARD)
	sb.set_border_width_all(2)
	sb.border_color = DT.GOLD if is_cur else DT.GLASS_ROW_BORDER
	cell.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	cell.add_child(col)

	# —— 顶部场景大图横幅（CD .sc-img）——
	var banner := Control.new()
	banner.custom_minimum_size = Vector2(0, 96)
	banner.clip_contents = true
	var imgpath := "res://assets/art/background/spot_%s.png" % str(s.get("bg_key", sid))
	if ResourceLoader.exists(imgpath):
		var img := TextureRect.new()
		img.texture = load(imgpath)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			img.modulate = Color(0.46, 0.46, 0.46)  # 锁定=灰暗
		banner.add_child(img)
	col.add_child(banner)

	# —— 下方信息体（CD .sc-body）——
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 12)
	body.add_theme_constant_override("margin_right", 12)
	body.add_theme_constant_override("margin_top", 9)
	body.add_theme_constant_override("margin_bottom", 10)
	col.add_child(body)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	body.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var nm := Label.new()
	nm.text = str(s["name"])
	nm.add_theme_font_size_override("font_size", DT.FS_HEAD)
	nm.add_theme_font_override("font", g._serif)  # 钓点名衬线
	nm.add_theme_color_override("font_color", DT.TEXT_TITLE if unlocked else DT.TEXT_MUTED_GLASS)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nm)
	if is_cur:
		head.add_child(make_pill("当前", DT.GOLD, DT.INK_ON_GOLD))
	elif unlocked:
		var btn := Button.new()
		btn.text = "前往"
		btn.custom_minimum_size = Vector2(64, 30)
		apply_button_skin(btn, true)
		btn.pressed.connect(g._switch_spot.bind(sid))
		head.add_child(btn)
	box.add_child(head)
	var desc := Label.new()
	desc.text = str(s["desc"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", DT.FS_2XS)
	desc.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS if unlocked else DT.TEXT_FAINT_GLASS)
	box.add_child(desc)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", DT.FS_2XS)
	if unlocked:
		var prog := spot_species_progress(g, sid)
		var line := "鱼种收集 %d/%d" % [prog[0], prog[1]]
		if is_cur:
			if g.active_event != "":
				line += "　·　当前事件：%s" % EventData.display_name(g.active_event)
			else:
				line += "　·　风平浪静"
		info.text = line
		info.add_theme_color_override("font_color", DT.POSITIVE)
	else:
		# near-miss 可见化：静态解锁条件 + 当前进度「还差 N」——目标梯度效应，越接近越想挂
		var lock_line := "🔒 %s" % SpotData.unlock_text(sid)
		var up := SpotData.unlock_progress_pair(sid, g.lifetime_catches, g.lifetime_coins, g.dex.size())
		if up.size() == 2 and int(up[1]) > 0:
			lock_line += "　·　%d/%d，还差 %d" % [int(up[0]), int(up[1]),
				maxi(0, int(up[1]) - int(up[0]))]
		info.text = lock_line
		info.add_theme_color_override("font_color", DT.BAG_FULL)
	box.add_child(info)
	return cell


# ============================ 稀有捕获卡（P0 好玩补丁）============================

## 鎏金/七彩入手的仪式面板：大图 + 衬线名 + 「1 in X」赔率徽章 + 保存 PNG。
## 数据在 g._capture_card_data（_rare_ceremony 灌入）；只展示不结算——鱼已按正常流程入篓。
static func fill_capture_card(g: CornerFishing, v: VBoxContainer) -> void:
	var c: Dictionary = g._capture_card_data
	if c.is_empty():
		return
	var vr := int(c.get("var", 0))
	var q := int(c.get("q", 0))
	var vcol := FishData.variant_color(vr)
	var id := str(c.get("id", ""))
	v.add_theme_constant_override("separation", DT.SP_2)

	var icon := TextureRect.new()
	icon.texture = g._fish_texture(id)
	icon.custom_minimum_size = Vector2(0, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(icon)

	var nm := Label.new()
	nm.text = FishData.variant_label(vr) + FishData.display_name(id)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", DT.FS_HEAD + 4)
	nm.add_theme_font_override("font", g._serif)
	nm.add_theme_color_override("font_color", vcol)
	v.add_child(nm)

	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", DT.CHIP_GAP)
	pills.add_child(make_pill("全球约 1 / %d 竿" % FishData.variant_odds(vr), vcol, DT.INK_ON_GOLD))
	if bool(c.get("hand", false)):
		pills.add_child(make_pill("🎣 亲手起钩", DT.BRONZE, DT.INK_ON_GOLD))
	v.add_child(pills)

	v.add_child(_kv_row("体重", "%.2f kg%s" % [float(c.get("w", 0.0)),
		("　·　" + FishData.size_tag(id, c["w"]).trim_suffix("·")) if FishData.size_tag(id, c["w"]) != "" else ""]))
	v.add_child(_kv_row("卖价", "%d 金币" % int(c.get("v", 0))))
	if q > 0:
		v.add_child(_kv_row("品相", FishData.quality_label(q).trim_suffix("·")))
	v.add_child(_kv_row("入手", Time.get_date_string_from_system()))

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", DT.SP_3)
	var keep := Button.new()
	keep.text = "收下"
	keep.custom_minimum_size = Vector2(120, 36)
	apply_button_skin(keep, true)
	keep.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		close_panel(g))
	btns.add_child(keep)
	var snap := Button.new()
	snap.text = "📸 保存捕获卡"
	snap.custom_minimum_size = Vector2(140, 36)
	apply_button_skin(snap, false)
	snap.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._save_capture_card())
	btns.add_child(snap)
	v.add_child(btns)


# ============================ 鱼缸页（活水族箱）============================

static func fill_decor_tab(g: CornerFishing, v: VBoxContainer) -> void:
	var stat := Label.new()
	stat.text = "🐟 水族箱 · %d/%d 条　观赏卖价加成 +%d%%" % [
		g.display.size(), Decor.NUM_SLOTS, int(round(Decor.value_bonus(g) * 100.0))]
	stat.add_theme_font_size_override("font_size", DT.FS_XS)
	stat.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(stat)
	# 活水族箱视图：缸内鱼沿平滑路径游动，点鱼看纪录
	var aq := Aquarium.new()
	aq.name = "Aquarium"
	aq.setup(g)
	v.add_child(aq)
	var tip := Label.new()
	tip.text = "点缸里的鱼看它的纪录，也能把它捞回鱼篓。鎏金/七彩会发光。"
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(0.70, 0.66, 0.58))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(440, 0)
	v.add_child(tip)
	v.add_child(HSeparator.new())
	# 从鱼篓放入
	var pick_lbl := Label.new()
	if Decor.is_full(g):
		pick_lbl.text = "水族箱满了（%d 条），先捞回一条再放新的。" % Decor.NUM_SLOTS
	else:
		pick_lbl.text = "从鱼篓挑一条放进缸（离开鱼篓、永久展示，可再捞回）："
	pick_lbl.add_theme_font_size_override("font_size", 12)
	pick_lbl.add_theme_color_override("font_color", Color(0.70, 0.66, 0.58))
	pick_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pick_lbl.custom_minimum_size = Vector2(440, 0)
	v.add_child(pick_lbl)
	if not Decor.is_full(g) and not g.inventory.is_empty():
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 144)   # 高度下限；下面 EXPAND_FILL 让它吃掉面板底部留白
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 4)
		# 价值降序，便于挑“最值得养”的
		var idxs := g._sorted_bag_indices(false)
		for i in idxs:
			list.add_child(decor_pick_row(g, g.inventory[i], i))
		sc.add_child(list)
		v.add_child(sc)


static func decor_pick_row(g: CornerFishing, c: Dictionary, idx: int) -> Control:
	var tier := FishData.tier_of(str(c["id"]))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", dark_row_style(0.46))
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6 if side in ["left", "right"] else 3)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)
	row.add_child(g._fish_icon(str(c["id"]), 32))
	var nm := Label.new()
	nm.text = "%s%s%s" % [FishData.size_tag(str(c["id"]), float(c["w"])),
		FishData.display_name(str(c["id"])), "★".repeat(int(c.get("q", 0)))]
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", g._ui_tier_color(tier, false))
	row.add_child(nm)
	var meta := Label.new()
	meta.text = "%.2fkg" % float(c["w"])
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", Color(0.78, 0.68, 0.45))
	row.add_child(meta)
	var btn := Button.new()
	btn.text = "放入"
	btn.custom_minimum_size = Vector2(48, 28)
	apply_button_skin(btn, true)
	btn.pressed.connect(func() -> void: Decor.add_from_inventory(g, idx))
	row.add_child(btn)
	return panel


# ============================ 成就页 ============================

static func fill_ach_tab(g: CornerFishing, v: VBoxContainer) -> void:
	var stat := Label.new()
	stat.text = "已达成 %d/%d" % [g.achievements_done.size(), AchievementData.LIST.size()]
	stat.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66))
	v.add_child(stat)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 330)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	var sorted: Array = AchievementData.LIST.duplicate()
	sorted.sort_custom(func(a, b):
		return g.achievements_done.has(a["id"]) and not g.achievements_done.has(b["id"]))
	for a in sorted:
		list.add_child(ach_row(g, a))
	sc.add_child(list)
	v.add_child(sc)


static func ach_row(g: CornerFishing, a: Dictionary) -> Control:
	var done: bool = g.achievements_done.has(a["id"])
	var panel := PanelContainer.new()
	var sb := dark_row_style(0.5 if done else 0.4)
	if done:
		sb.set_border_width_all(1)
		sb.border_color = Color(DT.GOLD.r, DT.GOLD.g, DT.GOLD.b, 0.5)
	panel.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 11)
	margin.add_theme_constant_override("margin_right", 11)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	var mark := Label.new()
	mark.text = "✓" if done else "○"
	mark.custom_minimum_size = Vector2(18, 0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.add_theme_font_size_override("font_size", DT.FS_HEAD)
	mark.add_theme_color_override("font_color", DT.POSITIVE if done else DT.TEXT_FAINT_GLASS)
	row.add_child(mark)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 0)
	var nm := Label.new()
	nm.text = str(a["name"])
	nm.add_theme_font_size_override("font_size", DT.FS_LABEL)
	nm.add_theme_color_override("font_color", DT.TEXT_ON_GLASS if done else DT.TEXT_MUTED_GLASS)
	info.add_child(nm)
	var ds := Label.new()
	ds.text = str(a["desc"])
	ds.add_theme_font_size_override("font_size", DT.FS_2XS)
	ds.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS if done else DT.TEXT_FAINT_GLASS)
	info.add_child(ds)
	row.add_child(info)
	if done:
		row.add_child(make_pill("达成", DT.GOLD, DT.INK_ON_GOLD))
	else:
		var rw := int(a.get("reward", 0))
		if rw > 0:
			var rwl := Label.new()
			rwl.text = "+%d" % rw
			rwl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rwl.add_theme_font_size_override("font_size", DT.FS_XS)
			rwl.add_theme_color_override("font_color", DT.GOLD)
			row.add_child(rwl)
	return panel


# ============================ 订单页 + 周目标 ============================

static func fill_order_tab(g: CornerFishing, v: VBoxContainer) -> void:
	g._ensure_daily_order()
	var target := str(g.daily_order.get("fish", ""))
	if not FishData.FISH.has(target):
		var bad := Label.new()
		bad.text = "今日订单生成失败。"
		bad.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66))
		v.add_child(bad)
		return
	var done := bool(g.daily_order.get("done", false))
	var need := int(g.daily_order.get("need", 1))
	var indices := g._daily_order_indices()
	var have := indices.size()
	var reward := g._daily_order_reward(indices)
	var kind := str(g.daily_order.get("kind", "species"))

	var stat := Label.new()
	stat.text = "每日订单 · %s" % str(g.daily_order.get("date", ""))
	stat.add_theme_font_size_override("font_size", DT.FS_XS)
	stat.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(stat)

	var panel := PanelContainer.new()
	var osb := dark_row_style(0.5)             # CD：暗行底（非浅纸）
	if have >= need and not done:
		osb.set_border_width_all(2)
		osb.border_color = DT.GOLD             # 可交付 → 金边
	panel.add_theme_stylebox_override("panel", osb)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12 if side in ["left", "right"] else 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	margin.add_child(row)
	row.add_child(g._fish_icon(target, 48))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = g._order_title()
	title.add_theme_font_override("font", g._font_bold)
	title.add_theme_font_size_override("font_size", DT.FS_HEAD)
	title.add_theme_color_override("font_color", DT.TEXT_ON_GLASS if not done else DT.TEXT_MUTED_GLASS)
	info.add_child(title)
	var kind_label: String = {"species": "指定鱼种", "tier": "指定品阶", "weight": "大物", "perfect": "完美品质"}.get(kind, "")
	var desc := Label.new()
	var mtxt := "（收鱼郎在场 ×%.1f！）" % g.MERCHANT_MULT if g._merchant_active else ""
	desc.text = "%s订单 · 交付未上锁的符合渔获，按鱼价 ×%.1f 结算%s" % [kind_label, g.DAILY_ORDER_MULT, mtxt]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(220, 0)
	desc.add_theme_font_size_override("font_size", DT.FS_2XS)
	desc.add_theme_color_override("font_color", DT.GOLD if g._merchant_active and not done else DT.TEXT_MUTED_GLASS)
	info.add_child(desc)
	var progress := Label.new()
	if done:
		progress.text = "今日已完成"
	else:
		progress.text = "进度 %d/%d%s" % [have, need, " · 可交付 +%s" % g._coin_str(reward) if have >= need else ""]
	progress.add_theme_font_size_override("font_size", DT.FS_XS)
	progress.add_theme_color_override("font_color", DT.GOLD if have >= need and not done else DT.TEXT_MUTED_GLASS)
	info.add_child(progress)
	var sug := str(g.daily_order.get("spot", ""))
	if not done and have < need and SpotData.has(sug) and sug != g.current_spot and (sug in g.unlocked_spots):
		var sl := Label.new()
		sl.text = "建议去「%s」钓这条" % SpotData.display_name(sug)
		sl.add_theme_font_size_override("font_size", 12)
		sl.add_theme_color_override("font_color", Color(0.42, 0.56, 0.74))
		info.add_child(sl)
	row.add_child(info)

	var btn := Button.new()
	btn.text = "已完成" if done else "交付"
	btn.custom_minimum_size = Vector2(64, 34)
	btn.disabled = done or have < need
	apply_button_skin(btn, have >= need and not done)
	btn.pressed.connect(g._try_complete_daily_order)
	row.add_child(btn)
	v.add_child(panel)

	var hint := Label.new()
	hint.text = "锁定的目标鱼会留在鱼篓里，不会被订单交付。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.70, 0.66, 0.58))
	v.add_child(hint)
	fill_weekly_panel(g, v)


## CD 统计卡（hero 数字 + 标签）
static func _stat_card(g: CornerFishing, value: String, key: String) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", dark_row_style(0.5))
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 13)
	mg.add_theme_constant_override("margin_right", 13)
	mg.add_theme_constant_override("margin_top", 11)
	mg.add_theme_constant_override("margin_bottom", 11)
	pc.add_child(mg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	mg.add_child(box)
	var vl := Label.new()
	vl.text = value
	vl.add_theme_font_override("font", g._font_bold)       # CD .stat .v weight 800 → embolden
	vl.add_theme_font_size_override("font_size", 20)
	vl.add_theme_color_override("font_color", DT.TEXT_TITLE)
	box.add_child(vl)
	var kl := Label.new()
	kl.text = key
	kl.add_theme_font_size_override("font_size", DT.FS_2XS)
	kl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	box.add_child(kl)
	return pc


## 紧凑标签:值 行
static func _kv_row(k: String, val: String) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", dark_row_style(0.4))
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 11)
	mg.add_theme_constant_override("margin_right", 11)
	mg.add_theme_constant_override("margin_top", 6)
	mg.add_theme_constant_override("margin_bottom", 6)
	pc.add_child(mg)
	var row := HBoxContainer.new()
	mg.add_child(row)
	var kl := Label.new()
	kl.text = k
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kl.add_theme_font_size_override("font_size", DT.FS_XS)
	kl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	row.add_child(kl)
	var vl := Label.new()
	vl.text = val
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vl.add_theme_font_size_override("font_size", DT.FS_XS)
	vl.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	row.add_child(vl)
	return pc


## CD 任务页：每日订单 + 周挑战 + 统计 + 成就，合并为一个滚动页（保留全部功能）。
static func fill_tasks_tab(g: CornerFishing, v: VBoxContainer) -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 384)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", DT.SP_2)
	sc.add_child(list)

	# 订单 + 周挑战（复用现有渲染）
	fill_order_tab(g, list)

	# 本周巨物赛（钓鱼比赛事件）
	fill_competition_panel(g, list)

	# —— 统计：hero 卡格 + 详细行 ——
	_section(list, "统计")
	var big_id := ""
	var big_w := 0.0
	for id in g.dex:
		if float(g.dex[id]["w"]) > big_w:
			big_w = float(g.dex[id]["w"])
			big_id = id
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", DT.SP_3)
	grid.add_theme_constant_override("v_separation", DT.SP_3)
	grid.add_child(_stat_card(g, g._coin_str(g.lifetime_catches), "累计渔获"))
	grid.add_child(_stat_card(g, g._coin_str(g.lifetime_coins), "累计收入"))
	grid.add_child(_stat_card(g, g._coin_str(g._today_catches()), "今日渔获"))
	grid.add_child(_stat_card(g, g._coin_str(g._today_income()), "今日收入"))
	grid.add_child(_stat_card(g, ("%.2fkg" % big_w) if big_id != "" else "—", "最大个体"))
	grid.add_child(_stat_card(g, g._coin_str(g.coins), "当前金币"))
	list.add_child(grid)
	var q := g.best_quality
	var rows := [
		["图鉴收集", "%d / %d 种" % [g.dex.size(), FishData.FISH.size()]],
		["成就达成", "%d / %d" % [g.achievements_done.size(), AchievementData.LIST.size()]],
		["最高品相", (str(FishData.QUALITY_NAMES[clampi(q, 0, 3)]) + "★".repeat(q)) if q > 0 else "普通"],
		["巨物纪录", "已钓到" if g.caught_giant else "尚无"],
		["累计专注", "%d 分钟" % int(g.focus_minutes_total)],
		["亲手起钩", "%d 条" % g.hand_catches],
		["猫税", "被叼走 %d 条" % g.pet_steals],
		["鱼贩合约", ("带走 %d 条 · +%s 金币" % [g.auto_sold_n, g._coin_str(g.auto_sold_v)]) if g.auto_sell_bought else "未签约"],
		["鱼篓容量", "%d 格" % g._bag_capacity()],
		["当前装备", "鱼竿 Lv.%d · %s · %s · %s" % [
			g.rod_level, FishData.BAITS[g.bait_level]["name"], FishData.HOOKS[g.hook_level]["name"],
			FishData.LURES[g.lure_level]["name"]]],
	]
	for r in rows:
		list.add_child(_kv_row(str(r[0]), str(r[1])))

	# —— 成就 ——
	_section(list, "成就 %d/%d" % [g.achievements_done.size(), AchievementData.LIST.size()])
	var sorted: Array = AchievementData.LIST.duplicate()
	sorted.sort_custom(func(a, b):
		return g.achievements_done.has(a["id"]) and not g.achievements_done.has(b["id"]))
	for a in sorted:
		list.add_child(ach_row(g, a))
	v.add_child(sc)


static func fill_weekly_panel(g: CornerFishing, v: VBoxContainer) -> void:
	g._ensure_weekly()
	v.add_child(HSeparator.new())
	var wdone := bool(g.weekly.get("done", false))
	var prog := g._weekly_progress()
	var target := int(g.weekly.get("target", 1))
	var stat := Label.new()
	stat.text = "本周挑战"
	stat.add_theme_font_size_override("font_size", DT.FS_XS)
	stat.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(stat)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", dark_row_style(0.5))   # CD：暗行底（非浅纸）
	var mg := MarginContainer.new()
	for s in ["left", "right"]:
		mg.add_theme_constant_override("margin_" + s, 11)
	for s in ["top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 9)
	panel.add_child(mg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	mg.add_child(box)
	var title := Label.new()
	title.text = g._weekly_desc()
	title.add_theme_font_override("font", g._font_bold)
	title.add_theme_font_size_override("font_size", DT.FS_SM)
	title.add_theme_color_override("font_color", DT.TEXT_ON_GLASS if not wdone else DT.TEXT_MUTED_GLASS)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(330, 0)
	box.add_child(title)
	var bar := make_progress(float(mini(prog, target)) / maxf(1.0, float(target)), DT.GOLD, 8)
	box.add_child(bar)
	var row := HBoxContainer.new()
	var pl := Label.new()
	pl.text = "%d / %d　奖励 %s 金币" % [mini(prog, target), target, g._coin_str(int(g.weekly.get("reward", 0)))]
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.add_theme_font_size_override("font_size", DT.FS_XS)
	pl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	row.add_child(pl)
	var btn := Button.new()
	btn.text = "已领取" if wdone else "领取"
	btn.custom_minimum_size = Vector2(64, 30)
	btn.disabled = wdone or prog < target
	apply_button_skin(btn, prog >= target and not wdone)
	btn.pressed.connect(g._try_claim_weekly)
	row.add_child(btn)
	box.add_child(row)
	v.add_child(panel)


# —— 本周巨物赛卡（钓鱼比赛事件，与周挑战同构）——
static func fill_competition_panel(g: CornerFishing, v: VBoxContainer) -> void:
	g._ensure_competition()
	var fid := str(g.competition.get("fish", ""))
	if not FishData.FISH.has(fid):
		return
	var line := Competition.shadow_weight(g)
	var best := float(g.competition.get("best", 0.0))
	var claimed := bool(g.competition.get("claimed", false))
	v.add_child(HSeparator.new())
	var stat := Label.new()
	stat.text = "本周巨物赛"
	stat.add_theme_font_size_override("font_size", DT.FS_XS)
	stat.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(stat)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", dark_row_style(0.5))
	var mg := MarginContainer.new()
	for s in ["left", "right"]:
		mg.add_theme_constant_override("margin_" + s, 11)
	for s in ["top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 9)
	panel.add_child(mg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	mg.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var icon := g._fish_icon(fid, 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	var title := Label.new()
	title.text = "冲「%s」体重榜" % FishData.display_name(fid)
	title.add_theme_font_override("font", g._font_bold)
	title.add_theme_font_size_override("font_size", DT.FS_SM)
	title.add_theme_color_override("font_color", DT.TEXT_ON_GLASS if not claimed else DT.TEXT_MUTED_GLASS)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if claimed:
		head.add_child(make_pill("✓ 已夺金", Color(0.22, 0.50, 0.30, 0.5), Color(0.72, 0.92, 0.74)))
	box.add_child(head)
	box.add_child(make_progress(clampf(best / maxf(0.01, line), 0.0, 1.0), Color(1.0, 0.82, 0.32), 8))
	var pl := Label.new()
	pl.text = "目标 ≥%.2fkg　·　本周最佳 %.2fkg　·　夺金 +%s 金币" % [line, best, g._coin_str(int(g.competition.get("reward", 0)))]
	pl.add_theme_font_size_override("font_size", DT.FS_XS)
	pl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pl.custom_minimum_size = Vector2(330, 0)
	box.add_child(pl)
	var hint := Label.new()
	hint.text = "💡 本周内现钓到一条 ≥%.1fkg 的「%s」即自动夺金" % [line, FishData.display_name(fid)]
	hint.add_theme_font_size_override("font_size", DT.FS_2XS)
	hint.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(330, 0)
	box.add_child(hint)
	v.add_child(panel)


# ============================ 背包页 ============================

static func fill_bag_tab(g: CornerFishing, v: VBoxContainer) -> void:
	# —— 排序 + 订单筛选（CD .seg pill）——
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", DT.CHIP_GAP)
	for m in g.BAG_SORT_NAMES.size():
		var sb := Button.new()
		sb.text = g.BAG_SORT_NAMES[m]
		apply_tab_skin(sb, m == g._bag_sort)
		if m != g._bag_sort:
			sb.pressed.connect(func(mm = m) -> void:
				g._bag_sort = mm
				g._open_panel("catch"))
		seg.add_child(sb)
	var seg_sp := Control.new()
	seg_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.add_child(seg_sp)
	var filt := Button.new()
	filt.text = "订单鱼"
	filt.tooltip_text = "只看今日订单的目标鱼"
	apply_tab_skin(filt, g._bag_filter_order, DT.GOLD)
	filt.pressed.connect(func() -> void:
		g._bag_filter_order = not g._bag_filter_order
		g._open_panel("catch"))
	seg.add_child(filt)
	v.add_child(seg)

	# —— 容量 + 批量操作 ——
	var total := 0
	var unlocked := 0
	var junk := 0
	var below := 0
	for c in g.inventory:
		if not bool(c.get("lock", false)):
			total += g._sell_value(c)
			unlocked += 1
			if not g._order_matches(c):
				junk += 1
			if int(c.get("var", 0)) < 2 and int(c.get("q", 0)) < 3 \
					and not g._order_matches(c) \
					and FishData.tier_of(str(c["id"])) <= g._sell_tier:
				below += 1
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", DT.CHIP_GAP)
	var cap := Label.new()
	cap.text = "%d/%d" % [g.inventory.size(), g._bag_capacity()]
	cap.add_theme_font_size_override("font_size", DT.FS_XS)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_theme_color_override("font_color", DT.BAG_FULL if g._bag_full() else DT.TEXT_MUTED_GLASS)
	head.add_child(cap)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var sell_junk := Button.new()
	sell_junk.text = "卖杂鱼"
	sell_junk.custom_minimum_size = Vector2(0, 28)
	sell_junk.disabled = junk == 0
	sell_junk.tooltip_text = "卖出 %d 条非订单、非收藏的鱼（保留订单目标鱼与锁定）" % junk
	sell_junk.add_theme_font_size_override("font_size", DT.FS_XS)
	apply_button_skin(sell_junk, false)
	sell_junk.pressed.connect(g._sell_junk)
	head.add_child(sell_junk)
	var sell_all := Button.new()
	sell_all.text = "全部兑换 +%s" % g._coin_str(total)
	sell_all.custom_minimum_size = Vector2(0, 28)
	sell_all.disabled = unlocked == 0
	sell_all.tooltip_text = "卖出 %d 条未上锁的鱼%s（锁定的会留下）" % [
		unlocked, "（收鱼郎×1.5）" if g._merchant_active else ""]
	sell_all.add_theme_font_size_override("font_size", DT.FS_XS)
	apply_button_skin(sell_all, true)
	sell_all.pressed.connect(g._sell_all)
	head.add_child(sell_all)
	# —— 批量「卖掉≤品阶及以下」：品阶选择 + 永远可点的卖按钮 ——
	var tier_ob := OptionButton.new()
	tier_ob.focus_mode = Control.FOCUS_NONE
	tier_ob.custom_minimum_size = Vector2(0, 28)
	tier_ob.add_theme_font_size_override("font_size", DT.FS_XS)
	for t in FishData.TIER_NAMES.size():
		tier_ob.add_item(FishData.TIER_NAMES[t], t)
	tier_ob.select(g._sell_tier)
	tier_ob.item_selected.connect(func(idx: int) -> void:
		g._sell_tier = idx
		g._open_panel("catch"))   # 重绘以更新按钮文案/数量
	head.add_child(tier_ob)
	var sell_below := Button.new()
	sell_below.text = "卖掉%s及以下(%d)" % [FishData.TIER_NAMES[g._sell_tier], below]
	sell_below.custom_minimum_size = Vector2(0, 28)
	sell_below.disabled = false   # 永远可点；无符合鱼时在 _sell_below_tier 内给提示，避免“点不动”错觉
	sell_below.tooltip_text = "卖出未上锁、非订单、非珍稀（鎏金/七彩/★★★），且品阶≤%s 的鱼（收藏锁保留）。当前可卖 %d 条" % [FishData.TIER_NAMES[g._sell_tier], below]
	sell_below.add_theme_font_size_override("font_size", DT.FS_XS)
	apply_button_skin(sell_below, false)
	sell_below.pressed.connect(func() -> void: g._sell_below_tier(g._sell_tier))
	head.add_child(sell_below)
	if g.bag_level <= g.BAG_COSTS.size():
		var cost: int = g.BAG_COSTS[g.bag_level - 1]
		var expand := Button.new()
		expand.text = "扩容"
		expand.custom_minimum_size = Vector2(0, 28)
		expand.disabled = g.coins < cost
		expand.tooltip_text = "扩到 %d 格，花费 %s 金币" % [g.BAG_CAPS[g.bag_level], g._coin_str(cost)]
		expand.add_theme_font_size_override("font_size", DT.FS_XS)
		apply_button_skin(expand, false)
		expand.pressed.connect(g._try_expand_bag)
		head.add_child(expand)
	v.add_child(head)

	if g.inventory.is_empty():
		v.add_child(_empty_note("鱼篓还是空的，\n等浮漂动一动。"))
		return

	# —— 网格（CD .bgrid）：4 列鱼卡，点卡身=卖，右上「锁」角标 ——
	var idxs := g._sorted_bag_indices(g._bag_filter_order)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 300)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 填满 sheet 高度（带框）
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if idxs.is_empty():
		v.add_child(_empty_note("没有符合条件的鱼。"))
		return
	var grid := GridContainer.new()
	grid.columns = 8 if g.display_mode != "immersive" else 4   # 带框全宽 sheet → 更密
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", DT.SP_3)
	grid.add_theme_constant_override("v_separation", DT.SP_3)
	for i in idxs:
		grid.add_child(fish_cell(g, g.inventory[i], i))
	sc.add_child(grid)
	v.add_child(sc)


## CD .empty —— 暗行空态提示卡
static func _empty_note(text: String) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 92)
	pc.add_theme_stylebox_override("panel", dark_row_style(0.4))
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", DT.FS_SM)
	l.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
	pc.add_child(l)
	return pc


## CD .fishcell —— 鱼篓网格卡：品阶/变体色边框 + 图 + 名 + 「卖N」；右上「锁」可点；点卡身=卖。
## 保留全部功能：单条卖/锁、星级品质、巨物前缀、变体◆、品阶色编码。
static func fish_cell(g: CornerFishing, c: Dictionary, idx: int) -> Control:
	var id := str(c["id"])
	var tier := FishData.tier_of(id)
	var vr := int(c.get("var", 0))
	var locked: bool = bool(c.get("lock", false))
	# 边框始终按【品阶】着色，保证"品阶排序"后同品阶鱼视觉成组（不再出现
	# 变体蓝边鱼混在橙边鱼中间的错觉）。变体身份改由「◆」前缀 + 名字颜色表达。
	var tier_edge := g._ui_tier_color(tier, false)
	var edge := FishData.variant_color(vr) if vr >= 1 else tier_edge
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(0, 106)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := dark_row_style(0.42)
	sb.set_border_width_all(2)
	sb.border_color = Color(tier_edge.r, tier_edge.g, tier_edge.b, 0.85)
	cell.add_theme_stylebox_override("panel", sb)
	cell.tooltip_text = "%s · %.2fkg · 点击卖出" % [FishData.display_name(id), float(c["w"])]
	cell.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if locked:
				g._toast("已锁定收藏，先点右上「锁」解锁再卖", 1.5, DT.BAG_FULL)
			else:
				g._sell_one(idx))
	var mg := MarginContainer.new()
	mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mg.add_theme_constant_override("margin_left", 6)
	mg.add_theme_constant_override("margin_right", 6)
	mg.add_theme_constant_override("margin_top", 4)
	mg.add_theme_constant_override("margin_bottom", 6)
	cell.add_child(mg)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	mg.add_child(box)
	# 顶行：右上「锁」幽灵角标
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.custom_minimum_size = Vector2(0, 15)
	var tsp := Control.new()
	tsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tsp)
	var lk := Button.new()
	lk.text = "锁"
	lk.tooltip_text = "解除收藏锁" if locked else "上锁收藏（不被卖出 / 交付）"
	lk.custom_minimum_size = Vector2(20, 15)
	lk.focus_mode = Control.FOCUS_NONE
	var lk_empty := StyleBoxEmpty.new()
	lk.add_theme_stylebox_override("normal", lk_empty)
	lk.add_theme_stylebox_override("pressed", lk_empty)
	lk.add_theme_stylebox_override("hover", lk_empty)
	lk.add_theme_stylebox_override("focus", lk_empty)
	lk.add_theme_font_size_override("font_size", DT.FS_2XS)
	lk.add_theme_color_override("font_color", DT.GOLD_BRIGHT if locked else DT.TEXT_FAINT_GLASS)
	lk.add_theme_color_override("font_hover_color", DT.GOLD_BRIGHT)
	lk.pressed.connect(func() -> void: Audio.play_ui("ui_click"))
	lk.pressed.connect(g._toggle_lock.bind(idx))
	top.add_child(lk)
	box.add_child(top)
	# 图标
	var icon := g._fish_icon(id, 44)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	# 名字（品阶/变体色编码，◆=变体）
	var nm := Label.new()
	nm.text = ("◆" + FishData.display_name(id)) if vr >= 1 else FishData.display_name(id)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_font_override("font", g._font_bold)        # CD .fn weight 700
	nm.add_theme_font_size_override("font_size", DT.FS_2XS + 1)
	nm.add_theme_color_override("font_color", edge)
	box.add_child(nm)
	# meta：星级 / 巨物 / 重量
	var meta := Label.new()
	var parts: Array[String] = []
	var q := int(c.get("q", 0))
	if q > 0:
		parts.append("★".repeat(q))
	var sztag := FishData.size_tag(id, c["w"]).replace("·", "").strip_edges()
	if sztag != "":
		parts.append(sztag)
	parts.append("%.2fkg" % float(c["w"]))
	meta.text = " ".join(parts)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.clip_text = true
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_font_size_override("font_size", DT.FS_MICRO)
	meta.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	box.add_child(meta)
	# 价值 / 卖出提示
	var val := Label.new()
	val.text = "已锁" if locked else "卖 %s" % g._coin_str(g._sell_value(c))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.add_theme_font_override("font", g._font_bold)        # CD .fv weight 800
	val.add_theme_font_size_override("font_size", DT.FS_XS)
	val.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS if locked else DT.GOLD_BRIGHT)
	box.add_child(val)
	return cell


# ============================ 图鉴页 ============================

# ============================ 鱼种详情卡（点击图鉴的鱼弹出）============================

static func fill_fish_detail(g: CornerFishing, v: VBoxContainer) -> void:
	var id := str(g._detail_fish)
	if not FishData.FISH.has(id):
		return
	var info: Dictionary = FishData.FISH[id]
	var tier := FishData.tier_of(id)
	var rec: Dictionary = g.dex.get(id, {})
	var lore: Dictionary = FishLore.LORE.get(id, {})

	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 404)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 填满 sheet 高度（与其它页一致）：消除底部死区，让变体墙/返回按钮直接可见
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	sc.add_child(col)
	v.add_child(sc)

	# —— 照片：有真实照片则显示，否则回退水彩鱼图 ——
	var photo_path := "res://assets/art/fish_photos/%s.jpg" % id
	var has_photo := ResourceLoader.exists(photo_path)
	var pcard := PanelContainer.new()
	pcard.add_theme_stylebox_override("panel", paper_style(0.95))
	var pm := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		pm.add_theme_constant_override("margin_" + s, 8)
	pcard.add_child(pm)
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 4)
	pm.add_child(pbox)
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(0, 224 if has_photo else 132)
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.texture = (load(photo_path) as Texture2D) if has_photo else g._fish_texture(id)
	pbox.add_child(img)
	var cap := Label.new()
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.custom_minimum_size = Vector2(460, 0)
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Color(0.46, 0.43, 0.37))
	cap.text = _photo_credit(id) if has_photo else "（暂用示意水彩图，真实照片待补）"
	pbox.add_child(cap)
	col.add_child(pcard)

	# —— 名 · 品阶（衬线）——
	var nm := Label.new()
	nm.text = "%s · %s" % [FishData.TIER_NAMES[tier], FishData.display_name(id)]
	nm.add_theme_font_size_override("font_size", 20)
	nm.add_theme_font_override("font", g._serif)
	nm.add_theme_color_override("font_color", g._ui_tier_color(tier, false))
	col.add_child(nm)

	# —— 品种描述 + 冷知识 ——
	if lore.has("desc"):
		var d := Label.new()
		d.text = str(lore["desc"])
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(470, 0)
		d.add_theme_font_size_override("font_size", 13)
		d.add_theme_color_override("font_color", Color(0.86, 0.83, 0.74))
		col.add_child(d)
	if lore.has("fact"):
		var fa := Label.new()
		fa.text = "💡 " + str(lore["fact"])
		fa.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fa.custom_minimum_size = Vector2(470, 0)
		fa.add_theme_font_size_override("font_size", 12)
		fa.add_theme_color_override("font_color", Color(0.82, 0.70, 0.42))
		col.add_child(fa)

	# —— 真实档案 ——
	var tags_cn := []
	for t in info.get("tags", []):
		tags_cn.append(str(FishLore.TAG_CN.get(t, t)))
	col.add_child(_kv_card([
		["生态", "　".join(tags_cn)],
		["体重", "%.2f – %.2f kg" % [float(info["wmin"]), float(info["wmax"])]],
		["卖价", "%s – %s 金币" % [g._coin_str(int(info["vmin"])), g._coin_str(int(info["vmax"]))]],
	]))

	# —— 个人纪录 ——
	if not rec.is_empty():
		var fd := str(rec.get("fd", ""))
		var wd := str(rec.get("wd", ""))
		var pw := float(rec.get("w", 0.0))
		var wmax := float(info["wmax"])
		var pct := int(round(pw / wmax * 100.0)) if wmax > 0.0 else 0
		col.add_child(_kv_card([
			["累计钓获", "×%d" % int(rec.get("n", 1))],
			["🏆 个人最大", "%.2f kg　·　理论上限 %.2f kg（%d%%）" % [pw, wmax, pct]],
			["破纪录于", wd if wd != "" else "—"],
			["首次捕获", fd if fd != "" else "很久以前"],
		]))

	# —— 变体墙（显式 4 格：普通 / 斑斓 / 鎏金 / 七彩）——
	var vmask := int(rec.get("vmask", 0))
	var vgot := (1 if not rec.is_empty() else 0)
	for vi in range(1, FishData.VARIANT_NAMES.size()):
		if vmask & (1 << vi):
			vgot += 1
	var vwrap := PanelContainer.new()
	vwrap.add_theme_stylebox_override("panel", paper_style(0.95))
	var vmar := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		vmar.add_theme_constant_override("margin_" + s, 8)
	vwrap.add_child(vmar)
	var vcol := VBoxContainer.new()
	vcol.add_theme_constant_override("separation", 6)
	vmar.add_child(vcol)
	var vtitle := Label.new()
	vtitle.text = "变体墙　%d / %d　·　鳞 %d/%d/%d" % [vgot, FishData.VARIANT_NAMES.size(),
		int(g.scales[0]), int(g.scales[1]), int(g.scales[2])]
	vtitle.add_theme_font_size_override("font_size", 12)
	vtitle.add_theme_color_override("font_color", Color(0.50, 0.47, 0.40))
	vtitle.tooltip_text = "重复钓到已点亮的变体折 1 枚同档鳞（斑斓鳞/鎏金鳞/七彩鳞）；\n同档鳞可定向点亮已收录鱼的同档缺格（按品阶 3/4/5 枚一格）"
	vcol.add_child(vtitle)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 6)
	vcol.add_child(vrow)
	for vi in range(FishData.VARIANT_NAMES.size()):
		var got := (not rec.is_empty()) if vi == 0 else ((vmask & (1 << vi)) != 0)
		var vname := "普通" if vi == 0 else str(FishData.VARIANT_NAMES[vi])
		var vc: Color = Color(0.42, 0.39, 0.34) if vi == 0 else FishData.variant_color(vi)
		var slot := PanelContainer.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Color(vc.r, vc.g, vc.b, 0.14) if got else Color(0.0, 0.0, 0.0, 0.04)
		ssb.set_border_width_all(1)
		ssb.border_color = Color(vc.r, vc.g, vc.b, 0.8) if got else Color(0.3, 0.28, 0.24, 0.35)
		ssb.set_corner_radius_all(6)
		ssb.set_content_margin_all(6)
		slot.add_theme_stylebox_override("panel", ssb)
		var sbox := VBoxContainer.new()
		sbox.alignment = BoxContainer.ALIGNMENT_CENTER
		sbox.add_theme_constant_override("separation", 2)
		slot.add_child(sbox)
		var snm := Label.new()
		snm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		snm.text = vname
		snm.add_theme_font_size_override("font_size", 12)
		snm.add_theme_color_override("font_color", vc.darkened(0.2) if got else Color(0.5, 0.47, 0.42, 0.6))
		sbox.add_child(snm)
		if got or vi == 0 or rec.is_empty():
			var sst := Label.new()
			sst.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sst.add_theme_font_size_override("font_size", 11)
			if got:
				sst.text = "已遇" if vi == 0 else "✓ ×%d" % int(FishData.VARIANT_MULTS[vi])
				sst.add_theme_color_override("font_color", vc.darkened(0.1))
			else:
				sst.text = "待捕"
				sst.add_theme_color_override("font_color", Color(0.5, 0.47, 0.42, 0.5))
			sbox.add_child(sst)
		else:
			# 已收录鱼的缺失变体格：同档鳞定向兑换入口（点亮收集位，不发鱼）
			var rcost := FishData.scale_cost(FishData.tier_of(id))
			var have: int = int(g.scales[vi - 1])
			var rb := Button.new()
			rb.text = "兑 %d鳞" % rcost
			rb.add_theme_font_size_override("font_size", 11)
			rb.custom_minimum_size = Vector2(0, 24)
			rb.disabled = have < rcost
			rb.tooltip_text = "花 %d 枚%s点亮此格（现有 %d）" % [rcost, FishData.SCALE_NAMES[vi - 1], have]
			apply_button_skin(rb, false)
			if not rb.disabled:
				rb.pressed.connect(g._redeem_variant.bind(id, vi))
			sbox.add_child(rb)
		vrow.add_child(slot)
	col.add_child(vwrap)

	# —— 限定说明（仅限定鱼）：当前时段能否遇到 ——
	var lim := FishData.limited_of(id)
	if not lim.is_empty():
		var avail := FishData.is_available(id, g.day_phase)
		var night := Color(0.40, 0.47, 0.72)
		var lwrap := PanelContainer.new()
		var lsb := StyleBoxFlat.new()
		lsb.bg_color = Color(night.r, night.g, night.b, 0.16)
		lsb.set_border_width_all(1)
		lsb.border_color = Color(night.r, night.g, night.b, 0.55)
		lsb.set_corner_radius_all(8)
		lsb.set_content_margin_all(8)
		lwrap.add_theme_stylebox_override("panel", lsb)
		var lbox := VBoxContainer.new()
		lbox.add_theme_constant_override("separation", 3)
		lwrap.add_child(lbox)
		var phase_cn := []
		for p in lim.get("phases", []):
			phase_cn.append(Weather.display_name(str(p)))
		var lt := Label.new()
		lt.text = "🌙 限定 · %s　（仅 %s 可遇）" % [str(lim.get("label", "限定鱼")), "／".join(phase_cn)]
		lt.add_theme_font_size_override("font_size", 13)
		lt.add_theme_color_override("font_color", Color(0.82, 0.86, 0.97))
		lbox.add_child(lt)
		var la := Label.new()
		la.text = ("✓ 此刻正当时，快去钓！" if avail else "✗ 当前不可遇，换到对应时段再来")
		la.add_theme_font_size_override("font_size", 12)
		la.add_theme_color_override("font_color", Color(0.66, 0.84, 0.60) if avail else Color(0.90, 0.66, 0.54))
		lbox.add_child(la)
		if lim.has("hint"):
			var lh := Label.new()
			lh.text = "「%s」" % str(lim["hint"])
			lh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lh.custom_minimum_size = Vector2(470, 0)
			lh.add_theme_font_size_override("font_size", 11)
			lh.add_theme_color_override("font_color", Color(0.72, 0.74, 0.82))
			lbox.add_child(lh)
		col.add_child(lwrap)

	# —— 巨物赛 banner（该鱼是本周目标时）——
	if Competition.is_target(g, id):
		var gold := Color(1.0, 0.82, 0.32)
		var cwrap := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(gold.r, gold.g, gold.b, 0.14)
		csb.set_border_width_all(1)
		csb.border_color = Color(gold.r, gold.g, gold.b, 0.6)
		csb.set_corner_radius_all(8)
		csb.set_content_margin_all(8)
		cwrap.add_theme_stylebox_override("panel", csb)
		var cbox := VBoxContainer.new()
		cbox.add_theme_constant_override("separation", 3)
		cwrap.add_child(cbox)
		var ct := Label.new()
		ct.text = "🏆 本周巨物赛 · 目标鱼"
		ct.add_theme_font_size_override("font_size", 13)
		ct.add_theme_color_override("font_color", Color(0.98, 0.86, 0.50))
		cbox.add_child(ct)
		var cl := Label.new()
		cl.text = Competition.status_line(g)
		cl.add_theme_font_size_override("font_size", 12)
		cl.add_theme_color_override("font_color", Color(0.70, 0.92, 0.72) if bool(g.competition.get("claimed", false)) else Color(0.88, 0.84, 0.74))
		cbox.add_child(cl)
		col.add_child(cwrap)

	# —— 按钮：百科外链 + 返回图鉴 ——
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	if lore.has("wiki"):
		var wb := Button.new()
		wb.text = "百科 ↗"
		wb.custom_minimum_size = Vector2(0, 32)
		wb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apply_button_skin(wb, true)
		var wurl := "https://zh.wikipedia.org/wiki/" + str(lore["wiki"])
		wb.pressed.connect(func() -> void:
			Audio.play_ui("ui_click")
			OS.shell_open(wurl))
		btns.add_child(wb)
	var bb := Button.new()
	bb.text = "← 返回图鉴"
	bb.custom_minimum_size = Vector2(0, 32)
	bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button_skin(bb, false)
	bb.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		g._set_catch_tab(1))
	btns.add_child(bb)
	col.add_child(btns)


static func _kv_card(rows: Array) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", paper_style(0.90))
	var mg := MarginContainer.new()
	for s in ["left", "right"]:
		mg.add_theme_constant_override("margin_" + s, 10)
	for s in ["top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 7)
	card.add_child(mg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	mg.add_child(box)
	for r in rows:
		var row := HBoxContainer.new()
		var k := Label.new()
		k.text = str(r[0])
		k.custom_minimum_size = Vector2(74, 0)
		k.add_theme_font_size_override("font_size", 12)
		k.add_theme_color_override("font_color", Color(0.50, 0.47, 0.40))
		row.add_child(k)
		var val := Label.new()
		val.text = str(r[1])
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.add_theme_font_size_override("font_size", 13)
		val.add_theme_color_override("font_color", Color(0.26, 0.25, 0.22))
		row.add_child(val)
		box.add_child(row)
	return card


static func _photo_credit(id: String) -> String:
	var path := "res://assets/art/fish_photos/CREDITS.json"
	if not FileAccess.file_exists(path):
		return "📷 Wikimedia Commons"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "📷 Wikimedia Commons"
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY and data.has(id):
		var c: Dictionary = data[id]
		var author := str(c.get("author", "")).split("\n")[0]
		return "📷 %s · %s · 维基共享资源" % [author, str(c.get("license", ""))]
	return "📷 Wikimedia Commons"


static var _dex_tier := -1   # 图鉴品阶筛选：-1=全部，0-5=各品阶

static func fill_dex_tab(g: CornerFishing, v: VBoxContainer) -> void:
	var vc := 0  # 已收集稀有变体数（每种鱼 ×3 稀有）
	for id in g.dex:
		var vm := int(g.dex[id].get("vmask", 0))
		for vi in range(1, FishData.VARIANT_NAMES.size()):
			if vm & (1 << vi):
				vc += 1
	var vtotal := FishData.FISH.size() * (FishData.VARIANT_NAMES.size() - 1)
	var stat := Label.new()
	stat.text = "收集 %d/%d　·　变体 %d/%d　·　鳞 %d/%d/%d　·　渔获 %d" % [
		g.dex.size(), FishData.FISH.size(), vc, vtotal,
		int(g.scales[0]), int(g.scales[1]), int(g.scales[2]), g.lifetime_catches]
	stat.add_theme_font_size_override("font_size", DT.FS_XS)
	stat.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(stat)

	# near-miss：本水域图鉴缺口一行金字（就差几种！），集齐则安静地不显示
	var sp := spot_species_progress(g, g.current_spot)
	if int(sp[1]) > 0 and int(sp[0]) < int(sp[1]):
		var near := Label.new()
		near.text = "🎯 %s还差 %d 种集齐" % [SpotData.display_name(g.current_spot), int(sp[1]) - int(sp[0])]
		near.add_theme_font_size_override("font_size", DT.FS_XS)
		near.add_theme_color_override("font_color", DT.GOLD)
		v.add_child(near)

	# 品阶筛选 seg（CD：全部 + 6 品阶，品阶 pill 用品阶色）
	var tier_names := ["普通", "优良", "稀有", "史诗", "传说", "神话"]
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", DT.CHIP_GAP)
	var allb := Button.new()
	allb.text = "全部"
	apply_tab_skin(allb, _dex_tier == -1)
	if _dex_tier != -1:
		allb.pressed.connect(func() -> void:
			_dex_tier = -1
			g._open_panel("catch"))
	seg.add_child(allb)
	for t in range(6):
		var tb := Button.new()
		tb.text = tier_names[t]
		apply_tab_skin(tb, _dex_tier == t, DT.tier_color(t))
		if _dex_tier != t:
			tb.pressed.connect(func(tt = t) -> void:
				_dex_tier = tt
				g._open_panel("catch"))
		seg.add_child(tb)
	v.add_child(seg)

	var ids := FishData.FISH.keys()
	ids.sort_custom(func(a, b): return FishData.tier_of(a) < FishData.tier_of(b))
	if _dex_tier >= 0:
		ids = ids.filter(func(id): return FishData.tier_of(id) == _dex_tier)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 296)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 填满 sheet 高度（带框）
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 10 if g.display_mode != "immersive" else 5   # 带框全宽 sheet → 更密
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", DT.SP_2)
	grid.add_theme_constant_override("v_separation", DT.SP_2)
	for id in ids:
		grid.add_child(dex_card(g, str(id)))
	sc.add_child(grid)
	v.add_child(sc)


static func dex_card(g: CornerFishing, id: String) -> Control:
	var known := g.dex.has(id)
	var tier := FishData.tier_of(id)
	var tc := g._ui_tier_color(tier, false)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(0, 82)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := dark_row_style(0.40)
	sb.set_border_width_all(1)
	sb.border_color = Color(tc.r, tc.g, tc.b, 0.7) if known else DT.GLASS_ROW_BORDER
	cell.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	cell.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	margin.add_child(box)
	var icon := g._fish_icon(id, 38)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.modulate = Color(1, 1, 1, 1.0) if known else Color(0, 0, 0, 0.34)  # 未发现=黑剪影
	box.add_child(icon)
	var nm := Label.new()
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	if known and not FishData.limited_of(id).is_empty():
		nm.text = "🌙" + FishData.display_name(id)   # 限定鱼月亮徽标
	else:
		nm.text = FishData.display_name(id) if known else "？？？"
	nm.add_theme_font_size_override("font_size", DT.FS_MICRO)
	nm.add_theme_color_override("font_color", tc if known else DT.TEXT_FAINT_GLASS)
	box.add_child(nm)
	# 变体收集圆点（CD .vdots：斑斓/鎏金/七彩）
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 3)
	dots.custom_minimum_size = Vector2(0, 8)
	var vm := int(g.dex.get(id, {}).get("vmask", 0)) if known else 0
	for vi in range(1, FishData.VARIANT_NAMES.size()):
		var d := Label.new()
		d.text = "●"
		d.add_theme_font_size_override("font_size", DT.FS_MICRO - 1)
		var on := (vm & (1 << vi)) != 0
		d.add_theme_color_override("font_color", FishData.variant_color(vi) if on else Color(1, 1, 1, 0.14))
		dots.add_child(d)
	box.add_child(dots)
	if known:
		var r: Dictionary = g.dex[id]
		var tip := "%s · ×%d" % [FishData.display_name(id), int(r["n"])]
		if float(r["w"]) > 0.0:
			tip += " · 最大 %.2fkg" % float(r["w"])
		if int(r["n"]) >= 10:
			tip += " · ✦集齐"
		if bool(r.get("big", false)):
			tip += " · 巨"
		if bool(r.get("perf", false)):
			tip += " · 完★"
		cell.tooltip_text = tip
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Audio.play_ui("ui_click")
				g._open_fish_detail(id))
	return cell


## 卡片小字描边：彩色徽章/纪录叠在浅米黄纸背景上时一眼可读
## （保留各自颜色语义，只补一圈暖墨细描边把字「托」起来）。
static func badge_legible(lbl: Label) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0.16, 0.12, 0.08, 0.92))
	lbl.add_theme_constant_override("outline_size", 2)


static func dex_badges(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	var n := int(r["n"])
	var col10 := Label.new()
	col10.add_theme_font_size_override("font_size", 10)
	if n >= 10:
		col10.text = "✦集齐"
		col10.add_theme_color_override("font_color", Color(0.97, 0.82, 0.38))
	else:
		col10.text = "%d/10" % n
		col10.add_theme_color_override("font_color", Color(0.62, 0.58, 0.50))
	badge_legible(col10)
	row.add_child(col10)
	if bool(r.get("big", false)):
		var b := Label.new()
		b.text = "巨"
		b.add_theme_font_size_override("font_size", 10)
		b.add_theme_color_override("font_color", Color(0.95, 0.70, 0.36))
		badge_legible(b)
		row.add_child(b)
	if bool(r.get("perf", false)):
		var p := Label.new()
		p.text = "完★"
		p.add_theme_font_size_override("font_size", 10)
		p.add_theme_color_override("font_color", Color(0.84, 0.66, 0.95))
		badge_legible(p)
		row.add_child(p)
	# 稀有变体收集点（斑斓/鎏金/七彩）：已见亮色圆点
	var vm := int(r.get("vmask", 0))
	for vi in range(1, FishData.VARIANT_NAMES.size()):
		if vm & (1 << vi):
			var d := Label.new()
			d.text = "●"
			d.add_theme_font_size_override("font_size", 10)
			d.add_theme_color_override("font_color", FishData.variant_color(vi))
			badge_legible(d)
			row.add_child(d)
	return row


# ============================ 升级页（鱼竿/鱼饵/鱼钩）============================

# CD .row —— 带缩略图的列表行；返回 [panel, hbox]，调用方往 hbox 追加右侧控件（pill/按钮）
static func list_row(thumb_path: String, title: String, sub: String, highlight := false) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := dark_row_style(0.52)
	sb.set_corner_radius_all(DT.R_CELL)
	if highlight:
		sb.set_border_width_all(2)
		sb.border_color = DT.GOLD
	panel.add_theme_stylebox_override("panel", sb)
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 11)
	mg.add_theme_constant_override("margin_right", 11)
	mg.add_theme_constant_override("margin_top", 8)
	mg.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(mg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	mg.add_child(row)
	if thumb_path != "" and ResourceLoader.exists(thumb_path):
		var thumb := TextureRect.new()
		thumb.texture = load(thumb_path)
		thumb.custom_minimum_size = Vector2(40, 36)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(thumb)
	else:
		var thumb_fallback := ColorRect.new()
		thumb_fallback.color = Color(1, 1, 1, 0.86)
		thumb_fallback.custom_minimum_size = Vector2(40, 36)
		row.add_child(thumb_fallback)
	var grow := VBoxContainer.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grow.add_theme_constant_override("separation", 1)
	var nm := Label.new()
	nm.text = title
	nm.add_theme_font_size_override("font_size", DT.FS_SM)
	nm.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	grow.add_child(nm)
	if sub != "":
		var sl := Label.new()
		sl.text = sub
		sl.add_theme_font_size_override("font_size", DT.FS_2XS)
		sl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grow.add_child(sl)
	row.add_child(grow)
	return [panel, row]


static func _equip_btn(row: HBoxContainer, text: String, enabled: bool, primary: bool, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(56, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", DT.FS_XS)
	apply_button_skin(b, primary)
	if enabled:
		b.pressed.connect(cb)
	row.add_child(b)


static func _equip_cost_btn(row: HBoxContainer, qty: String, cost: String, enabled: bool, primary: bool, cb: Callable) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(64, 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 2)
	var q := Label.new()
	q.text = qty
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_font_size_override("font_size", DT.FS_2XS)
	q.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	box.add_child(q)
	var b := Button.new()
	b.text = cost
	b.custom_minimum_size = Vector2(64, 32)
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", DT.FS_XS)
	apply_button_skin(b, primary)
	if enabled:
		b.pressed.connect(cb)
	box.add_child(b)
	row.add_child(box)


static func _compact_cost(n) -> String:
	var value := float(n)
	var abs_n := absf(value)
	if abs_n >= 10000:
		return _short_number_cost(value, 3)
	return _commas_local(int(round(value)))


static func _short_number_cost(value: float, sig_digits := 3) -> String:
	if is_nan(value) or value == 0.0:
		return "0"
	var abs_v := absf(value)
	var tier := int(floor(log(abs_v) / log(1000.0)))
	if tier <= 0:
		return _commas_local(int(round(value)))
	if tier >= CornerFishing.SHORT_NUMBER_UNITS.size():
		return _sci_cost(value, sig_digits)
	var suffix: String = CornerFishing.SHORT_NUMBER_UNITS[tier]
	var scaled := value / pow(1000.0, tier)
	var abs_scaled := absf(scaled)
	if abs_scaled >= 100.0:
		return "%d%s" % [int(round(scaled)), suffix]
	if abs_scaled >= 10.0:
		return "%.1f%s" % [snappedf(scaled, 0.1), suffix]
	return "%.2f%s" % [snappedf(scaled, 0.01), suffix]


static func _sci_cost(value: float, sig_digits := 3) -> String:
	if is_nan(value) or value == 0.0:
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


static func _commas_local(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out


static func _section(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", DT.FS_XS)
	l.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	l.custom_minimum_size = Vector2(0, 22)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	v.add_child(l)


static func fill_upgrades(g: CornerFishing, v: VBoxContainer) -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 360)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", DT.SP_2)
	sc.add_child(list)

	# 鱼竿（线性升级）。数字明牌：当前值 → 下一级值（概率型升级不亮数字就永远"无感"）
	var rc := g._rod_cost()
	var rod_sub := "咬钩 %.1fs · 卖价 +%d%%" % [g._avg_wait_for(g.rod_level), (g.rod_level - 1) * 8]
	if g.rod_level < 16:
		rod_sub += "　→ 升级后 %.1fs · +%d%%" % [g._avg_wait_for(g.rod_level + 1), g.rod_level * 8]
	else:
		rod_sub += "　→ 升级后 +%d%%（咬钩已封顶）" % (g.rod_level * 8)
	var rod := list_row("res://assets/art/equipment/rod_carbon.png", "鱼竿 Lv.%d" % g.rod_level, rod_sub, true)
	rod[0].tooltip_text = "决定稀有度：越高级越易上高阶鱼"
	_equip_btn(rod[1], "升级 %s" % _compact_cost(rc), g.coins >= rc, true, g._try_upgrade_rod)
	list.add_child(rod[0])

	_section(list, "属性装备 · 逐步揭露（装备 → 角色属性）")
	_add_attribute_equipment_rows(g, list)

	# 鱼饵（决定星级品质）
	_section(list, "鱼饵 · 决定星级品质（卖价倍率 ×1.8/×4/×8）")
	for i in FishData.BAITS.size():
		var b: Dictionary = FishData.BAITS[i]
		var probs: Array = b["probs"]
		var bp1 := float(probs[1])
		var bp2 := float(probs[2])
		var bp3 := float(probs[3])
		var sub := "★ %d%% · ★★ %.1f%% · ★★★ %.2f%%" % [bp1 * 100.0, bp1 * bp2 * 100.0, bp1 * bp2 * bp3 * 100.0]
		var cur := i == g.bait_level
		var rw := list_row("res://assets/art/equipment/bait_jar.png", str(b["name"]), sub, cur)
		rw[0].tooltip_text = str(b.get("desc", ""))
		if cur:
			rw[1].add_child(make_pill("使用中", DT.GOLD, DT.INK_ON_GOLD))
		elif i == g.bait_level + 1:
			var bcost := int(b["cost"])
			_equip_btn(rw[1], "升级 %s" % _compact_cost(bcost), g.coins >= bcost, true, g._try_upgrade_bait)
		elif i < g.bait_level:
			rw[1].add_child(make_pill("已超越", DT.GLASS_ROW_HOVER, DT.TEXT_MUTED_GLASS))
		else:
			rw[1].add_child(make_pill("🔒 %s" % _compact_cost(int(b["cost"])), DT.GLASS_ROW, DT.TEXT_FAINT_GLASS))
		list.add_child(rw[0])

	# 鱼钩（决定双钩几率）
	_section(list, "鱼钩 · 决定双钩几率（一次钓上两条）")
	for i in FishData.HOOKS.size():
		var h: Dictionary = FishData.HOOKS[i]
		var sub := "%s · 双钩 %d%%" % [h.get("desc", ""), int(float(h["double"]) * 100.0)]
		var cur := i == g.hook_level
		var rw := list_row("res://assets/art/equipment/hook_basic.png", str(h["name"]), sub, cur)
		if cur:
			rw[1].add_child(make_pill("使用中", DT.GOLD, DT.INK_ON_GOLD))
		elif i == g.hook_level + 1:
			var hcost := int(h["cost"])
			_equip_btn(rw[1], "升级 %s" % _compact_cost(hcost), g.coins >= hcost, true, g._try_upgrade_hook)
		elif i < g.hook_level:
			rw[1].add_child(make_pill("已超越", DT.GLASS_ROW_HOVER, DT.TEXT_MUTED_GLASS))
		else:
			rw[1].add_child(make_pill("🔒 %s" % _compact_cost(int(h["cost"])), DT.GLASS_ROW, DT.TEXT_FAINT_GLASS))
		list.add_child(rw[0])

	# 诱饵 / 窝料（变体收集杠杆——段头用收集口径，卖价倍率下沉到行内，防按金币回本误判性价比）
	_section(list, "诱饵 · 变体收集杠杆（越稀有的花色提升越多；重复变体折彩鳞）")
	for i in FishData.LURES.size():
		var lu: Dictionary = FishData.LURES[i]
		var lvb := float(lu["vbias"])
		var lsub := "斑斓 %.1f%% · 鎏金 %.2f%% · 七彩 %.3f%%" % [
			float(FishData.VARIANT_PROBS[1]) * FishData.variant_scale(1, lvb) * 100.0,
			float(FishData.VARIANT_PROBS[2]) * FishData.variant_scale(2, lvb) * 100.0,
			float(FishData.VARIANT_PROBS[3]) * FishData.variant_scale(3, lvb) * 100.0]
		var lcur := i == g.lure_level
		var lrw := list_row("res://assets/art/equipment/tackle_box.png", str(lu["name"]), lsub, lcur)
		lrw[0].tooltip_text = str(lu.get("desc", ""))
		if lcur:
			lrw[1].add_child(make_pill("使用中", DT.GOLD, DT.INK_ON_GOLD))
		elif i == g.lure_level + 1:
			var lcost := int(lu["cost"])
			_equip_btn(lrw[1], "升级 %s" % _compact_cost(lcost), g.coins >= lcost, true, g._try_upgrade_lure)
		elif i < g.lure_level:
			lrw[1].add_child(make_pill("已超越", DT.GLASS_ROW_HOVER, DT.TEXT_MUTED_GLASS))
		else:
			lrw[1].add_child(make_pill("🔒 %s" % _compact_cost(int(lu["cost"])), DT.GLASS_ROW, DT.TEXT_FAINT_GLASS))
		list.add_child(lrw[0])

	# 鱼贩合约（自动贩卖）：一次性买断 + 开关。只带走杂鱼，珍品/收藏/订单永远留给手动。
	_section(list, "鱼贩合约 · 满篓自动卖杂鱼（普通花色 · ≤★ · 稀有以下 · 非巨物；收藏/未交付订单不碰）")
	var asub := "与收鱼郎签长约：在线满篓时按市价自动带走一条最便宜的杂鱼（离线仍走折价兜底）；想留的杂鱼点🔒上锁即不碰"
	if g.auto_sell_bought:
		asub = "已签约 · 累计带走 %d 条 / +%s 金币" % [g.auto_sold_n, g._coin_str(g.auto_sold_v)]
	var arw := list_row("res://assets/art/equipment/coin_pouch.png", "鱼贩合约", asub, g._auto_sell_active())
	if not g.auto_sell_bought:
		_equip_btn(arw[1], "签约 %s" % _compact_cost(g.AUTO_SELL_COST), g.coins >= g.AUTO_SELL_COST, true, g._try_buy_autosell)
	else:
		arw[1].add_child(make_pill("生效中" if g.auto_sell_on else "已暂停",
			DT.GOLD if g.auto_sell_on else DT.GLASS_ROW_HOVER,
			DT.INK_ON_GOLD if g.auto_sell_on else DT.TEXT_MUTED_GLASS))
		_equip_btn(arw[1], "暂停" if g.auto_sell_on else "开启", true, false, g._toggle_autosell)
	list.add_child(arw[0])
	v.add_child(sc)


static func _add_attribute_equipment_rows(g: CornerFishing, list: VBoxContainer) -> void:
	for raw_id in g._visible_equipment_chain():
		var id := str(raw_id)
		if g._equipment_unlocked(id):
			_add_unlocked_attribute_equipment_row(g, list, id)
		else:
			_add_locked_attribute_equipment_row(g, list, id)


static func _add_unlocked_attribute_equipment_row(g: CornerFishing, list: VBoxContainer, id: String) -> void:
	var title := ""
	var icon := ""
	var sub := ""
	var tooltip := ""
	if id == "reel":
		title = "绕线轮 Lv.%d" % g.reel_level
		icon = "res://assets/art/equipment/line_spool.png"
		sub = "玩家速度 %.1f → %.1f" % [g._reel_speed(), g._reel_speed_for(g.reel_level + 1)]
		tooltip = "独立速度装备：通过 speed 属性缩短等待与收竿周期"
	else:
		var info: Dictionary = AnglerEquipment.ATTR_EQUIPMENT[id]
		var lv := g._gear_level(id)
		title = "%s Lv.%d" % [str(info["name"]), lv]
		icon = str(info["icon"])
		sub = _attr_equipment_sub(g, id, lv)
		tooltip = str(info["desc"])
	var row := list_row(icon, title, sub, true)
	row[0].tooltip_text = tooltip
	for cnt in [1, 10, 100]:
		var c := int(cnt)
		var cost := g._reel_upgrade_cost(c) if id == "reel" else g._gear_upgrade_cost(id, c)
		var cb := g._try_upgrade_reel.bind(c) if id == "reel" else g._try_upgrade_attr_gear.bind(id, c)
		_equip_cost_btn(row[1], "+%d 级" % c, _compact_cost(cost), g.coins >= cost, c == 1, cb)
	list.add_child(row[0])


static func _add_locked_attribute_equipment_row(g: CornerFishing, list: VBoxContainer, id: String) -> void:
	var title := "绕线轮" if id == "reel" else str(AnglerEquipment.ATTR_EQUIPMENT[id]["name"])
	var icon := "res://assets/art/equipment/line_spool.png" if id == "reel" else str(AnglerEquipment.ATTR_EQUIPMENT[id]["icon"])
	var cost := g._equipment_unlock_cost(id)
	var sub := "未解锁 · %s · 解锁后 Lv.1" % g._equipment_unlock_note(id)
	var row := list_row(icon, title, sub, false)
	row[0].tooltip_text = "逐步揭露装备：先解锁上一件，再开放这一件"
	_equip_btn(row[1], "解锁 %s" % _compact_cost(cost), g.coins >= cost, true, g._try_unlock_equipment.bind(id))
	list.add_child(row[0])


static func _attr_equipment_sub(g: CornerFishing, id: String, lv: int) -> String:
	var cur = g._gear_stats(id, lv)
	var nxt = g._gear_stats(id, lv + 1)
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
	var attrs: Dictionary = AnglerEquipment.ATTR_EQUIPMENT[id]["attrs"]
	for key in attrs.keys():
		parts.append("%s %.1f→%.1f" % [labels[str(key)], float(cur.get(str(key))), float(nxt.get(str(key)))])
	return " · ".join(parts)


# ============================ 设置 / 引导 / 离线小结 ============================

static func audio_slider(v: VBoxContainer, label: String, value: float, setter: Callable) -> void:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	lbl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(0, 18)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(x: float) -> void: setter.call(x))
	v.add_child(sl)


static func fill_settings(g: CornerFishing, v: VBoxContainer) -> void:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 384)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", DT.SP_3)
	sc.add_child(col)

	# 游玩 / 测试 模式开关（开发期）：开启后展开「测试台」，改昼夜/金钱/鱼等，仅本会话生效、不写档。
	var tm_row := HBoxContainer.new()
	tm_row.add_theme_constant_override("separation", 8)
	var tm_lbl := Label.new()
	tm_lbl.text = "测试模式（开发用）"
	tm_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	tm_lbl.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	tm_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tm_row.add_child(tm_lbl)
	var tm_btn := CheckButton.new()
	tm_btn.button_pressed = g.test_mode
	tm_btn.focus_mode = Control.FOCUS_NONE
	tm_btn.toggled.connect(func(on: bool) -> void: TestMode.set_enabled(g, on))
	tm_row.add_child(tm_btn)
	col.add_child(tm_row)
	if g.test_mode:
		fill_test_console(g, col)
	col.add_child(HSeparator.new())

	# 自动垂钓（原底栏开关迁来）：开=浮标自动起竿/起钩；关=手动操作
	var cast_row := HBoxContainer.new()
	cast_row.add_theme_constant_override("separation", 8)
	var cast_lbl := Label.new()
	cast_lbl.text = "自动垂钓"
	cast_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	cast_lbl.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	cast_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_row.add_child(cast_lbl)
	var cast_btn := CheckButton.new()
	cast_btn.button_pressed = g.auto_cast
	cast_btn.focus_mode = Control.FOCUS_NONE
	cast_btn.toggled.connect(func(on: bool) -> void:
		g.auto_cast = on
		g._update_action_button())
	cast_row.add_child(cast_btn)
	col.add_child(cast_row)
	var cast_hint := Label.new()
	cast_hint.text = "咬钩的瞬间点「起钩！」可亲手起钩（体重 +10%）；稀有鱼会多挣扎几秒等你。不点也照常自动上鱼，永不惩罚。"
	cast_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cast_hint.add_theme_font_size_override("font_size", DT.FS_2XS)
	cast_hint.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
	col.add_child(cast_hint)
	col.add_child(HSeparator.new())

	# 自动卖鱼（付费占位）
	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 8)
	var auto_lbl := Label.new()
	auto_lbl.text = "🔒 自动卖鱼"
	auto_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	auto_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	auto_lbl.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
	auto_row.add_child(auto_lbl)
	auto_row.add_child(make_pill("敬请期待", DT.GLASS_ROW, DT.GOLD))
	col.add_child(auto_row)
	col.add_child(HSeparator.new())

	# 静音
	var mute_row := HBoxContainer.new()
	mute_row.add_theme_constant_override("separation", 8)
	var mute_lbl := Label.new()
	mute_lbl.text = "静音"
	mute_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	mute_lbl.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	mute_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mute_row.add_child(mute_lbl)
	var mute_btn := CheckButton.new()
	mute_btn.button_pressed = Audio.muted
	mute_btn.focus_mode = Control.FOCUS_NONE
	mute_btn.toggled.connect(func(on: bool) -> void:
		Audio.set_muted(on)
		if not on:
			Audio.start_ambience())
	mute_row.add_child(mute_btn)
	col.add_child(mute_row)
	audio_slider(col, "主音量", Audio.master_volume, Audio.set_master_volume)
	audio_slider(col, "音效", Audio.sfx_volume, Audio.set_sfx_volume)
	audio_slider(col, "环境音", Audio.ambience_volume, Audio.set_ambience_volume)
	# 背景音乐单独给一个开关：挂机玩家常常想留着水声、只把曲子关掉，
	# 关掉后音量记忆保留（Audio.music_enabled 与 music_volume 是两个字段）。
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 8)
	var music_lbl := Label.new()
	music_lbl.text = "背景音乐"
	music_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	music_lbl.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	music_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_row.add_child(music_lbl)
	var music_btn := CheckButton.new()
	music_btn.button_pressed = Audio.music_enabled
	music_btn.focus_mode = Control.FOCUS_NONE
	music_btn.toggled.connect(func(on: bool) -> void: Audio.set_music_enabled(on))
	music_row.add_child(music_btn)
	col.add_child(music_row)
	audio_slider(col, "音乐音量", Audio.music_volume, Audio.set_music_volume)
	col.add_child(HSeparator.new())

	# 专注模式
	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 8)
	var focus_lbl := Label.new()
	focus_lbl.text = "专注模式（少打扰）"
	focus_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	focus_lbl.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	focus_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_row.add_child(focus_lbl)
	var focus_btn := CheckButton.new()
	focus_btn.button_pressed = g.focus_mode
	focus_btn.focus_mode = Control.FOCUS_NONE
	focus_btn.toggled.connect(func(on: bool) -> void:
		g._set_focus(on)
		g._save())
	focus_row.add_child(focus_btn)
	col.add_child(focus_row)
	col.add_child(HSeparator.new())

	# 水彩纸纹（画面质感层开关；实时生效，方便对比 / 定强度）
	var paper_row := HBoxContainer.new()
	paper_row.add_theme_constant_override("separation", 8)
	var paper_lbl := Label.new()
	paper_lbl.text = "水彩纸纹"
	paper_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	paper_lbl.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	paper_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper_row.add_child(paper_lbl)
	var paper_btn := CheckButton.new()
	paper_btn.button_pressed = g.paper_grain
	paper_btn.focus_mode = Control.FOCUS_NONE
	paper_btn.toggled.connect(func(on: bool) -> void:
		g._set_paper_grain(on)
		g._save())
	paper_row.add_child(paper_btn)
	col.add_child(paper_row)
	col.add_child(HSeparator.new())

	# 不透明度
	var ol := Label.new()
	ol.text = "不透明度"
	ol.add_theme_font_size_override("font_size", DT.FS_SM)
	ol.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	col.add_child(ol)
	var sl := HSlider.new()
	sl.min_value = 0.3
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = g._opacity
	sl.custom_minimum_size = Vector2(0, 18)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(g._set_opacity)
	col.add_child(sl)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)
	col.add_child(HSeparator.new())

	# 界面缩放（带框模式整窗等比放大，小字一起变大；不改布局、不会错位）
	var ui_lbl := Label.new()
	ui_lbl.text = "界面缩放 · 当前 %d%%" % int(round(g.ui_scale * 100.0))
	ui_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	ui_lbl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	col.add_child(ui_lbl)
	var ui_row := HBoxContainer.new()
	ui_row.add_theme_constant_override("separation", DT.SP_2)
	for s in g.UI_SCALE_OPTIONS:
		var sb := Button.new()
		sb.text = "%d%%" % int(round(s * 100.0))
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.custom_minimum_size = Vector2(0, 30)
		var active: bool = is_equal_approx(g.ui_scale, s)
		apply_tab_skin(sb, active)
		if not active:
			sb.pressed.connect(func() -> void:
				g._set_ui_scale(s)
				g._save()
				g._refresh_panel())   # 重建设置页 → 高亮跳到新档
		ui_row.add_child(sb)
	col.add_child(ui_row)
	var ui_hint := Label.new()
	ui_hint.text = "点档位，或直接拖窗口边角自由缩放（怎么拖都等比不变形）"
	ui_hint.add_theme_font_size_override("font_size", DT.FS_2XS)
	ui_hint.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
	col.add_child(ui_hint)
	var gap_ui := Control.new()
	gap_ui.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap_ui)

	# 帧率（挂件默认 30 省电；可调高换更顺滑的画面，更耗电）
	var fps_lbl := Label.new()
	fps_lbl.text = "帧率"
	fps_lbl.add_theme_font_size_override("font_size", DT.FS_SM)
	fps_lbl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	col.add_child(fps_lbl)
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", DT.SP_2)
	for fps in g.FPS_OPTIONS:
		var fb := Button.new()
		fb.text = str(fps)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.custom_minimum_size = Vector2(0, 30)
		apply_tab_skin(fb, g.max_fps == fps)
		if g.max_fps != fps:
			fb.pressed.connect(func() -> void:
				g._set_max_fps(fps)
				g._save()
				g._refresh_panel())   # 重建设置页 → 高亮跳到新选项
		fps_row.add_child(fb)
	col.add_child(fps_row)
	var fps_hint := Label.new()
	fps_hint.text = "数字越高画面越顺滑，也越耗电"
	fps_hint.add_theme_font_size_override("font_size", DT.FS_2XS)
	fps_hint.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
	col.add_child(fps_hint)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap2)

	# 窗口
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", DT.SP_3)
	var reset := Button.new()
	reset.text = "回到右下角"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.custom_minimum_size = Vector2(0, 34)
	apply_button_skin(reset, false)
	reset.pressed.connect(g._place_corner)
	br.add_child(reset)
	var quit := Button.new()
	quit.text = "退出游戏"
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.custom_minimum_size = Vector2(0, 34)
	apply_button_skin(quit, false)
	quit.pressed.connect(g._quit_game)
	br.add_child(quit)
	col.add_child(br)

	# 开启新存档（开发期：清空进度回到全新开局）。两点确认防误触：首点变红警示，3.5s 内再点执行。
	col.add_child(HSeparator.new())
	var ns_hint := Label.new()
	ns_hint.text = "开发期：存档无价值，可随时清空重开"
	ns_hint.add_theme_font_size_override("font_size", DT.FS_2XS)
	ns_hint.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
	col.add_child(ns_hint)
	var ns_armed := [false]   # 装箱布尔：lambda 跨次按可改写状态
	var ns := Button.new()
	ns.text = "开启新存档"
	ns.focus_mode = Control.FOCUS_NONE
	ns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ns.custom_minimum_size = Vector2(0, 34)
	apply_button_skin(ns, false)
	ns.pressed.connect(func() -> void:
		if ns_armed[0]:
			g._new_save()
			return
		ns_armed[0] = true
		ns.text = "⚠ 再点一次：清空进度并新建"
		ns.modulate = Color(1.0, 0.62, 0.52)   # 红调警示
		g.get_tree().create_timer(3.5).timeout.connect(func() -> void:
			if is_instance_valid(ns):
				ns_armed[0] = false
				ns.text = "开启新存档"
				ns.modulate = Color(1, 1, 1)))
	col.add_child(ns)
	v.add_child(sc)


# ============================ 测试台（开发期，逻辑见 test_mode.gd）============================

## 设置页内的测试台：仅 g.test_mode 时渲染。改昼夜/金钱/鱼/装备/触发，全部即时生效、不写档。
static func fill_test_console(g: CornerFishing, col: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", DT.SP_2)
	col.add_child(box)
	var tip := Label.new()
	tip.text = "🧪 测试台 · 改动仅本会话生效，回游玩模式即还原正式档"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", DT.FS_2XS)
	tip.add_theme_color_override("font_color", DT.GOLD_BRIGHT)
	box.add_child(tip)
	var attrs_btn := Button.new()
	attrs_btn.text = "打开属性面板"
	attrs_btn.custom_minimum_size = Vector2(0, 34)
	attrs_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button_skin(attrs_btn, false)
	attrs_btn.pressed.connect(func() -> void: g._set_dev_attrs_open(true))
	box.add_child(attrs_btn)

	# —— 时间 / 节奏 ——
	_test_head(box, "昼夜时段")
	var phase_row := _test_row(box)
	for ph in Weather.ORDER:
		var phase_id: String = ph
		_test_seg(phase_row, Weather.display_name(phase_id), g._forced_phase == phase_id,
			func() -> void: TestMode.force_phase(g, phase_id))
	_test_seg(phase_row, "跟随时钟", g._forced_phase == "", func() -> void: TestMode.follow_clock(g))

	_test_head(box, "钓鱼提速")
	var sp_row := _test_row(box)
	for i in TestMode.SPEED_OPTIONS.size():
		var mult: float = TestMode.SPEED_OPTIONS[i]
		_test_seg(sp_row, str(TestMode.SPEED_LABELS[i]), is_equal_approx(g.test_speed, mult),
			func() -> void: TestMode.set_speed(g, mult))

	# —— 经济 ——
	_test_head(box, "金币")
	var coin_row := _test_row(box)
	_test_seg(coin_row, "+1k", false, func() -> void: TestMode.add_coins(g, 1000))
	_test_seg(coin_row, "+10k", false, func() -> void: TestMode.add_coins(g, 10000))
	_test_seg(coin_row, "+100k", false, func() -> void: TestMode.add_coins(g, 100000))
	_test_seg(coin_row, "清零", false, func() -> void: TestMode.zero_coins(g))

	_test_head(box, "装备 · 背包（上行 +1，下行 拉满）")
	var gear_defs := [["rod", "鱼竿"], ["bait", "鱼饵"], ["hook", "鱼钩"], ["bag", "背包"]]
	var gear_row := _test_row(box)
	for d in gear_defs:
		var kind: String = d[0]
		_test_seg(gear_row, str(d[1]) + "+1", false, func() -> void: TestMode.bump_gear(g, kind, false))
	var gear_row2 := _test_row(box)
	for d in gear_defs:
		var kind2: String = d[0]
		_test_seg(gear_row2, str(d[1]) + "满", false, func() -> void: TestMode.bump_gear(g, kind2, true))

	_test_head(box, "速度装备 · 绕线轮（测试版可升可降）")
	var reel_info := Label.new()
	reel_info.text = "Lv.%d · 速度 %.1f · 一竿 %.2fs · 倍率 %.0f%%" % [
		g.reel_level, g._reel_speed(), g._avg_wait_for_reel(g.reel_level), g._speed_wait_mult() * 100.0]
	reel_info.add_theme_font_size_override("font_size", DT.FS_2XS)
	reel_info.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	box.add_child(reel_info)
	var reel_row := _test_row(box)
	_test_seg(reel_row, "-100", false, func() -> void: TestMode.bump_reel(g, -100))
	_test_seg(reel_row, "-10", false, func() -> void: TestMode.bump_reel(g, -10))
	_test_seg(reel_row, "-1", false, func() -> void: TestMode.bump_reel(g, -1))
	_test_seg(reel_row, "+1", false, func() -> void: TestMode.bump_reel(g, 1))
	_test_seg(reel_row, "+10", false, func() -> void: TestMode.bump_reel(g, 10))
	_test_seg(reel_row, "+100", false, func() -> void: TestMode.bump_reel(g, 100))
	var reel_row2 := _test_row(box)
	for target in [0, 10, 50, 100, 250]:
		var lv := int(target)
		_test_seg(reel_row2, "设%d" % lv, g.reel_level == lv, func() -> void: TestMode.set_reel(g, lv))

	# —— 鱼 / 收集 ——
	_test_head(box, "给指定鱼")
	_test_fish_picker(g, box)
	var fish_row := _test_row(box)
	_test_seg(fish_row, "样本包", false, func() -> void: TestMode.sample_pack(g))
	_test_seg(fish_row, "清空鱼篓", false, func() -> void: TestMode.clear_bag(g))
	var coll_row := _test_row(box)
	_test_seg(coll_row, "解锁全部钓点", false, func() -> void: TestMode.unlock_all_spots(g))
	_test_seg(coll_row, "点亮全图鉴", false, func() -> void: TestMode.fill_dex(g))

	# —— 系统触发 ——
	_test_head(box, "系统触发")
	var sys_row := _test_row(box)
	_test_seg(sys_row, "召唤鱼贩", false, func() -> void: TestMode.summon_merchant(g))
	_test_seg(sys_row, "重置订单", false, func() -> void: TestMode.reroll_order(g))
	_test_seg(sys_row, "专注充能", false, func() -> void: TestMode.charge_focus(g, 2))
	var ev_list := Events.eligible(g)
	if ev_list.is_empty():
		var none := Label.new()
		none.text = "（当前钓点暂无可触发事件）"
		none.add_theme_font_size_override("font_size", DT.FS_2XS)
		none.add_theme_color_override("font_color", DT.TEXT_FAINT_GLASS)
		box.add_child(none)
	else:
		var ev_row := _test_row(box)
		for eid in ev_list:
			var id: String = eid
			_test_seg(ev_row, EventData.display_name(id), false,
				func() -> void: TestMode.fire_event(g, id))


## 测试台分区小标题。
static func _test_head(col: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", DT.FS_2XS)
	l.add_theme_color_override("font_color", DT.GOLD)
	col.add_child(l)


## 测试台等宽按钮行容器。
static func _test_row(col: VBoxContainer) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", DT.SP_2)
	col.add_child(r)
	return r


## 测试台小分段按钮：active 高亮（沿用页签皮肤），填充等宽。
static func _test_seg(row: HBoxContainer, text: String, active: bool, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 28)
	apply_tab_skin(b, active)
	b.pressed.connect(cb)
	row.add_child(b)


## 「给鱼」选择器：鱼种（按品阶→名排序）+ 星级 + 变体 + 给鱼。选择记在 g 上，重建面板不丢。
static func _test_fish_picker(g: CornerFishing, col: VBoxContainer) -> void:
	var ids := FishData.FISH.keys()
	ids.sort_custom(func(a, b):
		var ta := FishData.tier_of(str(a))
		var tb := FishData.tier_of(str(b))
		if ta != tb:
			return ta < tb
		return str(a) < str(b))
	if g._test_pick_fish == "" or not FishData.FISH.has(g._test_pick_fish):
		g._test_pick_fish = str(ids[0]) if not ids.is_empty() else ""
	var fish_ob := OptionButton.new()
	fish_ob.focus_mode = Control.FOCUS_NONE
	fish_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fish_ob.custom_minimum_size = Vector2(0, 28)
	for i in ids.size():
		var id: String = str(ids[i])
		fish_ob.add_item("%s｜%s" % [FishData.TIER_NAMES[FishData.tier_of(id)], FishData.display_name(id)], i)
		fish_ob.set_item_metadata(i, id)
		if id == g._test_pick_fish:
			fish_ob.select(i)
	fish_ob.item_selected.connect(func(idx: int) -> void:
		g._test_pick_fish = str(fish_ob.get_item_metadata(idx)))
	col.add_child(fish_ob)

	var qv_row := _test_row(col)
	var q_ob := OptionButton.new()
	q_ob.focus_mode = Control.FOCUS_NONE
	q_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_ob.custom_minimum_size = Vector2(0, 28)
	var q_names := ["无星", "上品★", "极品★★", "完美★★★"]
	for i in q_names.size():
		q_ob.add_item(q_names[i], i)
	q_ob.select(clampi(g._test_pick_q, 0, q_names.size() - 1))
	q_ob.item_selected.connect(func(idx: int) -> void: g._test_pick_q = idx)
	qv_row.add_child(q_ob)

	var v_ob := OptionButton.new()
	v_ob.focus_mode = Control.FOCUS_NONE
	v_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_ob.custom_minimum_size = Vector2(0, 28)
	var v_names := ["普通", "斑斓", "鎏金", "七彩"]
	for i in v_names.size():
		v_ob.add_item(v_names[i], i)
	v_ob.select(clampi(g._test_pick_var, 0, v_names.size() - 1))
	v_ob.item_selected.connect(func(idx: int) -> void: g._test_pick_var = idx)
	qv_row.add_child(v_ob)

	var give := Button.new()
	give.text = "给鱼"
	give.focus_mode = Control.FOCUS_NONE
	give.custom_minimum_size = Vector2(64, 28)
	apply_button_skin(give, true)
	give.pressed.connect(func() -> void:
		TestMode.give_fish(g, g._test_pick_fish, g._test_pick_q, g._test_pick_var))
	qv_row.add_child(give)


## 【新增】开场世界观动画：讲完故事再决定谁出发。逐页播、可跳过。
## g._story_step 记住播到第几页；点「下一句」重建面板翻下一页，最后一页直达选人页。
static func fill_story(g: CornerFishing, v: VBoxContainer) -> void:
	var pages := [
		"有个朋友，最近总是不在工位上。",
		"倒不是摸鱼——是真的人不在。年假攒够那天，他/她把电脑一合，说走就走，一头扎进了地图里。",
		"行李不多：一根鱼竿，一顶帐篷，剩下全靠现场发挥。路线也没规划，走到哪儿钓到哪儿。",
		"从家门口那道再普通不过的河湾，一路钓到深海、钓到珊瑚礁、钓到没手机信号的溶洞——地图有多大，鱼篓就有多杂。",
		"他/她说好了：每到一个新地方，随手钓的第一条像样的鱼，都「云」寄一份记录回来给你看看。",
		"你不用出门，也不用一直盯着——桌角这方小水塘，就是那份「远程连线」。他/她在外面钓，这边替你把日子撑住。",
		"故事讲完了。出发前，先定一件正事——这一趟，派谁去？",
	]
	var idx: int = clampi(g._story_step, 0, pages.size() - 1)
	var body := Label.new()
	body.text = pages[idx]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(380, 0)
	body.add_theme_font_size_override("font_size", DT.FS_BODY)
	body.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	v.add_child(body)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	# 页码点：走了几步一眼看到，纯装饰不可点。
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 6)
	for i in pages.size():
		var d := PanelContainer.new()
		d.custom_minimum_size = Vector2(6, 6)
		var dsb := StyleBoxFlat.new()
		dsb.set_corner_radius_all(3)
		dsb.bg_color = DT.GOLD if i == idx else DT.GLASS_ROW
		d.add_theme_stylebox_override("panel", dsb)
		dots.add_child(d)
	v.add_child(dots)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if idx < pages.size() - 1:
		var skip := Button.new()
		skip.text = "跳过"
		skip.custom_minimum_size = Vector2(0, 36)
		skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apply_button_skin(skip, false)
		skip.pressed.connect(func() -> void:
			g._story_step = pages.size() - 1
			g._open_panel("story"))
		row.add_child(skip)
		var next := Button.new()
		next.text = "下一句"
		next.custom_minimum_size = Vector2(0, 36)
		next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apply_button_skin(next, true)
		next.pressed.connect(func() -> void:
			g._story_step += 1
			g._open_panel("story"))
		row.add_child(next)
	else:
		var go := Button.new()
		go.text = "开始选人"
		go.custom_minimum_size = Vector2(0, 36)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		apply_button_skin(go, true)
		go.pressed.connect(func() -> void:
			g._open_panel("character"))
		row.add_child(go)
	v.add_child(row)


## 【新增】选背包客：Jim / Ganie 二选一，纯人设文案，不影响任何数值。
static func fill_character(g: CornerFishing, v: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "选好了就出发——往后收到的「路上消息」都会是这位的口气。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(380, 0)
	hint.add_theme_font_size_override("font_size", DT.FS_SM)
	hint.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
	v.add_child(hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap)
	for cid in ["jim", "ganie"]:
		var c := CharacterData.get_character(cid)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", paper_style(0.9))
		var mg := MarginContainer.new()
		for s in ["left", "top", "right", "bottom"]:
			mg.add_theme_constant_override("margin_" + s, 10)
		card.add_child(mg)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		mg.add_child(cv)
		var nm := Label.new()
		nm.text = "%s · %s" % [str(c.get("name", "")), str(c.get("tag", ""))]
		nm.add_theme_font_size_override("font_size", DT.FS_HEAD)
		nm.add_theme_color_override("font_color", DT.INK)
		cv.add_child(nm)
		var bl := Label.new()
		bl.text = str(c.get("blurb", ""))
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(340, 0)
		bl.add_theme_font_size_override("font_size", DT.FS_XS)
		bl.add_theme_color_override("font_color", DT.INK_SOFT)
		cv.add_child(bl)
		var pick := Button.new()
		pick.text = "就 %s 了，出发！" % str(c.get("name", ""))
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(0, 34)
		apply_button_skin(pick, true)
		pick.pressed.connect(func() -> void:
			g.player_character = cid
			g.chosen_character = true
			g._save()
			g._story_step = 0
			g._open_panel("intro"))
		cv.add_child(pick)
		v.add_child(card)


static func fill_intro(g: CornerFishing, v: VBoxContainer) -> void:
	var who := CharacterData.display_name(g.player_character)
	var tips := [
		"· 浮标是自动的——%s 把竿子往这儿一插，剩下的交给手气。" % who,
		"· 钓到的鱼自动进「鱼篓」，右下角 🐟 点开能卖钱、翻图鉴、看订单 / 成就。",
		"· 🎣 鱼竿页管装备升级：鱼竿(稀有度) / 鱼饵(星级) / 鱼钩(双钩) / 诱饵(稀有变体)。",
		"· ⚙ 设置里能调音量、开专注模式，或者重新出发（新开一局）。",
		"· 按住场景空白处能把这方小水塘拖到桌面任意角落，随手一放。",
		"· 撞上金色「收鱼郎」或蓝色「鱼汛」记得多留意——限时加成，错过了下次再等。",
	]
	for t in tips:
		var l := Label.new()
		l.text = t
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(360, 0)
		l.add_theme_font_size_override("font_size", DT.FS_SM)
		l.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
		v.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	var btn := Button.new()
	btn.text = "好，开始钓"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 36)
	apply_button_skin(btn, true)
	btn.pressed.connect(func() -> void:
		g.seen_intro = true
		g._save()
		g._close_panel())
	v.add_child(btn)


static func fill_offline_report(g: CornerFishing, v: VBoxContainer) -> void:
	var rep := g._offline_report
	var hi := Label.new()
	hi.text = "欢迎回来，钓友"
	hi.add_theme_font_size_override("font_size", DT.FS_HEAD)
	hi.add_theme_color_override("font_color", DT.TEXT_TITLE)
	v.add_child(hi)
	var line := Label.new()
	line.text = "离线 %s，挂竿钓得 %d 条入篓%s" % [
		str(rep.get("dur", "")), int(rep.get("count", 0)),
		"（鱼篓已满）" if bool(rep.get("full", false)) else ""]
	line.add_theme_color_override("font_color", DT.TEXT_ON_GLASS)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(360, 0)
	v.add_child(line)
	var top: Dictionary = rep.get("top", {})
	if not top.is_empty():
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", paper_style(0.9))
		var mg := MarginContainer.new()
		for s in ["left", "top", "right", "bottom"]:
			mg.add_theme_constant_override("margin_" + s, 8 if s in ["left", "right"] else 6)
		card.add_child(mg)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		mg.add_child(row)
		row.add_child(g._fish_icon(str(top["id"]), 48))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		var t := FishData.tier_of(str(top["id"]))
		var nm := Label.new()
		nm.text = "最值钱 · %s %s%s" % [FishData.TIER_NAMES[t],
			FishData.size_tag(str(top["id"]), float(top["w"])), FishData.display_name(str(top["id"]))]
		nm.add_theme_color_override("font_color", g._ui_tier_color(t, true))
		info.add_child(nm)
		var meta := Label.new()
		meta.text = "%.2fkg · %s 金币%s" % [float(top["w"]), g._coin_str(int(top["v"])),
			"（已折价兑金，不在篓中）" if bool(rep.get("top_folded", false)) else ""]
		meta.add_theme_font_size_override("font_size", 12)
		meta.add_theme_color_override("font_color", Color(0.5, 0.46, 0.4))
		info.add_child(meta)
		row.add_child(info)
		v.add_child(card)
	var total := Label.new()
	total.text = "合计可卖 ≈ %s 金币（已入鱼篓，去卖出变现）" % g._coin_str(int(rep.get("value", 0)))
	total.add_theme_color_override("font_color", Color(0.72, 0.58, 0.28))
	total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	total.custom_minimum_size = Vector2(360, 0)
	v.add_child(total)
	var ov_n := int(rep.get("overflow_n", 0))
	if ov_n > 0:
		var ov := Label.new()
		ov.text = "鱼篓装满后，另有 %d 条折价兑成 +%s 金币（已自动入账）" % [ov_n, g._coin_str(int(rep.get("overflow_v", 0)))]
		ov.add_theme_font_size_override("font_size", DT.FS_XS)
		ov.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
		ov.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ov.custom_minimum_size = Vector2(360, 0)
		v.add_child(ov)
	var notable: Array = rep.get("notable", [])
	if not notable.is_empty():
		var nlbl := Label.new()
		var n_total := int(rep.get("notable_n", notable.size()))
		nlbl.text = ("其中珍稀 %d 条，价值最高的 %d 条：" % [n_total, notable.size()]) \
			if n_total > notable.size() else ("其中珍稀 %d 条：" % n_total)
		nlbl.add_theme_font_size_override("font_size", DT.FS_XS)
		nlbl.add_theme_color_override("font_color", DT.TEXT_MUTED_GLASS)
		v.add_child(nlbl)
		var shown := 0
		for c in notable:
			if shown >= 6:
				break
			var t2 := FishData.tier_of(str(c["id"]))
			var rl := Label.new()
			rl.text = "· %s%s%s %.2fkg%s" % [FishData.quality_label(int(c.get("q", 0))),
				FishData.TIER_NAMES[t2] + "·", FishData.display_name(str(c["id"])), float(c["w"]),
				"（已兑金）" if bool(c.get("folded", false)) else ""]
			rl.add_theme_font_size_override("font_size", 12)
			rl.add_theme_color_override("font_color", g._ui_tier_color(t2, false))
			v.add_child(rl)
			shown += 1
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	var go := Button.new()
	go.text = "去鱼篓看看"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(0, 34)
	apply_button_skin(go, true)
	go.pressed.connect(func() -> void:
		g._offline_report = {}
		g._catch_tab = 0
		g._open_panel("catch"))
	v.add_child(go)
