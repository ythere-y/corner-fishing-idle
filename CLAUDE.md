# 背包钓鱼手记 · 项目总纲(给本机 Claude Code)
<!-- 【修改】原「角落垂钓」→ 最终定名「背包钓鱼手记」（见 docs/lore_backpacker.md 候选清单），仅同步标题，正文流程未变。 -->

> 先看「🧭 项目全貌」与「工作流硬规矩」(总体);动具体模块前,到「分部规范」找对应**真值来源**再下手。

## 🧭 项目全貌(三份总入口 —— 每次对话必读、每次改动必更新)

本项目的"全貌"由三份**根目录文档**承载,是单一可信源(给人看、也给每个 AI 对话看):

- **[VISION.md](VISION.md)** —— 愿景/北极星:做什么、为谁、**明确不做什么**。
- **[ROADMAP.md](ROADMAP.md)** —— 现在进行态:里程碑 + `▶ 当前焦点`,勾选框即进度。
- **[BACKLOG.md](BACKLOG.md)** —— 想法冰箱 + 决策日志。

**硬规矩(与跑 validate 同级 —— 改了东西却没更新文档,视为改动未完成):**

1. **对话开始**:先读这三份(尤其 ROADMAP 的 `▶ 当前焦点`),再动手。
2. **完成任何改动后,立即同步更新对应文档:**
   - 在 ROADMAP 勾掉 / 移动条目;焦点完成则更新 `▶ 当前焦点`。
   - 冒出的新点子 → 写进 BACKLOG 冰箱(别只在对话里口头说完就丢)。
   - 改了方向 / 砍了功能 → 改 VISION,并在 BACKLOG 决策日志记**一句为什么**。
3. **每轮交付后,用一两句中文向用户汇报**:做完了什么 + ROADMAP 现在的 `▶ 当前焦点` 是什么 —— 让用户无需读文档即掌握全貌。
4. 提交时**只 `git add` 这三个显式文件**,绝不 `-A`(本仓库多对话共用);决策日志只增不删。

## 这是什么(总体)

贴桌面角落、透明融进壁纸、自动挂机钓鱼的**水彩风桌面挂件**。Godot 4.6 / 2D / GDScript。

- **定位**:不打扰的陪伴式放置游戏(Rusty's Retirement 生态位 + Chillquarium 收集深度)。气质安静、克制、水彩卷轴味;冷冬调 + 单一暖金强调色。
- **核心循环**:抛竿 → 等待 → 浮标咬钩 → 自动上鱼入篓 → 手动卖出变现。
- **长线**:多品阶鱼类收集(星级 × 稀有变体构成多维收集轴),多钓点生态,桌面宠物🐱、活水族箱🐠、专注奖励、每日订单、成就、离线收益。(具体数量/品阶/系数等易变数据看 fish_data.gd 与 README,本文不写死。)
- **完整玩法 / 模块职责 / 存档版本以 [README.md](README.md) 为准**(玩法清单 + 「结构」职责表 + 「存档」节是单一事实源,本文不复述)。

## 工作流硬规矩(适用所有改动)

- 引擎 Godot 4.6 / GDScript。逻辑入口 `main.gd`、面板 `ui_panels.gd`、场景绘制 `scene_painter.gd`;完整模块职责见 README「结构」表。
- **拉到新美术资源后先 `godot --headless --import` 再运行**,否则看不到新图(.godot/ 不入库)。
- **协作模型见 [CONTRIBUTING.md](CONTRIBUTING.md)**:多人 / 多 AI 并行 = 「分支 + PR + 受保护 main」,改动各走分支、经审查再并回 `main`,**别再多条对话共用一个工作目录**。单人快速迭代仍可直接在 `main` 上做;一旦有第二个贡献者(人或 AI)同时动手,就必须分支隔离。提交永远只 `git add <显式文件>`、绝不 `-A`。
- **文档以 MD 为单一可信源**(AI 读写、git 跟踪);同名 HTML 仅人读视图,改动先改 MD 再生成 HTML。
- **验证**:逻辑改动跑 `godot --headless -s tools/validate_game.gd`(必须全过);视觉改动跑 `tools/dev_screenshot.gd` 出图人工把关。
- 拿不准就先列差异问人,别一次性"照搬全部"。

## 分部规范(改对应内容前先读其真值来源)

### UI / 界面 → `design-ref/`

UI **设计真理来源**是 `design-ref/`。**改 UI 必读** `design-ref/_HANDOFF_INDEX.md` 与 `design-ref/handoff/`:每屏看活规格 `playable/Corner Fishing.html`(点 5 页签看真实状态,别凭静态截图猜),色/字/距读 `tokens/*.css`,组件读 `components/**`,整窗参考 `ui_kits/corner_fishing/app.jsx`。

**规矩(否则会改坏游戏)**

- 这是"移植 / 翻译",不是"运行"。`design-ref` 里的 `.jsx/.css/.html` **不要**当成能直接导入或运行的代码;用 GDScript 把设计意图实现到 `main.gd` / `ui_panels.gd`。
- **游戏已整合过的入口 / 按钮以 `design-ref/handoff/` 为准,勿用旧设计稿回滚。**
- 游戏特有系统(透明窗、鼠标穿透、羽化 shader、存档迁移等)设计稿不涉及,**别碰**。

### 鱼数据 / 图鉴看板 → `fish_data.gd` + `docs/fish_gallery.html`(强制:动鱼必须同步)

`docs/fish_gallery.html` 是核对每条鱼「**名字 ↔ 真实世界图 ↔ 游戏图**」是否匹配的看板(展示项目当前全部鱼)。

- **只要在 `fish_data.gd` 里新增 / 改名 / 删除鱼,就必须重新生成这个看板**,否则视为改动未完成:
  ```
  godot --headless --path . -s tools/gen_fish_gallery.gd
  ```
  (看板由该生成器从 `fish_data.gd` 直接产出,不要手改 HTML——改数据后重跑即可,永不漂移。)
- 真实图放 `assets/art/fish_photos/<id>.jpg`,游戏图放 `assets/art/fish/<id>.png`;**缺图自动显示「待补」占位**(支持只填名字、分批补图)。

### 鱼图标美术 → `docs/fish_icon_art_standard.md`

强制标准(production bar);清单 `docs/fish_icon_manifest.md` 受它治理。

### 音频资源 → `docs/audio_asset_rules.md`

### 多车道并行 → `docs/parallel-dev-contract.md`
