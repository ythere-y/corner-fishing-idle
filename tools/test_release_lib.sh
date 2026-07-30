#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo_root"

. tools/release_lib.sh

test "$(release_version project.godot)" = "0.1.0"
test "$(release_stem 0.1.0)" = "Backpack-and-Bait-v0.1.0-windows-x86_64"
assert_semver "0.1.0"
if assert_semver "v0.1"; then
	echo "无效版本被接受" >&2
	exit 1
fi

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

touch "$fixture/BackpackAndBait.exe"
if assert_package_contents "$fixture"; then
	echo "不完整包被接受" >&2
	exit 1
fi

touch \
	"$fixture/BackpackAndBait.pck" \
	"$fixture/PLAYTEST-LICENSE.txt" \
	"$fixture/PLAYTEST.txt"
if assert_package_contents "$fixture"; then
	echo "空文件包被接受" >&2
	exit 1
fi

printf 'exe\n' > "$fixture/BackpackAndBait.exe"
printf 'pck\n' > "$fixture/BackpackAndBait.pck"
printf 'license\n' > "$fixture/PLAYTEST-LICENSE.txt"
printf 'readme\n' > "$fixture/PLAYTEST.txt"
assert_package_contents "$fixture"

printf 'unexpected\n' > "$fixture/debug.log"
if assert_package_contents "$fixture"; then
	echo "包含额外文件的包被接受" >&2
	exit 1
fi

printf 'release helpers: PASS\n'
