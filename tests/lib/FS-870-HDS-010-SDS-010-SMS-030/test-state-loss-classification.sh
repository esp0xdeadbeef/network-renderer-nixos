#!/usr/bin/env bash
# GAMP-ID: FS-870-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
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
            interfaces.tenant-client = {
              interfaceName = "tenant-client";
              sourceKind = "tenant";
              addresses = [ "10.20.20.1/24" ];
            };
            runtimeTarget.advertisements.dhcp4 = [
              {
                id = "client-v4";
                enabled = true;
                interface = "tenant-client";
                subnet = "10.20.20.0/24";
                pool = "10.20.20.100 - 10.20.20.199";
                router = "10.20.20.1";
                dnsServers = [ "10.20.20.1" ];
              }
            ];
          };
        };
    in
      builtins.deepSeq advertisementModel.dhcp4Scopes true
  ' >"${tmp}/missing.out" 2>"${tmp}/missing.err"; then
  fail "FAIL state-loss-classification: missing required persistent state was accepted"
fi

grep -F 'state-loss classification' "${tmp}/missing.err" >/dev/null \
  || fail "FAIL state-loss-classification: missing-state diagnostic did not classify state loss"
grep -F 'runtimeTarget.stateContracts.persistence.dhcp4Leases' "${tmp}/missing.err" >/dev/null \
  || fail "FAIL state-loss-classification: missing-state diagnostic did not name the missing CPM contract field"
grep -F "lease-state contract 'client-v4'" "${tmp}/missing.err" >/dev/null \
  || fail "FAIL state-loss-classification: missing-state diagnostic did not tie loss to the affected DHCP service scope"

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
            interfaces.tenant-client = {
              interfaceName = "tenant-client";
              sourceKind = "tenant";
              addresses = [ "10.20.20.1/24" ];
            };
            runtimeTarget = {
              advertisements.dhcp4 = [
                {
                  id = "client-v4";
                  enabled = true;
                  interface = "tenant-client";
                  subnet = "10.20.20.0/24";
                  pool = "10.20.20.100 - 10.20.20.199";
                  router = "10.20.20.1";
                  dnsServers = [ "10.20.20.1" ];
                }
              ];
              stateContracts.persistence.dhcp4Leases = [
                {
                  service = "dhcp4";
                  id = "client-v4";
                  mode = "persistent";
                  interface = "tenant-client";
                  path = "/persist/network/state/one";
                }
                {
                  service = "dhcp4";
                  id = "client-v4";
                  mode = "persistent";
                  interface = "tenant-client";
                  path = "/persist/network/state/two";
                }
              ];
            };
          };
        };
    in
      builtins.deepSeq advertisementModel.dhcp4Scopes true
  ' >"${tmp}/ambiguous.out" 2>"${tmp}/ambiguous.err"; then
  fail "FAIL state-loss-classification: ambiguous required persistent state was accepted"
fi

grep -F 'state-loss classification' "${tmp}/ambiguous.err" >/dev/null \
  || fail "FAIL state-loss-classification: ambiguous-state diagnostic did not classify state loss"
grep -F 'ambiguous lease-state contract' "${tmp}/ambiguous.err" >/dev/null \
  || fail "FAIL state-loss-classification: ambiguous-state diagnostic did not identify the ambiguous contract"
grep -F "lease-state contract 'client-v4'" "${tmp}/ambiguous.err" >/dev/null \
  || fail "FAIL state-loss-classification: ambiguous-state diagnostic did not tie loss to the affected DHCP service scope"

if env REPO_ROOT="${repo_root}" nix eval \
  --extra-experimental-features 'nix-command flakes' \
  --impure --expr '
    let
      repoRoot = builtins.getEnv "REPO_ROOT";
      flake = builtins.getFlake ("path:" + repoRoot);
      lib = flake.inputs.nixpkgs.lib;
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
      kea =
        import (repoRoot + "/s88/ControlModule/access/render/kea.nix") {
          inherit lib pkgs;
          scope = {
            fileStem = "client-v4";
            interfaceName = "tenant-client";
            subnetId = 1;
            subnet = "10.20.20.0/24";
            pool = "10.20.20.100 - 10.20.20.199";
            router = "10.20.20.1";
            dnsServers = [ "10.20.20.1" ];
            domain = "lan.";
            leaseState = {
              service = "dhcp4";
              id = "client-v4";
              kind = "lease-state";
              mode = "persistent";
              required = true;
              interface = "tenant-client";
            };
          };
        };
    in
      builtins.toString kea.systemd.services."gen-kea-client-v4".serviceConfig.ExecStart
  ' >"${tmp}/path.out" 2>"${tmp}/path.err"; then
  fail "FAIL state-loss-classification: persistent state without a path was accepted"
fi

grep -F 'state-loss classification' "${tmp}/path.err" >/dev/null \
  || fail "FAIL state-loss-classification: missing-path diagnostic did not classify state loss"
grep -F 'scope.leaseState.path' "${tmp}/path.err" >/dev/null \
  || fail "FAIL state-loss-classification: missing-path diagnostic did not name scope.leaseState.path"
grep -F 'client-v4' "${tmp}/path.err" >/dev/null \
  || fail "FAIL state-loss-classification: missing-path diagnostic did not tie loss to the affected service scope"

echo "PASS state-loss-classification"
