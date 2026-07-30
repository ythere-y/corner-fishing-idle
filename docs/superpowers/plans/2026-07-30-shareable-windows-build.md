# Windows 可分享试玩包 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将最新游戏内容打包为无需安装 Godot、可直接分享的 Windows x86_64 免安装 ZIP。

**Architecture:** 在现有 `feat/shareable-windows-build` 上合并级联 PR #29 的最新内容；以 `project.godot` 为版本真值，用 Godot 4.6 Windows Desktop 预设导出 EXE/PCK，再由可测试的 shell 构建脚本执行验证、白名单打包与 SHA-256 生成。GitHub Actions 复用同一脚本，普通构建只产 artifact，标签构建创建 draft Release。

**Tech Stack:** Godot 4.6、GDScript、POSIX shell、GitHub Actions、ZIP、SHA-256。

## Global Constraints

- `main` 受保护；全部改动留在 `feat/shareable-windows-build` 并更新 PR #27。
- 以 `origin/main` 和已合并的级联 PR 分支为远端真值，不带入主工作区未提交文件。
- 导出目标固定为 Windows x86_64，文件名固定为 `BackpackAndBait.exe`。
- 初始试玩版本固定为 `0.1.0`，标签格式固定为 `v0.1.0`。
- 试玩包为未签名免安装 ZIP，允许 SmartScreen 显示“未知发布者”。
- 包内只允许 EXE、PCK、`开始游玩.txt` 与 `内测许可.txt`。
- 不创建安装器、不写注册表、不请求管理员权限、不新增遥测。

---

### Task 1: 同步级联 PR 的最新游戏内容

**Files:**
- Merge: `origin/fix/relationship-image-fallback` into `feat/shareable-windows-build`
- Verify: `tools/validate_game.gd`

**Interfaces:**
- Consumes: PR #27 当前分支与 PR #29 合并后的远端提交 `12d3f13`
- Produces: 同时包含发布设计、人情图片修复和到访聊天重构的单一分支

- [ ] **Step 1: 确认分支关系与工作树**

Run:

```bash
git fetch --prune
git status --short --branch
git log --oneline --left-right feat/shareable-windows-build...origin/fix/relationship-image-fallback
```

Expected: 工作树干净，右侧包含 PR #29 的到访聊天提交。

- [ ] **Step 2: 合并最新级联分支**

Run:

```bash
git merge --no-ff origin/fix/relationship-image-fallback -m "合并最新到访对话与 Windows 发布分支"
```

Expected: 无冲突合并；若有冲突，逐文件保留两侧有效改动后继续。

- [ ] **Step 3: 首次导入并验证同步结果**

Run:

```bash
'/Applications/Godot.app/Contents/MacOS/Godot' --headless --editor --quit --path .
'/Applications/Godot.app/Contents/MacOS/Godot' --headless --path . -s tools/validate_game.gd
```

Expected: 输出 `=== 结果: 0 失败 ===`，进程状态为 0。

---

### Task 2: 建立版本、导出预设与构建函数的测试边界

**Files:**
- Modify: `project.godot`
- Create: `export_presets.cfg`
- Create: `tools/release_lib.sh`
- Create: `tools/test_release_lib.sh`

**Interfaces:**
- Consumes: `project.godot` 的 `application/config/version`
- Produces: `release_version`、`release_stem`、`assert_semver`、`assert_package_contents` shell 函数

- [ ] **Step 1: 先写失败的 release helper 测试**

Create `tools/test_release_lib.sh`，覆盖：

```sh
#!/bin/sh
set -eu
. "$(dirname "$0")/release_lib.sh"

test "$(release_version project.godot)" = "0.1.0"
test "$(release_stem 0.1.0)" = "Backpack-and-Bait-v0.1.0-windows-x86_64"
assert_semver "0.1.0"
if assert_semver "v0.1"; then
  echo "无效版本被接受" >&2
  exit 1
fi
printf 'release helpers: PASS\n'
```

- [ ] **Step 2: 运行测试并确认因功能缺失失败**

Run:

```bash
sh tools/test_release_lib.sh
```

Expected: FAIL，原因是 `release_lib.sh` 尚不存在。

- [ ] **Step 3: 添加版本真值、导出预设与最小 helper**

在 `project.godot` 的 `[application]` 中添加：

```ini
config/version="0.1.0"
```

