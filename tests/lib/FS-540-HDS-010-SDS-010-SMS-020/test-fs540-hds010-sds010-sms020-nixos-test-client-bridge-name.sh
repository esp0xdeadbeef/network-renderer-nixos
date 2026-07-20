#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${result_json}" "${stderr_file}"' EXIT

nix_eval_json_or_fail \
  "FS-540 NixOS test-client bridge name materialization" \
  "${result_json}" \
  "${stderr_file}" \
  env REPO_ROOT="${repo_root}" \
    nix eval \
      --extra-experimental-features 'nix-command flakes' \
      --impure --json --expr '
        let
          repoRoot = builtins.getEnv "REPO_ROOT";
          flake = builtins.getFlake ("path:" + repoRoot);
          lib = flake.inputs.nixpkgs.lib;
          originalBridge = "br-mini-smt-dns-resolver-config-tenant-client";
          renderedBridge = "br-mini--baff8b";
          hostPlan = {
            selectedUnits = [ "dns-resolver-config-access-dns" ];
            selectedRoles = {
              "dns-resolver-config-access-dns" = "endpoint-client";
            };
            deploymentHostUnitRoles = {
              "dns-resolver-config-access-dns" = "endpoint-client";
            };
            deploymentHostRoles."endpoint-client".container.enable = true;
            deploymentHostContainerNamingUnits = [ "dns-resolver-config-access-dns" ];
            deploymentHostName = "s-router-test-clients";
            bridgeNameMap.${originalBridge} = renderedBridge;
            localAttachTargets = [
              {
                unitName = "dns-resolver-config-access-dns";
                ifName = "tenant-client";
                hostBridgeName = originalBridge;
                renderedHostBridgeName = originalBridge;
                identity = {
                  portName = "tenant-client";
                };
              }
            ];
            normalizedRuntimeTargets."dns-resolver-config-access-dns" = {
              runtimeTargetId = "dns-resolver-config-access-dns";
              logicalNode = {
                enterprise = "mini-smt";
                site = "dns-resolver-config";
                name = "access-dns";
              };
              interfaces.tenant-client = {
                sourceKind = "wan";
                hostBridge = originalBridge;
                connectivity.sourceKind = "wan";
              };
            };
          };
          renderedContainers = import (repoRoot + "/s88/ControlModule/mapping/container-runtime/default.nix") {
            inherit lib hostPlan;
          };
          container = renderedContainers."dns-resolver-config-access-dns";
          iface = container.interfaces.tenant-client;
          checks = {
            host_bridge_uses_rendered_name = container.hostBridge == renderedBridge;
            host_bridge_not_overlong = builtins.stringLength container.hostBridge <= 15;
            interface_bridge_uses_rendered_name = iface.renderedHostBridgeName == renderedBridge;
            primary_bridge_shortcut_enabled = (iface.usePrimaryHostBridge or false) == true;
            original_bridge_would_be_invalid = builtins.stringLength originalBridge > 15;
          };
        in
        {
          ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
          failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
          inherit checks;
          observed = {
            inherit originalBridge renderedBridge;
            hostBridge = container.hostBridge;
            interfaceRenderedHostBridgeName = iface.renderedHostBridgeName;
          };
        }
      '

assert_json_checks_ok "FS-540 NixOS test-client bridge name materialization" "${result_json}"

echo "PASS FS-540 NixOS test-client bridge name materialization"
