#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"
source "${repo_root}/tests/lib/example-render-scan.sh"

check_policy_unscoped_catchalls() {
  local example_dir="$1"
  local dry_json="$2"

  _jq -r --arg example "${example_dir}" '
    def bare_pair_accept:
      test("^\\s*iifname .+ oifname .+ accept$");

    [
      .render.containers
      | to_entries[] as $host
      | $host.value
      | to_entries[]
      | select((.value.specialArgs.s88RoleName // "") == "policy")
      | . as $container
      | (($container.value.firewall.ruleset // "") | split("\n")[] | select(bare_pair_accept))
      | {
          host: $host.key,
          policy: $container.key,
          rule: .
        }
    ]
    | sort_by(.host, .policy)
    | group_by(.host + "\u0000" + .policy)[]
    | . as $group
    | (
        $group[0]
        | "!!!! " + $example
          + " host=" + .host
          + " policy=" + .policy
          + " has " + ($group | length | tostring)
          + " unscoped catch-all forwarding rules not tied to intent relations"
      ),
      (
        $group[:8][]
        | "!!!!   sample: " + .rule
      )
  ' "${dry_json}"
}

run_example_render_scan \
  "policy-firewall-no-unscoped-catchall" \
  check_policy_unscoped_catchalls
