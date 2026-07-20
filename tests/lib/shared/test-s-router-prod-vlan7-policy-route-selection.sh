#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"
source "${repo_root}/tests/lib/adjacent-repo-paths.sh"

migration_candidate_requested=0
if [[ -n "${NIXOS_REPO_PATH:-}" ]]; then
  migration_candidate_requested=1
fi
nixos_repo="$(resolve_adjacent_repo NIXOS_REPO_PATH nixos)"
[[ -f "${nixos_repo}/flake.nix" ]] || fail "missing adjacent nixos flake: ${nixos_repo}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

result_json="${tmp_dir}/s-router-prod-vlan7-policy-route-selection.json"
stderr_file="${tmp_dir}/nix-eval.stderr"

if ! nix eval \
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
        vlan2IngressRule =
          rule:
          (rule.Family or null) == "ipv4"
          && (rule.From or null) == "192.168.1.0/24"
          && (rule.IncomingInterface or null) == "down-vlan2";
        primaryRule =
          rule:
          (rule.Table or 254) != 254
          && (rule.SuppressPrefixLength or null) == null;
        unique = values: builtins.attrValues (builtins.listToAttrs (map (value: {
          name = toString value;
          inherit value;
        }) values));
        vlan7PrimaryRules = builtins.filter (rule: vlan7IngressRule rule && primaryRule rule) rules;
        vlan2PrimaryRules = builtins.filter (rule: vlan2IngressRule rule && primaryRule rule) rules;
        vlan7Tables = unique (map (rule: rule.Table) vlan7PrimaryRules);
        vlan2Tables = unique (map (rule: rule.Table) vlan2PrimaryRules);
        vlan7Table = if builtins.length vlan7Tables == 1 then builtins.head vlan7Tables else null;
        vlan2Table = if builtins.length vlan2Tables == 1 then builtins.head vlan2Tables else null;
        correctVlan7Rules =
          builtins.filter (
            rule:
            vlan7IngressRule rule
            && primaryRule rule
            && (rule.Table or null) == vlan7Table
            && (rule.Priority or null) == vlan7Table
          ) rules;
        earlierStealingRules =
          builtins.filter (
            rule:
            vlan7IngressRule rule
            && (rule.Table or null) != vlan7Table
            && (rule.Priority or 999999) < (if vlan7Table == null then 0 else vlan7Table)
          ) rules;
        vlan7DefaultRoutes =
          builtins.filter (
            route:
            vlan7Table != null
            && (route.Table or null) == vlan7Table
            && (route.Destination or null) == "0.0.0.0/0"
            && (route.Gateway or null) != null
          ) routes;
        vlan2StealsVlan7 =
          builtins.filter (
            rule:
            vlan7IngressRule rule
            && vlan2Table != null
            && (rule.Table or null) == vlan2Table
          ) rules;
        ambiguousVlan7Table =
          if builtins.length vlan7Tables != 1 then
            [ "VLAN7 ingress does not resolve to exactly one non-main policy table" ]
          else
            [ ];
        ambiguousVlan2Table =
          if builtins.length vlan2Tables != 1 then
            [ "VLAN2 ingress does not resolve to exactly one non-main policy table" ]
          else
            [ ];
        sharedTenantTable =
          if vlan7Table != null && vlan7Table == vlan2Table then
            [ "VLAN7 and VLAN2 share a policy table" ]
          else
            [ ];
        missingCorrect =
          if correctVlan7Rules == [ ] then
            [ "missing VLAN7 source/interface rule for its allocated policy table" ]
          else
            [ ];
        hasSteals =
          if earlierStealingRules != [ ] then
            [ "earlier non-1004 rule steals VLAN7 ingress before table 1004" ]
          else
            [ ];
        missingDefault =
          if vlan7DefaultRoutes == [ ] then
            [ "missing gateway-qualified default route in the allocated VLAN7 policy table" ]
          else
            [ ];
        hasVlan2Steal =
          if vlan2StealsVlan7 != [ ] then
            [ "the VLAN2 policy table still matches VLAN7 source ingress" ]
          else
            [ ];
        failed =
          ambiguousVlan7Table
          ++ ambiguousVlan2Table
          ++ sharedTenantTable
          ++ missingCorrect
          ++ hasSteals
          ++ missingDefault
          ++ hasVlan2Steal;
      in
      {
        ok = failed == [ ];
        inherit failed;
        checks = {
          correctVlan7Rules = builtins.length correctVlan7Rules;
          earlierStealingRules = builtins.length earlierStealingRules;
          vlan2StealsVlan7 = builtins.length vlan2StealsVlan7;
          vlan7DefaultRoutes = builtins.length vlan7DefaultRoutes;
          inherit vlan2Table vlan7Table;
          matchingRules = builtins.filter vlan7IngressRule rules;
          matchingVlan2SourceRules = builtins.filter (
            rule: (rule.Family or null) == "ipv4" && (rule.From or null) == "192.168.1.0/24"
          ) rules;
        };
      }
    ' >"${result_json}" 2>"${stderr_file}"; then
  if [[ "${migration_candidate_requested}" -eq 0 ]] \
    && grep -Fq "FS-230-HDS-010-SDS-010-SMS-030" "${stderr_file}" \
    && grep -Fq "reverse-new-flow authority invention" "${stderr_file}"; then
    echo "PASS s-router-prod legacy source fails closed until explicit return authority is migrated"
    exit 0
  fi
  echo "FAIL s-router-prod VLAN7 policy route selection: nix eval crashed" >&2
  cat "${stderr_file}" >&2
  exit 1
fi

assert_json_checks_ok "s-router-prod VLAN7 policy route selection" "${result_json}"

echo "PASS s-router-prod VLAN7 policy route selection"
