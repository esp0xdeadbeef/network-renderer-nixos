#!/usr/bin/env bash
# GAMP-ID: FS-720-HDS-010-SDS-015-SMS-010
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-720-HDS-010-SDS-015-SMS-010.md
# OWNER:  network-renderer-nixos
#
# Predicates (from the SMS Consumed/Emitted contract): consume the canonical
# endpoint fixture, logical attachment and bridge-ID facts, and emit
# `systemd.network.netdevs` containing exactly one bridge netdev per effective
# bridge name.
#
# Behavioural: the emitter is called directly and its output asserted, so this
# case tests the function rather than the text of the file. Three fixtures:
# two PPPoE uplinks on distinct bridges, two on the same bridge, and one that is
# not PPPoE at all.
#
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL bridge-netdev-emission: $*" >&2; exit 1; }

emitter="s88/ControlModule/render/container-networks/pppoe-vlan-bridge.nix"
[[ -f "${repo_root}/${emitter}" ]] || fail "P1 the bridge netdev emitter does not exist at ${emitter}"

run_emitter() {
  local expr="$1"
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
      pkgs = import f.inputs.nixpkgs { };
      emit = import "'"${repo_root}/${emitter}"'" { lib = pkgs.lib; };
    in
      '"${expr}"'
  '
}

# Fixture A: two PPPoE uplinks on distinct bridges -> two bridge netdevs.
outA="$(run_emitter '
  let
    r = emit {
      interfaces = {
        eth0 = { _s88PppoeOwned = true; assignedUplinkName = "u0"; };
        eth1 = { _s88PppoeOwned = true; assignedUplinkName = "u1"; };
      };
      interfaceNames = [ "eth0" "eth1" ];
      renderedInterfaceNames = { eth0 = "ens3"; eth1 = "ens4"; };
      uplinks = {
        u0 = { mode = "pppoe"; vlan = 300; bridge = "br-wan-a"; };
        u1 = { mode = "pppoe"; vlan = 301; bridge = "br-wan-b"; };
      };
      wanUplinkName = "u0";
    };
  in
    { names = map (n: r.netdevs.${n}.netdevConfig.Name or null) (builtins.attrNames r.netdevs); }
' 2>&1)" || fail "P1 the emitter could not be evaluated
${outA}"

bridgesA="$(jq -r '[.names[] | select(. != null) | select(test("^br-"))] | sort | join(",")' <<<"${outA}")"
[[ "${bridgesA}" == "br-wan-a,br-wan-b" ]] \
  || fail "P1 expected one bridge netdev per distinct effective bridge name (br-wan-a,br-wan-b), got '${bridgesA}'"

# Fixture B: two PPPoE uplinks on the SAME bridge -> exactly one bridge netdev,
# because the netdev is keyed by bridge name and the emission must not duplicate.
outB="$(run_emitter '
  let
    r = emit {
      interfaces = {
        eth0 = { _s88PppoeOwned = true; assignedUplinkName = "u0"; };
        eth1 = { _s88PppoeOwned = true; assignedUplinkName = "u1"; };
      };
      interfaceNames = [ "eth0" "eth1" ];
      renderedInterfaceNames = { eth0 = "ens3"; eth1 = "ens4"; };
      uplinks = {
        u0 = { mode = "pppoe"; vlan = 300; bridge = "br-wan-same"; };
        u1 = { mode = "pppoe"; vlan = 301; bridge = "br-wan-same"; };
      };
      wanUplinkName = "u0";
    };
  in
    { names = map (n: r.netdevs.${n}.netdevConfig.Name or null) (builtins.attrNames r.netdevs); }
' 2>&1)" || fail "P1 the emitter could not be evaluated for the shared-bridge fixture
${outB}"

sameCount="$(jq -r '[.names[] | select(. == "br-wan-same")] | length' <<<"${outB}")"
[[ "${sameCount}" == "1" ]] \
  || fail "P2 two uplinks on the same bridge produced ${sameCount} netdevs for it; the bridge netdev must be keyed by bridge name and emitted once"

# Fixture C: a non-PPPoE interface with no VLAN or bridge -> no netdevs at all,
# so the emitter does not invent a bridge for an interface that has none.
outC="$(run_emitter '
  let
    r = emit {
      interfaces = { eth0 = { }; };
      interfaceNames = [ "eth0" ];
      renderedInterfaceNames = { eth0 = "ens3"; };
      uplinks = { };
      wanUplinkName = "";
    };
  in
    { count = builtins.length (builtins.attrNames r.netdevs); }
' 2>&1)" || fail "P1 the emitter could not be evaluated for the non-PPPoE fixture
${outC}"

netdevCount="$(jq -r '.count' <<<"${outC}")"
[[ "${netdevCount}" == "0" ]] \
  || fail "P3 a non-PPPoE interface produced ${netdevCount} netdevs; the emitter must not invent a bridge without modeled VLAN and bridge facts"

echo "PASS bridge-netdev-emission"
