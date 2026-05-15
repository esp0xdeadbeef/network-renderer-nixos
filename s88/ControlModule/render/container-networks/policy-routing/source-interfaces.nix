{
  lib,
  interfaces,
  interfaceNames,
  renderedInterfaceNames,
  addressForFamily,
  ipv4PeerFor31,
  ipv6PeerFor127,
  policyRoutingSources ? { },
  forwardingRules ? [ ],
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
      unitSources = policyRoutingSources.${targetName} or null;
    in
    if unitSources != null then
      unitSources
    else
      lib.filter (name: renderedNameFor name == targetName) interfaceNames;
}
