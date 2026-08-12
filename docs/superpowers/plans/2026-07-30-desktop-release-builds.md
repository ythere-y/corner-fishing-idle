# Windows + macOS 双平台自动发布 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 生成 Windows x86_64 与 macOS Universal 2 两套可分享试玩包，并让 `main` 每次更新后自动构建和上传双平台 artifacts。

**Architecture:** 保留现有 Windows 构建入口，新增 macOS 专用构建入口；平台命名、包白名单和版本处理集中在 `tools/release_lib.sh`。GitHub Actions 用 Linux 与 macOS 两个并行 job 复用本地脚本，普通 `main` push 只上传 artifacts，版本标签在两个 job 成功后创建包含双平台文件的 Draft Release。

**Tech Stack:** Godot 4.6 / GDScript、POSIX shell、macOS `ditto` / `lipo` / `codesign` / `PlistBuddy`、GitHub Actions

## Global Constraints

- 实现分支固定为 `feat/shareable-macos-build`，PR 初始 base 为 `feat/shareable-windows-build`，绝不直推 `main`。
- macOS 导出固定为 Godot 4.6 官方 Universal 2，必须同时包含 `x86_64` 与 `arm64`。
- Bundle identifier 固定为 `com.martinqi826.backpackandbait`。
- macOS 不使用 Developer ID、不公证，使用 Godot 内建 ad-hoc codesign。
- Windows 文件名由版本真值生成；当前为 `Backpack-and-Bait-v0.1.0-windows-x86_64.zip`。
- macOS 文件名由版本真值生成；当前为 `Backpack-and-Bait-v0.1.0-macos-universal.zip`。
- Pull Request、手动触发、`main` push 和 `v*` 标签触发双平台构建。
- 普通 `main` push 只上传 Actions artifacts；只有与项目版本严格相等的标签（当前为 `v0.1.0`）创建 Draft Release。
- 任何构建都必须先完成 Godot 全量验证并出现 `=== 结果: 0 失败 ===`。
- 只用列出实际路径的 `git add`，不使用 `git add -A`。

---

### Task 1: 平台命名与包白名单

**Files:**
- Modify: `tools/test_release_lib.sh`
- Modify: `tools/release_lib.sh`
- Modify: `tools/build_release.sh`

**Interfaces:**
- Consumes: `project.godot` 中的 `config/version`
- Produces: `release_stem PLATFORM VERSION`、`assert_windows_package_contents PACKAGE_DIR`、`assert_macos_package_contents PACKAGE_DIR`

- [ ] **Step 1: 写失败测试**

先在 `tools/test_release_lib.sh` 中把旧的单平台断言替换为：

```sh
test "$(release_stem windows_x86_64 0.1.0)" = \
	"Backpack-and-Bait-v0.1.0-windows-x86_64"
test "$(release_stem macos_universal 0.1.0)" = \
	"Backpack-and-Bait-v0.1.0-macos-universal"
if release_stem linux_x86_64 0.1.0 >/dev/null 2>&1; then
	echo "未知平台被接受" >&2
	exit 1
fi

windows_fixture=$(mktemp -d)
macos_fixture=$(mktemp -d)
trap 'rm -rf "$windows_fixture" "$macos_fixture"' EXIT

printf 'exe\n' > "$windows_fixture/BackpackAndBait.exe"
printf 'pck\n' > "$windows_fixture/BackpackAndBait.pck"
printf 'license\n' > "$windows_fixture/PLAYTEST-LICENSE.txt"
printf 'readme\n' > "$windows_fixture/PLAYTEST.txt"
assert_windows_package_contents "$windows_fixture"

mkdir -p "$macos_fixture/BackpackAndBait.app"
printf 'license\n' > "$macos_fixture/PLAYTEST-LICENSE.txt"
printf 'readme\n' > "$macos_fixture/PLAYTEST.txt"
assert_macos_package_contents "$macos_fixture"

printf 'unexpected\n' > "$macos_fixture/debug.log"
if assert_macos_package_contents "$macos_fixture"; then
	echo "macOS 包额外文件未被拒绝" >&2
	exit 1
fi
```

