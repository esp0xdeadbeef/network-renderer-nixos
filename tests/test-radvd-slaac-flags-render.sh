#!/usr/bin/env bash
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-015
# GAMP-ID: USR-MODEL-001-FS-001-HDS-002-SDS-001-001-SMS-001-CMC-001-015
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
eval_stderr="$(mktemp)"
trap 'rm -f "${result_json}" "${eval_stderr}"' EXIT

nix_eval_json_or_fail \
  radvd-slaac-flags-render \
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
        buildModel = ipv6Ra:
          import (repoRoot + "/s88/ControlModule/access/lookup/advertisements.nix") {
            inherit lib;
            containerModel = {
              interfaces.tenant-client = baseInterface;
              runtimeTarget.advertisements.ipv6Ra = [ ipv6Ra ];
            };
          };
        missingFlags =
          let
            scope = builtins.head (buildModel {
              interface = "tenant-client";
              prefixes = [ "fd42:dead:beef:20::/64" ];
              rdnss = [ "fd42:dead:beef:20::1" ];
              dnssl = [ "lan." ];
            }).radvdScopes;
          in
          builtins.tryEval (builtins.deepSeq {
            inherit (scope) managed otherConfig onLink autonomous;
          } true);
        explicit = buildModel {
          interface = "tenant-client";
          prefixes = [ "fd42:dead:beef:20::/64" ];
          rdnss = [ "fd42:dead:beef:20::1" ];
          dnssl = [ "lan." ];
          managed = true;
          otherConfig = true;
          onLink = false;
          autonomous = false;
        };
        scope = builtins.head explicit.radvdScopes;
        radvd =
          import (repoRoot + "/s88/ControlModule/access/render/radvd.nix") {
            inherit lib pkgs scope;
          };
        generatorScript = builtins.readFile radvd.systemd.services."radvd-generate-tenant-client".serviceConfig.ExecStart;
        checks = {
          missing_flags_refuse = missingFlags.success == false;
          explicit_scope_preserves_managed = scope.managed == true;
          explicit_scope_preserves_other_config = scope.otherConfig == true;
          explicit_scope_preserves_on_link = scope.onLink == false;
          explicit_scope_preserves_autonomous = scope.autonomous == false;
          rendered_managed_flag = builtins.match ".*AdvManagedFlag on;.*" generatorScript != null;
          rendered_other_config_flag = builtins.match ".*AdvOtherConfigFlag on;.*" generatorScript != null;
          rendered_on_link_flag = builtins.match ".*AdvOnLink off;.*" generatorScript != null;
          rendered_autonomous_flag = builtins.match ".*AdvAutonomous off;.*" generatorScript != null;
        };
      in
      {
        ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
        failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
        inherit checks;
      }
    '

assert_json_checks_ok radvd-slaac-flags-render "${result_json}"

echo "PASS radvd-slaac-flags-render"
