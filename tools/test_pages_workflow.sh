#!/bin/sh
set -eu

workflow=".github/workflows/pages.yml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  pattern="$1"
  description="$2"
  grep -Eq -- "$pattern" "$workflow" || fail "$description"
}

test -f "$workflow" || fail "$workflow does not exist"

assert_contains '^name: Web Pages$' 'workflow name is missing'
assert_contains '^  push:$' 'main push trigger is missing'
assert_contains '^      - main$' 'main branch filter is missing'
assert_contains '^  workflow_dispatch:$' 'manual trigger is missing'
assert_contains '^  pages: write$' 'Pages write permission is missing'
assert_contains '^  id-token: write$' 'OIDC permission is missing'
assert_contains 'uses: actions/checkout@v4' 'checkout action is missing'
assert_contains 'tools/validate_game\.gd' 'project validation is missing'
assert_contains '--export-release "Web" dist/web/index\.html' 'Web export is missing'
assert_contains 'uses: actions/configure-pages@v5' 'Pages configuration is missing'
assert_contains 'uses: actions/upload-pages-artifact@v3' 'Pages artifact upload is missing'
assert_contains '^          path: dist/web$' 'Web artifact path is incorrect'
assert_contains 'uses: actions/deploy-pages@v5' 'Pages deployment is missing'
assert_contains '^[[:space:]]+name: github-pages$' 'github-pages environment is missing'

printf 'pages workflow structure: PASS\n'
