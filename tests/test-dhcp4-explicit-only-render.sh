#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-014
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-014
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  dhcp4-explicit-only-render \
  "${result_json}" \
  "${eval_stderr}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
    --extra-experimental-features 'nix-command flakes' \
    --impure --json --expr '
      let
        repoRoot = builtins.getEnv "REPO_ROOT";
        flake = builtins.getFlake ("path:" + repoRoot);
        lib = flake.inputs.nixpkgs.lib;
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
        baseInterface = {
          interfaceName = "tenant-client";
          containerInterfaceName = "tenant-client";
          sourceKind = "tenant";
          addresses = [ "10.20.20.1/24" ];
          semanticInterface.subnet4 = "10.20.20.0/24";
        };
        withoutExplicitDhcp4 =
          import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
            inherit lib;
            containerModel = {
              containerName = "router-access-client";
              roleName = "access";
              roleConfig.container.advertise.dhcp4 = true;
              interfaces.tenant-client = baseInterface;
            };
          };
        withExplicitDhcp4 =
          import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
            inherit lib;
            containerModel = {
              interfaces.tenant-client = baseInterface;
              runtimeTarget = {
                advertisements.dhcp4 = [
                  {
                    id = "client";
                    interface = "tenant-client";
                    tenant = "client";
                    subnet = "10.20.20.0/24";
                    pool = "10.20.20.100 - 10.20.20.199";
                    router = "10.20.20.1";
                    dnsServers = [ "10.20.20.1" ];
                    domain = "lan.";
                  }
                ];
                stateContracts.persistence.dhcp4Leases = [
                  {
                    service = "dhcp4";
                    id = "client";
                    kind = "lease-state";
                    mode = "persistent";
                    required = true;
                    interface = "tenant-client";
                    tenant = "client";
                    source = "inventory-realization";
                    path = "/persist/network/state/dhcp4/router-access-client/client";
                  }
                ];
              };
            };
          };
        kea =
          import (repoRoot + "/s88/ControlModule/access/render/kea.nix") {
            inherit lib pkgs;
            scope = builtins.head withExplicitDhcp4.dhcp4Scopes;
          };
        service = kea.systemd.services."kea-dhcp4-client";
        genService = kea.systemd.services."gen-kea-client";
        derivedAlarmIds = map (alarm: alarm.alarmId or "") withoutExplicitDhcp4.alarms;
        checks = {
          absent_contract_emits_no_dhcp4_scope = withoutExplicitDhcp4.dhcp4Scopes == [ ];
          absent_contract_has_no_derived_dhcp4_alarm = !(builtins.elem "access-dhcp4-derived" derivedAlarmIds);
          explicit_contract_emits_one_dhcp4_scope = builtins.length withExplicitDhcp4.dhcp4Scopes == 1;
          explicit_scope_preserves_interface = (builtins.head withExplicitDhcp4.dhcp4Scopes).interfaceName == "tenant-client";
          explicit_scope_preserves_subnet = (builtins.head withExplicitDhcp4.dhcp4Scopes).subnet == "10.20.20.0/24";
          explicit_scope_preserves_lease_state = (builtins.head withExplicitDhcp4.dhcp4Scopes).leaseState.path == "/persist/network/state/dhcp4/router-access-client/client";
          renderer_emits_generator = genService.serviceConfig.Type == "oneshot";
          renderer_emits_kea_service =
            builtins.match ".*kea-dhcp4.*" (builtins.toString service.serviceConfig.ExecStart) != null;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok dhcp4-explicit-only-render "${result_json}"

echo "PASS dhcp4-explicit-only-render"
