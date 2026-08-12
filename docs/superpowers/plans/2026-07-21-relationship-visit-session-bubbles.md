# Relationship Visit Session and Bubble Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate relationship-visit state leakage and render the current visit as non-overlapping, single-row WeChat-style NPC and player bubbles.

**Architecture:** Replace the four loose transient fields with one non-persistent visit-session dictionary whose identity is tied to the current NPC and visit payload. Route every visit entry and exit through lifecycle helpers, while panel-only rebuilds preserve the active session. Build each NPC message and player option as its own full-width `HBoxContainer` inside a vertical message stream.

**Tech Stack:** Godot 4.6, GDScript, existing `UIPanels` builders, `RelationshipPortrait`, `tools/validate_game.gd`, `tools/dev_screenshot.gd`.

## Global Constraints

- Do not generate or replace NPC artwork; reuse the existing five portraits and `head_crop` regions.
- Every message and every reply option owns an independent full-width row; no manual Y positioning, negative spacing, or overlapping anchors.
- NPC messages are left aligned with a circular portrait; player options and sent replies are right aligned.
- Visit-session state is transient and must not be added to save data.
- Preserve the current relationship rewards, favor progression, visit scheduling, and fish-consumption rules.
- Do not modify or stage the Owner's local `main.tscn` or `ui_layout.json` changes.

---

### Task 1: Unify the transient visit-session lifecycle

**Files:**
- Modify: `main.gd:157-160, 1378-1570, 3190-3200`
- Modify: `test_mode.gd:276-310, 396-404`
- Test: `tools/validate_game.gd:1290-1450, 2740-2780`

**Interfaces:**
- Produces: `relationship_visit_session: Dictionary`
- Produces: `_begin_relationship_visit_session(npc_id: String) -> void`
- Produces: `_end_relationship_visit_session() -> void`
- Produces: `_relationship_visit_session_matches(npc_id: String, visit: Dictionary) -> bool`
- Produces: `_set_relationship_visit_reply(text: String, phase: String) -> void`
- Consumes: `relationship_state["visits"]`, `RelationshipData.make_visit(...)`, and the existing `_open_panel("relationship_visit")` rebuild path.

- [ ] **Step 1: Write failing lifecycle regressions**

Add assertions to the relationship section of `tools/validate_game.gd` that create a dirty session for 林阿姨, open 周叔 through the real entry helper, and verify every transient value is reset:

```gdscript
g.relationship_state["visits"]["zhou_uncle"] = RelationshipDataScript.make_visit(
	"zhou_uncle", "buff", g._relationship_now())
g.relationship_visit_session = {
	"npc_id": "lin_aunt", "visit_key": "stale", "phase": "feedback",
	"player_reply": "好，我记住了。", "notice": "旧提示",
	"feedback": {"text": "旧反馈", "tone": "good"},
}
g._open_relationship_visit("zhou_uncle")
_assert(str(g.relationship_visit_session.get("npc_id", "")) == "zhou_uncle" \
	and str(g.relationship_visit_session.get("phase", "")) == "decision" \
	and str(g.relationship_visit_session.get("player_reply", "")) == "" \
	and str(g.relationship_visit_session.get("notice", "")) == "" \
	and (g.relationship_visit_session.get("feedback", {}) as Dictionary).is_empty(),
	"切换 NPC 时必须建立干净的到访会话")
```

Add a second regression that sets `phase = "picker"`, closes the relationship panel through `g._close_panel()`, reopens the same visit, and expects a fresh `decision` phase rather than the old picker state. Add a third assertion that calls `TestMode.open_relationship_visit(g, "lin_aunt")` after dirtying another NPC's session and expects the same clean initialization.

- [ ] **Step 2: Run the validation and verify RED**

Run:

```bash
'/Applications/Godot.app/Contents/MacOS/Godot' --headless --log-file /tmp/corner-fishing-session-red.log -s tools/validate_game.gd
```

Expected: validation fails because `relationship_visit_session` and its lifecycle helpers do not exist, or because the old loose fields survive the alternate entry/close paths.