在两个 fixture 上继续保留缺文件、空文件和额外文件的负例。每个负例使用独立 fixture 状态，避免前一个断言污染后一个断言。

- [ ] **Step 2: 运行测试，确认按预期失败**

Run:

```bash
sh tools/test_release_lib.sh
```

Expected: FAIL，原因是 `release_stem` 尚不接受平台参数，或 `assert_macos_package_contents` 尚未定义。

- [ ] **Step 3: 实现最小平台 helper**

在 `tools/release_lib.sh` 中实现：

```sh
release_stem() {
	platform=$1
	version=$2
	case "$platform" in
		windows_x86_64)
			printf 'Backpack-and-Bait-v%s-windows-x86_64\n' "$version"
			;;
		macos_universal)
			printf 'Backpack-and-Bait-v%s-macos-universal\n' "$version"
			;;
		*)
			return 1
			;;
	esac
}

assert_windows_package_contents() {
	package_dir=$1
	actual=$(find "$package_dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)
	expected=$(printf '%s\n' BackpackAndBait.exe BackpackAndBait.pck PLAYTEST-LICENSE.txt PLAYTEST.txt | LC_ALL=C sort)
	test "$actual" = "$expected" || return 1
	for required_file in BackpackAndBait.exe BackpackAndBait.pck PLAYTEST-LICENSE.txt PLAYTEST.txt; do
		test -f "$package_dir/$required_file" || return 1
		test -s "$package_dir/$required_file" || return 1
	done
}

assert_macos_package_contents() {
	package_dir=$1
	actual=$(find "$package_dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)
	expected=$(printf '%s\n' BackpackAndBait.app PLAYTEST-LICENSE.txt PLAYTEST.txt | LC_ALL=C sort)
	test "$actual" = "$expected" || return 1
	test -d "$package_dir/BackpackAndBait.app" || return 1
	for required_file in PLAYTEST-LICENSE.txt PLAYTEST.txt; do
		test -f "$package_dir/$required_file" || return 1
		test -s "$package_dir/$required_file" || return 1
	done
}
```

在 `tools/build_release.sh` 中把调用改为：

```sh
stem=$(release_stem windows_x86_64 "$version")
assert_windows_package_contents "$package_dir"
```

- [ ] **Step 4: 运行 helper 测试和现有 Windows 构建**

Run:

```bash
sh tools/test_release_lib.sh
GODOT_BIN='/Applications/Godot.app/Contents/MacOS/Godot' sh tools/build_release.sh
```

Expected:

- `release helpers: PASS`
- Windows ZIP 和 `.sha256` 重新生成
- ZIP 白名单不变

- [ ] **Step 5: 提交**

```bash
git add tools/release_lib.sh tools/test_release_lib.sh tools/build_release.sh
git commit -m "扩展双平台发布命名与白名单"
```

---

### Task 2: macOS Universal 2 导出与本地打包

**Files:**
- Modify: `export_presets.cfg`
- Create: `tools/build_macos_release.sh`
- Modify: `release/PLAYTEST.txt`

**Interfaces:**
- Consumes: `release_stem macos_universal VERSION`、`assert_macos_package_contents PACKAGE_DIR`、Godot 4.6 `macos.zip` export template
- Produces: 当前版本的 `dist/Backpack-and-Bait-v0.1.0-macos-universal.zip` 及 `.sha256`

- [ ] **Step 1: 写 macOS 包结构集成检查**

先创建 `tools/build_macos_release.sh` 的失败骨架，只完成前置条件和明确失败：

```sh
#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"
. tools/release_lib.sh

if [ "$(uname -s)" != "Darwin" ]; then
	echo "macOS Universal 包必须在 macOS 主机上构建。" >&2
	exit 1
fi

echo "macOS 导出尚未实现" >&2
exit 1
```

