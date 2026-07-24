# Relationship Head Crop and Dialogue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让右侧到访气泡清晰显示五名 NPC 的头部，并把到访双方文案统一为第一人称短对白。

**Architecture:** `relationship_data.gd` 保存逐人 `head_crop` 与对话真值；`relationship_portrait.gd` 只在 `circle` 模式创建安全的 `AtlasTexture`；`ui_panels.gd` 移除系统标题行并使用短回复按钮。截图工具负责同时展示五个头部气泡和各类对话页。

**Tech Stack:** Godot 4.6、GDScript、AtlasTexture、项目内验证与截图工具。

## Global Constraints

- 不生成、复制或覆盖任何 NPC 图片。
- `card` / `hero` 继续显示完整图片，只有 `circle` 使用 `head_crop`。
- 玩家回复尽可能短，且必须是会说出口的话。
- 保留 Owner 未提交的 `main.tscn` 与 `ui_layout.json`，不得纳入提交。

---

### Task 1: 五名 NPC 头部裁切

**Files:**
- Modify: `relationship_data.gd`
- Modify: `relationship_portrait.gd`
- Modify: `tools/validate_game.gd`
- Modify: `tools/dev_screenshot.gd`

**Interfaces:**
- Produces: NPC `head_crop: Rect2`
- Produces: `RelationshipPortrait.texture_for(npc, mode := "card") -> Texture2D`

- [ ] **Step 1: 写失败回归**

断言每名 NPC 有正方形、位于 1254×1254 内的 `head_crop`；`texture_for(npc, "circle")` 返回 `AtlasTexture`，`texture_for(npc, "card")` 返回原始纹理。

- [ ] **Step 2: 运行验证确认红灯**

Run: `'/Applications/Godot.app/Contents/MacOS/Godot' --headless -s tools/validate_game.gd`

Expected: 缺少 `head_crop` 或新函数签名而失败。

- [ ] **Step 3: 配置并实现裁切**

使用逐图确认的初始裁切：林阿姨 `Rect2(310, 190, 520, 520)`、周叔 `Rect2(700, 20, 400, 400)`、阿棠 `Rect2(390, 120, 430, 430)`、小满 `Rect2(150, 450, 480, 480)`、马会长 `Rect2(690, 10, 420, 420)`。圆形模式创建 `AtlasTexture`，区域无效时返回 `null` 触发姓名首字回退。

- [ ] **Step 4: 增加五头像同屏截图并视觉迭代**

截图工具把五名 NPC 到访同时放入右侧栏，输出 `docs/img/relationship_visit_heads.png`。逐个检查脸部大小和中心，根据截图只调整对应 `head_crop`。

- [ ] **Step 5: 运行验证并提交**

Expected: `=== 结果: 0 失败 ===`。

### Task 2: 第一人称 NPC 台词与玩家短回复

**Files:**
- Modify: `relationship_data.gd`
- Modify: `ui_panels.gd`
- Modify: `main.gd`
- Modify: `tools/validate_game.gd`
- Modify: `tools/dev_screenshot.gd`
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `BACKLOG.md`

**Interfaces:**
- Produces: `visit_body()` 第一人称发言
- Produces: 玩家按钮短对白集合
- Consumes: 现有事务反馈态

- [ ] **Step 1: 写失败回归**

断言聊天记录不再渲染 `visit_title()`；按钮不得出现“记下了、接受帮忙、挑一条鱼、交付一条鱼、登记一条鱼、稍后”；四类重复到访台词不得包含“带来一件委托、愿意帮你一把、留了几句话”等系统标题。

- [ ] **Step 2: 运行验证确认红灯**

Run: `'/Applications/Godot.app/Contents/MacOS/Godot' --headless -s tools/validate_game.gd`

Expected: 旧系统标题与命令按钮触发失败。

- [ ] **Step 3: 改写 NPC 与玩家对白**

聊天记录只添加 `visit_body()` 和必要的 Buff 发言。玩家按钮固定使用：“好，我记住了。”“我挑一条。”“给你看看。”“好，麻烦你了。”“今天先不了。”“我再想想。”“先收起来。”反馈文案改成 NPC 第一人称回复，金币／Buff 结果拆成系统回执行。

- [ ] **Step 4: 截图检查五类到访**

运行 `tools/dev_screenshot.gd`，检查剧情、送礼、委托、Buff、终章与反馈态均为真实对话，无系统标题或第三人称自述。

- [ ] **Step 5: 同步文档、最终验证与推送**

同步 README／ROADMAP／BACKLOG；运行完整验证至 0 失败；显式提交文件并推送 `feat/relationship-visit-dialogue`，更新 PR #29。