新增 `export_presets.cfg`，定义 `Windows Desktop`、`x86_64`、release template、独立 PCK、禁用代码签名，并排除 `design-ref/`、`docs/`、`tmp/`、`.github/` 和开发脚本。

新增 `tools/release_lib.sh`：

```sh
#!/bin/sh

release_version() {
  sed -n 's/^config\\/version="\\([^"]*\\)"$/\\1/p' "$1"
}

assert_semver() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+$'
}

release_stem() {
  printf 'Backpack-and-Bait-v%s-windows-x86_64\n' "$1"
}

assert_package_contents() {
  package_dir=$1
  actual=$(find "$package_dir" -maxdepth 1 -type f -exec basename {} \\; | LC_ALL=C sort)
  expected=$(printf '%s\n' BackpackAndBait.exe BackpackAndBait.pck 内测许可.txt 开始游玩.txt | LC_ALL=C sort)
  test "$actual" = "$expected"
}
```

- [ ] **Step 4: 运行 helper 测试**

Run:

```bash
sh tools/test_release_lib.sh
```

Expected: `release helpers: PASS`。

- [ ] **Step 5: 提交版本与预设**

```bash
git add project.godot export_presets.cfg tools/release_lib.sh tools/test_release_lib.sh
git commit -m "建立 Windows 导出版本与预设"
```

---

### Task 3: 实现可复现的本地构建与玩家包

**Files:**
- Modify: `.gitignore`
- Modify: `tools/test_release_lib.sh`
- Create: `tools/build_release.sh`
- Create: `release/开始游玩.txt`
- Create: `release/内测许可.txt`

**Interfaces:**
- Consumes: Godot 4.6 可执行文件、`Windows Desktop` 导出模板、Task 2 helper
- Produces: `dist/Backpack-and-Bait-v0.1.0-windows-x86_64.zip` 与同名 `.sha256`

- [ ] **Step 1: 先增加包白名单失败测试**

在 `tools/test_release_lib.sh` 中创建临时目录，仅放 `BackpackAndBait.exe`，调用：

```sh
if assert_package_contents "$fixture"; then
  echo "不完整包被接受" >&2
  exit 1
fi
```

随后补齐四个白名单文件并要求 `assert_package_contents "$fixture"` 成功。

- [ ] **Step 2: 运行测试并确认不完整包失败**

Run:

```bash
sh tools/test_release_lib.sh
```

Expected: fixture 不完整时被拒绝，完整时通过；若当前 helper 未覆盖空文件或额外文件，测试先失败。

- [ ] **Step 3: 收紧白名单并创建构建脚本**

`assert_package_contents` 同时验证四个文件非空、目录中没有额外文件。

`tools/build_release.sh` 必须：

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"
. tools/release_lib.sh

