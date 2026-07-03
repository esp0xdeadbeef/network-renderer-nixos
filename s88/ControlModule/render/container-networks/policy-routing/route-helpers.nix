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

  addressNetworkPrefix =
    address:
    if !(builtins.isString address) || !(lib.hasInfix "/" address) then
      null
    else
      let
        parts = lib.splitString "/" address;
        ip = builtins.head parts;
        prefixLength = builtins.elemAt parts 1;
      in
      if lib.hasInfix ":" ip then
        if prefixLength == "64" then
          let
            compressedParts = lib.splitString "::" ip;
          in
          if builtins.length compressedParts > 1 then
            let
              head = builtins.head compressedParts;
            in
            if head == "" then "::/64" else "${head}::/64"
          else
            let
              hextets = lib.splitString ":" ip;
            in
            if builtins.length hextets >= 4 then "${lib.concatStringsSep ":" (lib.take 4 hextets)}::/64" else null
        else
          null
      else
        let
          octets = lib.splitString "." ip;
        in
        if prefixLength == "24" && builtins.length octets == 4 then
          "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.0/24"
        else if prefixLength == "16" && builtins.length octets == 4 then
          "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.0.0/16"
        else if prefixLength == "8" && builtins.length octets == 4 then
          "${builtins.elemAt octets 0}.0.0.0/8"
        else
          null;
in
{
  inherit addressNetworkPrefix;

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
    route:
    builtins.isAttrs route
    && (((route.intent or { }).kind or null) == "service-dns-reachability");

  connectedP2pRoutesForInterface =
    ifName:
    let
      iface =
        if interfaces ? ${ifName} then
          interfaces.${ifName}
        else
          throw "connectedP2pRoutesForInterface: non-existent interface '${ifName}' — peer route references an interface that does not exist in the current layout.";
      peer4 = peers.ipv4PeerFor31 (peers.addressForFamily 4 iface);
      peer6 = peers.ipv6PeerFor127 (peers.addressForFamily 6 iface);
    in
    (lib.optional (peer4 != null) {
      dst = "${peer4}/31";
      via4 = peer4;
      scope = "link";
      proto = "kernel";
    })
    ++ (lib.optional (peer6 != null) {
      dst = "${peer6}/127";
      via6 = peer6;
      scope = "link";
      proto = "kernel";
    });

  connectedP2pScopeRoutesForInterface =
    ifName:
    let
      iface =
        if interfaces ? ${ifName} then
          interfaces.${ifName}
        else
          throw "connectedP2pScopeRoutesForInterface: non-existent interface '${ifName}' — peer route references an interface that does not exist in the current layout.";
      peer4 = peers.ipv4PeerFor31 (peers.addressForFamily 4 iface);
      peer6 = peers.ipv6PeerFor127 (peers.addressForFamily 6 iface);
    in
    (lib.optional (peer4 != null) {
      dst = "${peer4}/31";
      scope = "link";
      proto = "kernel";
    })
    ++ (lib.optional (peer6 != null) {
      dst = "${peer6}/127";
      scope = "link";
      proto = "kernel";
    });

  connectedScopeRoutesForInterface =
    ifName:
    lib.filter (route: route.dst != null) (
      map
        (address: {
          dst = addressNetworkPrefix address;
          scope = "link";
        })
        (interfaces.${ifName}.addresses or [ ])
    );
}
