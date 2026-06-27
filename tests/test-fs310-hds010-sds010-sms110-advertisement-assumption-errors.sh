#!/usr/bin/env bash
# GAMP-ID: FS-310-HDS-010-SDS-010-SMS-110
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      advertisementModel =
        import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
          inherit lib;
          containerModel = {
            containerName = "nixos-provider-handoff-access-a";
            roleName = "access";
            roleConfig.container.advertise.radvd = true;
            interfaces.ppp0 = {
              interfaceName = "ppp0";
              sourceKind = "tenant";
            };
          };
        };
    in
      builtins.deepSeq advertisementModel.warnings true
  ' >"${tmp}/ra.out" 2>"${tmp}/ra.err"; then
  fail "FAIL advertisement-assumption-errors: incomplete IPv6 RA assumption was accepted as a warning"
fi

grep -F 'FS-310-HDS-010-SDS-010-SMS-110' "${tmp}/ra.err" >/dev/null \
  || fail "FAIL advertisement-assumption-errors: diagnostic did not name the fail-closed SMS"
grep -F 'IPv6 RA advertisement was requested but rendered interface data is incomplete' "${tmp}/ra.err" >/dev/null \
  || fail "FAIL advertisement-assumption-errors: diagnostic did not name the IPv6 RA assumption"
grep -F 'renderer-only assumptions' "${tmp}/ra.err" >/dev/null \
  || fail "FAIL advertisement-assumption-errors: diagnostic did not preserve renderer assumption detail"

if env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      advertisementModel =
        import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
          inherit lib;
          containerModel = {
            containerName = "nixos-access-client";
            roleName = "access";
            roleConfig.container.advertise.dhcp4 = true;
            interfaces.tenant-client = {
              interfaceName = "tenant-client";
              sourceKind = "tenant";
            };
          };
        };
    in
      builtins.deepSeq advertisementModel.warnings true
  ' >"${tmp}/dhcp4.out" 2>"${tmp}/dhcp4.err"; then
  fail "FAIL advertisement-assumption-errors: incomplete DHCPv4 assumption was accepted as a warning"
fi

grep -F 'FS-310-HDS-010-SDS-010-SMS-110' "${tmp}/dhcp4.err" >/dev/null \
  || fail "FAIL advertisement-assumption-errors: DHCPv4 diagnostic did not name the fail-closed SMS"
grep -F 'DHCPv4 advertisement was requested but rendered interface data is incomplete' "${tmp}/dhcp4.err" >/dev/null \
  || fail "FAIL advertisement-assumption-errors: diagnostic did not name the DHCPv4 assumption"

env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      advertisementModel =
        import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
          inherit lib;
          containerModel = {
            containerName = "nixos-provider-handoff-access-a";
            roleName = "access";
            roleConfig.container.advertise.radvd = true;
            interfaces.ppp0 = {
              interfaceName = "ppp0";
              sourceKind = "pppoe-session";
            };
          };
        };
    in
      builtins.deepSeq advertisementModel.warnings (advertisementModel.warnings == [])
  ' >"${tmp}/pppoe.out" 2>"${tmp}/pppoe.err" \
  || {
    cat "${tmp}/pppoe.err" >&2
    fail "FAIL advertisement-assumption-errors: PPPoE session interface triggered renderer advertisement assumptions"
  }

grep -qx 'true' "${tmp}/pppoe.out" \
  || fail "FAIL advertisement-assumption-errors: PPPoE session interface produced warnings"

echo "PASS advertisement-assumption-errors"
