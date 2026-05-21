{ lib
, interfaces
, interfaceNames
, peers
,
}:
let
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
in
{
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

  isServiceDnsReachabilityRoute =
    route: builtins.isAttrs route && (route.intent.kind or null) == "service-dns-reachability";

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

  connectedP2pScopeRoutesForInterface =
    ifName:
    let
      iface = interfaces.${ifName};
      peer4 = peers.ipv4PeerFor31 (peers.addressForFamily 4 iface);
      peer6 = peers.ipv6PeerFor127 (peers.addressForFamily 6 iface);
    in
    (lib.optional (peer4 != null) {
      dst = "${peer4}/31";
      scope = "link";
    })
    ++ (lib.optional (peer6 != null) {
      dst = "${peer6}/127";
      scope = "link";
    });
}
