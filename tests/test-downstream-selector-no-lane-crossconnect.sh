#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"
source "${repo_root}/tests/lib/example-render-scan.sh"

check_downstream_selector_lane_crossconnects() {
  local example_dir="$1"
  local dry_json="$2"

  _jq -r --arg example "${example_dir}" '
    def lane_expr(prefix):
      "(\"" + prefix + "-[^\"]+\"|\\{[^}]*\"" + prefix + "-[^\"]+\"[^}]*\\})";
    def access_access:
      test("^\\s*iifname " + lane_expr("access") + " oifname " + lane_expr("access") + ".* accept($| )");
    def policy_policy:
      test("^\\s*iifname " + lane_expr("policy") + " oifname " + lane_expr("policy") + ".* accept($| )");

    .render.containers
    | to_entries[] as $host
    | $host.value
    | to_entries[]
    | select((.value.specialArgs.s88RoleName // "") == "downstream-selector")
    | . as $container
    | (($container.value.firewall.ruleset // "") | split("\n")[] | select(access_access or policy_policy))
    | "!!!! " + $example
      + " host=" + $host.key
      + " downstream-selector=" + $container.key
      + " illegally cross-connects access/policy lanes: " + .
  ' "${dry_json}"
}

run_example_render_scan \
  "downstream-selector-no-lane-crossconnect" \
  check_downstream_selector_lane_crossconnects
