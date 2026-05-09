#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"
source "${repo_root}/tests/lib/example-render-scan.sh"

check_upstream_selector_core_crossconnects() {
  local example_dir="$1"
  local dry_json="$2"

  _jq -r --arg example "${example_dir}" '
    def core_expr: "(\"core-[^\"]+\"|\\{[^}]*\"core-[^\"]+\"[^}]*\\})";
    def bad_core_pair:
      test("^\\s*iifname " + core_expr + " oifname " + core_expr + ".* accept($| )");

    .render.containers
    | to_entries[] as $host
    | $host.value
    | to_entries[]
    | select((.value.specialArgs.s88RoleName // "") == "upstream-selector")
    | . as $container
    | (($container.value.firewall.ruleset // "") | split("\n")[] | select(bad_core_pair))
    | "!!!! " + $example
      + " host=" + $host.key
      + " upstream-selector=" + $container.key
      + " illegally cross-connects core uplinks: " + .
  ' "${dry_json}"
}

run_example_render_scan \
  "upstream-selector-no-core-crossconnect" \
  check_upstream_selector_core_crossconnects
