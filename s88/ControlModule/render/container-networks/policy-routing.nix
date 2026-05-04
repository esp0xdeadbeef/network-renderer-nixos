{
  lib,
  containerModel,
  common,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  upstreamLanesMatch,
  isSelector,
  isUpstreamSelector,
  isPolicy,
  isDownstreamSelectorAccessInterface,
  isDownstreamSelectorPolicyInterface,
  isUpstreamSelectorCoreInterface,
  isUpstreamSelectorPolicyInterface,
  isPolicyDownstreamInterface,
  isPolicyUpstreamInterface,
  isOverlayInterface,
  isCoreTransitInterface,
  mkRoute,
}:

let
  peers = import ./policy-routing/peers.nix {
    inherit lib common;
  };

  routeSources = import ./policy-routing/source-interfaces.nix {
    inherit
      lib
      common
      interfaceNames
      renderedInterfaceNames
      upstreamLanesMatch
      isSelector
      isUpstreamSelector
      isPolicy
      isUpstreamSelectorCoreInterface
      isUpstreamSelectorPolicyInterface
      isPolicyDownstreamInterface
      isPolicyUpstreamInterface
      isOverlayInterface
      isCoreTransitInterface
      ;
  };

  siteDestinations = import ./policy-routing/site-destinations.nix {
    inherit lib containerModel common;
  };

  returnRoutes = import ./policy-routing/return-routes.nix {
    inherit lib common interfaces renderedInterfaceNames isUpstreamSelector isUpstreamSelectorCoreInterface;
    inherit (peers) addressForFamily ipv4PeerFor31 ipv6PeerFor127;
    inherit (siteDestinations) returnDestinationsForTenant;
  };

  routeGateway =
    route:
    if builtins.isString (route.via4 or null) && route.via4 != "" then
      { family = 4; gateway = route.via4; }
    else if builtins.isString (route.via6 or null) && route.via6 != "" then
      { family = 6; gateway = route.via6; }
    else
      null;

  interfacePeerForFamily =
    family: iface:
    let
      address = peers.addressForFamily family iface;
    in
    if family == 6 then peers.ipv6PeerFor127 address else peers.ipv4PeerFor31 address;

  routeOutputInterface =
    sourceIfName: route:
    let
      gateway = routeGateway route;
      sourceIface = interfaces.${sourceIfName};
      sourceInterfacePeer =
        if gateway == null then null else interfacePeerForFamily gateway.family sourceIface;
      matchingInterfaces =
        if gateway == null then
          [ ]
        else
          lib.filter
            (ifName: interfacePeerForFamily gateway.family interfaces.${ifName} == gateway.gateway)
            interfaceNames;
    in
    if gateway == null || sourceInterfacePeer == gateway.gateway || matchingInterfaces == [ ] then
      sourceIfName
    else
      builtins.head matchingInterfaces;

  rawRoutesForPolicyTable =
    tableId: interfaceName: sourceIfName:
    let
      sourceRoutes =
        if isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName then
          returnRoutes.forUpstreamCore interfaceName sourceIfName
        else
          (interfaces.${sourceIfName}.routes or [ ])
          ++ (returnRoutes.forUpstreamCore interfaceName sourceIfName);
    in
    lib.filter builtins.isAttrs (
      map (route: if builtins.isAttrs route then route // { table = tableId; } else null) sourceRoutes
    );

  policyRulesFor =
    interfaceName: tableId: sourceIfNames:
    if sourceIfNames == [ ] then
      [ ]
    else
      [
        {
          Family = "both";
          IncomingInterface = interfaceName;
          Priority = tableId;
          Table = 254;
          SuppressPrefixLength = 0;
        }
        {
          Family = "both";
          IncomingInterface = interfaceName;
          Priority = 10000 + tableId;
          Table = tableId;
        }
      ];
in
{
  policyRoutingByInterface =
    builtins.foldl'
      (
        acc: entry:
        let
          index = entry.index;
          ifName = entry.ifName;
          interfaceName = renderedInterfaceNames.${ifName};
          tableId = 2000 + index;
          sourceIfNames = routeSources.forTarget interfaceName;
          routesByInterface = builtins.foldl' (
            routesAcc: sourceIfName:
            builtins.foldl'
              (innerAcc: rawRoute:
                let
                  outputIfName = routeOutputInterface sourceIfName rawRoute;
                  renderedRoute = mkRoute rawRoute;
                in
                if renderedRoute == null then
                  innerAcc
                else
                  innerAcc
                  // {
                    ${outputIfName} = (innerAcc.${outputIfName} or [ ]) ++ [ renderedRoute ];
                  })
              routesAcc
              (rawRoutesForPolicyTable tableId interfaceName sourceIfName)
          ) { } sourceIfNames;
        in
        {
          routes = builtins.foldl' (
            routesAcc: sourceIfName:
            routesAcc
            // {
              ${sourceIfName} =
                (routesAcc.${sourceIfName} or [ ]) ++ (routesByInterface.${sourceIfName} or [ ]);
            }
          ) acc.routes (builtins.attrNames routesByInterface);
          rules = acc.rules // {
            ${ifName} =
              (acc.rules.${ifName} or [ ]) ++ policyRulesFor interfaceName tableId sourceIfNames;
          };
        }
      )
      {
        routes = { };
        rules = { };
      }
      (lib.imap0 (index: ifName: { inherit index ifName; }) interfaceNames);
}