- [ ] **Step 3: Implement the minimal session object and identity**

In `main.gd`, replace the loose feedback, notice, and picker fields with one transient dictionary while retaining `selected_relationship_visit_id` only as a compatibility selector during this task:

```gdscript
var selected_relationship_visit_id := ""
var relationship_visit_session: Dictionary = {}


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
```

Make `_open_relationship_visit(npc_id)` call `_begin_relationship_visit_session(npc_id)` before opening the panel. Make `_finish_relationship_visit_feedback()` call `_end_relationship_visit_session()`. In `_close_panel()`, capture whether `_panel_kind == "relationship_visit"`, close the panel, then end the session only for a real user close. Do not change `UIPanels.open_panel()` rebuilding, because it calls `UIPanels.close_panel(g, true)` directly and must preserve the session.

- [ ] **Step 4: Move all transient reads and writes into the session**

Replace every visit action's loose-field access with the session keys:

```gdscript
if not (relationship_visit_session.get("feedback", {}) as Dictionary).is_empty():
	return

relationship_visit_session["notice"] = "这条鱼已经不在鱼篓里了。"

relationship_visit_session["feedback"] = {"text": text, "tone": tone}
relationship_visit_session["phase"] = "feedback"
relationship_visit_session["notice"] = ""
```

Before each story, gift, task, buff, and finale mutation, reject the action unless the current session matches the selected NPC's current visit. This ensures a stale callback cannot settle a newly replaced visit.

- [ ] **Step 5: Route development tools through the lifecycle**

In `test_mode.gd`, change both `summon_relationship_visit(...)` and `open_relationship_visit(...)` to call:

```gdscript
g._open_relationship_visit(npc_id)
```

after creating the visit, instead of assigning `selected_relationship_visit_id` and opening the panel directly. Make `clear_relationship_visits(...)` call `g._end_relationship_visit_session()` before refreshing the UI.

- [ ] **Step 6: Run validation and verify GREEN**

Run the same headless command. Expected: `=== 结果: 0 失败 ===`, including the new switch-NPC, close/reopen, and test-mode assertions.

- [ ] **Step 7: Commit the lifecycle fix**

```bash
git add main.gd test_mode.gd tools/validate_game.gd
git commit -m "修复到访临时状态串线" \
  -m "统一所有入口与退出路径的会话生命周期。" \
  -m "Co-Authored-By: GPT-5 Codex <noreply@openai.com>"
```

---

### Task 2: Render independent NPC and player bubble rows

**Files:**
- Modify: `ui_panels.gd:579-770`
- Modify: `relationship_portrait.gd` only if the existing `circle` mode cannot produce a 36 px avatar without changing card/hero behavior
- Test: `tools/validate_game.gd:1290-1380`

**Interfaces:**
- Consumes: Task 1 session keys `phase`, `player_reply`, `notice`, and `feedback`.
- Produces: `_relationship_npc_message_row(parent, npc, message, node_name := "") -> HBoxContainer`
- Produces: `_relationship_player_message_row(parent, message, clickable, primary, on_pressed := Callable()) -> HBoxContainer`
- Produces node names: `RelationshipNpcMessageRow`, `RelationshipNpcAvatar`, `RelationshipNpcBubble`, `RelationshipPlayerMessageRow`, `RelationshipPlayerBubble`, and `RelationshipReplyOption`.

- [ ] **Step 1: Write failing bubble-structure tests**

After opening a story visit in `tools/validate_game.gd`, assert independent row ownership:

```gdscript
var npc_row := g._panel.find_child("RelationshipNpcMessageRow", true, false)
var npc_avatar := g._panel.find_child("RelationshipNpcAvatar", true, false)
var npc_bubble := g._panel.find_child("RelationshipNpcBubble", true, false)
var reply_rows := g._panel.find_children("RelationshipReplyOption", "HBoxContainer", true, false)
_assert(npc_row is HBoxContainer and npc_avatar != null and npc_bubble != null,
	"NPC 消息应使用独立整行的圆形头像与左侧气泡")
_assert(reply_rows.size() == 2 and reply_rows[0].get_parent() == reply_rows[1].get_parent() \
	and reply_rows[0] != reply_rows[1],
	"每个玩家回复选项应独占一条消息行")
_assert(npc_row.get_parent() == reply_rows[0].get_parent(),
	"NPC 与玩家消息行应由同一纵向消息流自然排版")
```

