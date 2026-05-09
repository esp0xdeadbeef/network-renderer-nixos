#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"
source "${repo_root}/tests/lib/example-render-scan.sh"

check_no_invalid_actions() {
  local example_dir="$1"
  local dry_json="$2"

  _jq -r --arg example "${example_dir}" '
    [
      .render.containers
      | to_entries[] as $host
      | $host.value
      | to_entries[]
      | . as $container
      | (($container.value.firewall.ruleset // "") | split("\n")[] | select(test("(^|[[:space:]])deny([[:space:]]|$)")))
      | {
          host: $host.key,
          container: $container.key,
          rule: .
        }
    ][]
    | "!!!! " + $example
      + " host=" + .host
      + " container=" + .container
      + " renders semantic deny as nft action instead of materializing drop: "
      + .rule
  ' "${dry_json}"
}

run_example_render_scan \
  "policy-firewall-no-invalid-actions" \
  check_no_invalid_actions
