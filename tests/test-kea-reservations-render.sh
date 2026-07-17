#!/usr/bin/env bash
# GAMP-ID: FS-970-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

template_from_command() {
  awk '{ for (i = 1; i <= NF; i++) if ($i == "--template") { print $(i + 1); exit } }' <<<"$1"
}

realize_template() {
  local template="$1"
  local drv_name
  drv_name="$(nix derivation show "${template}" | jq -r '.derivations | keys[0]')"
  nix-store --realise "/nix/store/${drv_name}" >/dev/null
}

kea4_command="$(
  env REPO_ROOT="${repo_root}" nix eval --raw \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        kea = import (repoRoot + "/s88/ControlModule/access/render/kea.nix") {
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
            reservations = [{
              mac = "02:10:20:00:00:10";
              address = "10.20.20.10";
              cidr = "10.20.20.10/32";
              hostOffset = 10;
              hostname = "client-fixed-10";
            }];
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
      in builtins.toString kea.systemd.services."gen-kea-client-v4".serviceConfig.ExecStart
    '
)"

kea6_command="$(
  env REPO_ROOT="${repo_root}" nix eval --raw \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        kea = import (repoRoot + "/s88/ControlModule/access/render/kea-dhcp6.nix") {
          inherit lib pkgs;
          scope = {
            fileStem = "client-v6";
            interfaceName = "tenant-client";
            subnetId = 1;
            subnet = "fd42:dead:beef:20::/64";
            pool = "fd42:dead:beef:20::100 - fd42:dead:beef:20::1ff";
            dnsServers = [ "fd42:dead:beef:20::1" ];
            domain = "lan.";
            reservations = [{
              mac = "02:10:20:00:00:10";
              address = "fd42:dead:beef:20:0:0:0:10";
              cidr = "fd42:dead:beef:20:0:0:0:10/128";
              hostOffset = 16;
              hostname = "client-fixed-10";
            }];
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
      in builtins.toString kea.systemd.services."gen-kea-dhcp6-client-v6".serviceConfig.ExecStart
    '
)"

kea4_template="$(template_from_command "${kea4_command}")"
kea6_template="$(template_from_command "${kea6_command}")"
[[ -n "${kea4_template}" && -n "${kea6_template}" ]] \
  || fail "FAIL kea-reservations-render: materializer command omitted a config template"

realize_template "${kea4_template}"
realize_template "${kea6_template}"

jq -e '
  .Dhcp4.subnet4[0].reservations
  == [{
    "hw-address": "02:10:20:00:00:10",
    "ip-address": "10.20.20.10",
    "hostname": "client-fixed-10"
  }]
' "${kea4_template}" >/dev/null \
  || fail "FAIL kea-reservations-render: DHCPv4 static reservation missing from template"

jq -e '
  .Dhcp6.subnet6[0].reservations
  == [{
    "hw-address": "02:10:20:00:00:10",
    "ip-addresses": ["fd42:dead:beef:20:0:0:0:10"],
    "hostname": "client-fixed-10"
  }]
' "${kea6_template}" >/dev/null \
  || fail "FAIL kea-reservations-render: DHCPv6 static reservation missing from template"

grep -F 'runtime-reservation-materializer.py' <<<"${kea4_command}${kea6_command}" >/dev/null \
  || fail "FAIL kea-reservations-render: config generation bypasses the standalone materializer"

echo "PASS kea-reservations-render"