Add a recursive geometry assertion after two process frames: sort the visible message rows by their index in the vertical container and verify `previous.position.y + previous.size.y <= next.position.y`. This directly catches the reported Y-axis overlap.

- [ ] **Step 2: Run validation and verify RED**

Run the headless validator. Expected: failures report missing bubble-row nodes and/or overlapping reply layout because the current implementation uses a shared action `HBoxContainer`.

- [ ] **Step 3: Build the NPC message row**

Replace `_relationship_dialogue_line(...)` with a row builder shaped as follows:

```gdscript
static func _relationship_npc_message_row(parent: VBoxContainer, npc: Dictionary,
		message: String, node_name := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "RelationshipNpcMessageRow" if node_name == "" else node_name
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var avatar := RelationshipPortraitScript.make(npc, "circle")
	avatar.name = "RelationshipNpcAvatar"
	avatar.custom_minimum_size = Vector2(36, 36)
	row.add_child(avatar)
	var bubble := PanelContainer.new()
	bubble.name = "RelationshipNpcBubble"
	bubble.custom_minimum_size.x = 120
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bubble.add_theme_stylebox_override("panel", paper_style())
	row.add_child(bubble)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	bubble.add_child(margin)
	var label := Label.new()
	label.custom_minimum_size.x = 280
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", DT.INK)
	margin.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	return row
```

The fixed 280 px label width leaves room for the 36 px avatar and card margins inside the 520 px panel; autowrap grows only the current row vertically. Do not set `position.y` anywhere in the message builder.

- [ ] **Step 4: Build clickable and sent player rows**

Create one full-width row per choice:

```gdscript
static func _relationship_player_message_row(parent: VBoxContainer, message: String,
		clickable: bool, primary: bool, on_pressed := Callable()) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "RelationshipReplyOption" if clickable else "RelationshipPlayerMessageRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if clickable:
		var bubble := Button.new()
		bubble.name = "RelationshipPlayerBubble"
		bubble.text = message
		bubble.focus_mode = Control.FOCUS_NONE
		apply_button_skin(bubble, primary)
		bubble.pressed.connect(func() -> void:
			Audio.play_ui("ui_click")
			on_pressed.call())
		row.add_child(bubble)
	else:
		var bubble := PanelContainer.new()
		bubble.name = "RelationshipPlayerBubble"
		bubble.add_theme_stylebox_override("panel", _relationship_sent_bubble_style())
		row.add_child(bubble)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 9)
		margin.add_theme_constant_override("margin_bottom", 9)
		bubble.add_child(margin)
		var label := Label.new()
		label.text = message
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("26301D"))
		margin.add_child(label)
	parent.add_child(row)
	return row
```

Add the exact non-interactive sent style:

```gdscript
static func _relationship_sent_bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("A8C879")
	style.set_corner_radius_all(14)
	style.corner_radius_top_right = 4
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("C7D99B")
	return style
```

The sent bubble is a `PanelContainer`, so it cannot remain interactive after selection.

- [ ] **Step 5: Drive the message stream from the session phase**

In `fill_relationship_visit(...)`:

1. Render the current NPC prompt as an NPC message row.
2. If `player_reply` is non-empty, render it as a sent player row.
3. If `feedback` is non-empty, render the feedback as the next NPC row and show only the finish action.
4. If `phase == "picker"`, render the fish picker below the sent reply.
5. Otherwise render each reply with a separate call to `_relationship_player_message_row(...)`.

Before invoking the existing action handlers, set the exact reply and phase:

```gdscript
g._set_relationship_visit_reply("好，我记住了。", "feedback")
g._complete_relationship_story()
```

For fish selection replies use phase `picker`; for “先收起来。” reset `player_reply` to an empty string and phase to `decision`; for real close call `g._close_panel()` so Task 1 destroys the session.

