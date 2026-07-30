#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

. tools/release_lib.sh

if [ "$(uname -s)" != "Darwin" ]; then
	echo "macOS Universal 包必须在 macOS 主机上构建。" >&2
	exit 1
fi

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

stem=$(release_stem macos_universal "$version")
mkdir -p dist
staging_dir=$(mktemp -d "$repo_root/dist/.staging-$stem.XXXXXX")
unpack_dir=
cleanup() {
	rm -rf -- "$staging_dir"
	if [ -n "$unpack_dir" ]; then
		rm -rf -- "$unpack_dir"
	fi
}
trap cleanup EXIT HUP INT TERM

package_dir="$staging_dir/$stem"
app_path="$package_dir/BackpackAndBait.app"
mkdir -p "$package_dir"

import_log="$repo_root/dist/import-$version.log"
validate_log="$repo_root/dist/validate-$version.log"
export_log="$repo_root/dist/export-macos-$version.log"

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
	--export-release "macOS" "$app_path"; then
	echo "macOS 导出失败。请确认已安装 Godot $godot_version 对应的官方导出模板。日志：$export_log" >&2
	exit 1
fi

cp release/PLAYTEST.txt release/PLAYTEST-LICENSE.txt "$package_dir/"

verify_macos_package() {
	verified_package_dir=$1
	verified_version=$2
	verified_app_path="$verified_package_dir/BackpackAndBait.app"
	assert_macos_package_contents "$verified_package_dir"

	plist="$verified_app_path/Contents/Info.plist"
	test -s "$plist"
	bundle_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
	short_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
	bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
	test "$short_version" = "$verified_version"
	test "$bundle_version" = "$verified_version"

	binary="$verified_app_path/Contents/MacOS/$bundle_executable"
	pck="$verified_app_path/Contents/Resources/$bundle_executable.pck"
	test -x "$binary"
	test -s "$binary"
	test -f "$pck"
	test -s "$pck"

	architectures=$(lipo -archs "$binary")
	printf '%s\n' "$architectures" | grep -Eq '(^| )x86_64( |$)'
	printf '%s\n' "$architectures" | grep -Eq '(^| )arm64( |$)'
	codesign --verify --deep --strict "$verified_app_path"
	codesign -dv --verbose=4 "$verified_app_path" 2>&1 | grep -q '^Signature=adhoc$'
}

verify_macos_package "$package_dir" "$version"

artifact="$repo_root/dist/$stem.zip"
ditto -c -k --keepParent "$package_dir" "$artifact"

if command -v shasum >/dev/null 2>&1; then
	checksum_tool=shasum
	(cd "$repo_root/dist" && shasum -a 256 "$stem.zip") > "$artifact.sha256"
elif command -v sha256sum >/dev/null 2>&1; then
	checksum_tool=sha256sum
	(cd "$repo_root/dist" && sha256sum "$stem.zip") > "$artifact.sha256"
else
	echo "缺少 shasum 或 sha256sum，无法生成校验文件。" >&2
	exit 1
fi

if [ "$checksum_tool" = shasum ]; then
	if ! (cd "$repo_root/dist" && shasum -a 256 -c "$stem.zip.sha256"); then
		echo "最终 ZIP 的 SHA-256 校验失败：$artifact" >&2
		exit 1
	fi
else
	if ! (cd "$repo_root/dist" && sha256sum -c "$stem.zip.sha256"); then
		echo "最终 ZIP 的 SHA-256 校验失败：$artifact" >&2
		exit 1
	fi
fi

unpack_dir=$(mktemp -d "$repo_root/dist/.verify-$stem.XXXXXX")
ditto -x -k "$artifact" "$unpack_dir"
verify_macos_package "$unpack_dir/$stem" "$version"

printf 'macOS Universal 试玩包已生成：\n%s\n%s\n' "$artifact" "$artifact.sha256"
