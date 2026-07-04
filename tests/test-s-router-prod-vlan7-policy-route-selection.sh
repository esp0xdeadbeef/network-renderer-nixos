#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

nixos_repo="${NIXOS_REPO_PATH:-${repo_root}/../nixos}"
[[ -f "${nixos_repo}/flake.nix" ]] || fail "missing adjacent nixos flake: ${nixos_repo}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

result_json="${tmp_dir}/s-router-prod-vlan7-policy-route-selection.json"
stderr_file="${tmp_dir}/nix-eval.stderr"

nix_eval_json_or_fail "s-router-prod VLAN7 policy route selection" "${result_json}" "${stderr_file}" \
  nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json \
    --override-input network-renderer-nixos "path:${repo_root}" \
    --override-input network-renderer-nixos-prod "path:${repo_root}" \
    "path:${nixos_repo}#nixosConfigurations.s-router-prod.config.containers.policy.config.systemd.network.networks" \
    --apply '
      networks:
      let
        names = builtins.attrNames networks;
        concat = builtins.concatLists;
        rules =
          concat (
            map (
              name:
              map (rule: rule // { unit = name; }) ((networks.${name}.routingPolicyRules or [ ]))
            ) names
          );
        routes =
          concat (
            map (
              name:
              map (route: route // { unit = name; }) ((networks.${name}.routes or [ ]))
            ) names
          );
        vlan7IngressRule =
          rule:
          (rule.Family or null) == "ipv4"
          && (rule.From or null) == "192.168.2.0/24"
          && (rule.IncomingInterface or null) == "downstr-vlan7";
        correctVlan7Rules =
          builtins.filter (
            rule:
            vlan7IngressRule rule
            && (rule.Table or null) == 1004
            && (rule.Priority or null) == 1004
          ) rules;
        earlierStealingRules =
          builtins.filter (
            rule:
            vlan7IngressRule rule
            && (rule.Table or null) != 1004
            && (rule.Priority or 999999) < 1004
          ) rules;
        vlan7DefaultRoutes =
          builtins.filter (
            route:
            (route.Table or null) == 1004
            && (route.Destination or null) == "0.0.0.0/0"
            && (route.Gateway or null) == "10.10.0.13"
          ) routes;
        vlan2StealsVlan7 =
          builtins.filter (
            rule:
            vlan7IngressRule rule
            && (rule.Table or null) == 1003
          ) rules;
        missingCorrect =
          if correctVlan7Rules == [ ] then
            [ "missing from 192.168.2.0/24 iif downstr-vlan7 table 1004 rule" ]
          else
            [ ];
        hasSteals =
          if earlierStealingRules != [ ] then
            [ "earlier non-1004 rule steals VLAN7 ingress before table 1004" ]
          else
            [ ];
        missingDefault =
          if vlan7DefaultRoutes == [ ] then
            [ "missing table 1004 default route via 10.10.0.13" ]
          else
            [ ];
        hasVlan2Steal =
          if vlan2StealsVlan7 != [ ] then
            [ "table 1003 still matches VLAN7 source ingress" ]
          else
            [ ];
        failed = missingCorrect ++ hasSteals ++ missingDefault ++ hasVlan2Steal;
      in
      {
        ok = failed == [ ];
        inherit failed;
        checks = {
          correctVlan7Rules = builtins.length correctVlan7Rules;
          earlierStealingRules = builtins.length earlierStealingRules;
          vlan2StealsVlan7 = builtins.length vlan2StealsVlan7;
          vlan7DefaultRoutes = builtins.length vlan7DefaultRoutes;
          matchingRules = builtins.filter vlan7IngressRule rules;
        };
      }
    '

assert_json_checks_ok "s-router-prod VLAN7 policy route selection" "${result_json}"

echo "PASS s-router-prod VLAN7 policy route selection"
