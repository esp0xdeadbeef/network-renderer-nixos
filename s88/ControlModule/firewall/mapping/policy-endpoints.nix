{ lib
, interfaceView ? { }
, currentSite ? { }
, communicationContract ? { }
, ownership ? { }
, runtimeTarget ? { }
, roleName ? null
, preferSiteNode ? false
, strictEndpointBindings ? false
, unitName ? null
, containerName ? null
, ...
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
      preferSiteNode
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
    inherit (interfaces) interfaceNameForLinkMatching interfaceLaneAccessMatches;
    inherit (transitAdjacency)
      transitAdjacencies
      adjacencyUnits
      adjacencyLinkName
      adjacenciesForPair
      adjacencyLaneAccessMatches
      ;
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
    inherit (transit) firstHopInterfaceToUnit firstHopInterfacesToUnit;
  };

  services = import ./policy-endpoints/services.nix {
    inherit lib currentSite communicationContract ownership common;
    inherit (tenants) tenantInterfaceByName tenantInterfacesByName;
  };

  upstream = import ./policy-endpoints/upstream.nix {
    inherit lib interfaceView currentSite common;
    inherit (interfaces)
      interfaceEntries
      interfaceLaneUplinkMatches
      interfaceNameForLink
      interfaceNameForLinkMatching
      sourceKindOf
      ;
    inherit (node) currentNodeName;
    inherit (transitAdjacency) transitAdjacencies adjacencyUnits adjacencyLinkName adjacencyLaneUplinkMatches;
  };

  resolver = import ./policy-endpoints/resolver.nix {
    inherit lib currentSite communicationContract common;
    inherit (tenants) tenantInterfaceByName tenantInterfacesByName;
    inherit (services) serviceInterfacesByName;
    inherit (upstream)
      upstreamInterfaceNames
      upstreamInterfacesForUplink
      wanEndpointNames
      explicitWanNames
      ;
    inherit (services) servicePreferredUplinksByName servicePreferredUplinksByRelation;
  };

  authority = import ./policy-endpoints/authority.nix {
    inherit
      lib
      currentSite
      runtimeTarget
      roleName
      strictEndpointBindings
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
  inherit (resolver) resolveEndpoint resolveRelationEndpoint allKnownInterfaces;
  inherit (common) samePolicyTenantLane;
  inherit (upstream) wanNames p2pNames localAdapterNames;
  inherit (authority) authoritativeBindings authorityGaps;

  allowForwardPair =
    relation: fromIf: toIf:
    let
      endpointIsService = endpoint: builtins.isAttrs endpoint && (endpoint.kind or null) == "service";
      endpointIsExternal = endpoint: builtins.isAttrs endpoint && (endpoint.kind or null) == "external";
      serviceRelation = endpointIsService (relation.from or null) || endpointIsService (relation.to or null);
      externalServiceIngress =
        endpointIsExternal (relation.from or null) && endpointIsService (relation.to or null);
      serviceUsesUpstreamLane =
        (
          endpointIsService (relation.from or null)
          && builtins.elem fromIf upstream.upstreamInterfaceNames
        )
        || (
          endpointIsService (relation.to or null)
          && builtins.elem toIf upstream.upstreamInterfaceNames
        );
    in
    if externalServiceIngress then
      true
    else if serviceRelation && serviceUsesUpstreamLane then
      common.samePolicyTenantLane fromIf toIf
    else
      serviceRelation || common.samePolicyTenantLane fromIf toIf;
}
