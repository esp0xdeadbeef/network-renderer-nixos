#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tests/lib/test-common.sh
. "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$result_json" "$stderr_file"' EXIT

nix_eval_json_or_fail "selector-runtime-interface-relation-audit" "$result_json" "$stderr_file" \
  env REPO_ROOT="${repo_root}" \
  nix eval --json --extra-experimental-features 'nix-command flakes' --impure \
  --expr '
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  interfacesForUnit = import (repoRoot + "/s88/ControlModule/render/dry-config-model/interfaces.nix") {
    inherit lib;
    runtimeContext = {
      deploymentHostForUnit = { ... }: "host-a";
    };
    normalizedRuntimeTargets = {
      router-a = {
        role = "downstream-selector";
        interfaces = {
          selector-edge = {
            renderedIfName = "ens20";
            hostBridge = "br-selector-edge";
          };
          unrelated = {
            renderedIfName = "ens21";
            hostBridge = "br-unrelated";
          };
        };
        forwardingIntent = {
          rules = [
            {
              relationId = "selector-handoff-forward--tenant--selector-transport-to-access-to-selector--no-uplink";
              comment = "selector-handoff-forward--tenant--selector-transport-to-access-to-selector--no-uplink";
              action = "accept";
              direction = "forward";
              fromInterface = "tenant-client";
              toInterface = "ens20";
              relationCardinality = {
                unit = "selector-forwarding-rule";
                decomposition = "one-rule-per-selector-handoff-direction";
              };
              from = {
                runtimeInterface = "tenant-client";
                relationPurpose = "selector-transport";
                hostFacing = false;
                backingRef = {
                  kind = "attachment";
                  name = "client";
                };
                lane = {
                  kind = "tenant";
                  access = "access-client";
                };
              };
              to = {
                runtimeInterface = "ens20";
                relationPurpose = "access-to-selector";
                hostFacing = false;
                backingRef = {
                  kind = "link";
                  name = "p2p-access-client-downstream-selector";
                };
                lane = {
                  kind = "access-edge";
                  access = "access-client";
                };
              };
            }
          ];
        };
      };
    };
    hostRenderings = {
      host-a = {
        bridgeNameMap = {
          br-selector-edge = "br-selector-edge";
          br-unrelated = "br-unrelated";
        };
        attachTargets = [ ];
      };
    };
    deploymentHostNames = [ "host-a" ];
    controlPlane = { };
    resolvedInventory = { };
  };
  rendered = interfacesForUnit "router-a";
  audit = rendered.selector-edge.selectorRelationAudit or [ ];
  first = builtins.elemAt audit 0;
  checks = {
    selector_edge_has_one_audit_record = builtins.length audit == 1;
    audit_maps_runtime_name = first.runtimeInterface == "ens20";
    audit_preserves_relation_identity =
      first.relationId == "selector-handoff-forward--tenant--selector-transport-to-access-to-selector--no-uplink"
      && first.relationPurpose == "access-to-selector";
    audit_preserves_host_facing_classification = first.hostFacing == false;
    audit_preserves_selector_role = first.runtimeTargetRole == "downstream-selector";
    audit_preserves_logical_relation_backing_ref =
      first.backingRef.kind == "link"
      && first.backingRef.name == "p2p-access-client-downstream-selector";
    unrelated_interface_has_no_selector_audit = !(rendered.unrelated ? selectorRelationAudit);
  };
in
{
  ok = builtins.all (value: value == true) (builtins.attrValues checks);
  failed = lib.mapAttrsToList (name: _value: name) (lib.filterAttrs (_name: value: value != true) checks);
  inherit checks rendered;
}
'

assert_json_checks_ok "selector-runtime-interface-relation-audit" "$result_json"
echo "PASS selector-runtime-interface-relation-audit"
