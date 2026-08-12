# Relationship Visit Dialogue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把河湾到访页重构为聊天记录式剧情与抉择界面，并把偏好按好感阶段隐藏在人情簿中。

**Architecture:** `relationship_data.gd` 提供偏好揭示与安全反馈纯函数；`main.gd` 负责一次性事务和运行时反馈态；`ui_panels.gd` 只负责对话记录、当前动作、按需鱼篓与反馈结束按钮。现有 v24 存档不增加字段，反馈态仅在当前运行时存在。

**Tech Stack:** Godot 4.6、GDScript、项目内 `tools/validate_game.gd` 回归与 `tools/dev_screenshot.gd` 视觉验证。

## Global Constraints

- 不生成新图片，继续使用 `assets/art/character/npc/` 中已有五张 NPC 水彩图。
- 到访页不得展示好感、完整偏好、近况计数、终章方向或永久奖励资料。
- 人情簿偏好阈值固定为：好感 0–1 未知、2–3 模糊、4–6 完整。
- 所有结算动作进入反馈态后必须幂等，反馈态只允许“结束这次到访”。
- `main.tscn` 与 `ui_layout.json` 的现有未提交改动属于 Owner，本计划不得覆盖或提交。
- 每次只 `git add` 明确文件，完整验证必须为 0 失败。

---

### Task 1: 偏好阶段揭示数据接口

**Files:**
- Modify: `relationship_data.gd`
- Test: `tools/validate_game.gd`

**Interfaces:**
- Produces: `preference_stage(favor: int) -> int`
- Produces: `preference_text(npc: Dictionary, favor: int) -> String`
- Produces: `gift_feedback(npc_id: String, catch: Dictionary, accepted: bool) -> String`

- [ ] **Step 1: 写失败回归**

在 `_check_relationship_foundation()` 中加入：

```gdscript
var lin := RelationshipDataScript.get_npc("lin_aunt")
_assert(RelationshipDataScript.preference_text(lin, 0) == "???",
    "低好感时人物偏好应完全隐藏")
_assert(RelationshipDataScript.preference_text(lin, 2) == str(lin["likes_hint"]),
    "中段好感应只显示模糊偏好线索")
_assert(RelationshipDataScript.preference_text(lin, 4) == str(lin["likes"]),
    "高段好感才应显示完整偏好")
var rejected := RelationshipDataScript.gift_feedback("lin_aunt", {"id": "sardine"}, false)
_assert(not rejected.contains(str(lin["likes"])),
    "送错鱼的反馈不得泄露完整偏好")
```

- [ ] **Step 2: 运行完整验证并确认红灯**

Run: `'/Applications/Godot.app/Contents/MacOS/Godot' --headless --log-file /tmp/relationship-dialogue-red-data.log -s tools/validate_game.gd`

Expected: 因 `preference_text` / `gift_feedback` 尚不存在而失败。

- [ ] **Step 3: 实现三段偏好接口**

为五名 NPC 增加 `likes_hint`，并加入：

```gdscript
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
        return "%s收下了%s，神情明显柔和下来。" % [str(npc.get("name", "对方")), fish_name]
    if bool(catch.get("lock", false)):
        return "这条鱼还被你仔细留着，先别拿来送人。"
    return "%s摆摆手：这条还是留给更合适的人吧。" % str(npc.get("name", "对方"))
```

- [ ] **Step 4: 运行完整验证并确认绿灯**

Run: 同 Step 2。

Expected: `=== 结果: 0 失败 ===`。

- [ ] **Step 5: 提交数据层**

```bash
git add relationship_data.gd tools/validate_game.gd
git commit -m "分阶段揭示人物偏好" -m "低好感隐藏具体口味，送错反馈不再泄露答案。" -m "Co-Authored-By: GPT-5 <noreply@openai.com>"
```

### Task 2: 事务反馈态与幂等边界

**Files:**
- Modify: `main.gd`
- Modify: `relationship_data.gd`
- Test: `tools/validate_game.gd`

