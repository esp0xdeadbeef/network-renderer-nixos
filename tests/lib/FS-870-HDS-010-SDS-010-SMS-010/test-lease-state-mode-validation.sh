#!/usr/bin/env bash
# GAMP-ID: FS-870-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_rejects_lease_mode() {
  local family="$1"
  local mode_fragment="$2"
  local label="$3"
  local out_file="${tmp}/${family}-${label}.out"
  local err_file="${tmp}/${family}-${label}.err"

  if env REPO_ROOT="${repo_root}" LEASE_FAMILY="${family}" LEASE_MODE_FRAGMENT="${mode_fragment}" nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        family = builtins.getEnv "LEASE_FAMILY";
        modeFragment = builtins.getEnv "LEASE_MODE_FRAGMENT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        commonScope = {
          interfaceName = "tenant-client";
          subnetId = 1;
          domain = "lan.";
          leaseState = {
            service = if family == "dhcp6" then "dhcpv6" else "dhcp4";
            id = "client-${family}";
            kind = "lease-state";
            required = true;
            interface = "tenant-client";
            tenant = "client";
            source = "inventory-realization";
            path = "/persist/network/state/${family}/router-access-client/client-${family}";
          } // builtins.fromJSON modeFragment;
        };
        kea =
          if family == "dhcp6" then
            import (repoRoot + "/s88/ControlModule/access/render/kea-dhcp6.nix") {
              inherit lib pkgs;
              scope = commonScope // {
                fileStem = "client-dhcp6";
                subnet = "fd42:dead:beef:20::/64";
                pool = "fd42:dead:beef:20::100 - fd42:dead:beef:20::1ff";
                dnsServers = [ "fd42:dead:beef:20::1" ];
              };
            }
          else
            import (repoRoot + "/s88/ControlModule/access/render/kea.nix") {
              inherit lib pkgs;
              scope = commonScope // {
                fileStem = "client-dhcp4";
                subnet = "10.20.20.0/24";
                pool = "10.20.20.100 - 10.20.20.199";
                router = "10.20.20.1";
                dnsServers = [ "10.20.20.1" ];
              };
            };
        serviceName = if family == "dhcp6" then "gen-kea-dhcp6-client-dhcp6" else "gen-kea-client-dhcp4";
      in
        builtins.toString kea.systemd.services.${serviceName}.serviceConfig.ExecStart
    ' >"$out_file" 2>"$err_file"; then
    fail "FAIL lease-state-mode-validation: ${family} accepted ${label} scope.leaseState.mode"
  fi

  grep -F 'scope.leaseState.mode' "$err_file" >/dev/null \
    || fail "FAIL lease-state-mode-validation: ${family} ${label} diagnostic did not name scope.leaseState.mode"
}

assert_rejects_lease_mode "dhcp4" '{}' "missing"
assert_rejects_lease_mode "dhcp4" '{"mode":"durable"}' "invalid"
assert_rejects_lease_mode "dhcp6" '{}' "missing"
assert_rejects_lease_mode "dhcp6" '{"mode":"durable"}' "invalid"

echo "PASS lease-state-mode-validation"
