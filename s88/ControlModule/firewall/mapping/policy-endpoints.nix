{
  lib,
  interfaceView ? { },
  currentSite ? { },
  communicationContract ? { },
  ownership ? { },
  runtimeTarget ? { },
  roleName ? null,
  unitName ? null,
  containerName ? null,
  ...
}:

let
  common = import ./policy-endpoints/common.nix { inherit lib; };

  interfaces = import ./policy-endpoints/interfaces.nix {
    inherit lib interfaceView common;
  };

  node = import ./policy-endpoints/node.nix {
    inherit
      lib
      currentSite
      runtimeTarget
      roleName
      common
      ;
    inherit (interfaces) interfaceEntries;
  };

  transitAdjacency = import ./policy-endpoints/transit-adjacency.nix {
    inherit lib currentSite common;
  };

  transit = import ./policy-endpoints/transit-path.nix {
    inherit lib common;
    inherit (node) currentNodeName;
    inherit (interfaces) interfaceNameForLink;
    inherit (transitAdjacency) transitAdjacencies adjacencyUnits adjacencyLinkName adjacencyForPair;
  };

  tenants = import ./policy-endpoints/tenants.nix {
    inherit
      lib
      currentSite
      runtimeTarget
      common
      ;
    inherit (interfaces) resolveInterfaceAlias;
    inherit (node) currentNodeName;
    inherit (transit) firstHopInterfaceToUnit;
  };

  services = import ./policy-endpoints/services.nix {
    inherit lib communicationContract ownership common;
    inherit (tenants) tenantInterfaceByName;
  };

  upstream = import ./policy-endpoints/upstream.nix {
    inherit lib interfaceView currentSite common;
    inherit (interfaces) interfaceEntries sourceKindOf interfaceNameForLink;
    inherit (node) currentNodeName;
    inherit (transitAdjacency) transitAdjacencies adjacencyUnits adjacencyLinkName;
  };

  resolver = import ./policy-endpoints/resolver.nix {
    inherit lib currentSite communicationContract common;
    inherit (tenants) tenantInterfaceByName;
    inherit (services) serviceInterfacesByName;
    inherit (upstream)
      upstreamInterfaceNames
      upstreamInterfacesForUplink
      wanEndpointNames
      explicitWanNames
      ;
  };

  authority = import ./policy-endpoints/authority.nix {
    inherit
      lib
      currentSite
      runtimeTarget
      roleName
      unitName
      containerName
      common
      ;
    inherit (node) currentNodeName;
    inherit (tenants) tenantAttachments tenantInterfaceByName;
    inherit (upstream) upstreamSelectorNodeName upstreamInterfaceNames;
    inherit (resolver) interfaceTags;
  };

  _ = authority.strictCheck;
in
{
  inherit (resolver) resolveEndpoint allKnownInterfaces;
  inherit (common) samePolicyTenantLane;
  inherit (upstream) wanNames p2pNames localAdapterNames;
  inherit (authority) authoritativeBindings authorityGaps;

  allowForwardPair =
    relation: fromIf: toIf:
    let
      endpointIsService = endpoint: builtins.isAttrs endpoint && (endpoint.kind or null) == "service";
    in
    endpointIsService (relation.from or null)
    || endpointIsService (relation.to or null)
    || common.samePolicyTenantLane fromIf toIf;
}
