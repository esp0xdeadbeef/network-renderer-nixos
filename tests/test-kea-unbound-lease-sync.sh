#!/usr/bin/env bash
# GAMP-ID: FS-880-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

nix_eval_true_or_fail \
  kea-unbound-lease-sync-render \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        dns =
          import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
            inherit lib pkgs;
            renderedModel.runtimeTarget.services.dns = {
              listen = [ "10.20.20.1" ];
              allowFrom = [ "10.20.20.0/24" ];
              forwarders = [ "10.20.10.1" ];
            };
          };
        kea =
          import (repoRoot + "/s88/ControlModule/access/render/kea.nix") {
            inherit lib pkgs;
            scope = {
              fileStem = "client";
              interfaceName = "tenant-client";
              subnetId = 20;
              subnet = "10.20.20.0/24";
              pool = "10.20.20.100 - 10.20.20.199";
              router = "10.20.20.1";
              dnsServers = [ "10.20.20.1" ];
              domain = "lan.";
              leaseDns = {
                ownerScope = "tenant-client";
                requesterScope = "tenant-client";
                namespace = "client.lan.";
              };
              leaseState = {
                service = "dhcp4";
                id = "client";
                kind = "lease-state";
                mode = "persistent";
                required = true;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                path = "/persist/network/state/dhcp4/router-access-client/client";
              };
            };
          };
        service = kea.systemd.services."kea-dhcp4-client";
        genService = kea.systemd.services."gen-kea-client";
        syncService = kea.systemd.services."kea-unbound-sync-client";
        syncTimer = kea.systemd.timers."kea-unbound-sync-client";
        dnsRemoteControl = dns.services.unbound.settings.remote-control;
      in
        if !(
          dnsRemoteControl."control-enable"
          && builtins.elem "127.0.0.1" dnsRemoteControl."control-interface"
          && builtins.elem "unbound.service" service.after
          && builtins.elem "unbound.service" service.wants
          && service.serviceConfig.StateDirectory == "kea"
          && genService.serviceConfig.Type == "oneshot"
          && syncService.serviceConfig.Type == "oneshot"
          && builtins.match ".*kea-unbound-sync[.]sh" syncService.serviceConfig.ExecStart != null
          && syncService.environment.LEASE_FILE == "/persist/network/state/dhcp4/router-access-client/client"
          && syncService.environment.NAMESPACE == "client.lan."
          && syncService.environment.OWNER_SCOPE == "tenant-client"
          && syncService.environment.REQUESTER_SCOPE == "tenant-client"
          && builtins.match ".*/unbound-control" syncService.environment.UNBOUND_CONTROL != null
          && builtins.elem "unbound.service" syncService.after
          && !(syncService ? wantedBy)
          && syncTimer.wantedBy == [ "timers.target" ]
          && syncTimer.timerConfig.Unit == "kea-unbound-sync-client.service"
        ) then
          throw "kea-unbound lease sync service contract failed"
        else true
    '

gen_command="$(
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
              fileStem = "client";
              interfaceName = "tenant-client";
              subnetId = 20;
              subnet = "10.20.20.0/24";
              pool = "10.20.20.100 - 10.20.20.199";
              router = "10.20.20.1";
              dnsServers = [ "10.20.20.1" ];
              domain = "lan.";
              leaseDns = {
                ownerScope = "tenant-client";
                requesterScope = "tenant-client";
                namespace = "client.lan.";
              };
              leaseState = {
                service = "dhcp4";
                id = "client";
                kind = "lease-state";
                mode = "persistent";
                required = true;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                path = "/persist/network/state/dhcp4/router-access-client/client";
              };
            };
          };
      in
        builtins.toString kea.systemd.services."gen-kea-client".serviceConfig.ExecStart
    '
)"

template="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "--template") { print $(i + 1); exit } }' <<<"${gen_command}")"
[[ -n "${template}" ]] || fail "FAIL kea-unbound-lease-sync: generator command omitted template"
template_drv="$(nix derivation show "${template}" | jq -r '.derivations | keys[0]')"
nix-store --realise "/nix/store/${template_drv}" >/dev/null
jq -e '.Dhcp4."lease-database".name == "/persist/network/state/dhcp4/router-access-client/client"' "${template}" >/dev/null \
  || fail "FAIL kea-unbound-lease-sync: template does not use CPM lease-state path"
