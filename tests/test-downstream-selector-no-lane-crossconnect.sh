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
    def capture_pair:
      capture("^\\s*iifname \"(?<in>[^\"]+)\" oifname \"(?<out>[^\"]+)\".* accept( comment \"(?<comment>[^\"]+)\")?.*$");
    . as $doc
    | def runtime_key_for($unit):
        ($doc.debug.normalizedRuntimeTargets // {})
        | keys[]
        | select(endswith("-" + $unit));
      def access_tail($access):
        if ($access | contains("-access-")) then
          ($access | split("-access-")[-1])
        else
          $access
        end;
      def aliases_by_runtime_if($runtimeTarget):
        reduce (($runtimeTarget.effectiveRuntimeRealization.interfaces // {}) | to_entries[]) as $iface ({};
          ($iface.value.backingRef.lane.kind // "") as $kind
          | ($iface.value.backingRef.lane.access // null) as $access
          | ($iface.value.runtimeIfName // null) as $runtimeIf
          | if $runtimeIf == null or $access == null then
              .
            else
              .[$runtimeIf] = (
                (.[$runtimeIf] // [])
                + (
                  if $kind == "access-edge" then
                    [ "access-" + (access_tail($access)) ]
                  elif $kind == "access" then
                    [ "policy-" + (access_tail($access)) ]
                  else
                    []
                  end
                )
              )
            end
        );
      def iface_matches($aliases; $expected; $actual):
        $expected == $actual or (($aliases[$expected] // []) | index($actual) != null);
      def cpm_rule_exists($unit; $pair):
        [
          runtime_key_for($unit) as $runtimeKey
          | ($doc.debug.normalizedRuntimeTargets[$runtimeKey]) as $runtimeTarget
          | (aliases_by_runtime_if($runtimeTarget)) as $aliases
          | (($runtimeTarget.forwardingIntent.rules // [])[])
          | select((.action // "accept") == "accept")
          | select(iface_matches($aliases; (.fromInterface // ""); $pair.in))
          | select(iface_matches($aliases; (.toInterface // ""); $pair.out))
          | select(
              ($pair.comment // "") == ""
              or (.relationId // .comment // "") == $pair.comment
            )
        ]
        | length > 0;

    $doc.render.containers
    | to_entries[] as $host
    | $host.value
    | to_entries[]
    | select((.value.specialArgs.s88RoleName // "") == "downstream-selector")
    | . as $container
    | (($container.value.firewall.ruleset // "") | split("\n")[] | select(access_access or policy_policy)) as $ruleLine
    | ($ruleLine | capture_pair) as $pair
    | select(cpm_rule_exists($container.key; $pair) | not)
    | "!!!! " + $example
      + " host=" + $host.key
      + " downstream-selector=" + $container.key
      + " emits downstream selector access/policy lane cross-connect not backed by CPM forwardingIntent: " + $ruleLine
  ' "${dry_json}"
}

run_example_render_scan \
  "downstream-selector-no-lane-crossconnect" \
  check_downstream_selector_lane_crossconnects
