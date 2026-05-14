{
  lib,
  common,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  upstreamLanesMatch,
  addressForFamily,
  ipv4PeerFor31,
  ipv6PeerFor127,
  isSelector,
  isUpstreamSelector,
  isPolicy,
  isUpstreamSelectorCoreInterface,
  isUpstreamSelectorPolicyInterface,
  isPolicyDownstreamInterface,
  isPolicyUpstreamInterface,
  isOverlayInterface,
  isCoreTransitInterface,
  forwardingRules ? [ ],
}:

let
  inherit (common)
    downstreamPairKeyFor
    policyTenantKeyFor
    stringHasPrefix
    ;

  renderedNameFor = name: renderedInterfaceNames.${name};

  routeUsesGateway =
    gateway: route:
    gateway != null && ((route.via4 or null) == gateway || (route.via6 or null) == gateway);

  interfacePeerForFamily =
    family: iface:
    let
      address = addressForFamily family iface;
    in
    if family == 6 then ipv6PeerFor127 address else ipv4PeerFor31 address;

  interfaceRoutesTowardTarget =
    targetName: sourceName:
    let
      targetIfKey = lib.findFirst (name: renderedNameFor name == targetName) null interfaceNames;
      targetIface = if targetIfKey == null then { } else interfaces.${targetIfKey} or { };
      sourceIface = interfaces.${sourceName} or { };
      routes = sourceIface.routes or [ ];
      targetPeer4 = interfacePeerForFamily 4 targetIface;
      targetPeer6 = interfacePeerForFamily 6 targetIface;
    in
    builtins.any
      (route: builtins.isAttrs route && (routeUsesGateway targetPeer4 route || routeUsesGateway targetPeer6 route))
      routes;

  hasAcceptForwardingRule =
    fromName: toName:
    builtins.any
      (rule:
        builtins.isAttrs rule
        && (rule.action or null) == "accept"
        && (rule.fromInterface or null) == fromName
        && (rule.toInterface or null) == toName)
      forwardingRules;
in
{
  forTarget =
    targetName:
    let
      targetIfKey = lib.findFirst (name: renderedNameFor name == targetName) null interfaceNames;
      pairKey = downstreamPairKeyFor targetName;
      pairPrefix =
        if stringHasPrefix "access-" targetName then
          "policy-"
        else if stringHasPrefix "policy-" targetName then
          "access-"
        else
          null;
      tenantKey = policyTenantKeyFor targetName;
    in
    if isSelector && pairKey != null && pairPrefix != null then
      lib.filter (name: renderedNameFor name == "${pairPrefix}${pairKey}") interfaceNames
    else if isUpstreamSelector && isUpstreamSelectorCoreInterface targetName then
      let
        policyInterfaces =
          lib.filter (
            name:
            isUpstreamSelectorPolicyInterface (renderedNameFor name)
          ) interfaceNames;
        acceptedPolicyInterfaces =
          lib.filter (
            name:
            hasAcceptForwardingRule targetName (renderedNameFor name)
          ) policyInterfaces;
      in
      lib.unique (
        lib.optionals (targetIfKey != null) [ targetIfKey ]
        ++ (if acceptedPolicyInterfaces != [ ] then acceptedPolicyInterfaces else policyInterfaces)
      )
    else if isUpstreamSelector && isUpstreamSelectorPolicyInterface targetName then
      lib.unique (
        lib.optionals (targetIfKey != null) [ targetIfKey ]
        ++ lib.filter (
          name:
          isUpstreamSelectorCoreInterface (renderedNameFor name)
          && (
            upstreamLanesMatch targetName (renderedNameFor name)
            || (targetIfKey != null && interfaceRoutesTowardTarget (renderedNameFor name) targetIfKey)
          )
        ) interfaceNames
      )
    else if isPolicy && isPolicyDownstreamInterface targetName then
      lib.filter (
        name:
        isPolicyDownstreamInterface (renderedNameFor name)
        || (isPolicyUpstreamInterface (renderedNameFor name)
          && (
            (tenantKey != null && policyTenantKeyFor (renderedNameFor name) == tenantKey)
            || hasAcceptForwardingRule targetName (renderedNameFor name)
          ))
      ) interfaceNames
    else if isPolicy && isPolicyUpstreamInterface targetName then
      lib.filter (
        name:
        (isPolicyDownstreamInterface (renderedNameFor name)
          && (
            (tenantKey != null && policyTenantKeyFor (renderedNameFor name) == tenantKey)
            || hasAcceptForwardingRule targetName (renderedNameFor name)
          ))
        || (isPolicyUpstreamInterface (renderedNameFor name)
          && tenantKey != null
          && (
            policyTenantKeyFor (renderedNameFor name) == tenantKey
            || hasAcceptForwardingRule targetName (renderedNameFor name)
          ))
      ) interfaceNames
    else if isOverlayInterface targetName then
      lib.unique (
        (lib.filter (name: renderedNameFor name == targetName) interfaceNames)
        ++ (lib.filter (name: isCoreTransitInterface (renderedNameFor name)) interfaceNames)
      )
    else if isCoreTransitInterface targetName then
      lib.unique (
        (lib.filter (name: renderedNameFor name == targetName) interfaceNames)
        ++ (lib.filter (name: isOverlayInterface (renderedNameFor name)) interfaceNames)
      )
    else
      lib.filter (name: renderedNameFor name == targetName) interfaceNames;
}
