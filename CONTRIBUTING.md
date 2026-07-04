# 协作守则 · CONTRIBUTING（背包钓鱼手记）
<!-- 【修改】原「角落垂钓」→ 最终定名「背包钓鱼手记」（见 docs/lore_backpacker.md 候选清单），仅同步标题。 -->

> **一句话**：`main` 永远是干净、能跑的「黄金版」。谁都不直接改它——改动各走各的**分支**，经**审查**后再并回来。
>
> 本文是**多人/多 AI 协作的总则**。AI 车道的细分见 [docs/parallel-dev-contract.md](docs/parallel-dev-contract.md)；项目全貌见 [VISION.md](VISION.md) / [ROADMAP.md](ROADMAP.md) / [BACKLOG.md](BACKLOG.md)。

---

## 0. 给非技术 Owner 的话（你只需要懂这一节）

- **你的角色**：定方向、定优先级、**批准 / 否决**。你**不需要**学 git 命令。
- **你怎么参与**：通过对话让 AI / 维护者执行；你只做两件事——**决策** + 在 GitHub 网页上点「**Approve / Merge**」。
- **一个口诀**：遇到任何改动，问一句——*"这会不会让 main 跑不起来？谁审过？"* 答得上来，就放心合。
- **心智模型**：`main` = 厨房里唯一那本「master 菜谱」，必须永远干净。每个人改时**先复印一份（分支）**改自己的，**主厨（维护者）审过再抄回 master**，一次一个，排队进。别让大家在同一本上同时涂。

---

## 1. 角色

| 角色 | 是谁 | 负责 |
|---|---|---|
| **Owner** | 你（项目发起人） | 愿景、优先级、最终拍板；在网页上批准合并 |
| **维护者 / 集成者** | 信任的技术伙伴 **或** 指定的一条 AI 对话（如 Claude） | 审查 PR、把关、合并、保持 `main` 永远能跑。**一个项目只设 1 个集成者**，避免多头乱合 |
| **贡献者** | 人 或 AI 对话 | 在自己分支上干活，提 PR；不直接碰 `main` |

---

## 2. 三条铁律（违背 = 混乱）

1. **`main` 受保护、永远能跑**：不直接推 `main`，一切走 PR；每次合并前 `tools/validate_game.gd` **0 失败**。
2. **一人 / 一 AI = 一分支 = 一任务**；**不共用工作区**（各自独立 clone 或 git worktree，绝不多人多 AI 同时编辑同一个文件夹）。
3. **改动走 PR + 至少一人审查**；GitHub 会自动检测冲突，审查防住坏代码进主线。

---

## 3. 标准工作流（人和 AI 都照此走）

```
1. 同步     git checkout main && git pull            # 拿最新黄金版
2. 开分支   git checkout -b feat/我的任务名            # 自己的复印件
3. 改 + 验证  改代码 → godot --headless -s tools/validate_game.gd（必须 0 失败）
4. 提交     git add <显式文件>  &&  git commit        # 只 add 改的文件，绝不 git add -A
5. 推分支   git push -u origin feat/我的任务名
6. 提 PR    在 GitHub 开 Pull Request，写清楚：改了什么 / 为什么 / 怎么验证的
7. 审 → 合   维护者审 → 合并进 main → 删掉这个分支
```

- **分支命名**：`feat/…`（新功能）、`fix/…`（修 bug）、`art/…`（美术）、`docs/…`（文档）。
- **提交信息**：中文一句话标题 +（可选）为什么；AI 提交结尾加 `Co-Authored-By: …`。
- **PR 描述**：必含「改了什么 / 为什么 / 怎么验证」（视觉改动附截图，逻辑改动附 validate 结果）。
- **小步勤提**：每个 PR 只做一件事、尽量小——好审、好合、好回退。

---

## 4. 区域归属（谁主哪块 —— 减少撞车）

> 原则：**一个文件，同一时间只允许一个任务在动**；要跨区改，先在 PR / 对话里讲好。

| 区域 | 主要文件 | 归属车道 |
|---|---|---|
| 逻辑 / 系统 / 引擎接入 | `main.gd` 及各拆出模块（`save_system` `events` `orders` `spots` 等） | 程序车道（Claude / 技术贡献者） |
| 数据 / 数值 | `fish_data.gd` `spot_data.gd` `event_data.gd` `achievements.gd` | 数据车道（可独立调） |
| 美术 / 音频 / 资源 | `assets/art/**` `assets/audio/**` | 美术车道（Codex / 美术贡献者）；程序只加载接入，**不覆盖** |
| 场景程序绘制 | `scene_painter.gd` | 视觉车道（**易撞**——动前必同步，且只一个任务动） |
| UI 设计真值 | `design-ref/` | 设计车道；游戏里是「翻译实现」，别把 `.jsx/.css` 当可运行代码 |
| 文档 / 全貌 | `VISION/ROADMAP/BACKLOG.md` `README.md` `docs/**` | 谁改功能谁顺手更新对应文档 |

AI 车道的更细约定（拆模块顺序、grep 定位、Codex 边界等）见 [docs/parallel-dev-contract.md](docs/parallel-dev-contract.md)。

---

## 5. AI 对话特别条款（当前主要贡献者就是多条 AI 对话）

- **绝不让两条 AI 对话同时编辑同一个工作文件夹**（已踩坑：会互相覆盖、git 状态错乱）。
- 每条 AI 对话：**动手前先 `git fetch`、以 `origin/main` 为基**、开自己的分支、**只 `git add <显式文件>`、绝不 `-A`**（本仓库 `.import` 噪声多、且多对话共用）。
- 由**一个集成者**统一审查 + 合并到 `main`；其他对话不直接推 `main`。

---

## 6. 「改动完成」的定义（Definition of Done）

一个 PR 能合并，必须同时满足：

- [ ] `tools/validate_game.gd` **0 失败**（视觉改动另附截图自查）。
- [ ] 相关**文档已同步**：`ROADMAP` 勾选 / 移动焦点、`BACKLOG` 记一句决策、`README` 改动数字。
- [ ] PR **经维护者审查**通过。
- [ ] 合并后**客户端能正常启动运行**。

---

## 7. 如何开启 `main` 分支保护（一次性，Owner 在 GitHub 网页点几下）

> 这一步把上面的规矩**变成系统强制**，不用靠人天天盯。

1. 打开仓库页 `github.com/Martinqi826/corner-fishing-idle` → **Settings**（设置）。
2. 左栏 **Branches**（分支）→ **Add branch ruleset** / **Add rule**。
3. 分支名填 `main`，勾选：
   - **Require a pull request before merging**（合并前必须 PR）
   - **Require approvals**（至少 1 个批准）
   - **Require status checks to pass**（若以后接了自动测试）
   - 可选 **Do not allow bypassing**（连管理员也走 PR——团队大了再开）
4. **Save**（保存）。之后任何人想改 `main` 都得走 PR + 审查，系统自动挡住直推。

---

*维护提醒：本守则是流程单一可信源。流程一旦调整，先改本文，再在 `BACKLOG` 决策日志记一句为什么。*
