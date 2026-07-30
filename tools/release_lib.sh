#!/bin/sh

release_version() {
	sed -n 's/^config\/version="\([^"]*\)"$/\1/p' "$1"
}

assert_semver() {
	printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

release_stem() {
	printf 'Backpack-and-Bait-v%s-windows-x86_64\n' "$1"
}

assert_package_contents() {
	package_dir=$1
	actual=$(find "$package_dir" -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort)
	expected=$(printf '%s\n' BackpackAndBait.exe BackpackAndBait.pck 内测许可.txt 开始游玩.txt | LC_ALL=C sort)
	test "$actual" = "$expected"
}