- [ ] **Step 2: 运行脚本，确认按预期失败**

Run:

```bash
sh tools/build_macos_release.sh
```

Expected: FAIL，输出 `macOS 导出尚未实现`，证明后续成功来自真实导出实现。

- [ ] **Step 3: 新增 Godot macOS 预设**

在 `export_presets.cfg` 新增 `[preset.1]`，关键选项必须是：

```ini
[preset.1]

name="macOS"
platform="macOS"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="design-ref/*, docs/*, release/*, tools/*, tmp/*, .github/*, .superpowers/*"
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.1.options]

export/distribution_type=0
binary_format/architecture="universal"
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
application/bundle_identifier="com.martinqi826.backpackandbait"
application/signature=""
application/short_version="0.1.0"
application/version="0.1.0"
display/high_res=true
shader_baker/enabled=false
codesign/codesign=1
notarization/notarization=0
```

用 Godot 4.6 首次载入后检查预设；若 Godot 自动补充当前版本的默认键，保留其生成值，但不得加入证书、Apple ID 或本机绝对路径。

- [ ] **Step 4: 实现真实 macOS 构建**

在 `tools/build_macos_release.sh` 复用 Windows 脚本的 Godot 定位、干净工作树、4.6 版本、SemVer、首次导入和完整验证逻辑。macOS 专有部分实现为：

```sh
stem=$(release_stem macos_universal "$version")
staging_dir=$(mktemp -d "$repo_root/dist/.staging-$stem.XXXXXX")
trap 'rm -rf -- "$staging_dir"' EXIT
package_dir="$staging_dir/$stem"
app_path="$package_dir/BackpackAndBait.app"
mkdir -p "$package_dir"

"$godot_bin" --headless --path . --log-file "$export_log" \
	--export-release "macOS" "$app_path"

cp release/PLAYTEST.txt release/PLAYTEST-LICENSE.txt "$package_dir/"
assert_macos_package_contents "$package_dir"

plist="$app_path/Contents/Info.plist"
test -s "$plist"
bundle_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
binary="$app_path/Contents/MacOS/$bundle_executable"
test -x "$binary"
test -s "$binary"

architectures=$(lipo -archs "$binary")
printf '%s\n' "$architectures" | grep -Eq '(^| )x86_64( |$)'
printf '%s\n' "$architectures" | grep -Eq '(^| )arm64( |$)'
codesign --verify --deep --strict "$app_path"

artifact="$repo_root/dist/$stem.zip"
ditto -c -k --keepParent "$package_dir" "$artifact"
```

生成 SHA-256 后，用第二个 `mktemp` 目录和 `ditto -x -k` 解压最终 ZIP，再次调用 `assert_macos_package_contents`，复查可执行位、两种架构和签名。不能只检查暂存目录。

- [ ] **Step 5: 更新统一试玩说明**

在 `release/PLAYTEST.txt` 保留 Windows 说明并增加 macOS：

```text
【macOS】
1. 本包同时支持 Apple Silicon 与 Intel Mac。
2. 请先完整解压 ZIP，再在 Finder 中打开 BackpackAndBait.app。
3. 本内测包没有 Developer ID 签名和 Apple 公证。首次启动若被阻止，请右键应用选择“打开”。
4. 若仍被阻止，请前往“系统设置 → 隐私与安全性”，确认应用来源后选择“仍要打开”。
5. 不需要关闭 Gatekeeper，也不需要管理员权限。
```

- [ ] **Step 6: 安装官方模板并运行真实 RED/GREEN 导出**

如果本机模板目录缺少 `macos.zip`，从已校验的官方
`Godot_v4.6-stable_export_templates.tpz` 提取：

