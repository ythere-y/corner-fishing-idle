#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

. tools/release_lib.sh

test "$(release_version project.godot)" = "0.1.0"
test "$(release_stem windows_x86_64 0.1.0)" = \
	"Backpack-and-Bait-v0.1.0-windows-x86_64"
test "$(release_stem macos_universal 0.1.0)" = \
	"Backpack-and-Bait-v0.1.0-macos-universal"
if release_stem linux_x86_64 0.1.0 >/dev/null 2>&1; then
	echo "未知平台被接受" >&2
	exit 1
fi
assert_semver "0.1.0"
if assert_semver "v0.1"; then
	echo "无效版本被接受" >&2
	exit 1
fi

windows_fixture=$(mktemp -d)
macos_fixture=$(mktemp -d)
windows_missing_fixture=$(mktemp -d)
windows_empty_fixture=$(mktemp -d)
windows_extra_fixture=$(mktemp -d)
macos_missing_fixture=$(mktemp -d)
macos_empty_fixture=$(mktemp -d)
macos_extra_fixture=$(mktemp -d)
trap 'rm -rf "$windows_fixture" "$macos_fixture" "$windows_missing_fixture" "$windows_empty_fixture" "$windows_extra_fixture" "$macos_missing_fixture" "$macos_empty_fixture" "$macos_extra_fixture"' EXIT

printf 'exe\n' > "$windows_fixture/BackpackAndBait.exe"
printf 'pck\n' > "$windows_fixture/BackpackAndBait.pck"
printf 'license\n' > "$windows_fixture/PLAYTEST-LICENSE.txt"
printf 'readme\n' > "$windows_fixture/PLAYTEST.txt"
assert_windows_package_contents "$windows_fixture"

mkdir -p "$macos_fixture/BackpackAndBait.app"
printf 'license\n' > "$macos_fixture/PLAYTEST-LICENSE.txt"
printf 'readme\n' > "$macos_fixture/PLAYTEST.txt"
assert_macos_package_contents "$macos_fixture"

printf 'exe\n' > "$windows_missing_fixture/BackpackAndBait.exe"
if assert_windows_package_contents "$windows_missing_fixture"; then
	echo "Windows 不完整包被接受" >&2
	exit 1
fi

touch \
	"$windows_empty_fixture/BackpackAndBait.exe" \
	"$windows_empty_fixture/BackpackAndBait.pck" \
	"$windows_empty_fixture/PLAYTEST-LICENSE.txt" \
	"$windows_empty_fixture/PLAYTEST.txt"
if assert_windows_package_contents "$windows_empty_fixture"; then
	echo "Windows 空文件包被接受" >&2
	exit 1
fi

printf 'exe\n' > "$windows_extra_fixture/BackpackAndBait.exe"
printf 'pck\n' > "$windows_extra_fixture/BackpackAndBait.pck"
printf 'license\n' > "$windows_extra_fixture/PLAYTEST-LICENSE.txt"
printf 'readme\n' > "$windows_extra_fixture/PLAYTEST.txt"
printf 'unexpected\n' > "$windows_extra_fixture/debug.log"
if assert_windows_package_contents "$windows_extra_fixture"; then
	echo "Windows 包额外文件未被拒绝" >&2
	exit 1
fi

mkdir -p "$macos_missing_fixture/BackpackAndBait.app"
printf 'license\n' > "$macos_missing_fixture/PLAYTEST-LICENSE.txt"
if assert_macos_package_contents "$macos_missing_fixture"; then
	echo "macOS 不完整包被接受" >&2
	exit 1
fi

mkdir -p "$macos_empty_fixture/BackpackAndBait.app"
touch "$macos_empty_fixture/PLAYTEST-LICENSE.txt" "$macos_empty_fixture/PLAYTEST.txt"
if assert_macos_package_contents "$macos_empty_fixture"; then
	echo "macOS 空文件包被接受" >&2
	exit 1
fi

mkdir -p "$macos_extra_fixture/BackpackAndBait.app"
printf 'license\n' > "$macos_extra_fixture/PLAYTEST-LICENSE.txt"
printf 'readme\n' > "$macos_extra_fixture/PLAYTEST.txt"
printf 'unexpected\n' > "$macos_extra_fixture/debug.log"
if assert_macos_package_contents "$macos_extra_fixture"; then
	echo "macOS 包额外文件未被拒绝" >&2
	exit 1
fi

printf 'release helpers: PASS\n'
