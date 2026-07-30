#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

. tools/release_lib.sh

if [ -n "${GODOT_BIN:-}" ]; then
	godot_bin=$GODOT_BIN
elif command -v godot >/dev/null 2>&1; then
	godot_bin=$(command -v godot)
elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
	godot_bin=/Applications/Godot.app/Contents/MacOS/Godot
else
	echo "未找到 Godot 4.6；请设置 GODOT_BIN=/path/to/godot。" >&2
	exit 1
fi

if [ ! -x "$godot_bin" ]; then
	echo "Godot 不可执行：$godot_bin" >&2
	exit 1
fi

tracked_status=$(git status --porcelain --untracked-files=no)
if [ -n "$tracked_status" ]; then
	echo "受版本控制文件存在未提交改动，拒绝构建：" >&2
	printf '%s\n' "$tracked_status" >&2
	exit 1
fi

godot_version=$("$godot_bin" --version)
if ! printf '%s\n' "$godot_version" | grep -Eq '^4\.6(\.|-)'; then
	echo "需要 Godot 4.6，当前为：$godot_version" >&2
	exit 1
fi

version=$(release_version project.godot)
if ! assert_semver "$version"; then
	echo "project.godot 的 config/version 不是 SemVer：$version" >&2
	exit 1
fi

stem=$(release_stem "$version")
mkdir -p dist
staging_dir=$(mktemp -d "$repo_root/dist/.staging-$stem.XXXXXX")
trap 'rm -rf -- "$staging_dir"' EXIT
package_dir="$staging_dir/$stem"
mkdir -p "$package_dir"

import_log="$repo_root/dist/import-$version.log"
validate_log="$repo_root/dist/validate-$version.log"
export_log="$repo_root/dist/export-$version.log"

if ! "$godot_bin" --headless --editor --quit --path . --log-file "$import_log"; then
	echo "Godot 首次导入失败，日志：$import_log" >&2
	exit 1
fi

if ! "$godot_bin" --headless --path . --log-file "$validate_log" -s tools/validate_game.gd; then
	echo "游戏验证失败，日志：$validate_log" >&2
	exit 1
fi
if ! grep -q '=== 结果: 0 失败 ===' "$validate_log"; then
	echo "验证日志未出现“0 失败”，拒绝导出：$validate_log" >&2
	exit 1
fi

if ! "$godot_bin" --headless --path . --log-file "$export_log" \
	--export-release "Windows Desktop" "$package_dir/BackpackAndBait.exe"; then
	echo "Windows 导出失败。请确认已安装 Godot $godot_version 对应的官方导出模板。日志：$export_log" >&2
	exit 1
fi

cp release/开始游玩.txt release/内测许可.txt "$package_dir/"
assert_package_contents "$package_dir"

archive_tmp="$staging_dir/$stem.zip"
(cd "$staging_dir" && zip -X -q -r "$archive_tmp" "$stem")
artifact="$repo_root/dist/$stem.zip"
mv -f "$archive_tmp" "$artifact"

if command -v shasum >/dev/null 2>&1; then
	(cd "$repo_root/dist" && shasum -a 256 "$stem.zip") > "$artifact.sha256"
elif command -v sha256sum >/dev/null 2>&1; then
	(cd "$repo_root/dist" && sha256sum "$stem.zip") > "$artifact.sha256"
else
	echo "缺少 shasum 或 sha256sum，无法生成校验文件。" >&2
	exit 1
fi

printf 'Windows 试玩包已生成：\n%s\n%s\n' "$artifact" "$artifact.sha256"
