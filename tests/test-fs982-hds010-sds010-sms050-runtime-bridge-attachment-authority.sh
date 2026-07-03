#!/usr/bin/env bash
# GAMP-ID: FS-982-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${result_json}" "${stderr_file}"' EXIT

nix_eval_json_or_fail \
  "FS-982-HDS-010-SDS-010-SMS-050 runtime bridge attachment authority" \
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
          realizationPorts = import (repoRoot + "/s88/Unit/physical/realization-ports.nix") {
            inherit lib;
          };
          selectedUnits = [ "access-vlan2" ];
          normalizedRuntimeTargets.access-vlan2.interfaces = {
            tenant-vlan2 = {
              renderedIfName = "lan2";
              hostBridge = "rt--tenant--attachment--attachment::access-vlan2::tenant::vlan2";
              attach = {
                kind = "bridge";
                bridge = "lan2";
              };
              connectivity.sourceKind = "tenant";
              backingRef = {
                kind = "attachment";
                name = "vlan2";
              };
            };
            access-vlan2 = {
              renderedIfName = "access-vlan2";
              hostBridge = "rt--p2p--link--link::site-a::p2p-access-vlan2-downstream-selector";
              attach = {
                kind = "bridge";
                bridge = "rt-downstream-access-vlan2";
              };
              connectivity.sourceKind = "p2p";
              backingRef = {
                kind = "link";
                name = "p2p-access-vlan2-downstream-selector";
              };
            };
            synthetic-only = {
              renderedIfName = "synthetic-only";
              hostBridge = "rt--synthetic-only";
              connectivity.sourceKind = "p2p";
            };
          };
          targets = realizationPorts.attachTargetsForUnitsFromRuntime {
            source = { };
            inherit selectedUnits normalizedRuntimeTargets;
            file = "FS-982-HDS-010-SDS-010-SMS-050";
          };
          byIfName = builtins.listToAttrs (
            map (target: {
              name = target.ifName;
              value = target;
            }) targets
          );
          tenant = byIfName.tenant-vlan2;
          p2p = byIfName.access-vlan2;
          synthetic = byIfName.synthetic-only;
          checks = {
            tenant_bridge_attach_uses_explicit_lan2 =
              tenant.hostBridgeName == "lan2"
              && tenant.kind == "bridge"
              && tenant.identity.attachmentKind == "bridge";
            p2p_bridge_attach_uses_explicit_transit_bridge =
              p2p.hostBridgeName == "rt-downstream-access-vlan2"
              && p2p.kind == "bridge"
              && p2p.identity.attachmentKind == "bridge";
            seeded_negative_without_attach_still_uses_synthetic_hostbridge =
              synthetic.hostBridgeName == "rt--synthetic-only"
              && synthetic.kind == "synthetic"
              && synthetic.identity.attachmentKind == "synthetic";
          };
        in
        {
          ok = builtins.all (name: checks.${name}) (builtins.attrNames checks);
          failed = builtins.filter (name: !(checks.${name})) (builtins.attrNames checks);
          inherit checks;
          observed = {
            tenant = {
              hostBridgeName = tenant.hostBridgeName;
              kind = tenant.kind;
              attachmentKind = tenant.identity.attachmentKind;
            };
            p2p = {
              hostBridgeName = p2p.hostBridgeName;
              kind = p2p.kind;
              attachmentKind = p2p.identity.attachmentKind;
            };
            synthetic = {
              hostBridgeName = synthetic.hostBridgeName;
              kind = synthetic.kind;
              attachmentKind = synthetic.identity.attachmentKind;
            };
          };
        }
      '

assert_json_checks_ok \
  "FS-982-HDS-010-SDS-010-SMS-050 runtime bridge attachment authority" \
  "${result_json}"

echo "PASS FS-982-HDS-010-SDS-010-SMS-050 runtime bridge attachment authority"
