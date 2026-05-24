{ lib
, interfaces
, interfaceNames
, renderedInterfaceNames
, isSelector
, isUpstreamSelector
, isPolicy
, isDownstreamSelectorPolicyInterface
, isUpstreamSelectorCoreInterface
, isUpstreamSelectorPolicyInterface
, isPolicyDownstreamInterface
, isPolicyUpstreamInterface
, returnRoutes
, explicitReturnRoutes
, policyOnlyProjection
, routeHelpers
, routeOutputInterface
, hasAcceptForwardingRule
, hasAcceptForwardingRuleForRoute
, isExternalValidationDelegatedPrefixRoute
,
}:
let
  inherit (routeHelpers)
    connectedP2pRoutesForInterface
    connectedP2pScopeRoutesForInterface
    connectedScopeRoutesForInterface
    isDefaultRoute
    isPolicyOnlyRoute
    isServiceDnsReachabilityRoute
    ;

  interfaceLaneAccess =
    interfaceName:
    let
      key = lib.findFirst (name: renderedInterfaceNames.${name} == interfaceName) null interfaceNames;
    in
    if key == null then null else ((interfaces.${key}.backingRef or { }).lane or { }).access or null;

  routeLaneAccess = route: ((route.lane or { }).access or null);

  routeMatchesInterfaceLane =
    interfaceName: route:
    let
      targetAccess = interfaceLaneAccess interfaceName;
      routeAccess = routeLaneAccess route;
    in
    targetAccess == null || routeAccess == targetAccess;
