# Windows + macOS 双平台自动发布设计

状态：Owner 已于 2026-07-30 确认

## 1. 目标

在现有 Windows 免安装试玩包基础上，增加无需安装 Godot 的 macOS 通用试玩包，并让 GitHub Actions 在 `main` 每次更新后自动完成双平台验证、导出、打包和 artifact 上传。

成功标准：

- Windows 产物保持 `Backpack-and-Bait-v<version>-windows-x86_64.zip`。
- macOS 产物为 `Backpack-and-Bait-v<version>-macos-universal.zip`。
- macOS ZIP 内包含可运行的 `BackpackAndBait.app`，同时支持 Intel x86_64 与 Apple Silicon ARM64。
- 两个平台产物都有相邻的 `.sha256` 校验文件。
- Pull Request、手动触发和每次 `main` push 都运行双平台构建。
- `v<version>` 标签只创建 Draft Release，并同时附带 Windows 与 macOS 的 ZIP、SHA-256。
- 本机维护者可以分别用一条命令重建 Windows 或 macOS 包。

## 2. 发布边界

本阶段面向朋友和内部评审，不是面向陌生用户的正式 macOS 分发：

- 不购买或接入 Apple Developer Program。
- 不使用 Developer ID 身份签名。
- 不执行 Apple 公证。
- macOS 使用 Godot 内建 ad-hoc 签名，降低应用包内部未签名组件带来的运行问题，但 Gatekeeper 仍可能阻止从网络下载的应用。
- 试玩说明只提供 Finder“右键 → 打开”和“系统设置 → 隐私与安全性 → 仍要打开”的系统放行方法，不引导关闭 Gatekeeper，也不要求管理员权限。

Windows 继续保持未签名内测包和 SmartScreen 说明。

## 3. 分支与集成

实现分支为 `feat/shareable-macos-build`，从包含最新 `main`、人情到访功能和 Windows 发布链路的 `feat/shareable-windows-build` 创建。

本任务使用堆叠 PR：

1. `feat/shareable-macos-build` 以 `feat/shareable-windows-build` 为 PR base，先审查 macOS 与双平台流水线增量。
2. Windows 整合 PR 合入 `main` 后，把本 PR base 改为 `main`。
3. 本 PR 合入 `main` 后，`main` 的每次新提交自动触发双平台构建。

不直接推送受保护的 `main`。

## 4. 导出预设

在 `export_presets.cfg` 保留 `Windows Desktop`，新增 `macOS`：

- 使用 Godot 4.6 官方 macOS export template。
- 架构为 `universal`，生成 Universal 2 应用。
- Bundle identifier 固定为 `com.martinqi826.backpackandbait`。
- 应用名固定为 `BackpackAndBait`。
- 最低系统版本沿用 Godot 4.6 官方模板默认值。
- 关闭 Developer ID 签名和公证，启用 Godot 内建 ad-hoc codesign。
- 资源过滤规则与 Windows 一致，不把设计稿、文档、开发工具和 CI 文件打进游戏数据。

预设不保存个人证书、Apple ID、密码、模板绝对路径或其他机器私有配置。

## 5. 构建脚本

保留 `tools/build_release.sh` 作为 Windows 兼容入口，新增 `tools/build_macos_release.sh`。两个入口复用 `tools/release_lib.sh` 中的平台无关能力：

- 读取并校验 `project.godot` 的 SemVer。
- 生成平台对应的 artifact stem。
- 检查受版本控制文件是否干净。
- 定位并校验 Godot 4.6。
- 首次导入项目。
- 运行 `tools/validate_game.gd`，必须出现 `=== 结果: 0 失败 ===`。
- 按平台白名单检查输出内容。
- 生成 ZIP 与 SHA-256。

macOS 构建只允许在 macOS 主机执行，因为最终包需要通过 `ditto` 保留 `.app` bundle 的可执行权限和 macOS 元数据。构建流程为：

