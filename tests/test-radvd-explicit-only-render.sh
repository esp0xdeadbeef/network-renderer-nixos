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
  radvd-explicit-only-render \
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
          addresses = [ "fd42:dead:beef:20::1/64" ];
          semanticInterface.subnet6 = "fd42:dead:beef:20::/64";
        };
        withoutExplicitRa =
          import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
            inherit lib;
            containerModel = {
              containerName = "router-access-client";
              roleName = "access";
              roleConfig.container.advertise.radvd = true;
              interfaces.tenant-client = baseInterface;
            };
          };
        withExplicitRa =
          import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
            inherit lib;
            containerModel = {
              interfaces.tenant-client = baseInterface;
              runtimeTarget.advertisements.ipv6Ra = [
                {
                  interface = "tenant-client";
                  prefixes = [ "fd42:dead:beef:20::/64" ];
                  rdnss = [ "fd42:dead:beef:20::1" ];
                  dnssl = [ "lan." ];
                  managed = false;
                  otherConfig = false;
                  onLink = true;
                  autonomous = true;
                }
              ];
            };
          };
        radvd =
          import (repoRoot + "/s88/ControlModule/access/render/radvd.nix") {
            inherit lib pkgs;
            scope = builtins.head withExplicitRa.radvdScopes;
          };
        service = radvd.systemd.services."radvd-tenant-client";
        genService = radvd.systemd.services."radvd-generate-tenant-client";
        derivedAlarmIds = map (alarm: alarm.alarmId or "") withoutExplicitRa.alarms;
        checks = {
          absent_contract_emits_no_radvd_scope = withoutExplicitRa.radvdScopes == [ ];
          absent_contract_has_no_derived_radvd_alarm = !(builtins.elem "access-radvd-derived" derivedAlarmIds);
          explicit_contract_emits_one_radvd_scope = builtins.length withExplicitRa.radvdScopes == 1;
          explicit_scope_preserves_interface = (builtins.head withExplicitRa.radvdScopes).interfaceName == "tenant-client";
          explicit_scope_preserves_prefix = (builtins.head withExplicitRa.radvdScopes).prefixes == [ "fd42:dead:beef:20::/64" ];
          explicit_scope_preserves_rdnss = (builtins.head withExplicitRa.radvdScopes).rdnss == [ "fd42:dead:beef:20::1" ];
          renderer_emits_generator = genService.serviceConfig.Type == "oneshot";
          renderer_emits_radvd_service =
            builtins.match ".*radvd.*" (builtins.toString service.serviceConfig.ExecStart) != null;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok radvd-explicit-only-render "${result_json}"

echo "PASS radvd-explicit-only-render"
