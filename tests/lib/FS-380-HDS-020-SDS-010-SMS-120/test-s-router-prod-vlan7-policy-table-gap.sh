#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-380-HDS-020-SDS-010-SMS-120.md
# SDS:    GAMP/SDS/FS-380-HDS-020-SDS-010.md
# OWNER:  network-renderer-nixos (rendered artifact) / nixos (host profile input)
# MODULE: Prod-Like VLAN4 Client Egress, policy-route selection
#
# EXPECTED TO FAIL. The renderer-side contract is implemented and proven by the
# two sibling cases in this directory. This case asserts the same contract
# against the adjacent `nixos` repository's `s-router-prod` host configuration,
# and that configuration currently renders no primary policy rule for either
# modelled downstream VLAN:
#
#   vlan2Table = null, vlan7Table = null
#
# so neither VLAN's ingress selects an allocated policy table. The SMS requires
# the routed selector chain
#
#   client -> access-vlan2 -> downstream-selector -> policy ->
#   upstream-selector -> core -> internet-vlan4
#
# to be policy-selected at every stage. Do not weaken this case to pass:
# supply the missing `s-router-prod` realisation input.
#
# Predicates asserted (from the SMS):
#   P1  VLAN7 ingress selects exactly one non-main policy table.
#   P2  VLAN2 ingress selects exactly one non-main policy table.
#   P3  VLAN7 and VLAN2 do not share a policy table.
#   P4  The VLAN7 policy table carries a gateway-qualified default route.
#   P5  No earlier rule steals VLAN7 ingress before its own table.
#   P6  The VLAN2 policy table does not match VLAN7 source ingress.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"
source "${repo_root}/tests/lib/adjacent-repo-paths.sh"

nixos_repo="$(resolve_adjacent_repo NIXOS_REPO_PATH nixos)"
[[ -f "${nixos_repo}/flake.nix" ]] || fail "missing adjacent nixos flake: ${nixos_repo}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

result_json="${tmp_dir}/gap.json"
stderr_file="${tmp_dir}/gap.stderr"

if ! nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json \
    --override-input network-renderer-nixos "path:${repo_root}" \
    "path:${nixos_repo}#nixosConfigurations.s-router-prod.config.containers.policy.config.systemd.network.networks" \
    --apply '
      networks:
      let
        names = builtins.attrNames networks;
        concat = builtins.concatLists;
        rules = concat (map (n: map (r: r // { unit = n; }) ((networks.${n}.routingPolicyRules or [ ]))) names);
        routes = concat (map (n: map (r: r // { unit = n; }) ((networks.${n}.routes or [ ]))) names);
        vlan7Ingress =
          r:
          (r.Family or null) == "ipv4"
          && (r.From or null) == "192.168.2.0/24"
          && (r.IncomingInterface or null) == "downstr-vlan7";
        vlan2Ingress =
          r:
          (r.Family or null) == "ipv4"
          && (r.From or null) == "192.168.1.0/24"
          && (r.IncomingInterface or null) == "down-vlan2";
        primary = r: (r.Table or 254) != 254 && (r.SuppressPrefixLength or null) == null;
        unique = vs: builtins.attrValues (builtins.listToAttrs (map (v: { name = toString v; value = v; }) vs));
        v7 = unique (map (r: r.Table) (builtins.filter (r: vlan7Ingress r && primary r) rules));
        v2 = unique (map (r: r.Table) (builtins.filter (r: vlan2Ingress r && primary r) rules));
        v7Table = if builtins.length v7 == 1 then builtins.head v7 else null;
        v2Table = if builtins.length v2 == 1 then builtins.head v2 else null;
        failed =
          (if builtins.length v7 != 1 then [ "P1 VLAN7 ingress does not select exactly one non-main policy table" ] else [ ])
          ++ (if builtins.length v2 != 1 then [ "P2 VLAN2 ingress does not select exactly one non-main policy table" ] else [ ])
          ++ (if v7Table != null && v7Table == v2Table then [ "P3 VLAN7 and VLAN2 share a policy table" ] else [ ])
          ++ (if builtins.length (builtins.filter (x: v7Table != null && (x.Table or null) == v7Table && (x.Destination or null) == "0.0.0.0/0" && (x.Gateway or null) != null) routes) == 0 then [ "P4 VLAN7 policy table has no gateway-qualified default route" ] else [ ])
          ++ (if builtins.length (builtins.filter (x: vlan7Ingress x && (x.Table or null) != v7Table && (x.Priority or 999999) < (if v7Table == null then 0 else v7Table)) rules) != 0 then [ "P5 an earlier rule steals VLAN7 ingress before its own table" ] else [ ])
          ++ (if builtins.length (builtins.filter (x: vlan7Ingress x && v2Table != null && (x.Table or null) == v2Table) rules) != 0 then [ "P6 the VLAN2 policy table matches VLAN7 source ingress" ] else [ ]);
      in
      {
        ok = failed == [ ];
        inherit failed;
        checks = {
          vlan2Table = v2Table;
          vlan7Table = v7Table;
          vlan2PrimaryRules = builtins.length (builtins.filter (r: vlan2Ingress r && primary r) rules);
          vlan7PrimaryRules = builtins.length (builtins.filter (r: vlan7Ingress r && primary r) rules);
        };
      }
    ' >"${result_json}" 2>"${stderr_file}"; then
  echo "FAIL s-router-prod VLAN7 policy table gap: nix eval crashed" >&2
  cat "${stderr_file}" >&2
  exit 1
fi

assert_json_checks_ok "s-router-prod VLAN7 policy table gap" "${result_json}"

echo "PASS s-router-prod VLAN7 policy table gap"
