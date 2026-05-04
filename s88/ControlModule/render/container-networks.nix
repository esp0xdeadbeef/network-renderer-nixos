{
  lib,
  containerModel,
  uplinks,
  wanUplinkName,
}:

let
  common = import ./container-networks/common.nix { inherit lib; };

  interfaces = containerModel.interfaces or { };
  interfaceView = import ./container-networks/interface-view.nix {
    inherit lib interfaces common;
  };

  networkManagerInterfaces =
    if
      containerModel ? networkManagerWanInterfaces
      && builtins.isList containerModel.networkManagerWanInterfaces
    then
      lib.filter builtins.isString containerModel.networkManagerWanInterfaces
    else
      [ ];

  routeRender = import ./container-networks/routes.nix {
    inherit lib containerModel common;
  };

  dynamicWan = import ./container-networks/dynamic-wan.nix {
    inherit lib uplinks wanUplinkName common;
  };

  hostBridgeWan = import ./container-networks/host-bridge-wan.nix {
    inherit lib containerModel uplinks wanUplinkName;
  };

  advertisements = import ./container-networks/advertisements.nix {
    inherit lib containerModel;
    inherit (interfaceView) interfaceKeyForRenderedName;
  };

  classes = import ./container-networks/classes.nix {
    inherit lib common;
    inherit (interfaceView) interfaceNames renderedInterfaceNames;
  };

  policyRouting = import ./container-networks/policy-routing.nix {
    inherit lib containerModel common;
    inherit (interfaceView)
      interfaces
      interfaceNames
      renderedInterfaceNames
      upstreamLanesMatch
      ;
    inherit (classes)
      isSelector
      isUpstreamSelector
      isPolicy
      isDownstreamSelectorAccessInterface
      isDownstreamSelectorPolicyInterface
      isUpstreamSelectorCoreInterface
      isUpstreamSelectorPolicyInterface
      isPolicyDownstreamInterface
      isPolicyUpstreamInterface
      isOverlayInterface
      isCoreTransitInterface
      ;
    inherit (routeRender) mkRoute;
  };

  loopback = import ./container-networks/loopback.nix {
    inherit lib containerModel;
  };

  interfaceUnits = import ./container-networks/interface-units.nix {
    inherit lib interfaces networkManagerInterfaces common;
    inherit (interfaceView) interfaceNames renderedInterfaceNames;
    inherit (routeRender)
      mkRoute
      isExternalValidationDelegatedPrefixRoute
      delegatedPrefixSourceForRoute
      ;
    inherit (dynamicWan) mkDynamicWanNetworkConfig needsIpv6AcceptRA;
    inherit (advertisements) advertisedOnlinkRoutesByInterface;
    inherit (policyRouting) policyRoutingByInterface;
    inherit (classes) keepInterfaceRoutesInMain isUpstreamSelectorCoreInterface;
  };
in
{
  networks = loopback.loopbackUnit // hostBridgeWan.networks // interfaceUnits.interfaceUnits;
  ipv6AcceptRAInterfaces =
    hostBridgeWan.ipv6AcceptRAInterfaces ++ interfaceUnits.ipv6AcceptRAInterfaces;
  inherit (interfaceUnits) dynamicDelegatedRoutes;
}
