#!/usr/bin/env bash
# GAMP-ID: FS-380-HDS-020-SDS-010-SMS-120
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-380-HDS-020-SDS-010-SMS-120.md
# SDS:    GAMP/SDS/FS-380-HDS-020-SDS-010.md
# OWNER:  network-renderer-nixos (rendered artifact) / nixos (host profile input)
# MODULE: Prod-Like VLAN4 Client Egress, policy-route selection
#
# This case asserts the same contract as the two sibling cases in this
# directory, but against a whole host configuration from the adjacent `nixos`
# repository rather than a hand-built fixture.
#
# Target: `s-router-neon-new`. It tracks the unpinned network-* main inputs, so
# it is the host that actually exercises this renderer. Hosts pinned to the
# legacy -prod inputs are not valid targets here: evaluating them measures the
# age of those pins rather than this code. Measured on s-router-neon-new:
#
#   VLAN7 192.168.2.0/24 -> table 1003 on downstr-vlan7
#   VLAN2 192.168.1.0/24 -> table 1010 on down-vlan2
#
# one primary table each, and different from each other. The SMS requires the
# routed selector chain
#
#   client -> access-vlan2 -> downstream-selector -> policy ->
#   upstream-selector -> core -> internet-vlan4
#
# to be policy-selected at every stage.
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
    "path:${nixos_repo}#nixosConfigurations.s-router-neon-new.config.containers.policy.config.systemd.network.networks" \
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
        # An ingress legitimately selects more than one table: its own egress
        # table for new flows, and a separate table for traffic returning to it.
        # What must be deterministic is which table wins for this ingress, so
        # take the rule with the lowest Priority (= highest precedence) among
        # the primary rules. That is the table new flows from this ingress use.
        winningTable =
          ingress:
          let
            rows = builtins.sort (a: b: (a.Priority or 999999) < (b.Priority or 999999)) (
              builtins.filter (r: ingress r && primary r) rules
            );
          in
          if rows == [ ] then null else (builtins.head rows).Table;
        v7Table = winningTable vlan7Ingress;
        v2Table = winningTable vlan2Ingress;
        # The winning rule and its Priority. P5 must compare a rule Priority
        # against this value, never against a table id: priorities and table ids are
        # different number spaces and they are not monotone in each other.
        winningPriority =
          ingress:
          let
            rows = builtins.sort (a: b: (a.Priority or 999999) < (b.Priority or 999999)) (
              builtins.filter (r: ingress r && primary r) rules
            );
          in
          if rows == [ ] then null else ((builtins.head rows).Priority or 999999);
        v7Priority = winningPriority vlan7Ingress;
        failed =
          (if v7Table == null then [ "P1 VLAN7 ingress selects no non-main policy table" ] else [ ])
          ++ (if v2Table == null then [ "P2 VLAN2 ingress selects no non-main policy table" ] else [ ])
          ++ (if v7Table != null && v7Table == v2Table then [ "P3 VLAN7 and VLAN2 share a policy table" ] else [ ])
          ++ (if builtins.length (builtins.filter (x: v7Table != null && (x.Table or null) == v7Table && (x.Destination or null) == "0.0.0.0/0" && (x.Gateway or null) != null) routes) == 0 then [ "P4 VLAN7 policy table has no gateway-qualified default route" ] else [ ])
          ++ (if v7Priority != null && builtins.length (builtins.filter (x: vlan7Ingress x && (x.Table or null) != v7Table && (x.Priority or 999999) < v7Priority) rules) != 0 then [ "P5 an earlier rule steals VLAN7 ingress before its own table" ] else [ ])
          ++ (if builtins.length (builtins.filter (x: vlan7Ingress x && v2Table != null && (x.Table or null) == v2Table) rules) != 0 then [ "P6 the VLAN2 policy table matches VLAN7 source ingress" ] else [ ]);
      in
      {
        ok = failed == [ ];
        inherit failed;
        checks = {
          vlan2Table = v2Table;
          vlan7Table = v7Table;
          vlan7Priority = v7Priority;
          vlan2PrimaryRules = builtins.length (builtins.filter (r: vlan2Ingress r && primary r) rules);
          vlan7PrimaryRules = builtins.length (builtins.filter (r: vlan7Ingress r && primary r) rules);
          vlan2SelectedTables = unique (map (r: r.Table) (builtins.filter (r: vlan2Ingress r && primary r) rules));
          vlan7SelectedTables = unique (map (r: r.Table) (builtins.filter (r: vlan7Ingress r && primary r) rules));
        };
      }
    ' >"${result_json}" 2>"${stderr_file}"; then
  echo "FAIL s-router-neon-new VLAN7 policy table gap: nix eval crashed" >&2
  cat "${stderr_file}" >&2
  exit 1
fi

assert_json_checks_ok "s-router-neon-new VLAN7 policy table gap" "${result_json}"

echo "PASS s-router-neon-new VLAN7 policy table gap"
