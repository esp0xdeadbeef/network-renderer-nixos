#!/usr/bin/env bash
# GAMP-ID: FS-270-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: NixOS renderer construction test
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/test-common.sh"

report="$(REPO_ROOT="${repo_root}" nix eval --impure --json --expr '
  let
    flake = builtins.getFlake ("path:" + builtins.getEnv "REPO_ROOT");
    lib = flake.inputs.nixpkgs.lib;
    system = builtins.currentSystem;
    traceId = "FS-270-HDS-010-SDS-010-SMS-020";
    relationId = "${traceId}__source-to-destination-icmp";
    row = flake.inputs.network-labs.outPath + "/GAMP/SMT/${traceId}";
    cpm = flake.inputs.network-control-plane-model.lib.${system}.compileAndBuild {
      input = import (row + "/intent.nix");
      inventory = import (row + "/inventory-nixos.nix");
    };
    site = cpm.control_plane_model.data."mini-smt".${traceId};
    target = builtins.head (builtins.filter
      (candidate: (candidate.logicalNode.name or null) == "downstream-selector")
      (builtins.attrValues site.runtimeTargets));
    effective = target.effectiveRuntimeRealization;
    interfaces = effective.interfaces;
    selectors = builtins.filter
      (rule: (rule.relationId or null) == relationId)
      (effective.routeSelectionRules or [ ]);
    hostModule = flake.lib.renderer.hostModule {
      inherit lib system cpm;
      hostName = "s-router-nixos";
      selectorFile = "tests/FS-270-HDS-010-SDS-010-SMS-020.sh";
    };
    evaluated = lib.nixosSystem {
      inherit system;
      modules = [ hostModule ];
    };
    networks = evaluated.config.containers.downstream-selector.config.systemd.network.networks;
    allRules = builtins.concatLists (map
      (network: network.routingPolicyRules or [ ])
      (builtins.attrValues networks));
    interfaceEntryForRuntime = runtimeName:
      builtins.head (builtins.filter
        (entry: (entry.value.runtimeIfName or null) == runtimeName)
        (map (name: { inherit name; value = interfaces.${name}; }) (builtins.attrNames interfaces)));
    networkForRuntime = runtimeName:
      builtins.head (builtins.filter
        (network: (network.matchConfig.Name or null) == runtimeName)
        (builtins.attrValues networks));
    cpmRouteFor = selector:
      let
        policyEntry = interfaceEntryForRuntime selector.policyInterface;
        familyRoutes = if selector.family == 4
          then policyEntry.value.routes.ipv4 or [ ]
          else policyEntry.value.routes.ipv6 or [ ];
      in
      builtins.head (builtins.filter
        (route:
          (route.relationId or null) == relationId
          && (route.intent.direction or null) == selector.direction
          && (route.dst or null) == selector.destinationPrefix)
        familyRoutes);
    renderedRuleFor = selector:
      builtins.any
        (rule:
          (rule.Family or null) == (if selector.family == 4 then "ipv4" else "ipv6")
          && (rule.From or null) == selector.sourcePrefix
          && (rule.To or null) == selector.destinationPrefix
          && (rule.IncomingInterface or null) == selector.incomingInterface
          && (rule.Priority or null) == selector.priority
          && (rule.Table or null) == selector.tableId
          && !(rule ? SuppressPrefixLength))
        allRules;
    renderedRouteFor = selector:
      let
        cpmRoute = cpmRouteFor selector;
        policyNetwork = networkForRuntime selector.policyInterface;
        gateway = if selector.family == 4 then cpmRoute.via4 else cpmRoute.via6;
      in
      builtins.any
        (route:
          (route.Destination or null) == selector.destinationPrefix
          && (route.Gateway or null) == gateway
          && (route.Table or null) == selector.tableId)
        (policyNetwork.routes or [ ]);
    signature = selector: builtins.concatStringsSep "|" [
      (builtins.toString selector.family)
      selector.direction
      selector.sourcePrefix
      selector.destinationPrefix
      selector.incomingInterface
      (builtins.toString selector.priority)
      (builtins.toString selector.tableId)
    ];
    renderedInterfaceNames = builtins.mapAttrs (_: iface: iface.runtimeIfName) interfaces;
    project = projectionInterfaces: selector:
      import (builtins.getEnv "REPO_ROOT" + "/s88/ControlModule/render/container-networks/policy-routing/relation-selection-rules.nix") {
        inherit lib renderedInterfaceNames;
        interfaces = projectionInterfaces;
        routeSelectionRules = [ selector ];
      };
    evaluationFails = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
    seededSelector = builtins.head selectors;
    seededPolicyEntry = interfaceEntryForRuntime seededSelector.policyInterface;
    interfacesWithoutRelationRoute = interfaces // {
      ${seededPolicyEntry.name} = seededPolicyEntry.value // {
        routes = { ipv4 = [ ]; ipv6 = [ ]; };
      };
    };
  in
  {
    selectorCount = builtins.length selectors;
    renderedRuleCount = builtins.length (builtins.filter renderedRuleFor selectors);
    renderedRouteCount = builtins.length (builtins.filter renderedRouteFor selectors);
    signatures = builtins.sort builtins.lessThan (map signature selectors);
    allSelectorsAreExact = builtins.all
      (selector:
        selector.authority == "relation-policy-state-owner"
        && selector.policyStateOwner == "policy"
        && selector.returnBehavior == "symmetric"
        && selector.trafficType == "icmp")
      selectors;
    noRelationDefault = builtins.all
      (selector: !(builtins.elem selector.destinationPrefix [ "0.0.0.0/0" "::/0" ]))
      selectors;
    seededWrongTableRejected = evaluationFails (project interfaces (seededSelector // {
      tableId = seededSelector.tableId + 1;
    }));
    seededMissingIngressRejected = evaluationFails (project interfaces (seededSelector // {
      incomingInterface = "missing-explicit-interface";
    }));
    seededMissingReturnContractRejected = evaluationFails (project interfaces (
      builtins.removeAttrs seededSelector [ "returnBehavior" ]
    ));
    seededMissingPolicyRouteRejected = evaluationFails (
      project interfacesWithoutRelationRoute seededSelector
    );
    seededTransitiveDefaultRejected = evaluationFails (project interfaces (seededSelector // {
      destinationPrefix = "0.0.0.0/0";
    }));
  }
')"

if ! jq -e '
  .selectorCount == 4
  and .renderedRuleCount == 4
  and .renderedRouteCount == 4
  and .allSelectorsAreExact
  and .noRelationDefault
  and .seededWrongTableRejected
  and .seededMissingIngressRejected
  and .seededMissingReturnContractRejected
  and .seededMissingPolicyRouteRejected
  and .seededTransitiveDefaultRejected
' <<<"${report}" >/dev/null; then
  jq . <<<"${report}" >&2
  echo "FAIL FS-270-HDS-010-SDS-010-SMS-020: NixOS did not materialize the complete CPM relation selector contract" >&2
  exit 1
fi

echo "PASS FS-270-HDS-010-SDS-010-SMS-020: NixOS materializes exact dual-stack policy-state selectors and bounded routes"