- [ ] **Step 6: Run validation and verify GREEN**

Run the full headless validator. Expected: `0 失败`, all message rows have non-overlapping vertical geometry, and existing relationship transaction tests remain green.

- [ ] **Step 7: Commit the bubble UI**

```bash
git add ui_panels.gd relationship_portrait.gd tools/validate_game.gd
git commit -m "将到访回复改为单行聊天气泡" \
  -m "NPC 左侧头像发言，玩家选项逐行右对齐且不再重叠。" \
  -m "Co-Authored-By: GPT-5 Codex <noreply@openai.com>"
```

---

### Task 3: Visual fixtures, documentation, and final verification

**Files:**
- Modify: `tools/dev_screenshot.gd:90-150`
- Modify: `README.md:92`
- Modify: `ROADMAP.md:55`
- Modify: `BACKLOG.md:8-40`
- Update: `docs/img/panel_relationship_visit.png`
- Update: `docs/img/panel_relationship_buff.png`
- Update: `docs/img/panel_relationship_gift.png`
- Update: `docs/img/panel_relationship_task.png`
- Update: `docs/img/panel_relationship_feedback.png`

**Interfaces:**
- Consumes: Task 1 lifecycle helpers and Task 2 message-row node names.
- Produces: deterministic visual fixtures for decision, picker, Buff, and feedback phases.

- [ ] **Step 1: Update screenshot setup to use public lifecycle paths**

Replace direct assignments to loose visit state with calls such as:

```gdscript
_main._open_relationship_visit("lin_aunt")
_main._set_relationship_visit_reply("好，我记住了。", "feedback")
_main._show_relationship_feedback("好，那我就放心了。\n已记录：河边第一壶茶", "good")
```

Keep the existing five-head screenshot. Add or retain deterministic screenshots for story choices, Buff choices, fish picker, and selected-reply-plus-feedback.

- [ ] **Step 2: Generate and inspect screenshots**

Run:

```bash
'/Applications/Godot.app/Contents/MacOS/Godot' --path . -s tools/dev_screenshot.gd
```

Inspect the relationship images. Required observations: each NPC bubble has a 36 px circular head crop, every reply occupies a separate right-aligned row, long text grows its own row, and the feedback row begins below the sent player row with no Y overlap.

- [ ] **Step 3: Restore unrelated generated images**

Use explicit `git restore -- docs/img/<file>` arguments for every unrelated screenshot touched by the script. Remove only the untracked `docs/img/panel_stats_debug.png`. Do not restore or stage `main.tscn` or `ui_layout.json`.

- [ ] **Step 4: Synchronize project documentation**

Update README and ROADMAP to state that visit UI now uses independent left/right bubble rows and a visit-scoped transient session. Add a dated BACKLOG decision explaining that full-width row ownership prevents overlap and unified lifecycle prevents cross-visit leakage.

- [ ] **Step 5: Run final verification**

Run:

```bash
git diff --check
'/Applications/Godot.app/Contents/MacOS/Godot' --headless --log-file /tmp/corner-fishing-session-bubbles-final.log -s tools/validate_game.gd
```

Expected: no whitespace errors and `=== 结果: 0 失败 ===`.

- [ ] **Step 6: Commit the fixtures and docs**

```bash
git add tools/dev_screenshot.gd README.md ROADMAP.md BACKLOG.md \
  docs/img/panel_relationship_visit.png \
  docs/img/panel_relationship_buff.png \
  docs/img/panel_relationship_gift.png \
  docs/img/panel_relationship_task.png \
  docs/img/panel_relationship_feedback.png
git commit -m "补齐到访气泡截图与文档" \
  -m "记录会话隔离和逐行聊天布局的最终行为。" \
  -m "Co-Authored-By: GPT-5 Codex <noreply@openai.com>"
```

- [ ] **Step 7: Push the existing feature branch**

```bash
git push origin feat/relationship-visit-dialogue
```

Expected: the existing stacked pull request updates without modifying `main` directly.
