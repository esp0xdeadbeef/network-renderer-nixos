#!/usr/bin/env bash
# GAMP-ID: FS-540-HDS-010-SDS-010-SMS-035
# GAMP-SCOPE: software-module-test
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
result="$(REPO_ROOT="${repo_root}" nix eval --json --impure --expr '
let
  repoRoot = builtins.getEnv "REPO_ROOT";
  flake = builtins.getFlake ("path:" + repoRoot);
  system = builtins.currentSystem;
  lib = flake.inputs.nixpkgs.lib;
  pkgs = import flake.inputs.nixpkgs { inherit system; };
  labs = flake.inputs.network-labs.outPath;
  traceId = "FS-540-HDS-010-SDS-010-SMS-030";
  source = import (labs + "/GAMP/SMT/FS-540-HDS-010-SDS-010-SMS-030/intent.nix");
  inventory = import (labs + "/GAMP/SMT/FS-540-HDS-010-SDS-010-SMS-030/inventory-nixos.nix");
  built = flake.inputs.network-control-plane-model.libBySystem.${system}.compileAndBuild {
    input = source;
    inherit inventory;
  };
  site = built.control_plane_model.data.mini-smt.${traceId};
  targetFor = nodeName:
    builtins.head (
      builtins.filter
        (target: (target.logicalNode.name or null) == nodeName)
        (builtins.attrValues site.runtimeTargets)
    );
  render = target:
    import (repoRoot + "/s88/ControlModule/render/containers/dns-services.nix") {
      inherit lib pkgs;
      renderedModel = {
        runtimeTarget = target;
        interfaces = { };
      };
      forwardingIntent = { };
    };
  recursiveTarget = targetFor "access-recursive";
  localTarget = targetFor "access-local";
  coreTarget = targetFor "core-primary";
  recursive = render recursiveTarget;
  local = render localTarget;
  core = render coreTarget;
  recursiveDns = recursiveTarget.services.dns;
  localDns = localTarget.services.dns;
  recursiveForwardZones = recursive.services.unbound.settings."forward-zone";
  localForwardZones = local.services.unbound.settings."forward-zone";
  coreForwardZones = core.services.unbound.settings."forward-zone";
  recursiveRoot = builtins.head (
    builtins.filter (zone: zone.name == ".") recursiveForwardZones
  );
  namedCore = builtins.head (
    builtins.filter
      (resolver: (resolver.kind or null) == "named-core-resolver")
      recursiveDns.upstreamResolvers
  );
  localZoneByName = builtins.listToAttrs (
    map (zone: { name = zone.name; value = zone; }) localForwardZones
  );
  localSourcePrefixes = builtins.concatMap
    (policy: policy.sourcePrefixes)
    recursiveDns.requesterPolicies;
  recursiveAccessControl = recursive.services.unbound.settings.server."access-control";
  mutatedLocalTarget = localTarget // {
    services = localTarget.services // {
      dns = localDns // {
        localOnlyPolicy = localDns.localOnlyPolicy // { recursion = true; };
      };
    };
  };
  mutatedRecursiveTarget = recursiveTarget // {
    services = recursiveTarget.services // {
      dns = recursiveDns // { forwarders = [ "seeded-mismatch" ]; };
    };
  };
  warnedRecursiveTarget = recursiveTarget // {
    services = recursiveTarget.services // {
      dns = recursiveDns // {
        reproducibilityWarnings = [
          {
            code = "DNS_CORE_UPSTREAM_HARDCODED";
            disposition = "warn";
          }
        ];
      };
    };
  };
  fatalRecursiveTarget = recursiveTarget // {
    services = recursiveTarget.services // {
      dns = recursiveDns // {
        reproducibilityWarnings = [
          {
            code = "DNS_EGRESS_SELECTION_AMBIGUOUS";
            disposition = "fail-closed";
          }
        ];
      };
    };
  };
  localNegative = builtins.tryEval (
    builtins.deepSeq (render mutatedLocalTarget).services.unbound.settings true
  );
  divergenceNegative = builtins.tryEval (
    builtins.deepSeq (render mutatedRecursiveTarget).services.unbound.settings true
  );
  fatalWarningNegative = builtins.tryEval (
    builtins.deepSeq (render fatalRecursiveTarget).services.unbound.settings true
  );
  warnedRecursive = render warnedRecursiveTarget;
in {
  positive =
    recursiveDns.recursionMode == "forwarding"
    && builtins.length recursiveForwardZones == 1
    && recursiveRoot."forward-addr" == namedCore.addresses
    && builtins.all
      (prefix: builtins.elem "${prefix} refuse_non_local" recursiveAccessControl)
      localSourcePrefixes
    && localDns.recursionMode == "local-only"
    && builtins.length localForwardZones == builtins.length localDns.localForwardZones
    && builtins.all
      (zone:
        builtins.hasAttr zone.name localZoneByName
        && localZoneByName.${zone.name}."forward-addr" == zone.forwardTo
        && localZoneByName.${zone.name}."forward-first" == false)
      localDns.localForwardZones
    && builtins.elem ". static" local.services.unbound.settings.server."local-zone"
    && coreTarget.services.dns.recursionMode == "iterative"
    && coreForwardZones == [ ]
    && core.services.unbound.enableRootTrustAnchor
    && builtins.length core.services.unbound.settings.server.interface == 4
    && recursive.warnings == [ ]
    && local.warnings == [ ]
    && core.warnings == [ ];
  localNegativeRejected = !localNegative.success;
  divergenceRejected = !divergenceNegative.success;
  fatalWarningRejected = !fatalWarningNegative.success;
  warningSurfaced =
    builtins.length warnedRecursive.warnings == 1
    && lib.hasInfix "DNS_CORE_UPSTREAM_HARDCODED" (builtins.head warnedRecursive.warnings);
}
')"

jq -e '
  .positive
  and .localNegativeRejected
  and .divergenceRejected
  and .fatalWarningRejected
  and .warningSurfaced
' <<<"${result}" >/dev/null

echo "PASS FS-540 NixOS local-only DNS authority materialization"