if grep -F '/var/lib/kea' "${template}" >/dev/null; then
  fail "FAIL kea-unbound-lease-sync: template used renderer-local /var/lib/kea lease path"
fi
if grep -F '"hooks-libraries"' "${template}" >/dev/null; then
  fail "FAIL kea-unbound-lease-sync: generated Kea config must not use libdhcp_run_script hook"
fi

bash -n "${repo_root}/s88/ControlModule/access/render/kea-unbound-sync.sh"
grep -F 'fqdn="$hostname.$NAMESPACE"' "${repo_root}/s88/ControlModule/access/render/kea-unbound-sync.sh" >/dev/null \
  || fail "FAIL kea-unbound-lease-sync: standalone sync does not publish relative leases under the modeled namespace"

kea_out="$(nix eval --raw nixpkgs#kea.outPath)"
unbound_out="$(nix eval --raw nixpkgs#unbound.outPath)"
unbound_control="${unbound_out}/bin/unbound-control"

[[ -x "$unbound_control" ]] || fail "FAIL kea-unbound-lease-sync: missing unbound-control ${unbound_control}"

cat >"${tmp}/good-no-hook.json" <<EOF
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": []
    },
    "lease-database": {
      "type": "memfile",
      "persist": false
    },
    "subnet4": []
  }
}
EOF

"${kea_out}/bin/kea-dhcp4" -t "${tmp}/good-no-hook.json" >/dev/null

nix_eval_true_or_fail \
  kea-unbound-lease-sync-fail-closed-without-authority \
  env REPO_ROOT="${repo_root}" \
    nix eval \
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
              fileStem = "client";
              interfaceName = "tenant-client";
              subnetId = 20;
              subnet = "10.20.20.0/24";
              pool = "10.20.20.100 - 10.20.20.199";
              router = "10.20.20.1";
              dnsServers = [ "10.20.20.1" ];
              domain = "lan.";
              leaseState = {
                service = "dhcp4";
                id = "client";
                kind = "lease-state";
                mode = "persistent";
                required = true;
                interface = "tenant-client";
                tenant = "client";
                source = "inventory-realization";
                path = "/persist/network/state/dhcp4/router-access-client/client";
              };
            };
          };
        service = kea.systemd.services."kea-dhcp4-client";
      in
        !builtins.hasAttr "kea-unbound-sync-client" kea.systemd.services
        && !builtins.hasAttr "kea-unbound-sync-client" kea.systemd.timers
        && !(builtins.elem "unbound.service" service.after)
        && !(builtins.elem "unbound.service" service.wants)
    '

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
            fileStem = "client";
            interfaceName = "tenant-client";
            subnetId = 20;
            subnet = "10.20.20.0/24";
            pool = "10.20.20.100 - 10.20.20.199";
            router = "10.20.20.1";
            dnsServers = [ "10.20.20.1" ];
            domain = "lan.";
            leaseDns = {
              requesterScope = "tenant-client";
              namespace = "client.lan.";
            };
            leaseState = {
              service = "dhcp4";
              id = "client";
              kind = "lease-state";
              mode = "persistent";
              required = true;
              interface = "tenant-client";
              tenant = "client";
              source = "inventory-realization";
              path = "/persist/network/state/dhcp4/router-access-client/client";
            };
          };
        };
    in
      kea.systemd.services."kea-unbound-sync-client".environment.OWNER_SCOPE
  ' >"${tmp}/partial-authority.out" 2>"${tmp}/partial-authority.err"; then
  fail "FAIL kea-unbound-lease-sync: partial leaseDns authority was accepted"
fi

grep -F 'scope.leaseDns.ownerScope' "${tmp}/partial-authority.err" >/dev/null \
  || fail "FAIL kea-unbound-lease-sync: partial leaseDns diagnostic did not name ownerScope"

echo "PASS kea-unbound-lease-sync"
