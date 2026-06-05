#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tests/lib/test-common.sh
. "${repo_root}/tests/lib/test-common.sh"

result_json="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$result_json" "$stderr_file"' EXIT

nix_eval_json_or_fail "runtime-interface-name-audit-mapping" "$result_json" "$stderr_file" \
  env REPO_ROOT="${repo_root}" \
  nix eval --json --extra-experimental-features 'nix-command flakes' --impure \
  --expr '
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  lib = flake.inputs.nixpkgs.lib;
  sortedAttrNames = attrs: lib.sort builtins.lessThan (builtins.attrNames attrs);
  mapping = import (repoRoot + "/s88/ControlModule/mapping/container-runtime/interfaces.nix") {
    inherit lib;
    lookup = {
      inherit sortedAttrNames;
      bridgeNameMap = {
        "br-policy-client" = "br-policy-client";
        "br-policy-stream" = "br-policy-stream";
      };
      localAttachTargets = [ ];
    };
  };
  providerOverlayRuntimeInterfaces =
    import (repoRoot + "/s88/ControlModule/render/provider-overlay-runtime-interfaces.nix") { inherit lib; };
  validLinuxIfName =
    name:
    builtins.isString name
    && name != ""
    && name != "."
    && name != ".."
    && builtins.stringLength name <= 15
    && builtins.match "[A-Za-z0-9_.-]+" name != null;
  normalized = mapping.normalizedInterfacesForUnit {
    unitName = "router-runtime-interface-audit";
    containerName = "router-runtime-interface-audit";
    interfaces = {
      "policy client wan with spaces" = {
        sourceKind = "tenant";
        renderedIfName = "policy client wan with spaces";
        hostBridge = "br-policy-client";
        backingRef = {
          kind = "attachment";
          name = "logical-policy-client-wan";
        };
      };
      "policy/client/wan/with/slashes" = {
        sourceKind = "tenant";
        renderedIfName = "policy/client/wan/with/slashes";
        hostBridge = "br-policy-stream";
        backingRef = {
          kind = "attachment";
          name = "logical-policy-stream-wan";
        };
      };
    };
  };
  providerRuntime = providerOverlayRuntimeInterfaces.materializeMissingProviderOverlayInterfaces {
    runtimeInterfaces = {
      "overlay-east-west-provider-logical-name" = {
        sourceKind = "overlay";
        renderedIfName = "overlay east west provider logical name";
        backingRef = {
          kind = "overlay";
          provider = "nebula";
          lane.name = "east-west";
        };
        materialization.nixos.ownsInterface = false;
      };
    };
    renderedInterfaces = { };
  };
  normalizedRuntimeNames = map (name: normalized.${name}.containerInterfaceName) (sortedAttrNames normalized);
  normalizedHostNames =
    map (name: normalized.${name}.hostInterfaceName)
      (lib.filter (name: !(normalized.${name}.usePrimaryHostBridge or false)) (sortedAttrNames normalized));
  providerRuntimeNames = map (name: providerRuntime.${name}.runtimeIfName) (sortedAttrNames providerRuntime);
  runtimeNames = normalizedRuntimeNames ++ normalizedHostNames ++ providerRuntimeNames;
  policyClient = normalized."policy client wan with spaces";
  policyStream = normalized."policy/client/wan/with/slashes";
  provider = providerRuntime."overlay-east-west-provider-logical-name";
  checks = {
    runtime_names_are_linux_valid = builtins.all validLinuxIfName runtimeNames;
    runtime_names_are_unique = builtins.length runtimeNames == builtins.length (lib.unique runtimeNames);
    logical_names_do_not_leak_as_runtime_names =
      !(builtins.elem "policy client wan with spaces" runtimeNames)
      && !(builtins.elem "policy/client/wan/with/slashes" runtimeNames)
      && !(builtins.elem "overlay east west provider logical name" runtimeNames);
    audit_maps_policy_client_runtime_to_logical =
      policyClient.runtimeInterfaceAudit.logicalInterfaceName == "policy client wan with spaces"
      && builtins.elem "policy client wan with spaces" policyClient.runtimeInterfaceAudit.aliases
      && policyClient.runtimeInterfaceAudit.cpmIdentity.backingRef.name == "logical-policy-client-wan";
    audit_maps_policy_stream_runtime_to_logical =
      policyStream.runtimeInterfaceAudit.logicalInterfaceName == "policy/client/wan/with/slashes"
      && builtins.elem "policy/client/wan/with/slashes" policyStream.runtimeInterfaceAudit.aliases
      && policyStream.runtimeInterfaceAudit.cpmIdentity.backingRef.name == "logical-policy-stream-wan";
    provider_overlay_runtime_name_is_mapped_and_auditable =
      validLinuxIfName provider.runtimeIfName
      && provider.runtimeInterfaceAudit.logicalInterfaceName == "overlay-east-west-provider-logical-name"
      && builtins.elem "overlay-east-west-provider-logical-name" provider.runtimeInterfaceAudit.aliases
      && provider.runtimeInterfaceAudit.providerIdentity.backingRef.provider == "nebula";
  };
in
{
  ok = builtins.all (value: value == true) (builtins.attrValues checks);
  failed = lib.mapAttrsToList (name: _value: name) (lib.filterAttrs (_name: value: value != true) checks);
  inherit checks runtimeNames normalized providerRuntime;
}
'

assert_json_checks_ok "runtime-interface-name-audit-mapping" "$result_json"
echo "PASS runtime-interface-name-audit-mapping"
