#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-013
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-013
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

nix_eval_true_or_fail \
  kea-dhcpv6-render \
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
                addresses = [ "fd42:dead:beef:20::1/64" ];
              };
              runtimeTarget = {
                advertisements = {
                  dhcpv6 = [
                    {
                      id = "client";
                      enabled = true;
                      interface = "tenant-client";
                      tenant = "client";
                      subnet = "fd42:dead:beef:20::/64";
                      pool = "fd42:dead:beef:20::100 - fd42:dead:beef:20::1ff";
                      dnsServers = [ "fd42:dead:beef:20::1" ];
                      domain = "lan.";
                    }
                  ];
                };
                stateContracts.persistence.dhcpv6Leases = [
                  {
                    service = "dhcpv6";
                    id = "client";
                    kind = "lease-state";
                    mode = "persistent";
                    required = true;
                    interface = "tenant-client";
                    tenant = "client";
                    source = "inventory-realization";
                    path = "/persist/network/state/dhcpv6/router-access-client/client";
                  }
                ];
              };
            };
          };
        kea =
          import (repoRoot + "/s88/ControlModule/access/render/kea-dhcp6.nix") {
            inherit lib pkgs;
            scope = builtins.head advertisementModel.dhcpv6Scopes;
          };
        service = kea.systemd.services."kea-dhcp6-client";
        genService = kea.systemd.services."gen-kea-dhcp6-client";
      in
        if !(
          builtins.length advertisementModel.dhcpv6Scopes == 1
          && advertisementModel.dhcp4Scopes == [ ]
          && advertisementModel.radvdScopes == [ ]
          && genService.serviceConfig.Type == "oneshot"
          && builtins.elem "gen-kea-dhcp6-client.service" service.after
          && builtins.elem "gen-kea-dhcp6-client.service" service.requires
          && builtins.match ".*kea-dhcp6.*" service.serviceConfig.ExecStart != null
        ) then
          throw "kea-dhcpv6 render contract failed"
        else true
    '

gen_script="$(
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
              fileStem = "client";
              interfaceName = "tenant-client";
              subnetId = 20;
              subnet = "fd42:dead:beef:20::/64";
              pool = "fd42:dead:beef:20::100 - fd42:dead:beef:20::1ff";
              dnsServers = [ "fd42:dead:beef:20::1" ];
              domain = "lan.";
              leaseState = {
                service = "dhcpv6";
                id = "client";
                kind = "lease-state";
                mode = "persistent";
                required = true;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                path = "/persist/network/state/dhcpv6/router-access-client/client";
              };
            };
          };
      in
        builtins.toString kea.systemd.services."gen-kea-dhcp6-client".serviceConfig.ExecStart
    '
)"
template="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "--template") { print $(i + 1); exit } }' <<<"${gen_script}")"
[[ -n "${template}" ]] || fail "FAIL kea-dhcpv6-render: generator command omitted template"
template_drv="$(nix derivation show "${template}" | jq -r '.derivations | keys[0]')"
nix-store --realise "/nix/store/${template_drv}" >/dev/null
jq -e '.Dhcp6 and (.Dhcp4 | not)' "${template}" >/dev/null
jq -e '.Dhcp6."lease-database".name == "/persist/network/state/dhcpv6/router-access-client/client"' "${template}" >/dev/null \
  || fail "FAIL kea-dhcpv6-render: template does not use CPM lease-state path"
if grep -F '/var/lib/kea' "${template}" >/dev/null; then
  fail "FAIL kea-dhcpv6-render: template used renderer-local /var/lib/kea lease path"
fi
grep -F 'runtime-reservation-materializer.py' <<<"${gen_script}" >/dev/null \
  || fail "FAIL kea-dhcpv6-render: generator bypasses standalone materializer"

kea_out="$(nix eval --raw nixpkgs#kea.outPath)"
cat >"${tmp}/good-dhcp6.json" <<EOF
{
  "Dhcp6": {
    "interfaces-config": {
      "interfaces": []
    },
    "lease-database": {
      "type": "memfile",
      "persist": false
    },
    "subnet6": []
  }
}
EOF

"${kea_out}/bin/kea-dhcp6" -t "${tmp}/good-dhcp6.json" >/dev/null

echo "PASS kea-dhcpv6-render"
