#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-005-SMS-001
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-005-SMS-001-CMC-001
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

nix_eval_true_or_fail \
  kea-persistence-contract-render \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        advertisementModel =
          import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
            inherit lib;
            containerModel = {
              interfaces.tenant-client = {
                interfaceName = "tenant-client";
                sourceKind = "tenant";
                addresses = [ "10.20.20.1/24" "fd42:dead:beef:20::1/64" ];
              };
              runtimeTarget = {
                advertisements = {
                  dhcp4 = [
                    {
                      id = "client-v4";
                      interface = "tenant-client";
                      tenant = "client";
                      subnet = "10.20.20.0/24";
                      pool = "10.20.20.100 - 10.20.20.199";
                      router = "10.20.20.1";
                      dnsServers = [ "10.20.20.1" ];
                      domain = "lan.";
                    }
                  ];
                  dhcpv6 = [
                    {
                      id = "client-v6";
                      interface = "tenant-client";
                      tenant = "client";
                      subnet = "fd42:dead:beef:20::/64";
                      pool = "fd42:dead:beef:20::100 - fd42:dead:beef:20::1ff";
                      dnsServers = [ "fd42:dead:beef:20::1" ];
                      domain = "lan.";
                    }
                  ];
                };
                stateContracts.persistence = {
                  dhcp4Leases = [
                    {
                      service = "dhcp4";
                      id = "client-v4";
                      kind = "lease-state";
                      mode = "persistent";
                      required = true;
                      interface = "tenant-client";
                      tenant = "client";
                      source = "inventory-realization";
                      path = "/persist/network/state/dhcp4/router-access-client/client-v4";
                    }
                  ];
                  dhcpv6Leases = [
                    {
                      service = "dhcpv6";
                      id = "client-v6";
                      kind = "lease-state";
                      mode = "persistent";
                      required = true;
                      interface = "tenant-client";
                      tenant = "client";
                      source = "inventory-realization";
                      path = "/persist/network/state/dhcpv6/router-access-client/client-v6";
                    }
                  ];
                };
              };
            };
          };
        dhcp4Scope = builtins.head advertisementModel.dhcp4Scopes;
        dhcpv6Scope = builtins.head advertisementModel.dhcpv6Scopes;
        kea4 =
          import (repoRoot + "/s88/ControlModule/access/render/kea.nix") {
            inherit lib pkgs;
            scope = dhcp4Scope;
          };
        kea6 =
          import (repoRoot + "/s88/ControlModule/access/render/kea-dhcp6.nix") {
            inherit lib pkgs;
            scope = dhcpv6Scope;
          };
        kea4Svc = kea4.systemd.services."kea-dhcp4-client-v4".serviceConfig;
        kea6Svc = kea6.systemd.services."kea-dhcp6-client-v6".serviceConfig;
      in
        if !(
          dhcp4Scope.leaseState.path == "/persist/network/state/dhcp4/router-access-client/client-v4"
          && dhcpv6Scope.leaseState.path == "/persist/network/state/dhcpv6/router-access-client/client-v6"
          && !(kea4Svc ? StateDirectory)
          && !(kea6Svc ? StateDirectory)
        ) then
          throw "Kea persistence contract render did not preserve CPM lease-state contracts"
        else true
    '