```bash
test "$(shasum -a 256 /tmp/Godot_v4.6-stable_export_templates.tpz | awk '{print $1}')" = \
  "3b30ac8c1772f25f5dfa5f65922cab0a90e7b960176891237c5772515ebccc46"
unzip -p /tmp/Godot_v4.6-stable_export_templates.tpz templates/macos.zip \
  > "/Users/huchao/Library/Application Support/Godot/export_templates/4.6.stable/macos.zip"
```

先在没有 macOS 预设或模板的状态运行失败骨架，已经获得 RED；实现后运行：

```bash
GODOT_BIN='/Applications/Godot.app/Contents/MacOS/Godot' sh tools/build_macos_release.sh
```

Expected: 生成 macOS ZIP 和 SHA-256，脚本内所有 `.app`、权限、架构、签名与解压复查均通过。

- [ ] **Step 7: 提交**

```bash
git add export_presets.cfg tools/build_macos_release.sh release/PLAYTEST.txt
git commit -m "加入 macOS Universal 试玩包构建"
```

---

### Task 3: `main` 更新触发双平台 GitHub Actions

**Files:**
- Move: `.github/workflows/windows-build.yml` → `.github/workflows/desktop-builds.yml`

**Interfaces:**
- Consumes: `tools/build_release.sh`、`tools/build_macos_release.sh`
- Produces: `windows-x86_64` 与 `macos-universal` 两个 Actions artifacts；标签触发的双平台 Draft Release

- [ ] **Step 1: 把工作流改为桌面双平台触发**

工作流头部改为：

```yaml
name: Desktop Builds

on:
  pull_request:
  workflow_dispatch:
  push:
    branches:
      - main
    tags:
      - "v*"
```

保留 `contents: read` 默认权限。

- [ ] **Step 2: 保留 Windows job 并新增 macOS job**

Windows job 名为 `windows-x86_64`，继续在 `ubuntu-latest` 下载 Linux editor 和 export templates，运行：

```yaml
- name: Test release helpers
  run: sh tools/test_release_lib.sh

- name: Build Windows package
  run: sh tools/build_release.sh
```

macOS job 名为 `macos-universal`，使用 `macos-latest`，关键安装步骤为：

```yaml
- name: Install Godot 4.6 and official export templates
  shell: bash
  run: |
    set -euo pipefail
    engine_dir="$RUNNER_TEMP/godot-engine"
    template_unpack="$RUNNER_TEMP/godot-templates"
    template_dir="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION_DIR"
    mkdir -p "$engine_dir" "$template_unpack" "$template_dir"
    curl -fsSL \
      "https://github.com/godotengine/godot-builds/releases/download/$GODOT_RELEASE/Godot_v${GODOT_RELEASE}_macos.universal.zip" \
      -o "$RUNNER_TEMP/godot.zip"
    curl -fsSL \
      "https://github.com/godotengine/godot-builds/releases/download/$GODOT_RELEASE/Godot_v${GODOT_RELEASE}_export_templates.tpz" \
      -o "$RUNNER_TEMP/templates.tpz"
    ditto -x -k "$RUNNER_TEMP/godot.zip" "$engine_dir"
    unzip -q "$RUNNER_TEMP/templates.tpz" -d "$template_unpack"
    cp -R "$template_unpack/templates/." "$template_dir/"
    printf 'GODOT_BIN=%s\n' "$engine_dir/Godot.app/Contents/MacOS/Godot" >> "$GITHUB_ENV"
```

随后运行 helper 测试和 `sh tools/build_macos_release.sh`，上传：

```yaml
name: macos-universal
path: |
  dist/*-macos-universal.zip
  dist/*-macos-universal.zip.sha256
```

- [ ] **Step 3: 让标签 Draft Release 等待并收集两个平台**

Draft Release job 改为：

```yaml
needs:
  - windows-x86_64
  - macos-universal
```

分别下载两个 artifact 到 `release-artifacts/windows` 和 `release-artifacts/macos`，`gh release create` 上传：

```text
release-artifacts/windows/*.zip
release-artifacts/windows/*.zip.sha256
release-artifacts/macos/*.zip
release-artifacts/macos/*.zip.sha256
```

