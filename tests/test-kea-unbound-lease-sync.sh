#!/usr/bin/env bash
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
            };
          };
        service = kea.systemd.services."kea-dhcp4-client";
        syncService = kea.systemd.services."kea-unbound-sync-client";
        syncTimer = kea.systemd.timers."kea-unbound-sync-client";
        dnsRemoteControl = dns.services.unbound.settings.remote-control;
      in
        if !(
          dnsRemoteControl."control-enable"
          && builtins.elem "127.0.0.1" dnsRemoteControl."control-interface"
          && builtins.elem "unbound.service" service.after
          && builtins.elem "unbound.service" service.wants
          && syncService.serviceConfig.Type == "oneshot"
          && syncService.serviceConfig.ExecStart == "/run/kea-unbound-sync/client.sh"
          && builtins.elem "unbound.service" syncService.after
          && !(syncService ? wantedBy)
          && syncTimer.wantedBy == [ "timers.target" ]
          && syncTimer.timerConfig.Unit == "kea-unbound-sync-client.service"
        ) then
          throw "kea-unbound lease sync service contract failed"
        else true
    '

kea_out="$(nix eval --raw nixpkgs#kea.outPath)"
unbound_out="$(nix eval --raw nixpkgs#unbound.outPath)"
hook="${kea_out}/lib/kea/hooks/libdhcp_run_script.so"
unbound_control="${unbound_out}/bin/unbound-control"

[[ -f "$hook" ]] || fail "FAIL kea-unbound-lease-sync: missing Kea hook ${hook}"
[[ -x "$unbound_control" ]] || fail "FAIL kea-unbound-lease-sync: missing unbound-control ${unbound_control}"

cat >"${tmp}/kea.json" <<EOF
{
  "Dhcp4": {
    "hooks-libraries": [
      {
        "library": "${hook}",
        "parameters": {
          "name": "/bin/true",
          "sync": false
        }
      }
    ],
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

"${kea_out}/bin/kea-dhcp4" -t "${tmp}/kea.json" >/dev/null

echo "PASS kea-unbound-lease-sync"