**Interfaces:**
- Produces: `relationship_visit_feedback: Dictionary`
- Produces: `relationship_visit_notice: String`
- Produces: `relationship_picker_open: bool`
- Produces: `_show_relationship_feedback(text: String, tone := "neutral") -> void`
- Produces: `_finish_relationship_visit_feedback() -> void`
- Produces: `_decline_relationship_buff() -> void`
- Consumes: Task 1 `gift_feedback(...)`

- [ ] **Step 1: 写失败回归**

为成功送礼、剧情确认、Buff 接受和委托完成各断言一次：

```gdscript
restored._relationship_gift(0)
_assert(not restored.relationship_visit_feedback.is_empty(),
    "送礼结算后应保留 NPC 对话反馈")
var inventory_after := restored.inventory.size()
restored._relationship_gift(0)
_assert(restored.inventory.size() == inventory_after,
    "反馈态重复触发不得再次扣鱼")
_assert(restored.selected_relationship_visit_id == "lin_aunt",
    "反馈结束前应保留当前 NPC 供页面显示")
```

对 Buff 婉拒加入：

```gdscript
restored._decline_relationship_buff()
_assert((restored.relationship_state.get("buff", {}) as Dictionary).is_empty(),
    "婉拒帮忙不得写入 Buff")
_assert(not restored.relationship_visit_feedback.is_empty(),
    "婉拒后应显示 NPC 告别反馈")
```

- [ ] **Step 2: 运行完整验证并确认红灯**

Run: `'/Applications/Godot.app/Contents/MacOS/Godot' --headless --log-file /tmp/relationship-dialogue-red-feedback.log -s tools/validate_game.gd`

Expected: 缺少反馈态接口，或旧实现清空 NPC 并关闭面板。

- [ ] **Step 3: 增加运行时反馈状态**

在 `main.gd` 增加：

```gdscript
var relationship_visit_feedback := {}
var relationship_visit_notice := ""
var relationship_picker_open := false

func _show_relationship_feedback(text: String, tone := "neutral") -> void:
    if not relationship_visit_feedback.is_empty():
        return
    relationship_visit_feedback = {"text": text, "tone": tone}
    _update_relationship_visit_bar()
    _update_hud()
    _open_panel("relationship_visit")

func _finish_relationship_visit_feedback() -> void:
    relationship_visit_feedback = {}
    selected_relationship_visit_id = ""
    _close_panel()
```

`_open_relationship_visit()` 每次打开新到访前清空旧反馈、失败提示和选鱼展开态。所有成功事务移除到访并保存，但不清空 `selected_relationship_visit_id`、不直接 `_close_panel()`；改为调用 `_show_relationship_feedback(...)`。函数入口先检查 `relationship_visit_feedback`，非空时立即返回，形成幂等护栏。

- [ ] **Step 4: 实现 Buff 婉拒**

```gdscript
func _decline_relationship_buff() -> void:
    if not relationship_visit_feedback.is_empty():
        return
    var npc_id := selected_relationship_visit_id
    var visits: Dictionary = relationship_state.get("visits", {})
    if str((visits.get(npc_id, {}) as Dictionary).get("kind", "")) != "buff":
        return
    visits.erase(npc_id)
    relationship_state["visits"] = visits
    _save()
    _show_relationship_feedback("没事，需要时再喊我。", "neutral")
```

- [ ] **Step 5: 保留失败校验的可继续选择语义**

鱼索引失效、委托鱼不匹配和终章鱼不匹配时，把安全失败文案写入 `relationship_visit_notice`，保留到访与当前抉择，并调用 `_open_panel("relationship_visit")` 刷新对话；玩家下一次点击有效鱼前清空该提示。送礼不合口味继续沿用“错失本次机会”，移除到访后进入拒绝反馈态。所有拒绝文案必须通过数据层安全文案，不能拼接原始 `likes`。