in
tableId: interfaceName: sourceIfName:
let
  targetIfName = lib.findFirst
    (
      name: renderedInterfaceNames.${name} == interfaceName
    )
    null
    interfaceNames;
  targetServiceDnsDestinations =
    if targetIfName == null then
      [ ]
    else
      map (route: route.dst) (
        lib.filter (route: isServiceDnsReachabilityRoute route && builtins.isString (route.dst or null)) (
          interfaces.${targetIfName}.routes or [ ]
        )
      );
  explicitNonDefaultRoutes = lib.filter
    (
      route:
      builtins.isAttrs route
      && !(isDefaultRoute route)
      && !(isPolicyOnlyRoute route)
      && !(isServiceDnsReachabilityRoute route)
      && !(builtins.elem (route.dst or null) targetServiceDnsDestinations)
    )
    (interfaces.${sourceIfName}.routes or [ ]);
  explicitAcceptedNonDefaultRoutes = lib.filter
    (
      route: hasAcceptForwardingRuleForRoute interfaceName renderedInterfaceNames.${sourceIfName} route
    )
    explicitNonDefaultRoutes;
  upstreamCoreReturnRoutes =
    if isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName then
      lib.concatMap
        (
          name:
          if
            isUpstreamSelectorPolicyInterface renderedInterfaceNames.${name}
            && hasAcceptForwardingRule interfaceName renderedInterfaceNames.${name}
          then
            (returnRoutes.forUpstreamCore interfaceName name) ++ (explicitReturnRoutes.forPolicyInterface name)
          else
            [ ]
        )
        interfaceNames
    else
      [ ];
  upstreamPolicyCoreConnectedRoutes =
    if isUpstreamSelector && isUpstreamSelectorPolicyInterface interfaceName then
      lib.concatMap
        (
          name:
          if isUpstreamSelectorCoreInterface renderedInterfaceNames.${name} then
            connectedP2pRoutesForInterface name
          else
            [ ]
        )
        interfaceNames
    else
      [ ];
  explicitForwardTargetDefaultRoutes =
    if targetIfName != null && sourceIfName != targetIfName then
      map
        (
          route:
          route
          // lib.optionalAttrs (isDefaultRoute route) {
            metric = 50;
          }
        )
        (
          lib.filter
            (
              route:
              builtins.isAttrs route
              && (isDefaultRoute route || isPolicyOnlyRoute route)
              && routeMatchesInterfaceLane interfaceName route
              && hasAcceptForwardingRuleForRoute interfaceName renderedInterfaceNames.${sourceIfName} route
            )
            (interfaces.${sourceIfName}.routes or [ ])
        )
    else
      [ ];
  policyDownstreamDefaultRoutes =
    if isPolicy && isPolicyDownstreamInterface interfaceName then
      lib.concatMap
        (
          name:
          if hasAcceptForwardingRule interfaceName renderedInterfaceNames.${name} then
            lib.filter
              (
                route:
                builtins.isAttrs route
                && isDefaultRoute route
                && hasAcceptForwardingRuleForRoute interfaceName renderedInterfaceNames.${name} route
              )
              (interfaces.${name}.routes or [ ])
          else
            [ ]
        )
        interfaceNames
    else
      [ ];
  downstreamSelectorReturnConnectedRoutes =
    if
      isSelector
      && isDownstreamSelectorPolicyInterface interfaceName
      && hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName}
    then
      connectedP2pScopeRoutesForInterface sourceIfName
    else
      [ ];
  policyUpstreamReturnRoutes =
    if isPolicy && isPolicyUpstreamInterface interfaceName then
      returnRoutes.forTenantInterface sourceIfName
    else
      [ ];
  explicitForwardReturnConnectedRoutes =
    if hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName} then
      connectedScopeRoutesForInterface sourceIfName
    else
      [ ];
  sourceRoutes =
    if
      isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName && sourceIfName == targetIfName
    then
      (lib.filter
        (
          route: builtins.isAttrs route && (!(isDefaultRoute route) || isPolicyOnlyRoute route)
        )
        (interfaces.${sourceIfName}.routes or [ ]))
      ++ upstreamCoreReturnRoutes
    else if
      isUpstreamSelector
      && isUpstreamSelectorPolicyInterface interfaceName
      && sourceIfName == targetIfName
    then
      (lib.filter builtins.isAttrs (interfaces.${sourceIfName}.routes or [ ]))
      ++ upstreamPolicyCoreConnectedRoutes
    else if isUpstreamSelector && isUpstreamSelectorCoreInterface interfaceName then
      (returnRoutes.forUpstreamCore interfaceName sourceIfName)
      ++ explicitAcceptedNonDefaultRoutes
      ++ explicitForwardTargetDefaultRoutes
    else
      (interfaces.${sourceIfName}.routes or [ ])
      ++ (returnRoutes.forUpstreamCore interfaceName sourceIfName)
      ++ explicitForwardTargetDefaultRoutes
      ++ policyDownstreamDefaultRoutes
      ++ policyUpstreamReturnRoutes
      ++ downstreamSelectorReturnConnectedRoutes;
  sourceRoutesWithConnectedReturns = sourceRoutes ++ explicitForwardReturnConnectedRoutes;
  staticPolicyRoutes = lib.filter
    (
      route: !(isExternalValidationDelegatedPrefixRoute route)
    )
    sourceRoutesWithConnectedReturns;
  explicitAcceptedOutputRoutes = lib.filter
    (
      route:
      let
        outputIfName = routeOutputInterface sourceIfName route;
        outputRenderedName = if outputIfName == null then null else renderedInterfaceNames.${outputIfName};
        targetUplink = if targetIfName == null then null else (((interfaces.${targetIfName}.backingRef or { }).lane or { }).uplink or null);
        outputUplink = if outputIfName == null then null else (((interfaces.${outputIfName}.backingRef or { }).lane or { }).uplink or null);
      in
        !(
          isUpstreamSelector
          && isUpstreamSelectorCoreInterface interfaceName
          && targetUplink == "east-west"
          && outputUplink != "east-west"
          && outputRenderedName != null
          && isUpstreamSelectorPolicyInterface outputRenderedName
          && !(hasAcceptForwardingRule interfaceName outputRenderedName)
        )
    )
    staticPolicyRoutes;
  scopedSourceRoutes =
    if sourceIfName == targetIfName then
      explicitAcceptedOutputRoutes
    else if
      isPolicy
      && isPolicyDownstreamInterface interfaceName
      && hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName}
      && builtins.any (route: builtins.isAttrs route && isDefaultRoute route) (
        interfaces.${sourceIfName}.routes or [ ]
      )
    then
      explicitAcceptedOutputRoutes
    else if hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName} then
      explicitAcceptedOutputRoutes
    else if
      policyOnlyProjection.mayProject interfaceName sourceIfName
      && isUpstreamSelector
      && isUpstreamSelectorPolicyInterface interfaceName
    then
      lib.filter (route: !(isDefaultRoute route) || isPolicyOnlyRoute route) explicitAcceptedOutputRoutes
    else if policyOnlyProjection.mayProject interfaceName sourceIfName then
      lib.filter (route: !(isDefaultRoute route) || isPolicyOnlyRoute route) explicitAcceptedOutputRoutes
    else
      lib.filter (route: !(isDefaultRoute route) && !(isPolicyOnlyRoute route)) explicitAcceptedOutputRoutes;
in
lib.filter builtins.isAttrs (
  map
    (
      route: if builtins.isAttrs route then route // { table = tableId; } else null
    )
    scopedSourceRoutes
)