godot_bin=${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
version=$(release_version project.godot)
assert_semver "$version"
stem=$(release_stem "$version")
package_dir="dist/$stem"

test -x "$godot_bin"
test -z "$(git status --porcelain --untracked-files=no)"
"$godot_bin" --version | grep -Eq '^4\\.6(\\.|-)'
"$godot_bin" --headless --editor --quit --path .
"$godot_bin" --headless --path . -s tools/validate_game.gd

mkdir -p dist
rm -rf -- "$package_dir"
mkdir -p "$package_dir"
"$godot_bin" --headless --path . --export-release "Windows Desktop" "$package_dir/BackpackAndBait.exe"
cp release/开始游玩.txt release/内测许可.txt "$package_dir/"
assert_package_contents "$package_dir"
(cd dist && zip -X -q -r "$stem.zip" "$stem")
shasum -a 256 "dist/$stem.zip" > "dist/$stem.zip.sha256"
```

删除仅限已校验的 `dist/$stem`，不得删除宽泛目录。

- [ ] **Step 4: 编写玩家说明和保守内测许可**

`开始游玩.txt` 说明解压、双击 EXE、拖动/缩放/退出、SmartScreen、存档位置和反馈信息。

`内测许可.txt` 明确本包仅供获准试玩，不授予源码、美术、音频再分发许可；第三方素材继续遵循仓库已有声明。

- [ ] **Step 5: 测试 helper 并提交**

Run:

```bash
sh tools/test_release_lib.sh
```

Expected: `release helpers: PASS`。

Commit:

```bash
git add .gitignore tools/release_lib.sh tools/test_release_lib.sh tools/build_release.sh release/开始游玩.txt release/内测许可.txt
git commit -m "加入 Windows 试玩包构建与白名单"
```

---

### Task 4: 增加 CI 构建并同步发布文档

**Files:**
- Create: `.github/workflows/windows-build.yml`
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `BACKLOG.md`
- Modify: `docs/superpowers/specs/2026-07-20-shareable-windows-build-design.md`

**Interfaces:**
- Consumes: `tools/build_release.sh`
- Produces: PR/手动触发 artifact；`v*` 标签触发 draft GitHub Release

- [ ] **Step 1: 添加 GitHub Actions 工作流**

工作流使用固定 Godot `4.6-stable` 官方 Linux 二进制与导出模板；设置 `XDG_DATA_HOME` 到 runner 临时目录；运行 `sh tools/test_release_lib.sh` 和 `GODOT_BIN=<runner Godot> sh tools/build_release.sh`。普通 job 使用 `actions/upload-artifact@v4`；标签 job 用 `gh release create --draft` 上传 ZIP 与 SHA-256，且先校验标签等于 `v$(release_version project.godot)`。

- [ ] **Step 2: 同步三份项目文档**

README 增加“下载/试玩”和“一键本地构建”；ROADMAP 标记 Windows 免安装内测包链路完成但 Windows 实机放行待验；BACKLOG 记录 ZIP、未签名 SmartScreen 和 draft Release 的决策。

- [ ] **Step 3: 静态检查并提交**

Run:

```bash
git diff --check
sh tools/test_release_lib.sh
```

Commit:

```bash
git add .github/workflows/windows-build.yml README.md ROADMAP.md BACKLOG.md docs/superpowers/specs/2026-07-20-shareable-windows-build-design.md
git commit -m "接入 Windows 构建流水线并同步文档"
```

---

### Task 5: 安装官方模板、生成并核验实际试玩包

**Files:**
- Generate (ignored): `dist/Backpack-and-Bait-v0.1.0-windows-x86_64.zip`
- Generate (ignored): `dist/Backpack-and-Bait-v0.1.0-windows-x86_64.zip.sha256`

**Interfaces:**
- Consumes: Godot 4.6 官方 export templates
- Produces: 可传给试玩者的最终 ZIP 与校验值

- [ ] **Step 1: 安装与本机 Godot 完全匹配的官方导出模板**

下载 `Godot_v4.6-stable_export_templates.tpz`，安装到 Godot 报告的 `4.6.stable` 模板目录；不使用未知第三方模板。

- [ ] **Step 2: 运行一键构建**

Run:

```bash
GODOT_BIN='/Applications/Godot.app/Contents/MacOS/Godot' sh tools/build_release.sh
```

Expected: 完整验证输出 `0 失败`，Godot export 成功，ZIP 与 `.sha256` 非空。

- [ ] **Step 3: 独立检查压缩包内容**

Run:

```bash
unzip -l dist/Backpack-and-Bait-v0.1.0-windows-x86_64.zip
shasum -a 256 -c dist/Backpack-and-Bait-v0.1.0-windows-x86_64.zip.sha256
```

Expected: 只有一个顶层目录和四个白名单文件；SHA-256 显示 `OK`。

- [ ] **Step 4: 重新运行完整项目验证并检查差异**

Run:

```bash
'/Applications/Godot.app/Contents/MacOS/Godot' --headless --path . -s tools/validate_game.gd
git diff --check
git status --short --branch
```

Expected: `0 失败`，没有未提交的受版本控制改动。

---

### Task 6: 更新 PR #27

**Files:**
- Push: `feat/shareable-windows-build`
- Update: GitHub PR #27

**Interfaces:**
- Consumes: 已验证提交和本地试玩产物
- Produces: 可审查的远端分支与包含构建证据的 PR

- [ ] **Step 1: 推送分支**

```bash
git push origin feat/shareable-windows-build
```

- [ ] **Step 2: 更新 PR 描述**

写明合入 PR #29、构建链路、ZIP 文件名、SHA-256、`0 失败`结果和“Windows 实机清单尚需试玩者/Owner 验证”；保留 Draft，直到 Windows 10/11 实机通过。

- [ ] **Step 3: 最终核对**

Run:

```bash
gh pr view 27 --json url,isDraft,headRefOid,mergeable,mergeStateStatus
```

Expected: PR #27 指向最新提交且仍为 Draft。