标题改为“Windows + macOS 内测版”，仍使用 `--draft`。

- [ ] **Step 4: 本地验证 YAML**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/desktop-builds.yml"); puts "workflow YAML: PASS"'
git diff --check
```

Expected: YAML 可解析，diff 无空白错误。

- [ ] **Step 5: 提交**

```bash
git add .github/workflows/windows-build.yml .github/workflows/desktop-builds.yml
git commit -m "让 main 更新自动构建双平台试玩包"
```

---

### Task 4: 同步双平台发布文档

**Files:**
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `BACKLOG.md`

**Interfaces:**
- Consumes: Tasks 1–3 的实际命令、产物名与 CI 触发规则
- Produces: 维护者和试玩者可执行的双平台说明

- [ ] **Step 1: 更新 README**

把“Windows 试玩包”调整为“Windows + macOS 试玩包”，明确：

- Windows 解压后双击 `BackpackAndBait.exe`，必须保留 PCK。
- macOS 解压后从 Finder 打开 `BackpackAndBait.app`。
- macOS 包为 Universal 2、无 Developer ID、未公证、使用 ad-hoc 签名。
- Gatekeeper 使用右键打开或隐私与安全性“仍要打开”，不关闭系统安全功能。
- 本地命令：

```bash
GODOT_BIN="/path/to/Godot-4.6" sh tools/build_release.sh
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot" sh tools/build_macos_release.sh
```

- `main` 每次更新会在 GitHub Actions 生成两个平台 artifacts。

- [ ] **Step 2: 更新 ROADMAP 与 BACKLOG**

ROADMAP 把发布焦点改为双平台，勾选：

- macOS Universal 2 预设
- 本地 Universal 打包、架构和 ad-hoc 签名检查
- `main` push 双平台 Actions artifacts

保留 Windows 与 macOS 实机放行未完成项。

BACKLOG 新增 2026-07-30 决策：选择 Universal 2、ad-hoc、单一双平台工作流、`main` 更新只产 artifact、版本标签才创建 Draft Release。

- [ ] **Step 3: 校验文档与真实命令一致**

逐项对照：

```bash
rg -n "macos-universal|build_macos_release|main|Universal|ad-hoc" \
  README.md ROADMAP.md BACKLOG.md release/PLAYTEST.txt
git diff --check
```

Expected: 所有命名与脚本一致，无“自动公开 Release”或“已完成 Intel 实机测试”的错误表述。

- [ ] **Step 4: 提交**

```bash
git add README.md ROADMAP.md BACKLOG.md
git commit -m "同步双平台试玩发布说明"
```

---

### Task 5: 本地实际 macOS 冒烟与最终证据

**Files:**
- Modify only if evidence reveals a defect: files from Tasks 1–4

**Interfaces:**
- Consumes: 完整 macOS ZIP、Windows ZIP、项目验证脚本
- Produces: 可交付的本地 artifacts 和验证证据

- [ ] **Step 1: 运行全量自动验证**

Run:

```bash
sh tools/test_release_lib.sh
'/Applications/Godot.app/Contents/MacOS/Godot' \
  --headless --log-file /tmp/corner-fishing-desktop-final.log \
  -s tools/validate_game.gd
