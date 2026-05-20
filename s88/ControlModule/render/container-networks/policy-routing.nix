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

  forwardingRulesResolved =
    (runtimeForwardingIntent.rules or [ ])
    ++ (forwardingIntentData.rules or [ ])
    ++ (explicitPairsToRules (runtimeForwardingIntent.normalizedExplicitForwardPairs or [ ]))
    ++ (explicitPairsToRules (forwardingIntentData.normalizedExplicitForwardPairs or [ ]))
    ++ (explicitPairsToRules (forwardingIntentData.policyRelationForwardPairs or [ ]));

  hasAcceptForwardingRule =
    fromName: toName:
    builtins.any
      (rule:
        builtins.isAttrs rule
        && (rule.action or null) == "accept"
        && (rule.fromInterface or null) == fromName
        && (rule.toInterface or null) == toName)
      forwardingRulesResolved;

  routeSources = import ./policy-routing/source-interfaces.nix {
    inherit lib interfaces interfaceNames renderedInterfaceNames;
    inherit (peers) addressForFamily ipv4PeerFor31 ipv6PeerFor127;
    policyRoutingSources = containerModel.policyRoutingSources or { };
    forwardingRules = forwardingRulesResolved;
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

  routeIntentKind = route: (route.intent.kind or null);

  isServiceDnsReachabilityRoute =
    route: builtins.isAttrs route && routeIntentKind route == "service-dns-reachability";

  explicitReturnRoutes = import ./policy-routing/explicit-return-routes.nix {
    inherit lib common interfaces interfaceNames renderedInterfaceNames;
    inherit (peers) addressForFamily ipv4PeerFor31 ipv6PeerFor127;
  };

  connectedP2pRoutesForInterface =
    ifName:
    let
      iface = interfaces.${ifName};
      peer4 = peers.ipv4PeerFor31 (peers.addressForFamily 4 iface);
      peer6 = peers.ipv6PeerFor127 (peers.addressForFamily 6 iface);
    in
    (lib.optional (peer4 != null) {
      dst = "${peer4}/31";
      via4 = peer4;
    })
    ++ (lib.optional (peer6 != null) {
      dst = "${peer6}/127";
      via6 = peer6;
    });

  policyOnlyProjection = import ./policy-routing/policy-only-projection.nix {
    inherit renderedInterfaceNames;
    policyRoutingSources = containerModel.policyRoutingSources or { };
  };

  rawRoutesForPolicyTable =
    tableId: interfaceName: sourceIfName:
    let
      targetIfName = lib.findFirst (name: renderedInterfaceNames.${name} == interfaceName) null interfaceNames;
      targetServiceDnsDestinations =
        if targetIfName == null then
          [ ]
        else
          map (route: route.dst) (
            lib.filter
              (route: isServiceDnsReachabilityRoute route && builtins.isString (route.dst or null))
              (interfaces.${targetIfName}.routes or [ ])
          );
      explicitNonDefaultRoutes =
        lib.filter
          (
            route:
            builtins.isAttrs route
            && !(isDefaultRoute route)
            && !(isPolicyOnlyRoute route)
            && !(builtins.elem (route.dst or null) targetServiceDnsDestinations)
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
      upstreamPolicyCoreConnectedRoutes =
        if isUpstreamSelector && isUpstreamSelectorPolicyInterface interfaceName then
          lib.concatMap (
            name:
            if isUpstreamSelectorCoreInterface renderedInterfaceNames.${name} then
              connectedP2pRoutesForInterface name
            else
              [ ]
          ) interfaceNames
        else
          [ ];
      explicitForwardTargetDefaultRoutes =
        if
          targetIfName != null
          && sourceIfName != targetIfName
          && hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName}
        then
          lib.filter
            (route: builtins.isAttrs route && (isDefaultRoute route || isPolicyOnlyRoute route))
            (interfaces.${targetIfName}.routes or [ ])
        else
          [ ];
      policyDownstreamDefaultRoutes =
        if isPolicy && isPolicyDownstreamInterface interfaceName then
          lib.concatMap
            (name:
              if hasAcceptForwardingRule interfaceName renderedInterfaceNames.${name} then
                lib.filter
                  (route: builtins.isAttrs route && isDefaultRoute route)
                  (interfaces.${name}.routes or [ ])
              else
                [ ])
            interfaceNames
        else
          [ ];
      sourceRoutes =
        if isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName && sourceIfName == targetIfName then
          (lib.filter
            (route: builtins.isAttrs route && (!(isDefaultRoute route) || isPolicyOnlyRoute route))
            (interfaces.${sourceIfName}.routes or [ ]))
          ++ upstreamCoreReturnRoutes
        else if isUpstreamSelector && isUpstreamSelectorPolicyInterface interfaceName && sourceIfName == targetIfName then
          (lib.filter builtins.isAttrs (interfaces.${sourceIfName}.routes or [ ])) ++ upstreamPolicyCoreConnectedRoutes
        else if isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName then
          (returnRoutes.forUpstreamCore interfaceName sourceIfName) ++ explicitNonDefaultRoutes
        else
          (interfaces.${sourceIfName}.routes or [ ])
          ++ (returnRoutes.forUpstreamCore interfaceName sourceIfName)
          ++ explicitForwardTargetDefaultRoutes
          ++ policyDownstreamDefaultRoutes;
      staticPolicyRoutes =
        lib.filter (route: !(isExternalValidationDelegatedPrefixRoute route)) sourceRoutes;
      scopedSourceRoutes =
        if sourceIfName == targetIfName then
          staticPolicyRoutes
        else if
          isPolicy
          && isPolicyDownstreamInterface interfaceName
          && builtins.any
            (route: builtins.isAttrs route && isDefaultRoute route)
            (interfaces.${sourceIfName}.routes or [ ])
        then
          staticPolicyRoutes
        else if hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName} then
          staticPolicyRoutes
        else if
          policyOnlyProjection.mayProject interfaceName sourceIfName
          && isUpstreamSelector
          && isUpstreamSelectorPolicyInterface interfaceName
        then
          lib.filter (route: !(isDefaultRoute route) || isPolicyOnlyRoute route) staticPolicyRoutes
        else if policyOnlyProjection.mayProject interfaceName sourceIfName then
          lib.filter (route: !(isDefaultRoute route) || isPolicyOnlyRoute route) staticPolicyRoutes
        else
          lib.filter (route: !(isDefaultRoute route) && !(isPolicyOnlyRoute route)) staticPolicyRoutes;
    in
    lib.filter builtins.isAttrs (
      map (route: if builtins.isAttrs route then route // { table = tableId; } else null) scopedSourceRoutes
    );

  routeDestinationKey = route: "${toString (route.table or "main")}|${route.dst or ""}";

  preferServiceDnsRoutes =
    routes:
    lib.concatMap
      (group:
        let
          serviceRoutes = lib.filter isServiceDnsReachabilityRoute group;
        in
        if serviceRoutes == [ ] then group else serviceRoutes)
      (builtins.attrValues (builtins.groupBy routeDestinationKey routes));

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
          baseSourceIfNames = routeSources.forTarget interfaceName;
          policyIngressLocalSourceIfNames =
            lib.optionals (isPolicy && isPolicyUpstreamInterface interfaceName) (
              lib.filter (name: isPolicyDownstreamInterface renderedInterfaceNames.${name}) interfaceNames
            );
          sourceIfNames = lib.unique (baseSourceIfNames ++ policyIngressLocalSourceIfNames);
          rawPolicyRoutes =
            preferServiceDnsRoutes (
              lib.concatMap
                (sourceIfName:
                  map (route: route // { _s88PolicySourceIfName = sourceIfName; })
                    (rawRoutesForPolicyTable tableId interfaceName sourceIfName))
                sourceIfNames
            );
          routesByInterface =
            builtins.foldl'
              (routesAcc: rawRoute:
                let
                  sourceIfName = rawRoute._s88PolicySourceIfName;
                  outputIfName = routeOutputInterface sourceIfName rawRoute;
                  renderedRoute = mkRoute (builtins.removeAttrs rawRoute [ "_s88PolicySourceIfName" ]);
                in
                if renderedRoute == null then
                  routesAcc
                else
                  routesAcc
                  // {
                    ${outputIfName} = (routesAcc.${outputIfName} or [ ]) ++ [ renderedRoute ];
                  })
              { }
              rawPolicyRoutes;
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
