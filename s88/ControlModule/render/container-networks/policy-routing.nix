{
  lib,
  containerModel,
  common,
  forwardingIntent ? null,
  firewallRuleset ? null,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  laneAccessForRenderedName,
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
  isExternalValidationDelegatedPrefixRoute,
}:

let
  peers = import ./policy-routing/peers.nix {
    inherit lib common;
  };

  forwardingIntentData =
    if forwardingIntent != null && builtins.isAttrs forwardingIntent then
      forwardingIntent
    else
      { };

  runtimeForwardingIntent =
    if builtins.isAttrs ((containerModel.runtimeTarget or { }).forwardingIntent or null) then
      containerModel.runtimeTarget.forwardingIntent
    else
      { };

  explicitPairsToRules =
    pairs:
    lib.concatMap (
      pair:
      if !(builtins.isAttrs pair) || (pair.action or "accept") != "accept" then
        [ ]
      else
        lib.concatMap (
          fromInterface:
          map (toInterface: {
            action = "accept";
            inherit fromInterface toInterface;
          }) (pair."out" or [ ])
        ) (pair."in" or [ ])
    ) pairs;

  routeSources = import ./policy-routing/source-interfaces.nix {
    inherit lib interfaces interfaceNames renderedInterfaceNames;
    inherit (peers) addressForFamily ipv4PeerFor31 ipv6PeerFor127;
    policyRoutingSources = containerModel.policyRoutingSources or { };
    forwardingRules =
      (runtimeForwardingIntent.rules or [ ])
      ++ (forwardingIntentData.rules or [ ])
      ++ (explicitPairsToRules (runtimeForwardingIntent.normalizedExplicitForwardPairs or [ ]))
      ++ (explicitPairsToRules (forwardingIntentData.normalizedExplicitForwardPairs or [ ]))
      ++ (explicitPairsToRules (forwardingIntentData.policyRelationForwardPairs or [ ]));
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

  isDefaultRoute =
    route:
    (route.dst or null) == "0.0.0.0/0"
    || (route.dst or null) == "::/0"
    || (route.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0";

  isPolicyOnlyRoute =
    route: builtins.isAttrs route && ((route.policyOnly or false) == true || (route._s88PolicyOnly or false) == true);

  explicitReturnRoutes = import ./policy-routing/explicit-return-routes.nix {
    inherit lib common interfaces interfaceNames renderedInterfaceNames;
    inherit (peers) addressForFamily ipv4PeerFor31 ipv6PeerFor127;
  };

  policyOnlyProjection = import ./policy-routing/policy-only-projection.nix {
    inherit renderedInterfaceNames;
    policyRoutingSources = containerModel.policyRoutingSources or { };
  };

  rawRoutesForPolicyTable =
    tableId: interfaceName: sourceIfName:
    let
      targetIfName = lib.findFirst (name: renderedInterfaceNames.${name} == interfaceName) null interfaceNames;
      explicitNonDefaultRoutes =
        lib.filter
          (
            route:
            builtins.isAttrs route
            && !(isDefaultRoute route)
            && !(isPolicyOnlyRoute route)
          )
          (interfaces.${sourceIfName}.routes or [ ]);
      upstreamCoreReturnRoutes =
        if isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName then
          lib.concatMap (
            name:
            if isUpstreamSelectorPolicyInterface renderedInterfaceNames.${name} then
              (returnRoutes.forUpstreamCore interfaceName name) ++ (explicitReturnRoutes.forPolicyInterface name)
            else
              [ ]
          ) interfaceNames
        else
          [ ];
      sourceRoutes =
        if isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName && sourceIfName == targetIfName then
          (lib.filter
            (route: builtins.isAttrs route && (!(isDefaultRoute route) || isPolicyOnlyRoute route))
            (interfaces.${sourceIfName}.routes or [ ]))
          ++ upstreamCoreReturnRoutes
        else if isUpstreamSelector && isUpstreamSelectorPolicyInterface interfaceName && sourceIfName == targetIfName then
          lib.filter builtins.isAttrs (interfaces.${sourceIfName}.routes or [ ])
        else if isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName then
          (returnRoutes.forUpstreamCore interfaceName sourceIfName) ++ explicitNonDefaultRoutes
        else
          (interfaces.${sourceIfName}.routes or [ ])
          ++ (returnRoutes.forUpstreamCore interfaceName sourceIfName);
      staticPolicyRoutes =
        lib.filter (route: !(isExternalValidationDelegatedPrefixRoute route)) sourceRoutes;
      scopedSourceRoutes =
        if sourceIfName == targetIfName then
          staticPolicyRoutes
        else if
          policyOnlyProjection.mayProject interfaceName sourceIfName
          && isUpstreamSelector
          && isUpstreamSelectorPolicyInterface interfaceName
        then
          lib.filter (route: !(isDefaultRoute route)) staticPolicyRoutes
        else if policyOnlyProjection.mayProject interfaceName sourceIfName then
          lib.filter (route: !(isDefaultRoute route) || isPolicyOnlyRoute route) staticPolicyRoutes
        else
          lib.filter (route: !(isDefaultRoute route) && !(isPolicyOnlyRoute route)) staticPolicyRoutes;
    in
    lib.filter builtins.isAttrs (
      map (route: if builtins.isAttrs route then route // { table = tableId; } else null) scopedSourceRoutes
    );

  policyRulesFor =
    interfaceName: tableId: sourceIfNames:
    let
      tableRule = {
        Family = "both";
        IncomingInterface = interfaceName;
        Priority = tableId;
        Table = tableId;
      };
      mainFallbackRule = {
        Family = "both";
        IncomingInterface = interfaceName;
        Priority = 10000 + tableId;
        Table = 254;
        SuppressPrefixLength = 0;
      };
      mainFirstRule = mainFallbackRule // {
        Priority = tableId;
      };
      tableSecondRule = tableRule // {
        Priority = 10000 + tableId;
      };
    in
    if sourceIfNames == [ ] then
      [ ]
    else if
      (isUpstreamSelector && isUpstreamSelectorPolicyInterface interfaceName)
      || (isSelector && isDownstreamSelectorPolicyInterface interfaceName)
    then
      [
        tableRule
        mainFallbackRule
      ]
    else
      [
        mainFirstRule
        tableSecondRule
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
            routesAcc: outputIfName:
            routesAcc
            // {
              ${outputIfName} =
                (routesAcc.${outputIfName} or [ ]) ++ (routesByInterface.${outputIfName} or [ ]);
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