```

Expected: helper PASS，Godot 输出 `=== 结果: 0 失败 ===`。

- [ ] **Step 2: 重建两套包**

Run:

```bash
GODOT_BIN='/Applications/Godot.app/Contents/MacOS/Godot' sh tools/build_release.sh
GODOT_BIN='/Applications/Godot.app/Contents/MacOS/Godot' sh tools/build_macos_release.sh
```

Expected: `dist/` 下出现两个 ZIP 和两个 `.sha256`。

- [ ] **Step 3: 独立检查 macOS 最终 ZIP**

Run:

```bash
verify_dir=$(mktemp -d)
ditto -x -k dist/Backpack-and-Bait-v0.1.0-macos-universal.zip "$verify_dir"
app="$verify_dir/Backpack-and-Bait-v0.1.0-macos-universal/BackpackAndBait.app"
plist="$app/Contents/Info.plist"
exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
file "$app/Contents/MacOS/$exe"
lipo -archs "$app/Contents/MacOS/$exe"
codesign --verify --deep --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=4 "$app" || true
```

Expected:

- `lipo` 同时列出 `x86_64 arm64`
- `codesign` exit 0
- `spctl` 可以因未公证而拒绝；这不是构建失败，但结果要记录在 PR

- [ ] **Step 4: 在本机启动应用做 Apple Silicon 冒烟**

Run:

```bash
open "$app"
```

人工验证：

- 应用显示透明桌面挂件而非测试模式。
- 可打开和关闭至少一个菜单。
- 可正常退出且活动监视器中无残留进程。
- 不声称完成 Intel 实机验证。

- [ ] **Step 5: 复制最终包到下载目录并校验**

```bash
cp dist/Backpack-and-Bait-v0.1.0-macos-universal.zip \
  /Users/huchao/Downloads/Backpack-and-Bait-v0.1.0-macos-universal.zip
cp dist/Backpack-and-Bait-v0.1.0-macos-universal.zip.sha256 \
  /Users/huchao/Downloads/Backpack-and-Bait-v0.1.0-macos-universal.zip.sha256
(cd /Users/huchao/Downloads && \
  shasum -a 256 -c Backpack-and-Bait-v0.1.0-macos-universal.zip.sha256)
```

- [ ] **Step 6: 处理验证缺陷**

预期本步骤不修改文件。如果 Step 1–5 暴露缺陷，停止本任务，回到对应 Task 的失败测试，完成新的 RED/GREEN 循环后，只提交该 Task 已列出的实际文件，再从 Step 1 重新运行完整验证。

---

### Task 6: 推送堆叠 PR 并验证远端双平台构建

**Files:**
- No source changes expected

**Interfaces:**
- Consumes: `feat/shareable-macos-build`
- Produces: 以 `feat/shareable-windows-build` 为 base 的 Draft PR 和双平台成功 checks

- [ ] **Step 1: 最终检查提交与工作区**

```bash
git status --short --branch
git log --oneline feat/shareable-windows-build..HEAD
git diff --check feat/shareable-windows-build...HEAD
```

Expected: 工作区干净，增量只包含设计、macOS 构建、双平台 CI 和文档。

- [ ] **Step 2: 推送分支**

```bash
git push -u origin feat/shareable-macos-build
```

- [ ] **Step 3: 创建 Draft PR**

PR base 为 `feat/shareable-windows-build`，正文必须包含：

- macOS Universal 2 与 ad-hoc 签名
- `main` push 自动生成 Windows + macOS artifacts
- 本地 0 失败、双架构、codesign 和 ZIP 校验
- Apple Silicon 本机结果
- Intel 实机尚未测试
- Windows 与 macOS 实机清单通过前保持 Draft

- [ ] **Step 4: 等待并检查 GitHub Actions**

Run:

```bash
gh run list --branch feat/shareable-macos-build --limit 5
run_id=$(gh run list --branch feat/shareable-macos-build --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --exit-status
```

Expected:

- `windows-x86_64` SUCCESS
- `macos-universal` SUCCESS
- 非标签构建的 `draft-release` SKIPPED

- [ ] **Step 5: 下载 CI macOS artifact 再验证并交付**

下载 `macos-universal` artifact 后运行 SHA-256、`ditto` 解压、`lipo` 和 `codesign` 检查。用 CI 版本替换下载目录中的本地版本，并把最终 SHA-256 写入 PR。

- [ ] **Step 6: 保持 PR 与工作区**

PR 保持 Draft，分支与当前工作区保留，等待 Owner 先合并 Windows 整合 PR，再把本 PR base 改为 `main` 并审批合并。不得自行合入 `main`。