kea4_gen_script="$(
  env REPO_ROOT="${repo_root}" nix eval --raw \
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
                tenant = "client";
                source = "inventory-realization";
                path = "/persist/network/state/dhcp4/router-access-client/client-v4";
              };
            };
          };
      in
        builtins.toString kea.systemd.services."gen-kea-client-v4".serviceConfig.ExecStart
    '
)"
kea4_gen_drv="$(
  env REPO_ROOT="${repo_root}" nix eval --raw \
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
                tenant = "client";
                source = "inventory-realization";
                path = "/persist/network/state/dhcp4/router-access-client/client-v4";
              };
            };
          };
      in
        kea.systemd.services."gen-kea-client-v4".serviceConfig.ExecStart.drvPath
    '
)"
kea6_gen_script="$(
  env REPO_ROOT="${repo_root}" nix eval --raw \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        kea =
          import (repoRoot + "/s88/ControlModule/access/render/kea-dhcp6.nix") {
            inherit lib pkgs;
            scope = {
              fileStem = "client-v6";
              interfaceName = "tenant-client";
              subnetId = 1;
              subnet = "fd42:dead:beef:20::/64";
              pool = "fd42:dead:beef:20::100 - fd42:dead:beef:20::1ff";
              dnsServers = [ "fd42:dead:beef:20::1" ];
              domain = "lan.";
              leaseState = {
                service = "dhcpv6";
                id = "client-v6";
                kind = "lease-state";
                mode = "persistent";
                required = true;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                path = "/persist/network/state/dhcpv6/router-access-client/client-v6";
              };
            };
          };
      in
        builtins.toString kea.systemd.services."gen-kea-dhcp6-client-v6".serviceConfig.ExecStart
    '
)"
kea6_gen_drv="$(
  env REPO_ROOT="${repo_root}" nix eval --raw \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        kea =
          import (repoRoot + "/s88/ControlModule/access/render/kea-dhcp6.nix") {
            inherit lib pkgs;
            scope = {
              fileStem = "client-v6";
              interfaceName = "tenant-client";
              subnetId = 1;
              subnet = "fd42:dead:beef:20::/64";
              pool = "fd42:dead:beef:20::100 - fd42:dead:beef:20::1ff";
              dnsServers = [ "fd42:dead:beef:20::1" ];
              domain = "lan.";
              leaseState = {
                service = "dhcpv6";
                id = "client-v6";
                kind = "lease-state";
                mode = "persistent";
                required = true;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                path = "/persist/network/state/dhcpv6/router-access-client/client-v6";
              };
            };
          };
      in
        kea.systemd.services."gen-kea-dhcp6-client-v6".serviceConfig.ExecStart.drvPath
    '
)"

nix-store -r "$kea4_gen_drv" "$kea6_gen_drv" >/dev/null

grep -F '"/persist/network/state/dhcp4/router-access-client/client-v4"' "$kea4_gen_script" >/dev/null \
  || fail "FAIL kea-persistence-contract-render: DHCPv4 generated config does not use CPM lease-state path"
grep -F '"/persist/network/state/dhcpv6/router-access-client/client-v6"' "$kea6_gen_script" >/dev/null \
  || fail "FAIL kea-persistence-contract-render: DHCPv6 generated config does not use CPM lease-state path"

if grep -F '/var/lib/kea' "$kea4_gen_script" "$kea6_gen_script" >/dev/null; then
  fail "FAIL kea-persistence-contract-render: renderer-local /var/lib/kea path leaked into generated Kea config"
fi

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
  ' >"${tmp}/missing-state.out" 2>"${tmp}/missing-state.err"; then
  fail "FAIL kea-persistence-contract-render: missing CPM lease-state contract was accepted"
fi
grep -F 'runtimeTarget.stateContracts.persistence.dhcp4Leases' "${tmp}/missing-state.err" >/dev/null \
  || fail "FAIL kea-persistence-contract-render: missing lease-state diagnostic did not name CPM field"

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
            fileStem = "bad";
            interfaceName = "tenant-bad";
            subnetId = 1;
            subnet = "10.20.99.0/24";
            pool = "10.20.99.100 - 10.20.99.199";
            router = "10.20.99.1";
            dnsServers = [ "10.20.99.1" ];
            domain = "lan.";
            leaseState = {
              service = "dhcp4";
              id = "bad";
              kind = "lease-state";
              mode = "persistent";
              required = true;
            };
          };
        };
    in
      builtins.toString kea.systemd.services."gen-kea-bad".serviceConfig.ExecStart
  ' >"${tmp}/missing-path.out" 2>"${tmp}/missing-path.err"; then
  fail "FAIL kea-persistence-contract-render: persistent lease-state without path was accepted"
fi
grep -F 'scope.leaseState.path' "${tmp}/missing-path.err" >/dev/null \
  || fail "FAIL kea-persistence-contract-render: missing lease path diagnostic did not name scope.leaseState.path"

echo "PASS kea-persistence-contract-render"