- [ ] **Step 6: 运行完整验证并确认绿灯**

Run: 同 Step 2。

Expected: `=== 结果: 0 失败 ===`，并且新增幂等断言通过。

- [ ] **Step 7: 提交事务层**

```bash
git add main.gd relationship_data.gd tools/validate_game.gd
git commit -m "让人情结算停留在对话反馈态" -m "选择后先展示 NPC 回复，再由玩家确认结束到访。" -m "Co-Authored-By: GPT-5 <noreply@openai.com>"
```

### Task 3: 人情簿偏好归位与到访对话布局

**Files:**
- Modify: `ui_panels.gd`
- Test: `tools/validate_game.gd`

**Interfaces:**
- Consumes: Task 1 `preference_text(...)`
- Consumes: Task 2 `relationship_visit_feedback`、`relationship_visit_notice`、`relationship_picker_open`、`_finish_relationship_visit_feedback()`、`_decline_relationship_buff()`
- Produces UI nodes: `RelationshipDialogueLog`、`RelationshipDecisionArea`、`RelationshipFishPicker`、`RelationshipFeedback`、`RelationshipFeedbackEnd`

- [ ] **Step 1: 写失败 UI 回归**

依次打开好感 0、2、4 的人情簿，检查 `RelationshipPreference_<id>` 文本；打开到访页后检查：

```gdscript
var dialogue := g._panel.find_child("RelationshipDialogueLog", true, false)
var decision := g._panel.find_child("RelationshipDecisionArea", true, false)
_assert(dialogue != null and decision != null,
    "到访页应使用对话记录和当前抉择区")
_assert(g._panel.find_child("RelationshipVisitMeta", true, false) == null,
    "到访页不应展示好感与偏好资料")
_assert(g._panel.find_child("RelationshipVisitFinaleInfo", true, false) == null,
    "到访页不应展示终章资料")
```

结算后重建页面并断言：

```gdscript
_assert(g._panel.find_child("RelationshipFeedback", true, false) != null,
    "结算后应追加 NPC 回复")
_assert(g._panel.find_child("RelationshipDecisionArea", true, false) == null,
    "反馈态不应继续显示原抉择")
_assert(g._panel.find_child("RelationshipFeedbackEnd", true, false) != null,
    "反馈态只保留结束按钮")
```

- [ ] **Step 2: 运行完整验证并确认红灯**

Run: `'/Applications/Godot.app/Contents/MacOS/Godot' --headless --log-file /tmp/relationship-dialogue-red-ui.log -s tools/validate_game.gd`

Expected: 新节点不存在，且旧到访页仍含 meta / finale 信息。

- [ ] **Step 3: 人情簿使用阶段偏好**

将人物卡偏好改为单独命名 Label：

```gdscript
var preference := Label.new()
preference.name = "RelationshipPreference_%s" % id
preference.text = "偏好：%s" % RelationshipDataScript.preference_text(
    npc, int(state.get("favor", 0)))
```

好感和近况继续在人情簿展示；到访页不再读取 `favor` 或 `npc["likes"]`。

- [ ] **Step 4: 构建聊天记录式到访头部**

用 `RelationshipPortraitScript.make(npc, "card")`、姓名和“当前到访”组成紧凑头部；创建 `RelationshipDialogueLog`，把 `visit_title()` 与 `visit_body()` 拆成连续对话行。移除旧 `meta` 和 `finale` Label。

- [ ] **Step 5: 构建当前抉择与按需鱼篓**

创建 `RelationshipDecisionArea`。闲谈、委托与终章默认只显示“挑一条鱼／交付一条鱼／登记一条鱼”和“稍后”；点击主动作后设置 `relationship_picker_open = true` 并调用 `_open_panel("relationship_visit")`，随后显示 `RelationshipFishPicker`。若 `relationship_visit_notice` 非空，把它作为最新 NPC 对话行显示，同时保留动作区。剧情显示“记下了／稍后”，Buff 显示“接受帮忙／婉拒／稍后”。

