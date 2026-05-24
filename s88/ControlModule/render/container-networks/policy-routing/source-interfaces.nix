{ lib
, interfaces
, interfaceNames
, renderedInterfaceNames
, addressForFamily
, ipv4PeerFor31
, ipv6PeerFor127
, policyRoutingSources ? { }
, forwardingRules ? [ ]
,
}:

let
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
      (
        route:
        builtins.isAttrs route && (routeUsesGateway targetPeer4 route || routeUsesGateway targetPeer6 route)
      )
      routes;

  namesFor =
    name:
    lib.unique (
      [ name ] ++ lib.optionals (builtins.hasAttr name renderedInterfaceNames) [ (renderedNameFor name) ]
    );

  interfaceKeysForRenderedName =
    renderedName: lib.filter (name: renderedNameFor name == renderedName) interfaceNames;

  interfaceKeyFor =
    name:
    if builtins.hasAttr name renderedInterfaceNames then
      name
    else
      let
        matches = interfaceKeysForRenderedName name;
      in
      if matches == [ ] then name else builtins.head matches;

  normalizeInterfaceKeys = names: lib.unique (map interfaceKeyFor names);

  hasAcceptForwardingRule =
    fromNames: toNames:
    builtins.any
      (
        rule:
        builtins.isAttrs rule
        && (rule.action or null) == "accept"
        && builtins.elem (rule.fromInterface or null) fromNames
        && builtins.elem (rule.toInterface or null) toNames
      )
      forwardingRules;

  acceptedForwardSourcesFor =
    targetName:
    let
      targetNames = lib.unique ([ targetName ] ++ interfaceKeysForRenderedName targetName);
    in
    lib.filter (name: hasAcceptForwardingRule (namesFor name) targetNames) interfaceNames;

  acceptedForwardTargetsFor =
    targetName:
    let
      sourceNames = lib.unique ([ targetName ] ++ interfaceKeysForRenderedName targetName);
    in
    lib.filter (name: hasAcceptForwardingRule sourceNames (namesFor name)) interfaceNames;
in
{
  forTarget =
    targetName:
    let
      unitSourcesRaw = policyRoutingSources.${targetName} or null;
      unitSources = if unitSourcesRaw == null then null else normalizeInterfaceKeys unitSourcesRaw;
      selfSources = lib.filter (name: renderedNameFor name == targetName) interfaceNames;
      acceptedForwardSources = acceptedForwardSourcesFor targetName;
      acceptedForwardTargets = acceptedForwardTargetsFor targetName;
    in
    if unitSources != null then
      lib.unique (unitSources ++ acceptedForwardSources ++ acceptedForwardTargets)
    else
      lib.unique (selfSources ++ acceptedForwardSources ++ acceptedForwardTargets);

  forTargetRules =
    targetName:
    let
      unitSourcesRaw = policyRoutingSources.${targetName} or null;
      unitSources = if unitSourcesRaw == null then null else normalizeInterfaceKeys unitSourcesRaw;
      selfSources = lib.filter (name: renderedNameFor name == targetName) interfaceNames;
      acceptedForwardSources = acceptedForwardSourcesFor targetName;
    in
    if acceptedForwardSources != [ ] then
      lib.unique (selfSources ++ acceptedForwardSources)
    else if unitSources != null then
      lib.unique unitSources
    else
      selfSources;
}
