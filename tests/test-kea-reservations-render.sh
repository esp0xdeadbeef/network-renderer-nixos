#!/usr/bin/env bash
# GAMP-ID: FS-970-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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
              reservations = [
                {
                  mac = "02:10:20:00:00:10";
                  address = "10.20.20.10";
                  cidr = "10.20.20.10/32";
                  hostOffset = 10;
                  hostname = "client-fixed-10";
                }
              ];
              leaseState = {
                service = "dhcp4";
                id = "client-v4";
                kind = "lease-state";
                mode = "ephemeral";
                required = false;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                runtimeLocation = "ephemeral";
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
              reservations = [
                {
                  mac = "02:10:20:00:00:10";
                  address = "10.20.20.10";
                  cidr = "10.20.20.10/32";
                  hostOffset = 10;
                  hostname = "client-fixed-10";
                }
              ];
              leaseState = {
                service = "dhcp4";
                id = "client-v4";
                kind = "lease-state";
                mode = "ephemeral";
                required = false;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                runtimeLocation = "ephemeral";
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
              reservations = [
                {
                  mac = "02:10:20:00:00:10";
                  address = "fd42:dead:beef:20:0:0:0:10";
                  cidr = "fd42:dead:beef:20:0:0:0:10/128";
                  hostOffset = 16;
                  hostname = "client-fixed-10";
                }
              ];
              leaseState = {
                service = "dhcpv6";
                id = "client-v6";
                kind = "lease-state";
                mode = "ephemeral";
                required = false;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                runtimeLocation = "ephemeral";
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
              reservations = [
                {
                  mac = "02:10:20:00:00:10";
                  address = "fd42:dead:beef:20:0:0:0:10";
                  cidr = "fd42:dead:beef:20:0:0:0:10/128";
                  hostOffset = 16;
                  hostname = "client-fixed-10";
                }
              ];
              leaseState = {
                service = "dhcpv6";
                id = "client-v6";
                kind = "lease-state";
                mode = "ephemeral";
                required = false;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                runtimeLocation = "ephemeral";
              };
            };
          };
      in
        kea.systemd.services."gen-kea-dhcp6-client-v6".serviceConfig.ExecStart.drvPath
    '
)"

nix-store -r "$kea4_gen_drv" "$kea6_gen_drv" >/dev/null

grep -F '"hw-address":"02:10:20:00:00:10"' "$kea4_gen_script" >/dev/null \
  || fail "FAIL kea-reservations-render: DHCPv4 reservation MAC missing"
grep -F '"ip-address":"10.20.20.10"' "$kea4_gen_script" >/dev/null \
  || fail "FAIL kea-reservations-render: DHCPv4 reservation address missing"
grep -F '"hw-address":"02:10:20:00:00:10"' "$kea6_gen_script" >/dev/null \
  || fail "FAIL kea-reservations-render: DHCPv6 reservation MAC missing"
grep -F '"ip-addresses":["fd42:dead:beef:20:0:0:0:10"]' "$kea6_gen_script" >/dev/null \
  || fail "FAIL kea-reservations-render: DHCPv6 reservation address missing"

echo "PASS kea-reservations-render"