- [ ] **Step 6: 构建反馈态**

当 `relationship_visit_feedback` 非空时，在对话末尾添加 `RelationshipFeedback`，不再创建任何原动作或鱼篓，只创建 `RelationshipFeedbackEnd`，按钮调用 `_finish_relationship_visit_feedback()`。

- [ ] **Step 7: 运行完整验证并确认绿灯**

Run: 同 Step 2。

Expected: `=== 结果: 0 失败 ===`，三段偏好和对话／反馈节点全部通过。

- [ ] **Step 8: 提交 UI 层**

```bash
git add ui_panels.gd tools/validate_game.gd
git commit -m "将到访页改为聊天抉择界面" -m "长期资料回归人情簿，到访只呈现当前剧情与反馈。" -m "Co-Authored-By: GPT-5 <noreply@openai.com>"
```

### Task 4: 五类视觉验证与文档同步

**Files:**
- Modify: `tools/dev_screenshot.gd`
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `BACKLOG.md`
- Test: `tools/validate_game.gd`

**Interfaces:**
- Consumes: Tasks 1–3 完成后的五类到访与反馈态。

- [ ] **Step 1: 扩充截图场景**

在 `tools/dev_screenshot.gd` 中保留现有剧情、Buff、终章截图，并增加闲谈选鱼、普通委托与选择后反馈态截图。每次截图前明确设置 `selected_relationship_visit_id`、`relationship_state["visits"]`、`relationship_visit_feedback` 与鱼篓样本。

- [ ] **Step 2: 运行截图工具**

Run: `'/Applications/Godot.app/Contents/MacOS/Godot' --path . -s tools/dev_screenshot.gd`

Expected: 剧情、闲谈、委托、Buff、终章与反馈态截图全部生成，无脚本错误。

- [ ] **Step 3: 逐张视觉检查**

检查 NPC 图正常、对话顺序清楚、到访页无好感／完整偏好／终章资料、当前抉择突出、鱼篓仅在展开态出现、反馈态只有结束按钮，并恢复与本任务无关的截图噪声。

- [ ] **Step 4: 同步三份文档**

`README.md` 说明到访改为聊天抉择、长期资料归人情簿、偏好三段揭示；`ROADMAP.md` 在河湾人情簿已完成项补记；`BACKLOG.md` 新增 Owner 对话化与偏好隐藏决策。

- [ ] **Step 5: 最终完整验证**

Run: `'/Applications/Godot.app/Contents/MacOS/Godot' --headless --log-file /tmp/relationship-dialogue-final.log -s tools/validate_game.gd`

Expected: `=== 结果: 0 失败 ===`。

- [ ] **Step 6: 检查明确文件并提交**

```bash
git diff --check
git add tools/dev_screenshot.gd README.md ROADMAP.md BACKLOG.md
git commit -m "补齐到访对话化验证与文档" -m "覆盖五类到访、反馈态与偏好揭示。" -m "Co-Authored-By: GPT-5 <noreply@openai.com>"
```

- [ ] **Step 7: 推送并创建叠加 PR**

```bash
git push -u origin feat/relationship-visit-dialogue
gh pr create --base fix/relationship-image-fallback --head feat/relationship-visit-dialogue --title "重构河湾到访为对话抉择" --body $'## 改了什么\n- 到访页改为聊天记录式剧情与当前抉择\n- 好感、近况、终章和偏好资料集中到人情簿\n- 偏好按好感三阶段揭示\n- 选择后展示 NPC 反馈，再由玩家结束到访\n\n## 为什么\n到访应专注此刻的剧情和选择，不应重复展示人物资料。\n\n## 怎么验证\n- Godot 全量验证：0 失败\n- 已检查剧情、闲谈、委托、Buff、终章与反馈态截图'
```

PR 正文必须包含“改了什么／为什么／怎么验证”，注明基于 PR #28 的叠加关系与 `validate_game.gd` 0 失败。
