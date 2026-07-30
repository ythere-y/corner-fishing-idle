# Final Review Fix Report

日期：2026-07-21
分支：`fix/relationship-visit-session-bubbles`（推送目标：`feat/relationship-visit-dialogue`）

## Finding → 代码 / 测试映射

1. 到访面板切换到其他面板时会话未结束
   - 代码：`main.gd::_open_panel(kind)` 在当前面板为 `relationship_visit` 且目标不是同种面板时，先调用 `_end_relationship_visit_session()`；同种重绘不销毁。
   - 测试：`tools/validate_game.gd::_check_relationship_foundation()` 设置 picker，执行到访 → catch → 重开同一到访，断言回到干净 `decision`。
2. 同 NPC 的旧 UI callable 可作用于后来替换的 visit
   - 代码：`main.gd::_relationship_visit_action_is_current()` 共用核对捕获的 `npc_id` / `visit_key`、当前 selector、当前 session 与实时 visit。reply setter、story、gift、task、buff accept/decline、finale 均在任何修改前调用；`ui_panels.gd` 的当前到访玩家回复、关闭/收起与三类鱼卡闭包均捕获创建时身份。
   - 测试：保存旧剧情按钮的 callable 与旧身份，替换同 NPC 为新 buff visit 并建立新 session，触发旧 callable，断言新 visit、`story_seen`、feedback、player reply 均未被修改。
3. feedback prompt 被同 NPC 新实时 visit 替换；decision/picker 身份失配不安全
   - 代码：`ui_panels.gd::fill_relationship_visit()` 在 feedback 阶段始终从 `session.visit_snapshot` 取 prompt；decision/picker 失配时按实时 visit 安全重建 session，无实时 visit 时结束 session 并显示已离开。
   - 测试：反馈期间替换同 NPC 实时 visit 并重绘，断言仍显示旧 snapshot prompt 与旧反馈，不显示新 buff prompt。

## RED

命令：

```bash
'/Applications/Godot.app/Contents/MacOS/Godot' --headless --log-file /tmp/relationship-final-review-red.log -s tools/validate_game.gd
```

准确失败：

```text
失败: 同 NPC 旧按钮回调不得修改或结算后来替换的新到访
失败: 到访切换到其他面板后重开同一到访必须建立新的决策会话
失败: 反馈阶段即使同 NPC 生成新到访也必须继续显示会话快照 prompt
=== 结果: 3 失败 ===
```

## GREEN

同一完整命令首次实现后输出：

```text
人情簿：逐级事件池 / 跨级补读 / 礼物好感 / 金币委托 / Buff 门槛 / 一次性终章 通过
=== 结果: 0 失败 ===
```

最终提交前会重新执行完整 validator 与 `git diff --check`，以最终新鲜输出为准。

## 边界自审

- 未改奖励、好感、到访排程、鱼消耗与锁定鱼规则。
- 未将 `relationship_visit_session` 加入 `save_system.gd` 或任何存档结构。
- 未改视觉设计、图片或截图 fixture。
- 同种 `relationship_visit` 重绘保留 session；只有切到其他 panel 或真实关闭才结束。
- 当前到访页的 story / buff / picker / later / collapse 玩家按钮和 hint / task / finale 鱼卡均携带创建时身份。
- feedback 可在实时 visit 已被移除或同 NPC 已生成新 visit 时继续完整显示原 prompt。

## 提交与推送

- Implementation commit：`edeae33 修复到访会话身份竞态`。
- Push：报告提交后推送到 `origin/feat/relationship-visit-dialogue`，最终结果见任务交接。
