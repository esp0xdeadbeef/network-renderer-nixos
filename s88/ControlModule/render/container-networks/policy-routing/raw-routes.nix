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
, returnRoutes
, explicitReturnRoutes
, policyOnlyProjection
, routeHelpers
, hasAcceptForwardingRule
, isExternalValidationDelegatedPrefixRoute
,
}:
let
  inherit (routeHelpers)
    connectedP2pRoutesForInterface
    connectedP2pScopeRoutesForInterface
    isDefaultRoute
    isPolicyOnlyRoute
    isServiceDnsReachabilityRoute
    ;
in
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
      lib.concatMap
        (
          name:
          if isUpstreamSelectorPolicyInterface renderedInterfaceNames.${name} then
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
    if
      targetIfName != null
      && sourceIfName != targetIfName
      && hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName}
    then
      lib.filter
        (route: builtins.isAttrs route && (isDefaultRoute route || isPolicyOnlyRoute route))
        (interfaces.${sourceIfName}.routes or [ ])
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
  downstreamSelectorReturnConnectedRoutes =
    if
      isSelector
      && isDownstreamSelectorPolicyInterface interfaceName
      && hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName}
    then
      connectedP2pScopeRoutesForInterface sourceIfName
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
      ++ policyDownstreamDefaultRoutes
      ++ downstreamSelectorReturnConnectedRoutes;
  staticPolicyRoutes =
    lib.filter (route: !(isExternalValidationDelegatedPrefixRoute route)) sourceRoutes;
  scopedSourceRoutes =
    if sourceIfName == targetIfName then
      staticPolicyRoutes
    else if
      isPolicy
      && isPolicyDownstreamInterface interfaceName
      && hasAcceptForwardingRule interfaceName renderedInterfaceNames.${sourceIfName}
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
)
