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

printf 'release helpers: PASS\n'