1. 导出到暂存目录的 `BackpackAndBait.app`。
2. 从 `Contents/Info.plist` 读取 `CFBundleExecutable`，验证对应主程序和游戏数据文件存在且非空。
3. 把 `.app`、`PLAYTEST.txt`、`PLAYTEST-LICENSE.txt` 放入单一顶层目录。
4. 使用 macOS `ditto` 生成外层 ZIP。
5. 解压到临时目录复查白名单、可执行位和 Mach-O 架构。
6. 用 `lipo -info` 确认主程序同时包含 `x86_64` 与 `arm64`。
7. 用 `codesign --verify --deep --strict` 验证 ad-hoc 签名结构。

构建脚本的暂存目录由 `mktemp` 创建，并在成功或失败退出时清理；最终产物只写入被 `.gitignore` 忽略的 `dist/`。

## 6. 包内容

Windows ZIP 继续使用现有白名单：

- `BackpackAndBait.exe`
- `BackpackAndBait.pck`
- `PLAYTEST.txt`
- `PLAYTEST-LICENSE.txt`

macOS ZIP 顶层目录只允许：

- `BackpackAndBait.app`
- `PLAYTEST.txt`
- `PLAYTEST-LICENSE.txt`

macOS 试玩说明增加：

- 支持 Intel 与 Apple Silicon。
- 先完整解压 ZIP，再从 Finder 启动。
- 首次启动可能被 Gatekeeper 阻止。
- 使用 Finder 右键“打开”；若仍被阻止，在系统设置的“隐私与安全性”中选择“仍要打开”。
- 不关闭系统安全功能。
- 存档位于 Godot `user://` 对应的 macOS 用户数据目录。

## 7. GitHub Actions

把现有 Windows 工作流收敛为一个桌面双平台工作流，触发条件为：

```yaml
on:
  pull_request:
  workflow_dispatch:
  push:
    branches:
      - main
    tags:
      - "v*"
```

构建任务并行运行：

- `windows-x86_64`：`ubuntu-latest`，安装 Godot 4.6 Linux editor 和官方 export templates，运行现有 Windows 构建入口。
- `macos-universal`：`macos-latest`，安装 Godot 4.6 macOS Universal editor 和同版本官方 export templates，运行 macOS 构建入口。

每个任务分别上传以平台命名的 artifact，保留 ZIP 和 `.sha256`。失败时不创建 Release。

标签任务等待两个构建任务成功，下载两份 artifact，校验标签严格等于 `v$(release_version project.godot)`，再创建包含四个文件的 Draft Release。普通 `main` push 只保存 Actions artifacts，不为每次提交创建 GitHub Release，避免发布页被开发快照淹没。

## 8. 测试与放行

自动检查：

- release helper 的平台 stem 与包白名单单元测试。
- 错误平台、缺文件、空文件和额外文件必须被拒绝。
- Godot 完整验证为 0 失败。
- Windows ZIP 完整性、PE32+ x86-64 和 SHA-256。
- macOS ZIP 完整性、`.app` 结构、主程序可执行位、Universal 2 架构、ad-hoc 签名和 SHA-256。
- GitHub Actions 两个平台任务均成功。

人工 macOS 冒烟检查：

- Apple Silicon Mac 解压、首次放行和启动。
- 如果可获得 Intel Mac，再完成一次原生 Intel 启动；没有 Intel 设备时以 `lipo` 双架构证据作为构建关卡，PR 中明确标注 Intel 实机未测。
- 打开与关闭主窗口、菜单、存档、最小化恢复和退出后无残留进程。

macOS 实机检查完成前，Release 保持 Draft。

## 9. 文档同步

- `README.md` 增加 macOS 下载、首次启动和本地构建说明，并把发布章节调整为双平台。
- `ROADMAP.md` 把当前发布焦点更新为 Windows + macOS 双平台内测包，区分自动链路完成与实机放行待完成。
- `BACKLOG.md` 记录选择 Universal 2、ad-hoc 签名、`main` push 自动 artifact 和标签 Draft Release 的原因。
- `release/PLAYTEST.txt` 同时覆盖 Windows 与 macOS，不维护两份容易漂移的说明。

## 10. 非目标

- 不制作 DMG 或安装器。
- 不接入 Developer ID、Apple 公证、App Store、Steam 或自动公开 Release。
- 不在每次 `main` push 时创建永久 Release。
- 不把 CI 成功等同于 Windows 或 macOS 的完整桌面实机验收。
- 不复活已封存的 `fish_display` 实验分支。
