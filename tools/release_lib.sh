#!/bin/sh

release_version() {
	sed -n 's/^config\/version="\([^"]*\)"$/\1/p' "$1"
}

assert_semver() {
	printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

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
